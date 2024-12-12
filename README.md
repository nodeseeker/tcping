# tcping

一款基于Golang的TCP Ping工具，支持IPv4、IPv6和域名，以及自定义端口、次数和间隔时间。

## 使用教程
### 安装方法

浏览器打开程序的发布页 [https://github.com/nodeseeker/tcping/releases](https://github.com/nodeseeker/tcping/releases)，在列表中找到对应CPU架构和平台的程序（如下图），比如x86_64的Linux系统，下载`tcping-linux-amd64.zip`，而x86_64的Windows，则下载`tcping-windows-amd64.zip`。下载完成后，解压即可得到一个名为`tcping`的文件，直接运行即可，如Linux平台 `./tcp 1.1.1.1 80 ` 就是`tcping` IP 为 `1.1.1.1` 的 `80` 端口，具体方法参考下面的使用方法和使用示例。如果是Linux平台，建议使用root用户将文件移动到`/usr/bin`中，这样就可以直接使用`tcping 1.1.1.1 80`而无需指定路径。

![releases_example](https://raw.githubusercontent.com/nodeseeker/tcping/main/assets/tcping_releases.jpg)

目前支持的多架构多平台如下：

- amd64的Linux、Windows和MacOS
- arm的Linux、Windows
- arm64的Linux、Windows和MacOS
- loongarch64的Linux

### 使用方法

以下为程序使用方法，**建议直接看使用示例**。

1. address和port为必填，其中，address可以是IPv4地址、IPv6地址，或者域名。端口即为服务器已经开启的端口，比如SSH默认的22端口，网站常用的80端口和443端口。
2. -4 是当输入的address为域名的时候，强制tcping解析出来的IPv4地址。同理，-6 是当输入的address为域名的时候，强制tcping解析出来的IPv6地址。
3. -n 是tcping的次数，后面必须跟一个正整数，比如 `-n 10`，就是tcping 10次，之后自动停止。默认一直tcping下去，只有`Ctrl C`才会停止。
4. -t 是设置每两次tcping之间的间隔，后面必须跟一个正整数，比如`-t 2`，是每隔2秒钟tcping一次。默认每秒钟tcping一次。

```
tcping [-4] [-6] [-n count] [-t timeout] address port
```

### 常见问题


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
tcping -4 nodeseek.com 443 # 这两个命令是等效的，以为默认使用IPv4地址
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
此处使用nodeseek.com(443端口对应https)，必须在地址和端口前加`-6`
```
tcping -6 nodeseek.com 443
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
此处使用cloudflare的1.1.1.1 (80端口对应http)，必须在地址和端口前加`-t 2`，3是指每连刺tcping之间为2秒钟，不写此指令则默认1秒
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
此处使用nodeseek.com(443端口对应https)，tcping IPv6地址，每2秒钟tcping一次，一共tcping 5次
```
tcping -6 -n 5 -t 2 nodeseek.com 443
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

#### 自己编译
程序使用纯golang编写，可以自己编译，编译方法如下，`$GOOS`是目标操作系统，`$GOARCH`是目标CPU架构，`$SRC_PATH`是源代码路径，`$OUT_FILE`是输出文件路径。
```
CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH go build -trimpath -ldflags="-w -s" -o "$OUT_FILE" $SRC_PATH
```
此外，也提供了批量编译脚本`complier.sh`，可以直接运行，但需要修改脚本中的目标平台和架构（`$GOOS`和`$GOARCH`变量）和源码路径（`$SRC_PATH`和`OUT_DIR`变量）。


#### glibc版本问题

**1.2.0版本已经解决了glibc依赖问题**

如果提示glibc找不到，如下：是因为系统的glibc版本过低，**请下载和使用带有`-static`后缀的版本**。
```
./tcping: /lib64/libc.so.6: version GLIBC_2.34' not found (required by ./tcping)
./tcping: /lib64/libc.so.6: version GLIBC_2.32' not found (required by ./tcping)
```
