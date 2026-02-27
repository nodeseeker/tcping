## 1. 帮助与版本

### 1.1 帮助（短/长）

```bash
./tcping -h
./tcping --help
```

### 1.2 版本（短/长）

```bash
./tcping -V
./tcping --version
```

------

## 2. 参数校验（错误路径）

### 2.1 缺少主机参数

```bash
./tcping
```

### 2.2 互斥参数：同时使用 -4 和 -6（应报错）

```bash
./tcping -4 -6 127.0.0.1
```

### 2.3 interval 非法（<=0 应报错）

```bash
./tcping -t 0 127.0.0.1
./tcping --interval 0 127.0.0.1
./tcping -t -10 127.0.0.1
```

### 2.4 timeout 非法（<=0 应报错）

```bash
./tcping -w 0 127.0.0.1
./tcping --timeout 0 127.0.0.1
./tcping -w -10 127.0.0.1
```

### 2.5 dns-timeout 非法（<=0 应报错）

```bash
./tcping --dns-timeout 0 127.0.0.1
./tcping --dns-timeout -10 127.0.0.1
```

### 2.6 端口非法（格式错误 / 越界）

```bash
./tcping 127.0.0.1 abc
./tcping 127.0.0.1 0
./tcping 127.0.0.1 65536
./tcping -p 0 127.0.0.1
./tcping -p 70000 127.0.0.1
```

------

## 3. 本地成功连接目标准备（启动监听端口）

### 3.1 使用 python3 启动 IPv4 TCP 监听

```bash
export PORT_OK=18080
python3 - <<'PY'
import socket
host="127.0.0.1"
port=18080
s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((host, port))
s.listen(128)
print(f"listening on {host}:{port}")
while True:
    c, _ = s.accept()
    c.close()
PY
```

### 3.2 或使用 nc 启动 IPv4 TCP 监听

```bash
export PORT_OK=18080
# 不同 nc 版本参数不同，下面是较常见用法之一：
nc -l 127.0.0.1 $PORT_OK
```

### 3.3 选择一个“未监听端口”（失败目标）

```bash
export PORT_BAD=18081
```

------

## 4. 基本功能：TCP 连接测试（成功/失败）

### 4.1 基本成功：host + port（位置参数）

```bash
./tcping -n 3 -t 200 -w 500 127.0.0.1 $PORT_OK
```

### 4.2 基本失败：连接拒绝/不可达（应输出 TCP连接失败）

```bash
./tcping -n 1 -t 200 -w 500 127.0.0.1 $PORT_BAD
```

------

## 5. 主机/端口输入格式解析

### 5.1 host:port 形式（IPv4）

```bash
./tcping -n 2 -t 200 -w 500 127.0.0.1:$PORT_OK
```

### 5.2 仅 host，端口来自 -p / --port

```bash
./tcping -n 2 -t 200 -w 500 -p $PORT_OK 127.0.0.1
./tcping -n 2 -t 200 -w 500 --port $PORT_OK 127.0.0.1
```

### 5.3 同时给 host:port 与第二个端口参数（第二个应覆盖）

```bash
./tcping -n 1 -t 200 -w 500 127.0.0.1:$PORT_BAD $PORT_OK
```

------

## 6. 次数与间隔（-n/-t）

### 6.1 有限次数（-n / --count）

```bash
./tcping -n 5 -t 100 -w 500 127.0.0.1 $PORT_OK
./tcping --count 5 --interval 100 --timeout 500 127.0.0.1 $PORT_OK
```

### 6.2 无限模式（Count=0）+ 手动中断（Ctrl+C）

```bash
./tcping -n 0 -t 300 -w 500 127.0.0.1 $PORT_OK
# 运行几秒后按 Ctrl+C，观察提示“操作被中断。”以及统计输出
```

------

## 7. IPv4 / IPv6 选择

### 7.1 强制 IPv4（-4 / --ipv4）

```bash
./tcping -4 -n 2 -t 200 -w 500 127.0.0.1 $PORT_OK
./tcping --ipv4 -n 2 -t 200 -w 500 127.0.0.1 $PORT_OK
```

### 7.2 IPv6 环境检测

```bash
python3 - <<'PY'
import socket, sys
try:
    s=socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    s.bind(("::1", 0))
    port=s.getsockname()[1]
    s.close()
    print("IPv6 OK")
except Exception as e:
    print("IPv6 NOT available:", e)
PY
```

### 7.3 启动 IPv6 监听

```bash
export PORT6_OK=18082
python3 - <<'PY'
import socket
host="::1"
port=18082
s=socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((host, port))
s.listen(128)
print(f"listening on [{host}]:{port}")
while True:
    c, _ = s.accept()
    c.close()
PY
```

选择一个“未监听端口”（IPv6目标）

```bash
export PORT_BAD=18083
```


### 7.4 IPv6 成功：强制 -6 + [::1]:port

