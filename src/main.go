package main

import (
	"context"
	"encoding/csv"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	version     = "v1.9.5"
	copyright   = "Copyright (c) 2026. All rights reserved."
	programName = "TCPing"

	defaultCSVFlushEvery = 50
	defaultCSVFlushTick  = 1 * time.Second

	defaultPort = 80
)

// =====================
// Options
// =====================

type Options struct {
	UseIPv4       bool
	UseIPv6       bool
	Count         int           // 0 = infinite
	Interval      time.Duration // ping interval
	Timeout       time.Duration // dial timeout
	DNSTimeout    time.Duration // dns lookup timeout
	ColorOutput   bool
	VerboseMode   bool
	ShowTimestamp bool
	ShowVersion   bool
	ShowHelp      bool
	Port          int // default is set by flags (80). Must be 1..65535.

	CSVAuto       bool
	CSVPath       string
	CSVFlushEvery int           // flush every N rows
	CSVFlushTick  time.Duration // also flush on tick
}

// =====================
// Statistics (Duration-based)
// =====================

type Statistics struct {
	mu sync.Mutex

	sentCount      int64
	respondedCount int64

	minRTT time.Duration
	maxRTT time.Duration
	sumRTT time.Duration

	lastRTT     time.Duration
	sumJitter   time.Duration
	jitterCount int64

	initialized bool
}

func (s *Statistics) Update(rtt time.Duration, success bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.sentCount++
	if !success {
		return
	}
	s.respondedCount++
	s.sumRTT += rtt

	if !s.initialized {
		s.minRTT = rtt
		s.maxRTT = rtt
		s.lastRTT = rtt
		s.initialized = true
		return
	}

	j := rtt - s.lastRTT
	if j < 0 {
		j = -j
	}
	s.sumJitter += j
	s.jitterCount++
	s.lastRTT = rtt

	if rtt < s.minRTT {
		s.minRTT = rtt
	}
	if rtt > s.maxRTT {
		s.maxRTT = rtt
	}
}

func (s *Statistics) SentCount() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sentCount
}

type StatsSnapshot struct {
	Sent      int64
	Received  int64
	Min       time.Duration
	Max       time.Duration
	Avg       time.Duration
	JitterAvg time.Duration
}

func (s *Statistics) Snapshot() StatsSnapshot {
	s.mu.Lock()
	defer s.mu.Unlock()

	var avg time.Duration
	if s.respondedCount > 0 {
		avg = time.Duration(s.sumRTT.Nanoseconds() / s.respondedCount)
	}

	var jitterAvg time.Duration
	if s.jitterCount > 0 {
		jitterAvg = time.Duration(s.sumJitter.Nanoseconds() / s.jitterCount)
	}

	return StatsSnapshot{
		Sent:      s.sentCount,
		Received:  s.respondedCount,
		Min:       s.minRTT,
		Max:       s.maxRTT,
		Avg:       avg,
		JitterAvg: jitterAvg,
	}
}

// =====================
// Runner
// =====================

type Runner struct {
	opts *Options

	host string
	port string

	chosenIP string // display + dial (JoinHostPort will bracket IPv6)
	ipType   string
	allIPs   []net.IP

	stats *Statistics

	csv   chan []string
	csvWG sync.WaitGroup
}

func NewRunner(opts *Options, host, port string) *Runner {
	return &Runner{
		opts:  opts,
		host:  host,
		port:  port,
		stats: &Statistics{},
	}
}

func (r *Runner) DisplayHost() string {
	if net.ParseIP(r.host) == nil && r.chosenIP != "" {
		return fmt.Sprintf("%s [%s]", r.host, r.chosenIP)
	}
	if r.chosenIP != "" {
		return r.chosenIP
	}
	return r.host
}

func (r *Runner) PrintSummary() {
	printSummary(r.stats, r.opts.VerboseMode, r.DisplayHost(), r.port)
}

func (r *Runner) SentCount() int64 {
	return r.stats.SentCount()
}

func (r *Runner) Run(ctx context.Context) error {
	if err := r.resolve(ctx); err != nil {
		return err
	}

	r.printIntro()

	if r.opts.CSVAuto {
		if r.opts.CSVPath == "" {
			r.opts.CSVPath = fmt.Sprintf("tcping_results_%s_%s.csv",
				sanitizeFilename(r.host),
				time.Now().Format("20060102-150405"))
		}
		r.csv = startCSVWriter(r.opts.CSVPath, &r.csvWG, r.opts.CSVFlushEvery, r.opts.CSVFlushTick)
		defer func() {
			close(r.csv)
			r.csvWG.Wait()
		}()
	}

	ticker := time.NewTicker(r.opts.Interval)
	defer ticker.Stop()

	for seq := 1; r.opts.Count == 0 || seq <= r.opts.Count; seq++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		r.pingOnce(ctx, seq)

		if r.opts.Count > 0 && seq == r.opts.Count {
			break
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}

	return nil
}

