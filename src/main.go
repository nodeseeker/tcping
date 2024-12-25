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
	version     = "v1.4.5"
	dividerLine = "------------------------------------------------------------"
)

// 优化统计结构
type Statistics struct {
	sync.Mutex
	sentCount      int
	respondedCount int
	minTime        float64
	maxTime        float64
	avgTime        float64 // 直接存储平均值，避免重复计算
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

	// 使用递推公式更新平均值
	s.avgTime = s.avgTime + (elapsed-s.avgTime)/float64(s.respondedCount)
	if elapsed < s.minTime {
		s.minTime = elapsed
	}
	if elapsed > s.maxTime {
		s.maxTime = elapsed
	}
}

// 统一的退出函数
func exit(code int, format string, args ...interface{}) {
	if format != "" {
		printError(format, args...)
	}
	os.Exit(code)
}

func printHelp() {
	fmt.Printf(`TCPing %s - TCP Connection Tester

Description:
    TCPing tests TCP connectivity to target host and port.

Usage: 
    tcping [options] <host> <port>

Options:
    -4              Force IPv4
    -6              Force IPv6
    -n <count>      Number of requests to send (default: infinite)
    -t <seconds>    Interval between requests (default: 1s)
    -w <ms>         Connection timeout (default: 1000ms)
    -v              Show version information
    -h              Show this help message

Examples:
    tcping google.com 80            # Basic usage
    tcping -4 -n 5 8.8.8.8 443      # IPv4, 5 requests
    tcping -w 2000 example.com 22   # 2 second timeout
`, version)
	os.Exit(0)
}

func printError(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", a...)
}

func printVersion() {
	fmt.Printf("TCPing version %s\n", version)
	fmt.Println("Copyright (c) 2024. All rights reserved.")
	os.Exit(0)
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
		printError("Cannot use both -4 and -6 flags together")
		os.Exit(1)
	}

	args := flag.Args()
	if len(args) < 2 {
		printError("Insufficient arguments")
		fmt.Println("\nUsage: tcping [options] <host> <port>")
		fmt.Println("Try 'tcping -h' for more information")
		os.Exit(1)
	}

	address := args[0]
	port := args[1]

	if err := validatePort(port); err != nil {
		printError("%v", err)
		os.Exit(1)
	}

	// 优化地址解析函数
	address = resolveAddress(address, *ipv4Flag || (!*ipv6Flag && isIPv4(address)),
		*ipv6Flag || isIPv6(address))

	fmt.Printf("TCPinging %s:%s...\n", address, port)
	stats := &Statistics{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		for i := 0; *countFlag == 0 || i < *countFlag; i++ {
			select {
			case <-ctx.Done():
				return
			default:
				pingOnce(address, port, *connectTimeoutFlag, stats)
				if *countFlag != 0 && i == *countFlag-1 {
					break
				}
				time.Sleep(time.Duration(*timeoutFlag) * time.Second)
			}
		}
		cancel()
	}()

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt, syscall.SIGTERM)

	select {
	case <-interrupt:
		fmt.Println("\nTcping interrupted.")
		cancel()
	case <-ctx.Done():
		fmt.Println("\nTcping completed.")
	}

	printTcpingStatistics(stats)
}

// 优化地址解析函数
func resolveAddress(address string, useIPv4, useIPv6 bool) string {
	// 如果已经是有效IP地址，直接返回
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

	ipList, err := net.LookupIP(address)
	if err != nil {
		exit(1, "Failed to resolve %s: %v", address, err)
	}

	if len(ipList) == 0 {
		exit(1, "No IP addresses found for %s", address)
	}

	// 如果指定了IP版本，只查找对应版本的地址
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

	// 未指定版本要求时，返回第一个地址
	ip := ipList[0]
	if ip.To4() == nil {
		return "[" + ip.String() + "]"
	}
	return ip.String()
}

func isIPv4(address string) bool {
	return strings.Count(address, ":") == 0
}

func isIPv6(address string) bool {
	return strings.Count(address, ":") >= 2
}

// 修改 pingOnce 函数使用浮点数计时
func pingOnce(address, port string, timeout int, stats *Statistics) {
	start := time.Now()
	conn, err := net.DialTimeout("tcp",
		address+":"+port,
		time.Duration(timeout)*time.Millisecond)
	elapsed := float64(time.Since(start).Microseconds()) / 1000.0 // 转换为毫秒的浮点数

	success := err == nil
	stats.update(elapsed, success)

	if !success {
		printError("Connection failed: %v", err)
		return
	}

	defer conn.Close()
	fmt.Printf("TCPing to %s:%s - time=%.3fms\n", address, port, elapsed)
}

// 优化统计信息打印
func printTcpingStatistics(stats *Statistics) {
	stats.Lock()
	defer stats.Unlock()

	fmt.Printf("\n%s\nTCPing Statistics:\n%s\n", dividerLine, dividerLine)

	if stats.sentCount > 0 {
		lossRate := float64(stats.sentCount-stats.respondedCount) / float64(stats.sentCount) * 100
		fmt.Printf("    Requests:  %d sent, %d received, %.1f%% loss\n",
			stats.sentCount, stats.respondedCount, lossRate)

		if stats.respondedCount > 0 {
			fmt.Printf("    Latency:   min=%.3fms, avg=%.3fms, max=%.3fms\n",
				stats.minTime, stats.avgTime, stats.maxTime)
		}
	}
	fmt.Println(dividerLine)
}
