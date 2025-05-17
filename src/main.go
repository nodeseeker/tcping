package main

import (
	"context"
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
	version     = "v1.6.4" // 更新版本号
	dividerLine = "------------------------------------------------------------"
	copyright   = "Copyright (c) 2023. All rights reserved." // 更新版权年份
	programName = "TCPing"
)

type Statistics struct {
	sync.Mutex
	sentCount      int
	respondedCount int
	minTime        float64
	maxTime        float64
	avgTime        float64
}

func (s *Statistics) update(elapsed float64, success bool) {
	s.Lock()
	defer s.Unlock()

	s.sentCount++
	if !success {
		return
	}

	s.respondedCount++
	if s.respondedCount == 1 {
		s.minTime = elapsed
		s.maxTime = elapsed
		s.avgTime = elapsed
		return
	}

	s.avgTime = s.avgTime + (elapsed-s.avgTime)/float64(s.respondedCount)
	if elapsed < s.minTime {
		s.minTime = elapsed
	}
	if elapsed > s.maxTime {
		s.maxTime = elapsed
	}
}

// 添加新的控制选项结构
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
	Port        int // 新增: 通过-p参数指定的端口
}

func exit(code int, format string, args ...interface{}) {
	if format != "" {
		fmt.Fprintf(os.Stderr, "错误: "+format+"\n", args...)
	}
	os.Exit(code)
}

func printHelp() {
	fmt.Printf(`%s %s - TCP 连接测试工具

描述:
    %s 测试到目标主机和端口的TCP连接性。

用法: 
    tcping [选项] <主机> [端口]      (默认端口: 80)

选项:
    -4              强制使用 IPv4
    -6              强制使用 IPv6
    -n <次数>       发送请求的次数 (默认: 无限)
    -p <端口>       指定要连接的端口 (默认: 80)
    -t <秒>         请求之间的间隔 (默认: 1秒)
    -w <毫秒>       连接超时 (默认: 1000毫秒)
    -c              启用彩色输出
    -V              启用详细模式，显示更多连接信息
    -v              显示版本信息
    -h              显示此帮助信息

示例:
    tcping google.com                # 基本用法 (默认端口 80)
    tcping google.com 80             # 基本用法指定端口
    tcping -p 443 google.com         # 使用-p参数指定端口
    tcping -4 -n 5 8.8.8.8 443       # IPv4, 5次请求
    tcping -w 2000 example.com 22    # 2秒超时
    tcping -4 -n 5 134744072 443     # 十进制IPv4格式, 8.8.8.8
    tcping 0x08080808 80             # 十六进制IPv4格式, 8.8.8.8
    tcping -c -V example.com 443     # 彩色输出和详细模式

`, programName, version, programName)
	exit(0, "")
}

func printVersion() {
	fmt.Printf("%s 版本 %s\n", programName, version)
	fmt.Println(copyright)
	exit(0, "")
}

func validatePort(port string) error {
	portNum, err := strconv.Atoi(port)
	if err != nil {
		return fmt.Errorf("端口号格式无效")
	}
	if portNum <= 0 || portNum > 65535 {
		return fmt.Errorf("端口号必须在 1 到 65535 之间")
	}
	return nil
}

func parseNumericIPv4(address string) net.IP {
	// Try decimal first
	if decIP, err := strconv.ParseUint(address, 10, 32); err == nil {
		return net.IPv4(
			byte(decIP>>24),
			byte(decIP>>16),
			byte(decIP>>8),
			byte(decIP),
		).To4()
	}

	// Try hexadecimal (with or without 0x prefix)
	addr := strings.ToLower(address)
	addr = strings.TrimPrefix(addr, "0x")
	if hexIP, err := strconv.ParseUint(addr, 16, 32); err == nil {
		return net.IPv4(
			byte(hexIP>>24),
			byte(hexIP>>16),
			byte(hexIP>>8),
			byte(hexIP),
		).To4()
	}

	return nil
}

