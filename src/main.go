package main

import (
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var stopPing chan bool

func main() {
	ipv4Flag := flag.Bool("4", false, "Ping IPv4 address")
	ipv6Flag := flag.Bool("6", false, "Ping IPv6 address")
	countFlag := flag.Int("n", 0, "Number of pings (default: infinite)")
	timeoutFlag := flag.Int("t", 1, "Time interval between pings in seconds")
	flag.Parse()

	if *ipv4Flag && *ipv6Flag {
		fmt.Println("Both -4 and -6 flags cannot be used together.")
		os.Exit(1)
	}

	args := flag.Args()
	if len(args) < 2 {
		fmt.Println("Usage: tcping [-4] [-6] [-n count] [-t timeout] address port")
		os.Exit(1)
	}

	address := args[0]
	port := args[1]

	if _, err := strconv.Atoi(port); err != nil || port == "0" {
		fmt.Println("Invalid port number.")
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
	stopPing = make(chan bool, 1)
	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt, syscall.SIGTERM)

	var sentCount int
	var respondedCount int
	var minTime, maxTime, totalResponseTime int64

	go func() {
		for i := 0; *countFlag == 0 || i < *countFlag; i++ {
			select {
			case <-stopPing:
				return
			default:
				start := time.Now()
				conn, err := net.DialTimeout("tcp", address+":"+port, time.Duration(*timeoutFlag)*time.Second)
				elapsed := time.Since(start).Milliseconds()

				sentCount++
				if err != nil {
					fmt.Printf("Failed to connect to %s:%s: %v\n", address, port, err)
				} else {
					conn.Close()
					respondedCount++
					if respondedCount == 1 || elapsed < minTime {
						minTime = elapsed
					}
					if elapsed > maxTime {
						maxTime = elapsed
					}
					totalResponseTime += elapsed
					fmt.Printf("tcping %s:%s in %dms\n", address, port, elapsed)
				}

				if *countFlag != 0 && i == *countFlag-1 {
					break
				}

				time.Sleep(time.Duration(*timeoutFlag) * time.Second)
			}
		}
		stopPing <- true
	}()

	select {
	case <-interrupt:
		fmt.Println("\nPing interrupted.")
		stopPing <- true
	case <-stopPing:
		fmt.Println("\nPing stopped.")
	}

	printTcpingStatistics(sentCount, respondedCount, minTime, maxTime, totalResponseTime)
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

func printTcpingStatistics(sentCount, respondedCount int, minTime, maxTime, totalResponseTime int64) {
	fmt.Println("")
	fmt.Println("--- Tcping Statistics ---")
	fmt.Printf("%d tcp ping sent, %d tcp ping responsed, %.2f%% loss\n", sentCount, respondedCount, float64(sentCount-respondedCount)/float64(sentCount)*100)
	if respondedCount > 0 {
		fmt.Printf("min/avg/max = %dms/%dms/%dms\n", minTime, totalResponseTime/int64(respondedCount), maxTime)
	} else {
		fmt.Println("No responses received.")
	}
}
