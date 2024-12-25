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

const version = "v1.4.1"

type Statistics struct {
	sync.Mutex
	sentCount         int
	respondedCount    int
	minTime           int64
	maxTime           int64
	totalResponseTime int64
}

func init() {
	flag.Usage = func() {
		helpText := `Usage: tcping [options] address port

Options:
    -4               Ping IPv4 address
    -6               Ping IPv6 address
    -n count         Number of pings (default: infinite)
    -t seconds       Time interval between pings
    -w milliseconds  Connection timeout
    -v               Show version information
    -h               Show help information

Examples:
    tcping google.com 80
    tcping -4 -n 5 -t 2 8.8.8.8 53
    tcping -6 -w 2000 2001:4860:4860::8888 443
`
		fmt.Fprintf(os.Stderr, "%s\n", strings.TrimSpace(helpText))
	}
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
		flag.Usage()
		os.Exit(0)
	}

	if *versionFlag {
		fmt.Printf("tcping version %s\n", version)
		os.Exit(0)
	}

	if *ipv4Flag && *ipv6Flag {
		fmt.Println("Both -4 and -6 flags cannot be used together.")
		os.Exit(1)
	}

	args := flag.Args()
	if len(args) < 2 {
		flag.Usage()
		os.Exit(1)
	}

	address := args[0]
	port := args[1]

	// 验证并获取端口数值
	portNum := validatePort(port)

	// 使用验证后的端口数值
	address = resolveAddress(address, getAddressType(address, *ipv4Flag, *ipv6Flag))
	fmt.Printf("Pinging %s:%d...\n", address, portNum)

	stats := &Statistics{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		for i := 0; *countFlag == 0 || i < *countFlag; i++ {
			select {
			case <-ctx.Done():
				return
			default:
				// 使用数值端口而不是字符串
				pingOnce(address, strconv.Itoa(portNum), *connectTimeoutFlag, stats)
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

// 修改端口验证函数，返回检验后的数值端口
func validatePort(port string) int {
	portNum, err := strconv.Atoi(port)
	if err != nil {
		fmt.Println("Error: port must be a number")
		os.Exit(1)
	}

	if portNum < 1 || portNum > 65535 {
		fmt.Printf("Error: port %d is invalid (must be between 1 and 65535)\n", portNum)
		os.Exit(1)
	}

	return portNum
}

// 简化地址类型判断
func getAddressType(address string, ipv4, ipv6 bool) string {
	if ipv4 {
		return "ipv4"
	}
	if ipv6 {
		return "ipv6"
	}
	if isIPv6(address) {
		return "ipv6"
	}
	return "ipv4"
}

// 简化地址解析函数
func resolveAddress(address, version string) string {
	ipList, err := net.LookupIP(address)
	if err != nil {
		fmt.Printf("Failed to resolve %s: %v\n", address, err)
		os.Exit(1)
	}

	for _, ip := range ipList {
		switch version {
		case "ipv4":
			if ip.To4() != nil {
				return ip.String()
			}
		case "ipv6":
			if ip.To16() != nil && ip.To4() == nil {
				return "[" + ip.String() + "]"
			}
		}
	}

	fmt.Printf("No %s addresses found for %s\n", version, address)
	os.Exit(1)
	return ""
}

func isIPv4(address string) bool {
	return strings.Count(address, ":") == 0
}

func isIPv6(address string) bool {
	return strings.Count(address, ":") >= 2
}

func pingOnce(address, port string, timeout int, stats *Statistics) {
	start := time.Now()
	conn, err := net.DialTimeout("tcp",
		address+":"+port,
		time.Duration(timeout)*time.Millisecond)
	elapsed := time.Since(start).Milliseconds()

	stats.Lock()
	defer stats.Unlock()

	stats.sentCount++
	if err != nil {
		fmt.Printf("Failed to connect to %s:%s: %v\n", address, port, err)
		return
	}

	defer conn.Close()
	stats.respondedCount++
	if stats.respondedCount == 1 || elapsed < stats.minTime {
		stats.minTime = elapsed
	}
	if elapsed > stats.maxTime {
		stats.maxTime = elapsed
	}
	stats.totalResponseTime += elapsed
	fmt.Printf("tcping %s:%s in %dms\n", address, port, elapsed)
}

func printTcpingStatistics(stats *Statistics) {
	stats.Lock()
	defer stats.Unlock()

	fmt.Println("\n--- Tcping Statistics ---")
	lossRate := float64(stats.sentCount-stats.respondedCount) / float64(stats.sentCount) * 100
	fmt.Printf("%d tcp ping sent, %d tcp ping responsed, %.2f%% loss\n",
		stats.sentCount, stats.respondedCount, lossRate)

	if stats.respondedCount > 0 {
		avgTime := stats.totalResponseTime / int64(stats.respondedCount)
		fmt.Printf("min/avg/max = %dms/%dms/%dms\n",
			stats.minTime, avgTime, stats.maxTime)
	} else {
		fmt.Println("No responses received.")
	}
}