func (r *Runner) printIntro() {
	if net.ParseIP(r.host) == nil {
		fmt.Printf("正在对 %s [%s - %s] 端口 %s 执行 TCP Ping\n", r.host, r.ipType, r.chosenIP, r.port)
	} else {
		fmt.Printf("正在对 %s 端口 %s 执行 TCP Ping\n", r.host, r.port)
	}

	if r.opts.VerboseMode && len(r.allIPs) > 1 {
		fmt.Printf("域名 %s 解析到的所有IP地址:\n", r.host)
		for i, ip := range r.allIPs {
			if ip.To4() != nil {
				fmt.Printf("  [%d] IPv4: %s\n", i+1, ip.String())
			} else {
				fmt.Printf("  [%d] IPv6: %s\n", i+1, ip.String())
			}
		}
		fmt.Printf("使用IP地址: %s\n\n", r.chosenIP)
	}
}

func (r *Runner) resolve(ctx context.Context) error {
	if ip := net.ParseIP(r.host); ip != nil {
		isV4 := ip.To4() != nil
		if r.opts.UseIPv4 && !isV4 {
			return fmt.Errorf("地址 %s 不是 IPv4 地址", r.host)
		}
		if r.opts.UseIPv6 && isV4 {
			return fmt.Errorf("地址 %s 不是 IPv6 地址", r.host)
		}
		r.allIPs = []net.IP{ip}
		r.chooseIP(ip)
		return nil
	}

	dnsCtx, cancel := context.WithTimeout(ctx, r.opts.DNSTimeout)
	defer cancel()

	res := net.Resolver{}
	ipAddrs, err := res.LookupIPAddr(dnsCtx, r.host)
	if err != nil {
		return fmt.Errorf("解析 %s 失败: %w", r.host, err)
	}
	if len(ipAddrs) == 0 {
		return fmt.Errorf("未找到 %s 的 IP 地址", r.host)
	}

	r.allIPs = make([]net.IP, 0, len(ipAddrs))
	for _, a := range ipAddrs {
		r.allIPs = append(r.allIPs, a.IP)
	}

	var chosen net.IP
	if r.opts.UseIPv4 {
		for _, ip := range r.allIPs {
			if ip.To4() != nil {
				chosen = ip
				break
			}
		}
		if chosen == nil {
			return fmt.Errorf("未找到 %s 的 IPv4 地址", r.host)
		}
	} else if r.opts.UseIPv6 {
		for _, ip := range r.allIPs {
			if ip.To4() == nil {
				chosen = ip
				break
			}
		}
		if chosen == nil {
			return fmt.Errorf("未找到 %s 的 IPv6 地址", r.host)
		}
	} else {
		for _, ip := range r.allIPs {
			if ip.To4() != nil {
				chosen = ip
				break
			}
		}
		if chosen == nil {
			for _, ip := range r.allIPs {
				if ip.To4() == nil {
					chosen = ip
					break
				}
			}
		}
		if chosen == nil {
			return fmt.Errorf("未找到 %s 的可用 IP 地址", r.host)
		}
	}

	r.chooseIP(chosen)
	return nil
}

func (r *Runner) chooseIP(ip net.IP) {
	if ip.To4() != nil {
		r.ipType = "IPv4"
	} else {
		r.ipType = "IPv6"
	}
	r.chosenIP = ip.String()
}