func resolveAddress(address string, useIPv4, useIPv6 bool) string {
	// 新增判断：如果使用 IPv6 且地址为数字（decimal 或 hex）格式，则直接报错提示
	if useIPv6 {
		if _, err := strconv.ParseUint(address, 10, 32); err == nil {
			exit(1, "IPv6 地址不支持十进制格式")
		}
		lowerAddr := strings.ToLower(address)
		if strings.HasPrefix(lowerAddr, "0x") {
			if _, err := strconv.ParseUint(strings.TrimPrefix(lowerAddr, "0x"), 16, 32); err == nil {
				exit(1, "IPv6 地址不支持十六进制格式")
			}
		}
	}

	// First try numeric IPv4 formats if IPv4 is requested or not explicitly IPv6
	if useIPv4 || !useIPv6 {
		if ip := parseNumericIPv4(address); ip != nil {
			return ip.String()
		}
	}

	// Then try standard IP parsing
	if ip := net.ParseIP(address); ip != nil {
		isV4 := ip.To4() != nil
		if useIPv4 && !isV4 {
			exit(1, "地址 %s 不是 IPv4 地址", address)
		}
		if useIPv6 && isV4 {
			exit(1, "地址 %s 不是 IPv6 地址", address)
		}
		if !isV4 {
			return "[" + ip.String() + "]"
		}
		return ip.String()
	}

	// Finally try DNS resolution
	ipList, err := net.LookupIP(address)
	if err != nil {
		exit(1, "解析 %s 失败: %v", address, err)
	}

	if len(ipList) == 0 {
		exit(1, "未找到 %s 的 IP 地址", address)
	}

	if useIPv4 {
		for _, ip := range ipList {
			if ip.To4() != nil {
				return ip.String()
			}
		}
		exit(1, "未找到 %s 的 IPv4 地址", address)
	}

	if useIPv6 {
		for _, ip := range ipList {
			if ip.To4() == nil {
				return "[" + ip.String() + "]"
			}
		}
		exit(1, "未找到 %s 的 IPv6 地址", address)
	}

	ip := ipList[0]
	if ip.To4() == nil {
		return "[" + ip.String() + "]"
	}
	return ip.String()
}

func isIPv4(address string) bool {
	if parseNumericIPv4(address) != nil {
		return true
	}
	return net.ParseIP(address) != nil && strings.Count(address, ":") == 0
}

func isIPv6(address string) bool {
	return strings.Count(address, ":") >= 2
}

// 修改函数签名，添加context参数
func pingOnce(ctx context.Context, address, port string, timeout int, stats *Statistics, seq int, ip string,
	opts *Options) {
	// 创建可取消的连接上下文
	dialCtx, dialCancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Millisecond)
	defer dialCancel()

	start := time.Now()
	var d net.Dialer
	conn, err := d.DialContext(dialCtx, "tcp", address+":"+port)
	elapsed := float64(time.Since(start).Microseconds()) / 1000.0

	// 检查错误是否是由于上下文取消导致的
	if err != nil && (ctx.Err() == context.Canceled || dialCtx.Err() == context.Canceled) {
		// 如果是因为取消操作导致的错误，不更新统计信息
		msg := "\n操作被中断, 连接尝试已中止\n"
		fmt.Print(infoText(msg, opts.ColorOutput))
		return
	}

	success := err == nil
	stats.update(elapsed, success)

	if !success {
		// 修改错误消息格式，去除重复的IP:端口信息
		errMsg := fmt.Sprintf("%v", err)

		// 创建更精确的匹配模式，确保删除错误中的IP:端口
		targetAddr := address + ":" + port
		if strings.Contains(errMsg, targetAddr) {
			// 替换所有包含IP:端口的部分
			errParts := strings.Split(errMsg, targetAddr)
			if len(errParts) > 1 {
				// 重新组装错误信息，跳过IP:端口部分
				if strings.HasPrefix(errMsg, "dial ") {
					prefix := strings.Split(errMsg, targetAddr)[0]
					suffix := strings.Join(strings.Split(errMsg, targetAddr)[1:], "")
					errMsg = prefix + suffix
				}
			}
		}

		msg := fmt.Sprintf("TCP连接失败 %s:%s: seq=%d 错误=%s\n", ip, port, seq, errMsg)
		fmt.Print(errorText(msg, opts.ColorOutput))

		if opts.VerboseMode {
			fmt.Printf("  详细信息: 连接尝试耗时 %.2fms, 目标 %s:%s\n", elapsed, address, port)
		}
		return
	}

	defer conn.Close()
	msg := fmt.Sprintf("从 %s:%s 收到响应: seq=%d time=%.2fms\n", ip, port, seq, elapsed)
	fmt.Print(successText(msg, opts.ColorOutput))

	if opts.VerboseMode {
		localAddr := conn.LocalAddr().String()
		fmt.Printf("  详细信息: 本地地址=%s, 远程地址=%s:%s\n", localAddr, ip, port)
	}
}

func printTCPingStatistics(stats *Statistics) {
	stats.Lock()
	defer stats.Unlock()

	fmt.Printf("\n\n--- 目标主机 TCP ping 统计 ---\n")

	if stats.sentCount > 0 {
		lossRate := float64(stats.sentCount-stats.respondedCount) / float64(stats.sentCount) * 100
		fmt.Printf("已发送 = %d, 已接收 = %d, 丢失 = %d (%.1f%% 丢失)\n",
			stats.sentCount, stats.respondedCount, stats.sentCount-stats.respondedCount, lossRate)

		if stats.respondedCount > 0 {
			fmt.Printf("往返时间(RTT): 最小 = %.2fms, 最大 = %.2fms, 平均 = %.2fms\n",
				stats.minTime, stats.maxTime, stats.avgTime)
		}
	}
}

