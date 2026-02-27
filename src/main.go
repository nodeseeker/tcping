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
	version     = "v1.8.4"
	copyright   = "Copyright (c) 2026. All rights reserved."
	programName = "TCPing"
)

// Statistics 保存 TCP ping 的统计数据，所有方法均通过内嵌的 Mutex 保证并发安全。
type Statistics struct {
	sync.Mutex
	sentCount      int64
	respondedCount int64
	minTime        float64
	maxTime        float64
	totalTime      float64
	lastTime       float64
	totalJitter    float64
	jitterCount    int64
}

func (s *Statistics) update(elapsed float64, success bool) {
	s.Lock()
	defer s.Unlock()

	s.sentCount++
	if !success {
		return
	}

	s.respondedCount++
	s.totalTime += elapsed

	// 首次成功响应：初始化边界值，无抖动样本。
	if s.respondedCount == 1 {
		s.minTime = elapsed
		s.maxTime = elapsed
		s.lastTime = elapsed
		return
	}

	// 计算抖动（与上次响应时间差的绝对值）。
	// FIX: 去掉冗余的 `respondedCount > 1` 判断，
	// 此处执行时 respondedCount 必然 > 1（上方已 return）。
	jitter := elapsed - s.lastTime
	if jitter < 0 {
		jitter = -jitter
	}
	s.totalJitter += jitter
	s.jitterCount++
	s.lastTime = elapsed

	if elapsed < s.minTime {
		s.minTime = elapsed
	}
	if elapsed > s.maxTime {
		s.maxTime = elapsed
	}
}

func (s *Statistics) getStats() (sent, responded int64, min, max, avg float64) {
	s.Lock()
	defer s.Unlock()

	if s.respondedCount > 0 {
		avg = s.totalTime / float64(s.respondedCount)
	}
	return s.sentCount, s.respondedCount, s.minTime, s.maxTime, avg
}

func (s *Statistics) getJitter() float64 {
	s.Lock()
	defer s.Unlock()

	if s.jitterCount > 0 {
		return s.totalJitter / float64(s.jitterCount)
	}
	return 0.0
}

// Options 是纯数据结构（value bag），不封装任何行为。
// FIX: 去除 sendCSVRow / CSVChan() / closeCSVChan 三个方法——
// Options 不应承担行为，channel 的方向控制由函数签名负责。
type Options struct {
	UseIPv4     bool
	UseIPv6     bool
	Count       int
	Interval    int
	Timeout     int
	ColorOutput bool
	VerboseMode bool
	ShowVersion bool
	ShowHelp    bool
	Port        int
	CSVPath     string
	Host        string
	// CSVChan 由 main() 在启动前赋值一次，运行期间只读，
	// 消除跨 goroutine 写字段的数据竞争。
	CSVChan chan []string
	CSVAuto bool
}

func handleError(err error, exitCode int) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		os.Exit(exitCode)
	}
}

func printHelp() {
	fmt.Printf(`%s %s - TCP 连接测试工具

描述:
    %s 测试到目标主机和端口的TCP连接性。

用法: 
    tcping [选项] <主机> [端口]      (默认端口: 80)

选项:
    -4, --ipv4              强制使用 IPv4
    -6, --ipv6              强制使用 IPv6
    -n, --count <次数>      发送请求的次数 (默认: 无限)
    -p, --port <端口>       指定要连接的端口 (默认: 80)
    -t, --interval <毫秒>   请求间隔 (默认: 1000毫秒)
    -w, --timeout <毫秒>    连接超时 (默认: 1000毫秒)
    -c, --color             启用彩色输出
    -v, --verbose           启用详细模式，显示更多连接信息
    -o, --csv               在当前目录生成csv文件记录
    -V, --version           显示版本信息
    -h, --help              显示此帮助信息

示例:
    tcping google.com                	# 基本用法 (默认端口 80)
    tcping google.com 443            	# 基本用法指定端口
    tcping google.com:443            	# 使用 host:port 格式
    tcping -p 443 google.com         	# 使用 -p 参数指定端口
    tcping -4 -n 5 8.8.8.8 443       	# IPv4, 5次请求
    tcping -w 2000 example.com 22    	# 2秒超时
    tcping -c -v example.com 443     	# 彩色输出和详细模式

`, programName, version, programName)
}