```bash
./tcping -6 -n 2 -t 200 -w 500 [::1]:$PORT6_OK
./tcping --ipv6 -n 2 -t 200 -w 500 [::1]:$PORT6_OK
```

### 7.5 IPv4/IPv6 不匹配错误（-4 连接 IPv6 应报错）

```bash
./tcping -4 -n 1 -t 200 -w 500 [::1]:$PORT6_OK
```

------

## 8. DNS 解析与 dns-timeout

### 8.1 正常解析（需要外网 DNS）

```bash
./tcping -n 1 -t 200 -w 1000 example.com 80
```

### 8.2 强制 IPv4/IPv6 解析（域名 + -4/-6）

```bash
./tcping -4 -n 1 -t 200 -w 1000 example.com 80
./tcping -6 -n 1 -t 200 -w 1000 example.com 80
```

### 8.3 DNS 失败（保留域 nonexistent.invalid）

```bash
./tcping -n 1 -t 200 -w 1000 nonexistent.invalid 80
```

### 8.4 dns-timeout 生效（尽量小的超时，行为依赖系统 resolver）

```bash
./tcping --dns-timeout 1 -n 1 -t 200 -w 1000 example.com 80
./tcping --dns-timeout 1 -n 1 -t 200 -w 1000 nonexistent.invalid 80
```

------

## 9. 详细输出（-v / --verbose）

### 9.1 verbose 成功路径：应显示“详细信息: 本地地址=..., 远程地址=...”

```bash
./tcping -v -n 2 -t 200 -w 500 127.0.0.1 $PORT_OK
./tcping --verbose -n 2 -t 200 -w 500 127.0.0.1 $PORT_OK
```

### 9.2 verbose 失败路径：应显示连接尝试耗时与目标信息

```bash
./tcping -v -n 1 -t 200 -w 300 127.0.0.1 $PORT_BAD
```

### 9.3 verbose 统计：应额外显示“抖动(Jitter)”

```bash
./tcping -v -n 5 -t 100 -w 500 127.0.0.1 $PORT_OK
```

------

## 10. 彩色输出（-c / --color）

> 观察输出是否包含彩色（ANSI escape）。

```bash
./tcping -c -n 2 -t 200 -w 500 127.0.0.1 $PORT_OK
./tcping --color -n 2 -t 200 -w 500 127.0.0.1 $PORT_BAD
```

------

## 11. CSV 输出（-o / --csv）

### 11.1 生成 CSV 文件（当前目录）

```bash
./tcping -o -n 3 -t 200 -w 500 127.0.0.1 $PORT_OK
ls -1 tcping_results_*.csv | tail -n 1
```

### 11.2 验证 CSV 表头与行数（应 >= header + n 行）

```bash
CSV_FILE="$(ls -1 tcping_results_*.csv | tail -n 1)"
head -n 1 "$CSV_FILE"
wc -l "$CSV_FILE"
```

### 11.3 验证 success/false 行存在（成功/失败各跑一次）

```bash
# 成功记录
./tcping -o -n 1 -t 200 -w 500 127.0.0.1 $PORT_OK
CSV_FILE="$(ls -1 tcping_results_*.csv | tail -n 1)"
grep -F ",true,," "$CSV_FILE" | tail -n 3

# 失败记录
./tcping -o -n 1 -t 200 -w 300 127.0.0.1 $PORT_BAD
CSV_FILE="$(ls -1 tcping_results_*.csv | tail -n 1)"
grep -F ",false," "$CSV_FILE" | tail -n 3
```

### 11.4 CSV flush 参数（边界测试：0 会被防御性兜底，不应崩溃）

```bash
./tcping -o --csv-flush-every 0 --csv-flush-tick 0 -n 3 -t 50 -w 500 127.0.0.1 $PORT_OK
```

------

## 12. 统计输出校验（发送/接收/丢失/RTT）

### 12.1 全成功：received == sent，丢失 0%

```bash
./tcping -n 5 -t 100 -w 500 127.0.0.1 $PORT_OK
```

### 12.2 全失败：received == 0，丢失 100%

```bash
./tcping -n 3 -t 100 -w 200 127.0.0.1 $PORT_BAD
```

------

## 13. 中断行为（Ctrl+C）

### 13.1 ticker 等待期间中断（观察 main 的“操作被中断。”只打印一次，并输出统计）

```bash
./tcping -n 0 -t 2000 -w 500 127.0.0.1 $PORT_OK
# 运行后立刻 Ctrl+C（大概率在 ticker 等待）
```

### 13.2 Dial 阻塞期间中断（尽量制造阻塞：对不可达 IP，超时设大一点，然后 Ctrl+C）

> 依赖网络环境；有些环境会立即返回“网络不可达”，不一定阻塞。

```bash
./tcping -n 0 -t 1000 -w 10000 10.255.255.1 81
# 看到正在尝试后 Ctrl+C
```

------

## 14. 清理

```bash
rm -f tcping_results_*.csv
```