func (r *Runner) pingOnce(ctx context.Context, seq int) {
	dialCtx, cancel := context.WithTimeout(ctx, r.opts.Timeout)
	defer cancel()

	start := time.Now()
	addr := net.JoinHostPort(r.chosenIP, r.port)

	conn, err := (&net.Dialer{}).DialContext(dialCtx, "tcp", addr)
	rtt := time.Since(start)

	if ctx.Err() != nil {
		if conn != nil {
			_ = conn.Close()
		}
		return
	}

	success := err == nil
	r.stats.Update(rtt, success)

	ts := time.Now().UTC().Format(time.RFC3339Nano)
	prefix := ""
	if r.opts.ShowTimestamp {
		prefix = "[" + formatDisplayTimestamp(time.Now()) + "] "
	}

	if !success {
		fmt.Print(errorText(fmt.Sprintf("%sTCP连接失败 %s:%s: seq=%d 错误=%v\n", prefix, r.chosenIP, r.port, seq, err), r.opts.ColorOutput))
		if r.opts.VerboseMode {
			fmt.Printf("%s  详细信息: 连接尝试耗时 %.2fms, 目标 %s\n", prefix, durMS(rtt), addr)
		}
		sendCSVRow(r.csv, []string{
			ts,
			strconv.Itoa(seq),
			r.host,
			r.chosenIP,
			r.port,
			fmt.Sprintf("%.2f", durMS(rtt)),
			"false",
			fmt.Sprintf("%v", err),
			"",
		})
		return
	}
	defer func() {
		if cerr := conn.Close(); cerr != nil && r.opts.VerboseMode {
			fmt.Printf("  关闭连接时出错: %v\n", cerr)
		}
	}()

	localAddr := conn.LocalAddr().String()

	fmt.Print(successText(fmt.Sprintf("%s从 %s:%s 收到响应: seq=%d time=%.2fms\n", prefix, r.chosenIP, r.port, seq, durMS(rtt)), r.opts.ColorOutput))
	if r.opts.VerboseMode {
		fmt.Printf("%s  详细信息: 本地地址=%s, 远程地址=%s\n", prefix, localAddr, addr)
	}

	sendCSVRow(r.csv, []string{
		ts,
		strconv.Itoa(seq),
		r.host,
		r.chosenIP,
		r.port,
		fmt.Sprintf("%.2f", durMS(rtt)),
		"true",
		"",
		localAddr,
	})
}

// =====================
// CSV writer
// =====================

func startCSVWriter(path string, wg *sync.WaitGroup, flushEvery int, flushTick time.Duration) chan []string {
	if flushEvery <= 0 {
		flushEvery = defaultCSVFlushEvery
	}
	if flushTick <= 0 {
		flushTick = defaultCSVFlushTick
	}

	ch := make(chan []string, 256)
	wg.Add(1)

	go func(ch <-chan []string) {
		defer wg.Done()

		f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "无法打开 CSV 文件 %s: %v\n", path, err)
			for range ch {
			}
			return
		}
		defer func() {
			_ = f.Sync()
			if cerr := f.Close(); cerr != nil {
				fmt.Fprintf(os.Stderr, "关闭 CSV 文件失败: %v\n", cerr)
			}
		}()

		w := csv.NewWriter(f)

		repl := strings.NewReplacer("\n", " ", "\r", " ")
		flush := func() {
			w.Flush()
			if err := w.Error(); err != nil {
				fmt.Fprintf(os.Stderr, "CSV flush 错误: %v\n", err)
			}
		}

		if fi, err := f.Stat(); err == nil && fi.Size() == 0 {
			if err := w.Write([]string{"timestamp", "seq", "host", "ip", "port", "elapsed_ms", "success", "error", "local_addr"}); err != nil {
				fmt.Fprintf(os.Stderr, "写入 CSV header 失败: %v\n", err)
			}
			flush()
		}

		t := time.NewTicker(flushTick)
		defer t.Stop()

		rowCount := 0
		for {
			select {
			case row, ok := <-ch:
				if !ok {
					flush()
					return
				}

				for i, v := range row {
					v = repl.Replace(v)
					row[i] = protectCSVFormula(v)
				}

				if err := w.Write(row); err != nil {
					fmt.Fprintf(os.Stderr, "CSV 写入错误: %v\n", err)
					continue
				}
				rowCount++
				if rowCount%flushEvery == 0 {
					flush()
				}

			case <-t.C:
				flush()
			}
		}
	}(ch)

	return ch
}

func protectCSVFormula(s string) string {
	if s == "" {
		return s
	}
	switch s[0] {
	case '=', '+', '-', '@', '\t':
		return "'" + s
	default:
		return s
	}
}

func sendCSVRow(ch chan<- []string, row []string) {
	if ch == nil {
		return
	}
	select {
	case ch <- row:
	default:
	}
}

// =====================
// CLI / parsing
// =====================