func printVersion() {
	fmt.Printf("%s 版本 %s\n", programName, version)
	fmt.Println(copyright)
}

func resolveAddress(address string, useIPv4, useIPv6 bool) (string, []net.IP, error) {
	if ip := net.ParseIP(address); ip != nil {
		isV4 := ip.To4() != nil
		if useIPv4 && !isV4 {
			return "", nil, fmt.Errorf("地址 %s 不是 IPv4 地址", address)
		}
		if useIPv6 && isV4 {
			return "", nil, fmt.Errorf("地址 %s 不是 IPv6 地址", address)
		}
		if !isV4 {
			return "[" + ip.String() + "]", []net.IP{ip}, nil
		}
		return ip.String(), []net.IP{ip}, nil
	}

	ipList, err := net.LookupIP(address)
	if err != nil {
		return "", nil, fmt.Errorf("解析 %s 失败: %v", address, err)
	}
	if len(ipList) == 0 {
		return "", nil, fmt.Errorf("未找到 %s 的 IP 地址", address)
	}

	if useIPv4 {
		for _, ip := range ipList {
			if ip.To4() != nil {
				return ip.String(), ipList, nil
			}
		}
		return "", ipList, fmt.Errorf("未找到 %s 的 IPv4 地址", address)
	}

	if useIPv6 {
		for _, ip := range ipList {
			if ip.To4() == nil {
				return "[" + ip.String() + "]", ipList, nil
			}
		}
		return "", ipList, fmt.Errorf("未找到 %s 的 IPv6 地址", address)
	}

	// 未强制指定版本：优先 IPv4，回退 IPv6。
	for _, ip := range ipList {
		if ip.To4() != nil {
			return ip.String(), ipList, nil
		}
	}
	for _, ip := range ipList {
		if ip.To4() == nil {
			return "[" + ip.String() + "]", ipList, nil
		}
	}

	// 理论上不可达，因为 ipList 非空。
	ip := ipList[0]
	if ip.To4() == nil {
		return "[" + ip.String() + "]", ipList, nil
	}
	return ip.String(), ipList, nil
}

func parseHostPort(input string) (host, port string, hasPort bool) {
	if strings.HasPrefix(input, "[") {
		if idx := strings.LastIndex(input, "]:"); idx != -1 {
			return input[1:idx], input[idx+2:], true
		}
		if strings.HasSuffix(input, "]") {
			return input[1 : len(input)-1], "", false
		}
		return input, "", false
	}

	if strings.Count(input, ":") == 1 {
		idx := strings.LastIndex(input, ":")
		return input[:idx], input[idx+1:], true
	}

	return input, "", false
}

// sendCSVRow 非阻塞地向 CSV channel 投递一行数据。
// FIX: 从 Options 方法改为独立函数，保持 Options 为纯数据结构。
// channel 方向声明为 chan<- 明确写入语义。
func sendCSVRow(ch chan<- []string, row []string) {
	if ch == nil {
		return
	}
	select {
	case ch <- row:
	default:
	}
}

