# tcping

一款基于Golang的TCP Ping工具，支持IPv4、IPv6和域名，以及自定义端口、次数和间隔时间。

## 使用教程
### 安装方法

浏览器打开程序的发布页 [https://github.com/nodeseeker/tcping/releases](https://github.com/nodeseeker/tcping/releases)，在列表中找到对应CPU架构和平台的程序（如下图），比如x86_64的Linux系统，下载`tcping-linux-amd64.zip`，而x86_64的Windows，则下载`tcping-windows-amd64.zip`。下载完成后，解压即可得到一个名为`tcping`的文件，直接运行即可，如Linux平台 `./tcp 1.1.1.1 80 ` 就是`tcping` IP 为 `1.1.1.1` 的 `80` 端口，具体方法参考下面的使用方法和使用示例。

为了方便使用，建议将`tcping`文件移动到系统的`PATH环境变量`中或者`bin`目录中，这样就可以在任何目录下直接使用`tcping`命令，例如`tcping  1.1.1.1 80`：
- 如果是Linux平台，建议使用root用户将文件移动到`/usr/bin`中
- 如果是Windows平台，建议向PATH 环境变量中添加工具位置
- 如果是macOS平台，建议直接将文件移动到`/usr/local/bin`中

![releases_example](https://raw.githubusercontent.com/nodeseeker/tcping/refs/heads/main/assets/tcping_releases.jpg)

目前支持的多架构多平台如下：

```
- linux系统：amd64/386/arm64/arm/loong64
- windows系统：386/amd64/arm/arm64
- macOS/darwin系统：amd64/arm64
```

### 使用方法

以下为程序使用方法，**建议直接看使用示例**。

1. address和port为必填，其中，address可以是IPv4地址、IPv6地址，或者域名。端口即为服务器已经开启的端口，比如SSH默认的22端口，网站常用的80端口和443端口。
2. -4 是当输入的address为域名的时候，强制tcping解析出来的IPv4地址。同理，-6 是当输入的address为域名的时候，强制tcping解析出来的IPv6地址。
3. -n 是tcping的次数，后面必须跟一个正整数，比如 `-n 10`，就是tcping 10次，之后自动停止。默认一直tcping下去，只有`Ctrl C`才会停止。
4. -t 是设置每两次tcping之间的间隔，后面必须跟一个正整数，比如`-t 2`，是每隔2秒钟tcping一次。默认每秒钟tcping一次。
5. -w 是设置tcping的超时时间，后面必须跟一个正整数，比如`-w 1000`，是设置tcping的超时时间为500毫秒。默认超时时间为1000毫秒，即1秒钟。

```
tcping [-4] [-6] [-n count] [-t timeout] address port
```

## 使用示例
### 1. tcping 一个IPv4地址和指定的80端口
此处使用cloudflare的1.1.1.1 (80端口对应http)
```
tcping 1.1.1.1 80
```

以下是响应
```
Pinging 1.1.1.1:80...
tcping 1.1.1.1:80 in 11ms
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 11ms
^C # 此处使用了Ctrl C停止tcping
Ping interrupted.

--- Tcping Statistics ---
4 tcp ping sent, 4 tcp ping responsed, 0.00% loss # 总尝试次数/成功次数/失败率
min/avg/max = 11ms/11ms/12ms # 最小tcping时间/平均tcping时间/最大tcping时间
```

### 2. tcping 一个IPv6地址和指定的80端口
此处使用cloudflare的2606:4700:4700::1111(80端口对应http)
```
tcping 2606:4700:4700::1111 80 
```

以下是响应
```
Pinging [2606:4700:4700::1111]:80...
Failed to connect to [2606:4700:4700::1111]:80: dial tcp [2606:4700:4700::1111]:80: i/o timeout # tcping失败
tcping [2606:4700:4700::1111]:80 in 29ms
tcping [2606:4700:4700::1111]:80 in 12ms
tcping [2606:4700:4700::1111]:80 in 12ms
^C
Ping interrupted.

--- Tcping Statistics ---
4 tcp ping sent, 3 tcp ping responsed, 25.00% loss # 4个tcping中有一个失败，所以失败率为25%
min/avg/max = 12ms/17ms/29ms
```

### 3. tcping 一个域名和指定的443端口，启用IPv4地址
此处使用nodeseek.com(443端口对应https)
```
tcping nodeseek.com 443
tcping -4 nodeseek.com 443 # 这两个命令是等效的，默认使用IPv4地址
```

以下是响应
```
Pinging 172.67.70.75:443...
tcping 172.67.70.75:443 in 11ms
tcping 172.67.70.75:443 in 12ms
tcping 172.67.70.75:443 in 11ms
tcping 172.67.70.75:443 in 12ms
^C
Ping interrupted.

--- Tcping Statistics ---
4 tcp ping sent, 4 tcp ping responsed, 0.00% loss
min/avg/max = 11ms/11ms/12ms
```

### 4. tcping 一个域名和指定的443端口，启用IPv6地址
此处使用www.cloudflare.com(443端口对应https)，必须在地址和端口前加`-6`
```
tcping -6 www.cloudflare.com 443
```

以下是响应
```
Pinging [2606:4700:20::ac43:464b]:443...
tcping [2606:4700:20::ac43:464b]:443 in 12ms
tcping [2606:4700:20::ac43:464b]:443 in 12ms
tcping [2606:4700:20::ac43:464b]:443 in 11ms
tcping [2606:4700:20::ac43:464b]:443 in 12ms
^C
Ping interrupted.

--- Tcping Statistics ---
4 tcp ping sent, 4 tcp ping responsed, 0.00% loss
min/avg/max = 11ms/11ms/12ms
```

### 5. tcping 一个IPv4地址和指定的80端口，限定tcping次数
此处使用cloudflare的1.1.1.1 (80端口对应http)，必须在地址和端口前加`-n 3`，3是指只tcping3次即自动停止，不写此指令则默认一直tcping
```
tcping -n 3 1.1.1.1 80
```

以下是响应
```
Pinging 1.1.1.1:80...
tcping 1.1.1.1:80 in 11ms
tcping 1.1.1.1:80 in 11ms
tcping 1.1.1.1:80 in 12ms

Ping stopped. # 此处到了设定次数，自动停止

--- Tcping Statistics ---
3 tcp ping sent, 3 tcp ping responsed, 0.00% loss
min/avg/max = 11ms/11ms/12ms
```

### 6. tcping 一个IPv4地址和指定的80端口，限定tcping间隔时间次数
此处使用cloudflare的1.1.1.1 (80端口对应http)，必须在地址和端口前加`-t 2`，2是指每两次tcping之间为2秒钟，不写此指令则默认1秒
```
tcping -t 2 1.1.1.1 80
```

以下是响应
```
Pinging 1.1.1.1:80...
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 11ms
tcping 1.1.1.1:80 in 11ms
tcping 1.1.1.1:80 in 12ms
^C
Ping interrupted.

--- Tcping Statistics ---
4 tcp ping sent, 4 tcp ping responsed, 0.00% loss
min/avg/max = 11ms/11ms/12ms
```

### 7. 综合演示tcping的所有功能
此处使用www.cloudflare.com(443端口对应https)，tcping IPv6地址，每2秒钟tcping一次，一共tcping 5次
```
tcping -6 -n 5 -t 2 www.cloudflare.com 443
```
以下是响应
```
Pinging [2606:4700:20::681a:b48]:443...
tcping [2606:4700:20::681a:b48]:443 in 11ms
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms

Ping stopped.

--- Tcping Statistics ---
5 tcp ping sent, 5 tcp ping responsed, 0.00% loss
min/avg/max = 11ms/11ms/12ms
```

### 8. tcping 一个IPv4地址和指定的80端口，设置超时时间
此处使用cloudflare的的1.1.1.1 (80端口对应http)，在地址和端口前加`-w 100`，100是指tcping超时时间为100毫秒。由于服务器距离较远，所以超时。主要用于给测试网络延迟设置一个上限。
```
PS C:\Users\Imes> tcping -w 100 1.1.1.1 80
Pinging 1.1.1.1:80...
Failed to connect to 1.1.1.1:80: dial tcp 1.1.1.1:80: i/o timeout
Failed to connect to 1.1.1.1:80: dial tcp 1.1.1.1:80: i/o timeout
Failed to connect to 1.1.1.1:80: dial tcp 1.1.1.1:80: i/o timeout
Failed to connect to 1.1.1.1:80: dial tcp 1.1.1.1:80: i/o timeout

Tcping interrupted.

--- Tcping Statistics ---
4 tcp ping sent, 0 tcp ping responsed, 100.00% loss
No responses received.
```

#### 自己编译
程序使用纯golang编写，可以自己编译，编译方法如下，`$GOOS`是目标操作系统，`$GOARCH`是目标CPU架构，`$SRC_PATH`是源代码路径，`$OUT_FILE`是输出文件路径。
```
CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH go build -trimpath -ldflags="-w -s" -o "$OUT_FILE" $SRC_PATH
```
此外，也提供了批量编译脚本`complier.sh`，可以直接运行，但需要修改脚本中的目标平台和架构（`$GOOS`和`$GOARCH`变量）和源码路径（`$SRC_PATH`和`OUT_DIR`变量）。



### 常见问题

1. **为什么需要使用tcping而不是普通的ping？**  
   普通的ping使用ICMP协议，而tcping使用TCP协议。有些网络环境下可能ICMP报文被过滤或屏蔽，但TCP连接仍然可用。tcping可以测试特定端口的连通性和响应时间，这是普通ping无法做到的。

2. **为什么有些域名无法进行IPv6测试？**  
   这可能是因为该域名没有配置AAAA记录（IPv6解析记录）。可以先通过DNS查询工具确认域名是否支持IPv6解析。

3. **出现"i/o timeout"表示什么？**  
   这表示连接超时，可能原因包括：目标服务器未开放该端口、防火墙阻止了连接、网络连接问题或服务器负载过重。

4. **glibc依赖问题**  
   1.2.0及更新版本已经解决了glibc依赖问题，建议使用新版本。如果旧版本提示glibc找不到（如下），是因为系统的glibc版本过低，请下载和使用带有`-static`后缀的版本，但**强烈推荐使用新版本**。
   ```
   ./tcping: /lib64/libc.so.6: version GLIBC_2.34' not found (required by ./tcping)
   ./tcping: /lib64/libc.so.6: version GLIBC_2.32' not found (required by ./tcping)
   ```
