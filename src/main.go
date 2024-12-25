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

const version = "v1.4.0"

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
    -v              Show version information
    -h              Show help information

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
		fmt.Println("Usage: tcping [-4] [-6] [-n count] [-t interval] [-w timeout] Address Port")
		os.Exit(1)
	}

	address := args[0]
	port := args[1]

	if err := validatePort(port); err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	if *ipv4Flag || (!*ipv6Flag && isIPv4(address)) {
		address = resolveAddress(address, "ipv4")
	} else if *ipv6Flag || isIPv6(address) {
		address = resolveAddress(address, "ipv6")
	} else {
		// Default to IPv4 if no -4 or -6 flags specified and address is not explicitly IPv6
		address = resolveAddress(address, "ipv4")
	}

	fmt.Printf("Pinging %s:%s...\n", address, port)
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

func validatePort(port string) error {
	portNum, err := strconv.Atoi(port)
	if err != nil {
		return fmt.Errorf("invalid port number format: %s", port)
	}

	if portNum <= 0 || portNum > 65535 {
		return fmt.Errorf("port number must be between 1 and 65535")
	}

	return nil
}

func resolveAddress(address, version string) string {
	ipList, err := net.LookupIP(address)
	if err != nil {
		fmt.Printf("Failed to resolve %s: %v\n", address, err)
		os.Exit(1)
	}

	for _, ip := range ipList {
		if version == "ipv4" && ip.To4() != nil {
			return ip.String()
		} else if version == "ipv6" && ip.To16() != nil && ip.To4() == nil {
			return "[" + ip.String() + "]"
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