func setupFlags(opts *Options) {
	flag.Usage = func() { printHelp() }

	flag.BoolVar(&opts.UseIPv4, "4", false, "")
	flag.BoolVar(&opts.UseIPv4, "ipv4", false, "")
	flag.BoolVar(&opts.UseIPv6, "6", false, "")
	flag.BoolVar(&opts.UseIPv6, "ipv6", false, "")

	flag.IntVar(&opts.Count, "n", 0, "")
	flag.IntVar(&opts.Count, "count", 0, "")

	intervalMS := flag.Int("t", 1000, "")
	flag.IntVar(intervalMS, "interval", 1000, "")

	timeoutMS := flag.Int("w", 1000, "")
	flag.IntVar(timeoutMS, "timeout", 1000, "")

	dnsTimeoutMS := flag.Int("dns-timeout", 1500, "")

	flag.IntVar(&opts.Port, "p", defaultPort, "")
	flag.IntVar(&opts.Port, "port", defaultPort, "")

	flag.BoolVar(&opts.ColorOutput, "c", false, "")
	flag.BoolVar(&opts.ColorOutput, "color", false, "")

	flag.BoolVar(&opts.VerboseMode, "v", false, "")
	flag.BoolVar(&opts.VerboseMode, "verbose", false, "")

	flag.BoolVar(&opts.ShowTimestamp, "D", false, "")
	flag.BoolVar(&opts.ShowTimestamp, "timestamp", false, "")

	flag.BoolVar(&opts.CSVAuto, "o", false, "")
	flag.BoolVar(&opts.CSVAuto, "csv", false, "")
	flag.IntVar(&opts.CSVFlushEvery, "csv-flush-every", defaultCSVFlushEvery, "")
	csvFlushTickMS := flag.Int("csv-flush-tick", int(defaultCSVFlushTick/time.Millisecond), "")

	flag.BoolVar(&opts.ShowVersion, "V", false, "")
	flag.BoolVar(&opts.ShowVersion, "version", false, "")
	flag.BoolVar(&opts.ShowHelp, "h", false, "")
	flag.BoolVar(&opts.ShowHelp, "help", false, "")

	flag.Parse()

	opts.Interval = time.Duration(*intervalMS) * time.Millisecond
	opts.Timeout = time.Duration(*timeoutMS) * time.Millisecond
	opts.DNSTimeout = time.Duration(*dnsTimeoutMS) * time.Millisecond
	opts.CSVFlushTick = time.Duration(*csvFlushTickMS) * time.Millisecond
}

func applyDefaults(opts *Options) {
	if opts.CSVFlushEvery <= 0 {
		opts.CSVFlushEvery = defaultCSVFlushEvery
	}
	if opts.CSVFlushTick <= 0 {
		opts.CSVFlushTick = defaultCSVFlushTick
	}
}

func isValidPort(n int) bool {
	return n >= 1 && n <= 65535
}

func validateOptions(opts *Options) error {
	if opts.UseIPv4 && opts.UseIPv6 {
		return errors.New("无法同时使用 -4 和 -6 标志")
	}
	if opts.Interval <= 0 {
		return errors.New("间隔时间必须大于 0")
	}
	if opts.Timeout <= 0 {
		return errors.New("超时时间必须大于 0")
	}
	if opts.DNSTimeout <= 0 {
		return errors.New("DNS 超时时间必须大于 0")
	}
	if !isValidPort(opts.Port) {
		return errors.New("端口号必须是 1 到 65535 之间的整数")
	}
	return nil
}

func parseTarget(opts *Options, args []string) (host string, port string, err error) {
	if len(args) < 1 {
		return "", "", errors.New("需要提供主机参数\n\n用法: tcping [选项] <主机> [端口]\n尝试 'tcping -h' 获取更多信息")
	}

	rawHost := strings.TrimSpace(args[0])
	h, p := splitHostMaybeWithPort(rawHost)

	if len(args) >= 2 {
		// allow passing ":1234" or "1234" as the second argument; trim whitespace
		p = strings.TrimSpace(args[1])
		p = strings.TrimPrefix(p, ":")
	}

	if p == "" {
		p = strconv.Itoa(opts.Port)
	}

	portNum, e := strconv.Atoi(p)
	if e != nil || !isValidPort(portNum) {
		return "", "", errors.New("端口号必须是 1 到 65535 之间的整数")
	}

	return h, p, nil
}

func splitHostMaybeWithPort(s string) (host string, port string) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", ""
	}

	if strings.HasPrefix(s, "[") {
		if h, p, err := net.SplitHostPort(s); err == nil {
			return h, p
		}
		if strings.HasSuffix(s, "]") {
			return strings.TrimSuffix(strings.TrimPrefix(s, "["), "]"), ""
		}
		return s, ""
	}

	if strings.Count(s, ":") == 1 {
		if h, p, err := net.SplitHostPort(s); err == nil {
			return h, p
		}
		return s, ""
	}

	return s, ""
}

// =====================
// Output / helpers
// =====================

