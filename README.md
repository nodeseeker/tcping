# TCPing

一款基于Golang的TCP Ping工具，支持IPv4、IPv6和域名，以及自定义端口、次数和间隔时间。支持彩色输出和详细的连接信息展示。

## 使用教程
### 安装方法

浏览器打开程序的发布页 [https://github.com/nodeseeker/tcping/releases](https://github.com/nodeseeker/tcping/releases)，在列表中找到对应CPU架构和平台的程序（如下图），比如x86_64的Linux系统，下载`tcping-linux-amd64.zip`，而x86_64的Windows，则下载`tcping-windows-amd64.zip`。下载完成后，解压即可得到一个名为`tcping`的文件，直接运行即可。

为了方便使用，建议将`tcping`文件移动到系统的`PATH环境变量`中或者`bin`目录中，这样就可以在任何目录下直接使用`tcping`命令：
- 如果是Linux平台，建议使用root用户将文件移动到`/usr/bin`中
- 如果是Windows平台，建议向PATH环境变量中添加工具位置或放置于`C:\Windows\System32`系统目录中
- 如果是macOS平台，建议直接将文件移动到`/usr/local/bin`中

![releases_example](https://raw.githubusercontent.com/nodeseeker/tcping/refs/heads/main/assets/tcping_releases.jpg)

目前支持的多架构多平台如下：

```
- linux系统：amd64/386/arm64/arm/loong64
- windows系统：386/amd64/arm/arm64
- macOS/darwin系统：amd64/arm64
```

### 使用方法

**TCPing** 工具提供了多种选项来满足不同的网络测试需求：

```
tcping [选项] <主机> [端口]
```

#### 命令行选项

| 短选项 | 长选项      | 描述                             | 默认值    |
|------|------------|----------------------------------|----------|
| -4   | --ipv4     | 强制使用 IPv4                      | 自动检测   |
| -6   | --ipv6     | 强制使用 IPv6                      | 自动检测   |
| -n   | --count    | 发送请求的次数                      | 无限      |
| -p   | --port     | 指定要连接的端口                    | 80       |
| -t   | --interval | 请求之间的间隔（秒）                 | 1秒       |
| -w   | --timeout  | 连接超时（毫秒）                    | 1000毫秒  |
| -c   | --color    | 启用彩色输出                        | 关闭      |
| -v   | --verbose  | 启用详细模式，显示更多连接信息         | 关闭      |
| -V   | --version  | 显示版本信息                        | -        |
| -h   | --help     | 显示帮助信息                        | -        |

#### 特殊地址格式支持

TCPing 支持多种IPv4地址格式：
- 标准点分十进制格式 (如 `8.8.8.8`)
- 十进制整数格式 (如 `134744072` 等同于 `8.8.8.8`)
- 十六进制格式 (如 `0x08080808` 等同于 `8.8.8.8`)

## 使用示例

### 基本用法

测试 Google DNS 服务器的 TCP 连接：

```
$ tcping 8.8.8.8 53
正在对 8.8.8.8 (IPv4 - 8.8.8.8) 端口 53 执行 TCP Ping
从 8.8.8.8:53 收到响应: seq=0 time=9.36ms
从 8.8.8.8:53 收到响应: seq=1 time=8.40ms
从 8.8.8.8:53 收到响应: seq=2 time=8.91ms
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 3, 已接收 = 3, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 8.40ms, 最大 = 9.36ms, 平均 = 8.89ms
```

### 指定次数和间隔

发送5次请求，每次间隔2秒：

```
$ tcping -n 5 -t 2 example.com 443
正在对 example.com (IPv4 - 93.184.216.34) 端口 443 执行 TCP Ping
从 93.184.216.34:443 收到响应: seq=0 time=142.93ms
从 93.184.216.34:443 收到响应: seq=1 time=138.45ms
从 93.184.216.34:443 收到响应: seq=2 time=140.12ms
从 93.184.216.34:443 收到响应: seq=3 time=137.68ms
从 93.184.216.34:443 收到响应: seq=4 time=139.74ms

--- 目标主机 TCP ping 统计 ---
已发送 = 5, 已接收 = 5, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 137.68ms, 最大 = 142.93ms, 平均 = 139.78ms
```

### 强制使用IPv6

测试IPv6连接：

```
$ tcping -6 ipv6.google.com 443
正在对 ipv6.google.com (IPv6 - 2404:6800:4003:c04::8b) 端口 443 执行 TCP Ping
从 2404:6800:4003:c04::8b:443 收到响应: seq=0 time=36.24ms
从 2404:6800:4003:c04::8b:443 收到响应: seq=1 time=35.87ms
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 2, 已接收 = 2, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 35.87ms, 最大 = 36.24ms, 平均 = 36.06ms
```

### 详细模式和彩色输出

启用详细信息显示和彩色输出：

```
$ tcping -c -v github.com 443
正在对 github.com (IPv4 - 20.205.243.166) 端口 443 执行 TCP Ping
从 20.205.243.166:443 收到响应: seq=0 time=138.45ms
  详细信息: 本地地址=192.168.1.100:50123, 远程地址=20.205.243.166:443
从 20.205.243.166:443 收到响应: seq=1 time=140.12ms
  详细信息: 本地地址=192.168.1.100:50124, 远程地址=20.205.243.166:443
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 2, 已接收 = 2, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 138.45ms, 最大 = 140.12ms, 平均 = 139.29ms
```

### 自定义超时时间

设置短超时时间（例如100毫秒）以快速诊断问题：

```
$ tcping -w 100 slow-server.example.com 80
正在对 slow-server.example.com (IPv4 - 203.0.113.1) 端口 80 执行 TCP Ping
TCP连接失败 203.0.113.1:80: seq=0 错误=连接超时
TCP连接失败 203.0.113.1:80: seq=1 错误=连接超时
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 2, 已接收 = 0, 丢失 = 2 (100.0% 丢失)
```

### 高级用法

使用十进制整数IP地址格式：

```
$ tcping 134744072 443
正在对 134744072 (IPv4 - 8.8.8.8) 端口 443 执行 TCP Ping
...
```

使用十六进制IP地址格式：

```
$ tcping 0x08080808 80
正在对 0x08080808 (IPv4 - 8.8.8.8) 端口 80 执行 TCP Ping
...
```

## 常见问题

1. **为什么需要使用TCPing而不是普通的ping？**  
   普通的ping使用ICMP协议，而TCPing使用TCP协议。有些网络环境下可能ICMP报文被过滤或屏蔽，但TCP连接仍然可用。TCPing可以测试特定端口的连通性和响应时间，这是普通ping无法做到的。

2. **为什么有些域名无法进行IPv6测试？**  
   这可能是因为该域名没有配置AAAA记录（IPv6解析记录）。可以先通过DNS查询工具确认域名是否支持IPv6解析。

3. **彩色输出功能在某些终端不起作用？**  
   某些终端（特别是Windows的cmd）可能不支持ANSI颜色代码。在这些环境下，可能需要使用支持ANSI的终端（如Windows Terminal）或不使用 `-c` 选项。

4. **程序在高负载网络下测试结果不准确？**  
   高负载网络环境可能导致TCP连接建立时间变长，这会影响测试结果。可以考虑多次测试并关注统计结果而非单次测试值。

5. **如何使用TCPing进行长期监控？**  
   可以使用 `-n` 参数设置一个大的值（如 `-n 1000`）并将输出重定向到文件，例如：`tcping -n 1000 example.com 443 > results.log`

## 自行编译

程序使用纯Golang编写，可以自己编译，编译方法如下：

```bash
CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH go build -trimpath -ldflags="-w -s" -o "$OUT_FILE" $SRC_PATH
```

其中：
- `$GOOS` 是目标操作系统（如 linux, windows, darwin）
- `$GOARCH` 是目标CPU架构（如 amd64, 386, arm64）
- `$SRC_PATH` 是源代码路径
- `$OUT_FILE` 是输出文件路径

此外，也提供了批量编译脚本`complier.sh`，可以直接运行，但需要修改脚本中的目标平台和架构。
