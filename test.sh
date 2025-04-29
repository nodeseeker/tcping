#!/bin/bash


# 定义测试目标
IPV4_TARGET="1.1.1.1"
IPV6_TARGET="2606:4700:4700::1111"
DOMAIN_TARGET="cloudflare.com"
PORT="80"
HTTPS_PORT="443"

# 定义测试函数
function run_test() {
    echo "Running test: $1"
    echo "Command: $2"
    eval "$2"
    if [ $? -eq 0 ]; then
        echo "Test passed: $1"
    else
        echo "Test failed: $1"
    fi
    echo "-----------------------------------"
}

# 测试 IPv4 地址
run_test "IPv4 Address Test" "./tcping $IPV4_TARGET $PORT"

# 测试 IPv6 地址
run_test "IPv6 Address Test" "./tcping -6 $IPV6_TARGET $PORT"

# 测试域名解析 (IPv4)
run_test "Domain IPv4 Test" "./tcping $DOMAIN_TARGET $HTTPS_PORT"

# 测试域名解析 (IPv6)
run_test "Domain IPv6 Test" "./tcping -6 $DOMAIN_TARGET $HTTPS_PORT"

# 测试指定次数
run_test "Ping with Count Test" "./tcping -n 3 $IPV4_TARGET $PORT"

# 测试指定间隔时间
run_test "Ping with Interval Test" "./tcping -t 2 $IPV4_TARGET $PORT"

# 测试超时时间
run_test "Ping with Timeout Test" "./tcping -w 100 $IPV4_TARGET $PORT"

# 综合测试
run_test "Comprehensive Test" "./tcping -6 -n 5 -t 2 $DOMAIN_TARGET $HTTPS_PORT"