func printHelp() {
	fmt.Printf(`%s %s - TCP 连接测试工具

描述:
    %s 测试到目标主机和端口的TCP连接性。

用法:
    tcping [选项] <主机> [端口]      (默认端口: 80)

选项:
    -4, --ipv4                  强制使用 IPv4
    -6, --ipv6                  强制使用 IPv6
    -n, --count <次数>          发送请求次数 (默认: 无限)
    -p, --port <端口>           指定要连接的端口 (默认: 80)
    -t, --interval <毫秒>       请求间隔 (默认: 1000)
    -w, --timeout <毫秒>        连接超时 (默认: 1000)
        --dns-timeout <毫秒>    DNS 解析超时 (默认: 1500)
    -c, --color                 启用彩色输出
    -v, --verbose               启用详细模式
	-D, --timestamp             显示时间戳 (yyyy-mm-dd hh:mm:ss)
    -o, --csv                   在当前目录生成 CSV 文件记录
        --csv-flush-every <N>   每 N 行 flush 一次 (默认: 50)
        --csv-flush-tick <毫秒> 定时 flush (默认: 1000)
    -V, --version               显示版本信息
    -h, --help                  显示帮助信息

示例:
    tcping google.com
    tcping google.com 443
    tcping google.com:443
    tcping -p 443 google.com
    tcping -4 -n 5 8.8.8.8 443
    tcping -w 2000 example.com 22
    tcping -c -v example.com 443

`, programName, version, programName)
}

func printVersion() {
	fmt.Printf("%s 版本 %s\n", programName, version)
	fmt.Println(copyright)
}

func printSummary(stats *Statistics, verbose bool, displayHost, port string) {
	s := stats.Snapshot()

	fmt.Printf("\n\n--- 目标 %s 端口 %s 的 TCP ping 统计 ---\n", displayHost, port)
	if s.Sent == 0 {
		return
	}

	lossRate := float64(s.Sent-s.Received) / float64(s.Sent) * 100
	fmt.Printf("已发送 = %d, 已接收 = %d, 丢失 = %d (%.1f%% 丢失)\n", s.Sent, s.Received, s.Sent-s.Received, lossRate)

	if s.Received > 0 {
		fmt.Printf("往返时间(RTT): 最小 = %.2fms, 最大 = %.2fms, 平均 = %.2fms\n",
			durMS(s.Min), durMS(s.Max), durMS(s.Avg))
		if verbose {
			fmt.Printf("抖动(Jitter): 平均 = %.2fms\n", durMS(s.JitterAvg))
		}
	}
}

func colorText(text, colorCode string, useColor bool) string {
	if !useColor {
		return text
	}
	return "\033[" + colorCode + "m" + text + "\033[0m"
}

func successText(text string, useColor bool) string { return colorText(text, "32", useColor) }
func errorText(text string, useColor bool) string   { return colorText(text, "31", useColor) }

func sanitizeFilename(s string) string {
	if s == "" {
		return "unknown"
	}
	s = strings.TrimSpace(s)
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') ||
			(r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') ||
			r == '.' || r == '_' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	if out := b.String(); out != "" {
		return out
	}
	return "unknown"
}

func durMS(d time.Duration) float64 {
	return float64(d.Microseconds()) / 1000.0
}

func formatDisplayTimestamp(t time.Time) string {
	// Format required: yyyy-mm-dd hh:mm:ss
	return t.Format("2006-01-02 15:04:05")
}

// =====================
// main
// =====================

func main() {
	opts := &Options{}
	setupFlags(opts)

	if opts.ShowHelp {
		printHelp()
		os.Exit(0)
	}
	if opts.ShowVersion {
		printVersion()
		os.Exit(0)
	}

	applyDefaults(opts)
	if err := validateOptions(opts); err != nil {
		fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		os.Exit(1)
	}

	host, port, err := parseTarget(opts, flag.Args())
	if err != nil {
		fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		os.Exit(1)
	}

	r := NewRunner(opts, host, port)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(interrupt)

	done := make(chan error, 1)
	go func() { done <- r.Run(ctx) }()

	var runErr error
	select {
	case <-interrupt:
		fmt.Printf("\n操作被中断。\n")
		cancel()
		runErr = <-done
	case runErr = <-done:
		if runErr != nil && !errors.Is(runErr, context.Canceled) {
			fmt.Fprintf(os.Stderr, "错误: %v\n", runErr)
		}
	}

	// Print summary only when it is meaningful:
	// - normal completion
	// - cancellation with at least one attempt sent
	if runErr == nil || (errors.Is(runErr, context.Canceled) && r.SentCount() > 0) {
		r.PrintSummary()
	}

	if runErr != nil && !errors.Is(runErr, context.Canceled) {
		os.Exit(1)
	}
}
