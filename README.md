# TCPing

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Go Version](https://img.shields.io/badge/Go-1.25+-blue.svg)](https://golang.org/)
[![Version](https://img.shields.io/badge/Version-v1.7.4-green.svg)](https://github.com/nodeseeker/tcping/releases)

一款基于Golang的高性能TCP Ping工具，支持IPv4、IPv6和域名解析，提供丰富的自定义选项和详细的连接信息展示。


## ✨ 功能概述

**TCPing** 是一个轻量级、高效的 TCP 连接测试工具，具备以下特性：



### 🌐 多协议支持
- 支持 IPv4 和 IPv6 地址解析
- 支持标准IPv4点分十进制格式（如 `8.8.8.8`）
- 智能域名解析，自动选择最优协议

### ⚙️ 灵活配置
- 自定义目标端口（1-65535）
- 可配置请求次数和发送间隔
- 可调节连接超时时间
- 支持无限次连续测试

### 🎨 友好输出
- 彩色输出模式，直观显示结果状态
- 详细模式显示完整连接信息
- 实时统计信息（最小/最大/平均延迟）
- 网络抖动(Jitter)计算，提供网络稳定性分析
- 完善的错误处理和提示信息

### 🛠️ 使用便捷
- 跨平台支持（Linux、Windows、macOS）
- 多架构支持（amd64、arm64、386、arm、loong64）
- 一键安装脚本，支持自动更新
- 无依赖运行，开箱即用



## 📦 安装方法

### 方法一：手动安装

#### 📥 下载预编译二进制文件 

访问 [GitHub Releases](https://github.com/nodeseeker/tcping/releases) 页面，选择适合您系统的版本：

![releases_example](https://raw.githubusercontent.com/nodeseeker/tcping/refs/heads/main/assets/tcping_releases.jpg)

#### 🗂️ 支持的平台和架构

| 操作系统 | 支持架构 | 下载文件示例 |
|----------|----------|-------------|
| **Linux** | amd64, 386, arm64, arm, loong64 | `tcping-linux-amd64.zip` |
| **Windows** | amd64, 386, arm64, arm | `tcping-windows-amd64.zip` |
| **macOS** | amd64, arm64 | `tcping-darwin-amd64.zip` |

#### 🔧 安装步骤

1. **下载对应版本**：根据您的系统选择合适的压缩包
2. **解压文件**：解压后得到 `tcping` 可执行文件
3. **配置环境**：将文件移动到系统PATH目录

#### 📍 推荐安装位置

- **Linux/macOS**：`/usr/local/bin/tcping`
- **Windows**：`C:\Windows\System32\tcping.exe` 或添加到PATH环境变量

#### ✅ 验证安装

```bash
tcping --version

TCPing 版本 v1.7.3
Copyright (c) 2025. All rights reserved.
```



### 方法二：

一键安装脚本（推荐）

#### 🌍 境外服务器
```bash
bash <(curl -Ls https://raw.githubusercontent.com/nodeseeker/tcping/main/install.sh) --force
```

#### 🇨🇳 境内服务器（国内优化版）
```bash
bash <(curl -Ls https://gh-proxy.com/raw.githubusercontent.com/nodeseeker/tcping/main/install_cn.sh) --force
```

> **注意：** 脚本会自动安装到 `/usr/local/bin` 目录，需要root权限

#### 📋 安装脚本选项

| 选项 | 长选项 | 说明 |
|------|--------|------|
| `-u` | `--uninstall` | 卸载 tcping |
| `-f` | `--force` | 强制安装（跳过确认） |
| `-v` | `--verbose` | 详细输出安装过程 |
| `-h` | `--help` | 显示帮助信息 |

#### 🔄 脚本功能特性
- **智能检测**：自动检测系统架构和已安装版本
- **版本管理**：支持安装、更新、卸载操作
- **依赖处理**：自动检测并安装必要依赖（curl、unzip等）
- **多源下载**：国内版本支持多个镜像源，提高下载成功率
- **错误处理**：完善的错误处理和用户提示


## 🚀 使用方法

### 基本语法
```bash
tcping [选项] <主机> [端口]
```

### 📋 命令行选项

| 短选项 | 长选项 | 描述 | 默认值 |
|--------|---------|------|--------|
| `-4` | `--ipv4` | 强制使用 IPv4 | 自动检测 |
| `-6` | `--ipv6` | 强制使用 IPv6 | 自动检测 |
| `-n` | `--count` | 发送请求的次数 | 无限 |
| `-p` | `--port` | 指定要连接的端口 | 80 |
| `-t` | `--interval` | 请求之间的间隔（毫秒） | 1000ms |
| `-w` | `--timeout` | 连接超时时间（毫秒） | 1000ms |
| `-c` | `--color` | 启用彩色输出 | 关闭 |
| `-v` | `--verbose` | 启用详细模式（包含抖动统计） | 关闭 |
| `-V` | `--version` | 显示版本信息 | - |
| `-h` | `--help` | 显示帮助信息 | - |



## 📖 使用示例

### 🔰 基础使用

#### 测试默认端口（80）
```bash
$ tcping google.com
正在对 google.com (IPv4 - 142.250.191.14) 端口 80 执行 TCP Ping
从 142.250.191.14:80 收到响应: seq=0 time=31.45ms
从 142.250.191.14:80 收到响应: seq=1 time=29.78ms
从 142.250.191.14:80 收到响应: seq=2 time=30.12ms
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 3, 已接收 = 3, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 29.78ms, 最大 = 31.45ms, 平均 = 30.45ms
```

#### 测试HTTPS端口（443）
```bash
$ tcping google.com 443
# 或使用 -p 参数
$ tcping -p 443 google.com
```

### 🎯 高级用法

#### 限制测试次数和间隔
```bash
$ tcping -n 5 -t 2000 example.com 443
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

#### 强制使用IPv6
```bash
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

#### 彩色输出和详细模式
```bash
$ tcping -c -v github.com 443
正在对 github.com (IPv4 - 20.205.243.166) 端口 443 执行 TCP Ping
域名 github.com 解析到的所有IP地址:
  [1] IPv4: 20.205.243.166
  [2] IPv4: 20.27.177.113
使用IP地址: 20.205.243.166

从 20.205.243.166:443 收到响应: seq=0 time=138.45ms
  详细信息: 本地地址=192.168.1.100:50123, 远程地址=20.205.243.166:443
从 20.205.243.166:443 收到响应: seq=1 time=140.12ms
  详细信息: 本地地址=192.168.1.100:50124, 远程地址=20.205.243.166:443
从 20.205.243.166:443 收到响应: seq=2 time=136.78ms
  详细信息: 本地地址=192.168.1.100:50125, 远程地址=20.205.243.166:443
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 3, 已接收 = 3, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 136.78ms, 最大 = 140.12ms, 平均 = 138.45ms
抖动(Jitter): 平均 = 1.67ms
```

#### 网络质量分析
```bash
$ tcping -v -n 10 -c unstable-server.com 80
正在对 unstable-server.com (IPv4 - 203.0.113.10) 端口 80 执行 TCP Ping
从 203.0.113.10:80 收到响应: seq=0 time=45.23ms
从 203.0.113.10:80 收到响应: seq=1 time=52.67ms
从 203.0.113.10:80 收到响应: seq=2 time=38.91ms
从 203.0.113.10:80 收到响应: seq=3 time=61.34ms
从 203.0.113.10:80 收到响应: seq=4 time=44.78ms
从 203.0.113.10:80 收到响应: seq=5 time=55.12ms
从 203.0.113.10:80 收到响应: seq=6 time=41.56ms
从 203.0.113.10:80 收到响应: seq=7 time=49.89ms
从 203.0.113.10:80 收到响应: seq=8 time=58.23ms
从 203.0.113.10:80 收到响应: seq=9 time=46.45ms

--- 目标主机 TCP ping 统计 ---
已发送 = 10, 已接收 = 10, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 38.91ms, 最大 = 61.34ms, 平均 = 49.42ms
抖动(Jitter): 平均 = 8.45ms
```

### 🔢 直接IP地址测试

#### 标准IPv4地址
```bash
$ tcping 8.8.8.8 443
正在对 8.8.8.8 (IPv4 - 8.8.8.8) 端口 443 执行 TCP Ping
...
```

#### IPv6地址
```bash
$ tcping 2001:4860:4860::8888 443
正在对 2001:4860:4860::8888 (IPv6 - 2001:4860:4860::8888) 端口 443 执行 TCP Ping
...
```

### ⚡ 快速诊断

#### 短超时测试
```bash
$ tcping -w 100 slow-server.example.com 80
正在对 slow-server.example.com (IPv4 - 203.0.113.1) 端口 80 执行 TCP Ping
TCP连接失败 203.0.113.1:80: seq=0 错误=连接超时
TCP连接失败 203.0.113.1:80: seq=1 错误=连接超时
^C
操作被中断。

--- 目标主机 TCP ping 统计 ---
已发送 = 2, 已接收 = 0, 丢失 = 2 (100.0% 丢失)
```

### 🛠️ 常用场景

| 使用场景 | 命令示例 | 说明 |
|----------|----------|------|
| 基本连通性测试 | `tcping google.com` | 测试HTTP连通性 |
| HTTPS服务测试 | `tcping -p 443 example.com` | 测试HTTPS服务 |
| SSH服务测试 | `tcping -p 22 server.com` | 测试SSH连接 |
| 数据库连接测试 | `tcping -p 3306 db.server.com` | 测试MySQL连接 |
| 快速诊断 | `tcping -n 3 -w 500 host.com 80` | 3次快速测试 |
| 持续监控 | `tcping -t 5000 -c service.com 443` | 每5秒测试一次 |
| 网络质量分析 | `tcping -v -n 20 target.com 443` | 详细统计含抖动分析 |
| 多IP域名测试 | `tcping -v cdn.example.com 80` | 查看域名所有IP并测试首个IP |



## 🔍 地址解析逻辑

TCPing 提供了强大而灵活的地址解析功能：

### IPv4 地址解析
| 格式类型 | 示例 | 说明 |
|----------|------|------|
| **标准点分十进制** | `8.8.8.8` | 传统IPv4格式 |

### IPv6 地址解析
- 支持标准 IPv6 地址格式（如 `2404:6800:4003:c04::8b`）
- 自动添加方括号用于端口分隔

### 域名解析
- 智能DNS解析，支持A和AAAA记录
- 根据 `-4` 或 `-6` 参数强制协议类型
- 自动选择最优可用地址
- 详细模式下显示所有解析到的IP地址

### 解析优先级
1. **直接IP解析**：解析标准IP地址格式
2. **DNS查询**：进行域名解析，优先选择IPv4地址



## 📊 网络统计分析

### 基础统计信息
TCPing 提供全面的网络连接统计：
- **发送/接收统计**：准确记录请求发送和响应接收数量
- **丢包率计算**：实时计算连接失败率
- **延迟统计**：最小、最大、平均往返时间(RTT)

### 网络抖动(Jitter)分析
在详细模式(`-v`)下，TCPing 会计算网络抖动：

#### 什么是网络抖动？
网络抖动是指连续两次测量之间延迟时间的变化，是衡量网络稳定性的重要指标：
- **低抖动**：网络连接稳定，延迟变化小
- **高抖动**：网络不稳定，可能影响实时应用

#### 抖动计算方法
```
抖动 = |当前RTT - 上一次RTT|
平均抖动 = 所有抖动值的平均数
```

#### 抖动值参考
| 抖动范围 | 网络质量 | 适用场景 |
|----------|----------|----------|
| < 5ms | 优秀 | 实时游戏、视频通话 |
| 5-20ms | 良好 | 一般网络应用 |
| 20-50ms | 一般 | 文件传输、网页浏览 |
| > 50ms | 较差 | 可能影响用户体验 |

#### 示例输出
```bash
$ tcping -v -n 10 example.com 443
...
--- 目标主机 TCP ping 统计 ---
已发送 = 10, 已接收 = 10, 丢失 = 0 (0.0% 丢失)
往返时间(RTT): 最小 = 45.23ms, 最大 = 52.67ms, 平均 = 48.45ms
抖动(Jitter): 平均 = 2.34ms
```

## ⚠️ 错误处理

TCPing 提供了全面的错误处理机制：

### 参数验证
- ✅ 端口范围验证（1-65535）
- ✅ 协议冲突检测（-4与-6同时使用）
- ✅ 数值参数合法性检查

### 网络错误
- 🔍 **地址解析失败**：详细的DNS错误信息
- ⏱️ **连接超时**：明确的超时提示
- 🚫 **连接被拒绝**：端口关闭或服务不可用
- 📡 **网络不可达**：路由或网络配置问题

### 用户友好提示
- 彩色错误输出（启用 `-c` 选项时）
- 详细的错误描述和可能的解决建议
- 完整的统计信息，包括失败次数和丢包率
- 详细模式下提供网络抖动分析，帮助诊断网络稳定性
- 智能域名解析显示，展示所有可用IP地址



## ❓ 常见问题

### 🤔 基础概念

**Q: 为什么使用TCPing而不是普通的ping？**
> **A:** 普通ping使用ICMP协议，在某些网络环境下可能被防火墙阻止。TCPing使用TCP协议测试特定端口，能够：
> - 测试具体服务的可用性（如HTTP、HTTPS、SSH等）
> - 绕过ICMP阻止策略
> - 提供更准确的应用层连通性测试

### 🌐 网络相关

**Q: 为什么有些域名无法进行IPv6测试？**
> **A:** 可能的原因：
> - 域名未配置AAAA记录（IPv6 DNS记录）
> - 您的网络不支持IPv6连接
> - DNS服务器不支持IPv6解析
> 
> **解决方案**：使用 `nslookup -type=AAAA domain.com` 检查IPv6记录

**Q: 测试结果显示连接成功，但服务实际不可用？**
> **A:** TCPing只测试TCP连接建立，不验证应用层协议。连接成功表示：
> - 目标端口已开放
> - 网络路径畅通
> - 但具体服务可能存在应用层问题

### 🎨 显示相关

**Q: 彩色输出在某些终端不起作用？**
> **A:** 解决方案：
> - **Windows**: 使用Windows Terminal或PowerShell 7+
> - **旧版CMD**: 不支持ANSI颜色，建议升级为`终端`（`Terminal`）
> - **Linux/macOS**: 确保终端支持ANSI转义序列

### 📊 性能相关

**Q: 高负载网络下测试结果不准确？**
> **A:** 建议：
> - 增加测试次数：`tcping -n 10 target.com`
> - 适当增加间隔：`tcping -t 2000 target.com`
> - 关注统计结果而非单次测试值
> - 在不同时间段进行多次测试
> - 使用详细模式查看抖动信息：`tcping -v target.com`

**Q: 网络抖动值多少算正常？**
> **A:** 抖动值参考：
> - **< 5ms**: 网络质量优秀，适合实时应用
> - **5-20ms**: 网络质量良好，一般应用无问题
> - **20-50ms**: 网络质量一般，可能影响实时性要求高的应用
> - **> 50ms**: 网络不稳定，建议检查网络配置
> 
> **注意**: 抖动值只在详细模式(`-v`)下显示

**Q: 为什么延迟很低但抖动很高？**
> **A:** 可能原因：
> - 网络路径不稳定（路由切换）
> - 网络设备负载波动
> - ISP网络质量问题
> - 本地网络环境干扰
> 
> **建议**: 在不同时间段多次测试，观察抖动变化趋势

### 🔧 技术问题

**Q: 如何测试特定本地IP绑定？**
> **A:** TCPing会自动选择最佳本地IP，若需指定，可考虑：
> - 配置路由表
> - 使用网络命名空间（Linux）
> - 临时禁用其他网络接口

**Q: 支持测试UDP端口吗？**
> **A:** 当前版本仅支持TCP连接测试。UDP测试需要不同的实现机制，可能在未来版本中添加。

## 🛠️ 自行编译

### 环境要求
- Go 1.24+ 
- Git

### 快速编译
```bash
# 克隆仓库
git clone https://github.com/nodeseeker/tcping.git
cd tcping

# 编译当前平台版本
go build -o tcping src/main.go

# 编译优化版本（推荐）
CGO_ENABLED=0 go build -trimpath -ldflags="-w -s" -o tcping src/main.go
```

### 交叉编译
```bash
# Linux amd64
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-w -s" -o tcping-linux-amd64 src/main.go

# Windows amd64  
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-w -s" -o tcping-windows-amd64.exe src/main.go

# macOS arm64
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-w -s" -o tcping-darwin-arm64 src/main.go
```

### 批量编译
项目提供了 `compiler.sh` 脚本，支持一键编译所有平台版本：

```bash
chmod +x compiler.sh
./compiler.sh
```

编译产物将输出到 `./bin` 目录，并自动生成SHA256校验文件。

### 功能测试
项目提供了 `test.sh` 脚本用于验证编译后的程序功能：

```bash
chmod +x test.sh
./test.sh
```

测试脚本会验证IPv4、IPv6和域名解析等核心功能。

### 编译参数说明
- `CGO_ENABLED=0`: 禁用CGO，确保静态链接
- `-trimpath`: 移除路径信息，减小文件大小
- `-ldflags="-w -s"`: 移除调试信息和符号表
- `-o`: 指定输出文件名


## 📄 许可证

本项目采用 [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html) 开源许可证。


### 👥 贡献者

感谢所有为项目做出贡献的开发者！

<a href="https://github.com/nodeseeker/tcping/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=nodeseeker/tcping" />
</a>

---


<div align="center">

**🌟 如果TCPing对您有帮助，请给我们一个Star！**

Made with ❤️ by [nodeseeker](https://github.com/nodeseeker)

</div>