func pingOnce(ctx context.Context, address, port string, timeout int, stats *Statistics, seq int, ip string, opts *Options) {
	dialCtx, dialCancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Millisecond)
	defer dialCancel()

	start := time.Now()
	conn, err := (&net.Dialer{}).DialContext(dialCtx, "tcp", address+":"+port)
	elapsed := float64(time.Since(start).Microseconds()) / 1000.0

	if ctx.Err() == context.Canceled {
		fmt.Print(infoText("\n操作被中断, 连接尝试已中止\n", opts.ColorOutput))
		return
	}

	success := err == nil
	stats.update(elapsed, success)

	if !success {
		fmt.Print(errorText(fmt.Sprintf("TCP连接失败 %s:%s: seq=%d 错误=%v\n", ip, port, seq, err), opts.ColorOutput))
		if opts.VerboseMode {
			fmt.Printf("  详细信息: 连接尝试耗时 %.2fms, 目标 %s:%s\n", elapsed, address, port)
		}
		sendCSVRow(opts.CSVChan, []string{
			time.Now().UTC().Format(time.RFC3339Nano),
			strconv.Itoa(seq), opts.Host, ip, port,
			fmt.Sprintf("%.2f", elapsed),
			"false", fmt.Sprintf("%v", err), "",
		})
		return
	}

	// FIX: 删除原有的死变量 `localAddr := ""`，连接成功后直接获取一次。
	localAddr := conn.LocalAddr().String()
	defer func() {
		if cerr := conn.Close(); cerr != nil && opts.VerboseMode {
			fmt.Printf("  关闭连接时出错: %v\n", cerr)
		}
	}()

	fmt.Print(successText(fmt.Sprintf("从 %s:%s 收到响应: seq=%d time=%.2fms\n", ip, port, seq, elapsed), opts.ColorOutput))
	if opts.VerboseMode {
		fmt.Printf("  详细信息: 本地地址=%s, 远程地址=%s:%s\n", localAddr, ip, port)
	}
	sendCSVRow(opts.CSVChan, []string{
		time.Now().UTC().Format(time.RFC3339Nano),
		strconv.Itoa(seq), opts.Host, ip, port,
		fmt.Sprintf("%.2f", elapsed),
		"true", "", localAddr,
	})
}

