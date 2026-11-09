#!/bin/bash

# tcping 全平台编译入口（CNB .cnb.yml 与 GitHub Actions release.yml 共用）
#
# 特性:
#   - BUILD_TIME 全程只计算一次（所有平台共用同一个时间戳，可用环境变量 BUILD_TIME 覆盖）
#   - 注入构建时间到二进制: -X main.buildTime=<yyyymmdd-hhmmss>，-V 可显示
#   - 编译后写 bin/VERSION 与 bin/BUILD_TIME，供 CI 读取拼接 release tag（v版本-yyyymmdd-hhmmss）
#
# 用法: bash tools/compiler.sh

set -e

# 源码包路径（必须用包路径 ./src，不要用文件参数 ./src/main.go）
SRC_PATH="./src"
# 输出目录
OUT_DIR="./bin"
# 程序名
APP_NAME="tcping"

# 构建时间：只算一次，所有平台共用；允许外部通过环境变量 BUILD_TIME 覆盖
BUILD_TIME="${BUILD_TIME:-$(TZ=Asia/Shanghai date +%Y%m%d-%H%M%S)}"
export BUILD_TIME

# 从 src/version.txt 读取版本号（唯一来源，纯数字如 1.9.10；Go 侧 go:embed 同源）
if [ ! -f src/version.txt ]; then
  echo "错误: 找不到 src/version.txt" >&2
  exit 1
fi
VERSION="v$(tr -d '[:space:]' < src/version.txt)"
if [ -z "$(tr -d '[:space:]' < src/version.txt)" ]; then
  echo "错误: src/version.txt 内容为空" >&2
  exit 1
fi

# 需要编译的目标平台和架构
PLATFORMS=(
  "darwin/amd64"
  "darwin/arm64"
  "linux/386"
  "linux/amd64"
  "linux/arm"
  "linux/arm64"
  "linux/loong64"
  "windows/386"
  "windows/amd64"
  "windows/arm64"
)

# 清理之前的编译产物
rm -rf $OUT_DIR
mkdir -p $OUT_DIR

# 初始化 SHA256SUMS 文件
> "$OUT_DIR/SHA256SUMS.txt"

echo "版本: ${VERSION}  构建时间: ${BUILD_TIME}"

# 编译并压缩每个平台
for PLATFORM in "${PLATFORMS[@]}"; do
  # 获取平台的 GOOS 和 GOARCH
  GOOS=$(echo $PLATFORM | cut -d'/' -f1)
  GOARCH=$(echo $PLATFORM | cut -d'/' -f2)

  # 设置输出文件路径
  OUT_FILE="$OUT_DIR/$APP_NAME"

  # 设置环境变量并编译（注入构建时间）
  echo "编译 ${GOOS}/${GOARCH}..."
  CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH \
    go build -trimpath -ldflags="-w -s -X main.buildTime=${BUILD_TIME}" \
    -o "$OUT_FILE" $SRC_PATH

  # 判断是否是 Windows 平台，需要添加 .exe 扩展名
  if [ "$GOOS" == "windows" ]; then
    mv "$OUT_FILE" "$OUT_FILE.exe"
    OUT_FILE="$OUT_FILE.exe"
  fi

  # 压缩分发包：Windows 用 zip，其余用 tar.gz
  # （Linux 服务器普遍没有 unzip，而 tar+gzip 是基础系统组件，能省一个依赖）
  echo "压缩 ${OUT_FILE}..."
  if [ "$GOOS" == "windows" ]; then
    zip -j "$OUT_DIR/$APP_NAME-${GOOS}-${GOARCH}.zip" "$OUT_FILE"
    sha256sum "$OUT_DIR/$APP_NAME-${GOOS}-${GOARCH}.zip" >> "$OUT_DIR/SHA256SUMS.txt"
  else
    tar -czf "$OUT_DIR/$APP_NAME-${GOOS}-${GOARCH}.tar.gz" -C "$OUT_DIR" "$APP_NAME"
    sha256sum "$OUT_DIR/$APP_NAME-${GOOS}-${GOARCH}.tar.gz" >> "$OUT_DIR/SHA256SUMS.txt"
  fi

  # 清理中间文件
  rm "$OUT_FILE"
done

# 写出版本号与构建时间，供 CI 读取拼接 release tag（v版本-yyyymmdd-hhmmss）
echo -n "$VERSION" > "$OUT_DIR/VERSION"
echo -n "$BUILD_TIME" > "$OUT_DIR/BUILD_TIME"

echo "编译和压缩完成，所有文件已存储在 $OUT_DIR 目录下。"
echo "  版本: $(cat $OUT_DIR/VERSION)  构建时间: $(cat $OUT_DIR/BUILD_TIME)"
echo "  release tag 建议: $(cat $OUT_DIR/VERSION)-$(cat $OUT_DIR/BUILD_TIME)"
