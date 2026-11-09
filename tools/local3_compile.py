#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tcping 编译包装脚本（Python 版，对齐 tools/compiler.sh 的输出逻辑）。

与原 shell 版本行为一致：
  - 输出目录 ./bin（已被 .gitignore 忽略，不会被追踪）
  - 清理旧产物后重新编译
  - 仅编译 win/amd64、linux/amd64、linux/arm64 三个目标
  - 压缩分发包: Windows 为 .zip，其余平台为 .tar.gz（tcping-${GOOS}-${GOARCH}.tar.gz）
  - 计算 SHA256 并追加到 ./bin/<编译时间>/SHA256SUMS.txt

本脚本在 shell 版基础上增加的便利项（自用）：
  - bin 下再套一层「编译时间戳」文件夹（如 bin/20260824_153000），区分每次构建
  - 同时保留未压缩的二进制（含 .exe），方便本地直接测试 / 复制分发，而非只有压缩包

与原 shell 版本的差异仅在于实现语言：
  - 用 Python 的 zipfile 替代 zip -j
  - 用 Python 的 hashlib 替代 sha256sum
  - 编译参数 CGO_ENABLED=0 go build -trimpath -ldflags="-w -s" 完全一致
  - zip 内仅包含单一二进制文件（等价 zip -j 拍平目录）

用法：
  python tools/compile.py
"""

import datetime
import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import zipfile

SRC_PATH = "./src"  # 必须用包路径；用 ./src/main.go 文件参数会导致 ldflags -X 注入失效
OUT_DIR = "bin"
APP_NAME = "tcping"

# 仅编译这三个目标（对齐需求：win amd64 / linux amd64 / linux arm64）
PLATFORMS = [
    ("windows", "amd64"),
    ("linux", "amd64"),
    ("linux", "arm64"),
]


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)

    # 编译时间戳文件夹，便于区分每次构建产物（如 bin/20260824_153000）
    build_time = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    build_dir = os.path.join(OUT_DIR, build_time)

    # 注入到二进制的构建时间（yyyymmdd-hhmmss，所有平台共用同一个）
    ver_stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

    # 仅清理本次构建的时间戳目录（每次时间戳不同，旧构建自然保留，不误删其它文件）
    if os.path.isdir(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(build_dir, exist_ok=True)

    sha256sums = os.path.join(build_dir, "SHA256SUMS.txt")
    with open(sha256sums, "w", encoding="utf-8") as _:
        pass  # 清空文件

    for goos, goarch in PLATFORMS:
        print(f"编译 {goos}/{goarch}...")

        # 每个平台独立子目录，命名与 zip 一致（如 tcping-windows-amd64/），
        # 二进制放进子目录，避免与 zip 平铺、跨平台相互覆盖/混淆。
        plat_dir = os.path.join(build_dir, f"{APP_NAME}-{goos}-{goarch}")
        os.makedirs(plat_dir, exist_ok=True)
        out_file = os.path.join(plat_dir, APP_NAME)

        env = dict(os.environ)
        env["CGO_ENABLED"] = "0"
        env["GOOS"] = goos
        env["GOARCH"] = goarch

        rc = subprocess.call(
            [
                "go", "build",
                "-trimpath",
                f"-ldflags=-w -s -X main.buildTime={ver_stamp}",
                "-o", out_file,
                SRC_PATH,
            ],
            env=env,
        )
        if rc != 0:
            print(f"  编译 {goos}/{goarch} 失败 (exit={rc})", file=sys.stderr)
            return rc

        # Windows 需要 .exe 扩展名
        if goos == "windows":
            exe_file = out_file + ".exe"
            os.replace(out_file, exe_file)
            out_file = exe_file

        # 保留二进制（方便本地测试 / 直接复制到目标机）
        bin_name = os.path.basename(out_file)

        # 压缩分发包：Windows 用 zip，Linux 用 tar.gz（tar+gzip 基础组件，省 unzip 依赖）
        if goos == "windows":
            archive_name = f"{APP_NAME}-{goos}-{goarch}.zip"
            archive_path = os.path.join(build_dir, archive_name)
            print(f"压缩 {out_file} -> {archive_name}...")
            with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as zf:
                zf.write(out_file, bin_name)
        else:
            archive_name = f"{APP_NAME}-{goos}-{goarch}.tar.gz"
            archive_path = os.path.join(build_dir, archive_name)
            print(f"压缩 {out_file} -> {archive_name}...")
            with tarfile.open(archive_path, "w:gz") as tf:
                tf.add(out_file, arcname=bin_name)

        # 计算 SHA256 并追加（同时记录二进制与压缩包的校验值）
        archive_digest = sha256_of(archive_path)
        bin_digest = sha256_of(out_file)
        with open(sha256sums, "a", encoding="utf-8") as f:
            f.write(f"{archive_digest}  {archive_name}\n")
            f.write(f"{bin_digest}  {bin_name}\n")

        # 二进制保留在 plat_dir，不再删除

    print(f"编译完成，所有文件已存储在 {build_dir} 目录下。")
    print(f"  各平台子目录 {APP_NAME}-${{GOOS}}-${{GOARCH}}/ 内为二进制（本地测试用）")
    print(f"  根目录 {APP_NAME}-${{GOOS}}-${{GOARCH}}.zip 为分发包")
    return 0


if __name__ == "__main__":
    sys.exit(main())