func printTCPingStatistics(stats *Statistics, opts *Options, host, port string) {
	sent, responded, min, max, avg := stats.getStats()

	fmt.Printf("\n\n--- 目标 %s 端口 %s 的 TCP ping 统计 ---\n", host, port)
	if sent == 0 {
		return
	}

	lossRate := float64(sent-responded) / float64(sent) * 100
	fmt.Printf("已发送 = %d, 已接收 = %d, 丢失 = %d (%.1f%% 丢失)\n", sent, responded, sent-responded, lossRate)

	if responded > 0 {
		fmt.Printf("往返时间(RTT): 最小 = %.2fms, 最大 = %.2fms, 平均 = %.2fms\n", min, max, avg)
		if opts.VerboseMode {
			fmt.Printf("抖动(Jitter): 平均 = %.2fms\n", stats.getJitter())
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
func infoText(text string, useColor bool) string    { return colorText(text, "36", useColor) }

func setupFlags(opts *Options) {
	flag.Usage = func() { printHelp() }

	flag.BoolVar(&opts.UseIPv4, "4", false, "")
	flag.BoolVar(&opts.UseIPv4, "ipv4", false, "")
	flag.BoolVar(&opts.UseIPv6, "6", false, "")
	flag.BoolVar(&opts.UseIPv6, "ipv6", false, "")
	flag.IntVar(&opts.Count, "n", 0, "")
	flag.IntVar(&opts.Count, "count", 0, "")
	flag.IntVar(&opts.Interval, "t", 1000, "")
	flag.IntVar(&opts.Interval, "interval", 1000, "")
	flag.IntVar(&opts.Timeout, "w", 1000, "")
	flag.IntVar(&opts.Timeout, "timeout", 1000, "")
	flag.IntVar(&opts.Port, "p", 0, "")
	flag.IntVar(&opts.Port, "port", 0, "")
	flag.BoolVar(&opts.ColorOutput, "c", false, "")
	flag.BoolVar(&opts.ColorOutput, "color", false, "")
	flag.BoolVar(&opts.VerboseMode, "v", false, "")
	flag.BoolVar(&opts.VerboseMode, "verbose", false, "")
	flag.BoolVar(&opts.ShowVersion, "V", false, "")
	flag.BoolVar(&opts.ShowVersion, "version", false, "")
	flag.BoolVar(&opts.ShowHelp, "h", false, "")
	flag.BoolVar(&opts.ShowHelp, "help", false, "")
	flag.BoolVar(&opts.CSVAuto, "o", false, "")
	flag.BoolVar(&opts.CSVAuto, "csv", false, "")

	flag.Parse()
}

func sanitizeFilename(s string) string {
	if s == "" {
		return "unknown"
	}
	s = strings.TrimSpace(s)
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '.' || r == '_' || r == '-' {
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

func validateOptions(opts *Options, args []string) (string, string, error) {
	optionsWithValue := map[string]*int{
		"-n": &opts.Count, "--count": &opts.Count,
		"-t": &opts.Interval, "--interval": &opts.Interval,
		"-w": &opts.Timeout, "--timeout": &opts.Timeout,
		"-p": &opts.Port, "--port": &opts.Port,
	}
	boolOptions := map[string]*bool{
		"-4": &opts.UseIPv4, "--ipv4": &opts.UseIPv4,
		"-6": &opts.UseIPv6, "--ipv6": &opts.UseIPv6,
		"-c": &opts.ColorOutput, "--color": &opts.ColorOutput,
		"-v": &opts.VerboseMode, "--verbose": &opts.VerboseMode,
		"-V": &opts.ShowVersion, "--version": &opts.ShowVersion,
		"-h": &opts.ShowHelp, "--help": &opts.ShowHelp,
	}

	var positionalArgs []string
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if ptr, ok := optionsWithValue[arg]; ok {
			if i+1 < len(args) {
				if val, err := strconv.Atoi(args[i+1]); err == nil {
					*ptr = val
					i++
					continue
				}
			}
		} else if ptr, ok := boolOptions[arg]; ok {
			*ptr = true
		} else if !strings.HasPrefix(arg, "-") {
			positionalArgs = append(positionalArgs, arg)
		}
	}

	if opts.UseIPv4 && opts.UseIPv6 {
		return "", "", errors.New("无法同时使用 -4 和 -6 标志")
	}
	if opts.Interval < 0 {
		return "", "", errors.New("间隔时间不能为负值")
	}
	if opts.Timeout <= 0 {
		return "", "", errors.New("超时时间必须大于 0")
	}
	if len(positionalArgs) < 1 {
		return "", "", errors.New("需要提供主机参数\n\n用法: tcping [选项] <主机> [端口]\n尝试 'tcping -h' 获取更多信息")
	}

	host, parsedPort, hasPort := parseHostPort(positionalArgs[0])
	port := "80"
	if hasPort {
		port = parsedPort
	}
	if len(positionalArgs) > 1 {
		port = positionalArgs[1]
	} else if !hasPort && opts.Port > 0 {
		port = strconv.Itoa(opts.Port)
	}

	portNum, err := strconv.Atoi(port)
	if err != nil {
		return "", "", errors.New("端口号格式无效")
	}
	if portNum <= 0 || portNum > 65535 {
		return "", "", errors.New("端口号必须在 1 到 65535 之间")
	}

	return host, port, nil
}

// startCSVWriter 初始化 CSV channel 并启动写入 goroutine。
// FIX: 不再返回 *sync.WaitGroup（返回局部变量指针是反模式）；
// 改为接受调用方传入的 *sync.WaitGroup，所有权归调用方，语义清晰。
// 写入 goroutine 接受 <-chan []string 只读参数，不持有 opts 指针，
// 彻底消除跨 goroutine 修改共享字段的可能。
func startCSVWriter(path string, wg *sync.WaitGroup) chan []string {
	ch := make(chan []string, 200)
	wg.Add(1)
	go func(ch <-chan []string) {
		defer wg.Done()

		f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			fmt.Fprintf(os.Stderr, "无法打开 CSV 文件 %s: %v\n", path, err)
			for range ch { // 排空 channel，避免发送方在满缓冲时受影响
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
		if fi, err := f.Stat(); err == nil && fi.Size() == 0 {
			_ = w.Write([]string{"timestamp", "seq", "host", "ip", "port", "elapsed_ms", "success", "error", "local_addr"})
			w.Flush()
		}

		replacer := strings.NewReplacer("\n", " ", "\r", " ")
		for row := range ch {
			for i, v := range row {
				row[i] = replacer.Replace(v)
			}
			if err := w.Write(row); err != nil {
				fmt.Fprintf(os.Stderr, "CSV 写入错误: %v\n", err)
				continue
			}
			w.Flush()
			if err := w.Error(); err != nil {
				fmt.Fprintf(os.Stderr, "CSV flush 错误: %v\n", err)
			}
		}
		w.Flush()
		if err := w.Error(); err != nil {
			fmt.Fprintf(os.Stderr, "CSV 最终 flush 错误: %v\n", err)
		}
	}(ch)

	return ch
}

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

	host, port, err := validateOptions(opts, flag.Args())
	handleError(err, 1)

	opts.Host = host

	address, allIPs, err := resolveAddress(host, opts.UseIPv4, opts.UseIPv6)
	handleError(err, 1)

	ipType := "IPv4"
	ipAddress := address
	if strings.HasPrefix(address, "[") && strings.HasSuffix(address, "]") {
		ipType = "IPv6"
		ipAddress = address[1 : len(address)-1]
	}

	if net.ParseIP(host) == nil {
		fmt.Printf("正在对 %s [%s - %s] 端口 %s 执行 TCP Ping\n", host, ipType, ipAddress, port)
	} else {
		fmt.Printf("正在对 %s 端口 %s 执行 TCP Ping\n", host, port)
	}

	if opts.VerboseMode && len(allIPs) > 1 {
		fmt.Printf("域名 %s 解析到的所有IP地址:\n", host)
		for i, ip := range allIPs {
			if ip.To4() != nil {
				fmt.Printf("  [%d] IPv4: %s\n", i+1, ip.String())
			} else {
				fmt.Printf("  [%d] IPv6: %s\n", i+1, ip.String())
			}
		}
		fmt.Printf("使用IP地址: %s\n\n", ipAddress)
	}

	// FIX: WaitGroup 由 main() 持有并传入 startCSVWriter，所有权语义清晰。
	var csvWg sync.WaitGroup
	if opts.CSVAuto {
		opts.CSVPath = fmt.Sprintf("tcping_results_%s_%s.csv",
			sanitizeFilename(opts.Host), time.Now().Format("20060102-150405"))
		opts.CSVChan = startCSVWriter(opts.CSVPath, &csvWg)
	}

	stats := &Statistics{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	var pingWg sync.WaitGroup
	pingWg.Add(1)
	go func() {
		defer pingWg.Done()
		for i := 0; opts.Count == 0 || i < opts.Count; i++ {
			select {
			case <-ctx.Done():
				return
			default:
			}

			pingOnce(ctx, address, port, opts.Timeout, stats, i, ipAddress, opts)

			if opts.Count != 0 && i == opts.Count-1 {
				break
			}

			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Duration(opts.Interval) * time.Millisecond):
			}
		}
	}()

	done := make(chan struct{})
	go func() {
		pingWg.Wait()
		close(done)
	}()

	select {
	case <-interrupt:
		fmt.Printf("\n操作被中断。\n")
		cancel()
	case <-done:
	}

	pingWg.Wait()

	// 所有 ping 结束后关闭 channel，等待 CSV 写入 goroutine 排空队列。
	if opts.CSVChan != nil {
		close(opts.CSVChan)
		csvWg.Wait()
	}

	displayHost := ipAddress
	if net.ParseIP(host) == nil {
		displayHost = fmt.Sprintf("%s [%s]", host, ipAddress)
	}
	printTCPingStatistics(stats, opts, displayHost, port)
}