func colorize(text string, colorCode string, useColor bool) string {
	if !useColor {
		return text
	}
	return "\033[" + colorCode + "m" + text + "\033[0m"
}

func successText(text string, useColor bool) string {
	return colorize(text, "32", useColor) // 绿色
}

func errorText(text string, useColor bool) string {
	return colorize(text, "31", useColor) // 红色
}

func infoText(text string, useColor bool) string {
	return colorize(text, "36", useColor) // 青色
}

func main() {
	// 创建选项结构
	opts := &Options{}

	// 解析命令行参数
	flag.BoolVar(&opts.UseIPv4, "4", false, "使用 IPv4 地址")
	flag.BoolVar(&opts.UseIPv6, "6", false, "使用 IPv6 地址")
	flag.IntVar(&opts.Count, "n", 0, "发送请求次数 (默认: 无限)")
	flag.IntVar(&opts.Interval, "t", 1, "请求间隔（秒）")
	flag.IntVar(&opts.Timeout, "w", 1000, "连接超时（毫秒）")
	flag.IntVar(&opts.Port, "p", 0, "指定要连接的端口 (默认: 80)")
	flag.BoolVar(&opts.ColorOutput, "c", false, "启用彩色输出")
	flag.BoolVar(&opts.VerboseMode, "V", false, "启用详细模式")
	flag.BoolVar(&opts.ShowVersion, "v", false, "显示版本信息")
	flag.BoolVar(&opts.ShowHelp, "h", false, "显示帮助信息")
	flag.Parse()

	// 参数验证
	if opts.ShowHelp {
		printHelp()
	}

	if opts.ShowVersion {
		printVersion()
	}

	if opts.UseIPv4 && opts.UseIPv6 {
		exit(1, "无法同时使用 -4 和 -6 标志")
	}

	if opts.Interval < 0 {
		exit(1, "间隔时间不能为负值")
	}

	if opts.Timeout < 0 {
		exit(1, "超时时间不能为负值")
	}

	args := flag.Args()
	if len(args) < 1 {
		exit(1, "需要提供主机参数\n\n用法: tcping [选项] <主机> [端口]\n尝试 'tcping -h' 获取更多信息")
	}

	host := args[0]
	port := "80" // 默认端口为 80

	// 优先级：命令行直接指定的端口 > -p参数指定的端口 > 默认端口80
	if len(args) > 1 {
		port = args[1]
	} else if opts.Port > 0 {
		// 如果通过-p参数指定了端口且命令行没有直接指定端口，则使用-p参数的值
		if opts.Port > 65535 {
			exit(1, "端口号必须在 1 到 65535 之间")
		}
		port = strconv.Itoa(opts.Port)
	}

	if err := validatePort(port); err != nil {
		exit(1, "%v", err)
	}

	useIPv4 := opts.UseIPv4 || (!opts.UseIPv6 && isIPv4(host))
	useIPv6 := opts.UseIPv6 || isIPv6(host)

	// 保存原始主机名用于显示
	originalHost := host

	// 解析IP地址
	address := resolveAddress(host, useIPv4, useIPv6)

	// 提取IP地址用于显示
	ipType := "IPv4"
	ipAddress := address
	if strings.HasPrefix(address, "[") && strings.HasSuffix(address, "]") {
		ipType = "IPv6"
		ipAddress = address[1 : len(address)-1]
	}

	fmt.Printf("正在对 %s (%s - %s) 端口 %s 执行 TCP Ping\n", originalHost, ipType, ipAddress, port)
	stats := &Statistics{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 创建信号捕获通道
	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt, syscall.SIGTERM, syscall.SIGINT)

	// 使用 WaitGroup 来确保后台 goroutine 正确退出
	var wg sync.WaitGroup
	wg.Add(1)

	go func() {
		defer wg.Done()
	pingLoop:
		for i := 0; opts.Count == 0 || i < opts.Count; i++ {
			// 首先检查是否已收到中断信号
			select {
			case <-ctx.Done():
				return
			default:
				// 继续执行
			}

			// 更新函数调用，传递context和序列号
			{
				pingOnce(ctx, address, port, opts.Timeout, stats, i, ipAddress, opts)
			}

			if opts.Count != 0 && i == opts.Count-1 {
				break pingLoop
			}

			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Duration(opts.Interval) * time.Second):
				// 继续下一次 ping
			}
		}
		cancel()
	}()

	// 等待中断信号或完成
	select {
	case <-interrupt:
		fmt.Printf("\n操作被中断。\n")
		cancel()
	case <-ctx.Done():
		// 静默完成
	}

	// 等待 goroutine 完成
	wg.Wait()
	printTCPingStatistics(stats)
}
