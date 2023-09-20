package main

import (
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
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

	go ping(address, port, *countFlag, *timeoutFlag)

	select {
	case <-interrupt:
		fmt.Println("\nPing interrupted.")
		stopPing <- true
	case <-stopPing:
		fmt.Println("\nPing stopped.")
	}
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

func ping(address, port string, count, timeout int) {
	defer func() {
		stopPing <- true
	}()

	for i := 0; count == 0 || i < count; i++ {
		select {
		case <-stopPing:
			return
		default:
			start := time.Now()
			conn, err := net.DialTimeout("tcp", address+":"+port, time.Duration(timeout)*time.Second)
			if err != nil {
				fmt.Printf("Failed to connect to %s:%s: %v\n", address, port, err)
			} else {
				conn.Close()
				elapsed := time.Since(start).Milliseconds()
				fmt.Printf("tcping %s:%s in %dms\n", address, port, elapsed)
			}

			if count != 0 && i == count-1 {
				break
			}

			time.Sleep(time.Duration(timeout) * time.Second)
		}
	}
}
