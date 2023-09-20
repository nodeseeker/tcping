# tcping

一款基于Golang的TCP Ping工具，支持IPv4、IPv6和域名，以及自定义端口、次数和间隔时间。

## 使用教程
### 安装方法

浏览器打开程序的发布页 [https://github.com/nodeseeker/tcping/releases](https://github.com/nodeseeker/tcping/releases)，在列表中找到对应CPU架构和平台的程序（如下图），比如x86_64的Linux系统，下载`tcping-linux-amd64.zip`，而x86_64的Windows，则下载`tcping-windows-amd64.zip`。下载完成后，解压即可得到一个名为`tcping`的文件，直接运行即可，如Linux平台 `./tcp 1.1.1.1 80 ` 就是tcping 1.1.1.1 的80端口，具体方法参考下面的使用方法和使用示例。如果是Linux平台，也可以使用root用户，将文件移动到`/usr/bin`中，这样就可以直接使用`tcp 1.1.1.1 80`而无需前面的`./`路径。

![releases_example](https://raw.githubusercontent.com/nodeseeker/tcping/main/assets/tcping_releases.jpg)

目前支持的多架构多平台如下：

- amd64的Linux、Windows和MacOS
- arm的Linux
- arm64的Linux和MacOS

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

#### glibc版本问题

如果提示`./tcping: /lib64/libc.so.6: version GLIBC_2.34' not found (required by ./tcping) ./tcping: /lib64/libc.so.6: version GLIBC_2.32' not found (required by ./tcping)`等，是因为系统的glibc版本过低，**请下载和使用带有`-static`后缀的版本**。

## 使用示例
### 1. tcping 一个IPv4地址和指定的80端口
此处使用cloudflare的1.1.1.1 (80端口对应http)
```
tcping 1.1.1.1 80
```

以下是响应
```
Pinging 1.1.1.1:80...
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 11ms
tcping 1.1.1.1:80 in 11ms
^C # 此处使用了Ctrl C停止tcping
Ping interrupted.
```

### 2. tcping 一个IPv6地址和指定的80端口
此处使用cloudflare的2606:4700:4700::1111(80端口对应http)
```
tcping 2606:4700:4700::1111 80 
```

以下是响应
```
Pinging [2606:4700:4700::1111]:80...
tcping [2606:4700:4700::1111]:80 in 235ms
tcping [2606:4700:4700::1111]:80 in 12ms
tcping [2606:4700:4700::1111]:80 in 12ms
tcping [2606:4700:4700::1111]:80 in 11ms
^C
Ping interrupted.
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
tcping 172.67.70.75:443 in 12ms
tcping 172.67.70.75:443 in 12ms
tcping 172.67.70.75:443 in 11ms
tcping 172.67.70.75:443 in 12ms
^C
Ping interrupted.
```

### 4. tcping 一个域名和指定的443端口，启用IPv6地址
此处使用nodeseek.com(443端口对应https)，必须在地址和端口前加`-6`
```
tcping -6 nodeseek.com 443
```

以下是响应
```
Pinging [2606:4700:20::681a:a48]:443...
tcping [2606:4700:20::681a:a48]:443 in 28ms
tcping [2606:4700:20::681a:a48]:443 in 13ms
tcping [2606:4700:20::681a:a48]:443 in 12ms
tcping [2606:4700:20::681a:a48]:443 in 12ms
^C
Ping interrupted.
```

### 5. tcping 一个IPv4地址和指定的80端口，限定tcping次数
此处使用cloudflare的1.1.1.1 (80端口对应http)，必须在地址和端口前加`-n 3`，3是指只tcping3次即自动停止，不写此指令则默认一直tcping
```
tcping -n 3 1.1.1.1 80
```

以下是响应
```
Pinging 1.1.1.1:80...
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 12ms

Ping stopped. # 此处到了设定次数，自动停止
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
tcping 1.1.1.1:80 in 12ms
tcping 1.1.1.1:80 in 12ms

Ping stopped.
```

### 7. 综合演示tcping的所有功能
此处使用nodeseek.com(443端口对应https)，tcping IPv6地址，每2秒钟tcping一次，一共tcping 5次
```
tcping -6 -n 5 -t 2 nodeseek.com 443
```
以下是响应
```
Pinging [2606:4700:20::681a:b48]:443...
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms
tcping [2606:4700:20::681a:b48]:443 in 12ms

Ping stopped.
```
