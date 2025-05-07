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
	version     = "v1.6.1"
	dividerLine = "------------------------------------------------------------"
	copyright   = "Copyright (c) 2025. All rights reserved."
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

func exit(code int, format string, args ...interface{}) {
	if format != "" {
		fmt.Fprintf(os.Stderr, "Error: "+format+"\n", args...)
	}
	os.Exit(code)
}

func printHelp() {
	fmt.Printf(`%s %s - TCP Connection Tester

Description:
    %s tests TCP connectivity to target host and port.

Usage: 
    tcping [options] <host> [port]      (default port: 80)

Options:
    -4              Force IPv4
    -6              Force IPv6
    -n <count>      Number of requests to send (default: infinite)
    -t <seconds>    Interval between requests (default: 1s)
    -w <ms>         Connection timeout (default: 1000ms)
    -v              Show version information
    -h              Show this help message

Examples:
    tcping google.com				# Basic usage (default port 80)
    tcping google.com 80         	# Basic usage with explicit port
    tcping -4 -n 5 8.8.8.8 443   	# IPv4, 5 requests
    tcping -w 2000 example.com 22  	# 2 second timeout
    tcping -4 -n 5 134744072 443   	# IPv4 in decimal format, 8.8.8.8
    tcping 0x08080808 80           	# IPv4 in hex format, 8.8.8.8

`, programName, version, programName)
	exit(0, "")
}

func printVersion() {
	fmt.Printf("%s version %s\n", programName, version)
	fmt.Println(copyright)
	exit(0, "")
}

func validatePort(port string) error {
	portNum, err := strconv.Atoi(port)
	if err != nil {
		return fmt.Errorf("invalid port number format")
	}
	if portNum <= 0 || portNum > 65535 {
		return fmt.Errorf("port number must be between 1 and 65535")
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
			exit(1, "Decimal format is not supported for IPv6 addresses")
		}
		lowerAddr := strings.ToLower(address)
		if strings.HasPrefix(lowerAddr, "0x") {
			if _, err := strconv.ParseUint(strings.TrimPrefix(lowerAddr, "0x"), 16, 32); err == nil {
				exit(1, "Hexadecimal format is not supported for IPv6 addresses")
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
			exit(1, "Address %s is not an IPv4 address", address)
		}
		if useIPv6 && isV4 {
			exit(1, "Address %s is not an IPv6 address", address)
		}
		if !isV4 {
			return "[" + ip.String() + "]"
		}
		return ip.String()
	}

	// Finally try DNS resolution
	ipList, err := net.LookupIP(address)
	if err != nil {
		exit(1, "Failed to resolve %s: %v", address, err)
	}

	if len(ipList) == 0 {
		exit(1, "No IP addresses found for %s", address)
	}

	if useIPv4 {
		for _, ip := range ipList {
			if ip.To4() != nil {
				return ip.String()
			}
		}
		exit(1, "No IPv4 address found for %s", address)
	}

	if useIPv6 {
		for _, ip := range ipList {
			if ip.To4() == nil {
				return "[" + ip.String() + "]"
			}
		}
		exit(1, "No IPv6 address found for %s", address)
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

func pingOnce(address, port string, timeout int, stats *Statistics) {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", address+":"+port, time.Duration(timeout)*time.Millisecond)
	elapsed := float64(time.Since(start).Microseconds()) / 1000.0

	success := err == nil
	stats.update(elapsed, success)

	if !success {
		fmt.Printf("%s to %s:%s - failed: %v\n", programName, address, port, err)
		return
	}

	defer conn.Close()
	fmt.Printf("%s to %s:%s - time=%.3fms\n", programName, address, port, elapsed)
}

func printTCPingStatistics(stats *Statistics) {
	stats.Lock()
	defer stats.Unlock()

	fmt.Printf("\n%s\n%s Statistics:\n%s\n", dividerLine, programName, dividerLine)

	if stats.sentCount > 0 {
		lossRate := float64(stats.sentCount-stats.respondedCount) / float64(stats.sentCount) * 100
		fmt.Printf("    Requests:  %d sent, %d received, %.1f%% loss\n",
			stats.sentCount, stats.respondedCount, lossRate)

		if stats.respondedCount > 0 {
			fmt.Printf("    Latency:   min = %.3fms, avg = %.3fms, max = %.3fms\n",
				stats.minTime, stats.avgTime, stats.maxTime)
		}
	}
	fmt.Println(dividerLine)
}

func main() {
	ipv4Flag := flag.Bool("4", false, "Ping IPv4 address")
	ipv6Flag := flag.Bool("6", false, "Ping IPv6 address")
	countFlag := flag.Int("n", 0, "Number of pings (default: infinite)")
	timeoutFlag := flag.Int("t", 1, "Time interval between pings in seconds")
	versionFlag := flag.Bool("v", false, "Show version information")
	helpFlag := flag.Bool("h", false, "Show help information")
	connectTimeoutFlag := flag.Int("w", 1000, "Connection timeout in milliseconds")
	flag.Parse()

	if *helpFlag {
		printHelp()
	}

	if *versionFlag {
		printVersion()
	}

	if *ipv4Flag && *ipv6Flag {
		exit(1, "Cannot use both -4 and -6 flags together")
	}

	args := flag.Args()
	if len(args) < 1 {
		exit(1, "Host argument is required\n\nUsage: tcping [options] <host> [port]\nTry 'tcping -h' for more information")
	}

	address := args[0]
	port := "80" // 默认端口为 80
	if len(args) > 1 {
		port = args[1]
	}

	if err := validatePort(port); err != nil {
		exit(1, "%v", err)
	}

	address = resolveAddress(address, *ipv4Flag || (!*ipv6Flag && isIPv4(address)),
		*ipv6Flag || isIPv6(address))

	fmt.Printf("%sing %s:%s...\n", programName, address, port)
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
		for i := 0; *countFlag == 0 || i < *countFlag; i++ {
			// 首先检查是否已收到中断信号
			select {
			case <-ctx.Done():
				return
			default:
				// 继续执行
			}

			pingOnce(address, port, *connectTimeoutFlag, stats)

			if *countFlag != 0 && i == *countFlag-1 {
				break pingLoop
			}

			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Duration(*timeoutFlag) * time.Second):
				// 继续下一次 ping
			}
		}
		cancel()
	}()

	// 等待中断信号或完成
	select {
	case <-interrupt:
		fmt.Printf("\n%s interrupted.\n", programName)
		cancel()
	case <-ctx.Done():
		fmt.Printf("\n%s completed.\n", programName)
	}

	// 等待 goroutine 完成
	wg.Wait()
	printTCPingStatistics(stats)
}
