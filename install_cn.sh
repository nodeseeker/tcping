#!/usr/bin/env bash
#
# tcping 安装/更新/卸载脚本（简体中文版，国内镜像优化）
# 用于自动安装、更新或卸载 tcping 工具
# 支持架构：amd64, arm64, 386, arm, loong64
#
# 用法示例：
#   sudo ./install_cn.sh              # 安装或更新 tcping
#   sudo ./install_cn.sh -u           # 卸载 tcping
#   sudo ./install_cn.sh -f           # 强制安装（跳过确认）
#   sudo ./install_cn.sh -v           # 详细输出
#

set -euo pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# 基本配置
readonly INSTALL_DIR="/usr/local/bin"
readonly TCPING_BIN="tcping"
readonly GITHUB_API="https://api.github.com/repos/nodeseeker/tcping"
readonly GITHUB_REPO="https://github.com/nodeseeker/tcping"
readonly TEMP_DIR="/tmp/tcping_install"

# 国内镜像源
readonly CN_MIRRORS=(
    "https://gh-proxy.com/https://github.com/nodeseeker/tcping/releases/download"
    "https://ghfast.top/https://github.com/nodeseeker/tcping/releases/download"
)

# 全局变量
VERBOSE=false
FORCE=false
UNINSTALL=false
CURRENT_VERSION=""
LATEST_VERSION=""

# 打印函数
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1" >&2; }
print_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[详细]${NC} $1"; }
print_title() { echo -e "${BOLD}${BLUE}$1${NC}"; }

# 帮助信息
show_help() {
    cat << EOF
TCPing 安装脚本（简体中文版）

用法: $0 [选项]

选项:
    -u, --uninstall     卸载 tcping
    -f, --force         强制安装（跳过确认）
    -v, --verbose       详细输出
    -h, --help          显示此帮助信息

支持的架构: amd64, arm64, 386, arm, loong64

示例:
    sudo $0             # 安装或更新 tcping
    sudo $0 -u          # 卸载 tcping
    sudo $0 -f          # 强制安装
    sudo $0 -v          # 详细输出安装过程

EOF
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
    print_verbose "Root 权限检查通过"
}

# 检查系统依赖
check_dependencies() {
    local missing_deps=()
    local deps=("curl" "unzip" "grep" "awk")
    print_verbose "检查系统依赖..."
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "缺少以下依赖程序: ${missing_deps[*]}"
        if [[ "$FORCE" == true ]]; then
            print_info "强制模式下自动安装依赖..."
            install_dependencies "${missing_deps[@]}"
        else
            echo -n "是否安装缺少的依赖？ [y/N]: "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                install_dependencies "${missing_deps[@]}"
            else
                print_error "缺少必要依赖，无法继续安装"
                exit 1
            fi
        fi
    else
        print_verbose "所有依赖已满足"
    fi
}

# 安装依赖
install_dependencies() {
    local deps=("$@")
    print_info "正在安装依赖: ${deps[*]}"
    if command -v apt &> /dev/null; then
        apt update && apt install -y "${deps[@]}"
    elif command -v yum &> /dev/null; then
        yum install -y "${deps[@]}"
    elif command -v dnf &> /dev/null; then
        dnf install -y "${deps[@]}"
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm "${deps[@]}"
    elif command -v apk &> /dev/null; then
        apk add "${deps[@]}"
    elif command -v zypper &> /dev/null; then
        zypper install -y "${deps[@]}"
    else
        print_error "无法识别的包管理器，请手动安装: ${deps[*]}"
        exit 1
    fi
    print_success "依赖安装完成"
}

# 获取系统架构
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "amd64";;
        aarch64|arm64)
            echo "arm64";;
        i386|i686)
            echo "386";;
        armv6l|armv7l|arm*)
            echo "arm";;
        loongarch64)
            echo "loong64";;
        *)
            print_error "不支持的架构: $arch"
            print_info "支持的架构: amd64, arm64, 386, arm, loong64"
            exit 1;;
    esac
}

# 获取当前已安装版本
get_current_version() {
    if command -v "$TCPING_BIN" &> /dev/null; then
        local version_output
        version_output=$("$TCPING_BIN" --version 2>/dev/null || echo "")
        if [[ -n "$version_output" ]]; then
            CURRENT_VERSION=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
    fi
    if [[ -n "$CURRENT_VERSION" ]]; then
        print_verbose "当前安装版本: $CURRENT_VERSION"
    else
        print_verbose "未检测到已安装的 tcping"
    fi
}

# 获取最新版本（优先国内镜像）
get_latest_version() {
    print_verbose "正在获取最新版本信息..."
    local api_response
    api_response=$(curl -s "$GITHUB_API/releases/latest" 2>/dev/null || echo "")
    if [[ -n "$api_response" ]]; then
        LATEST_VERSION=$(echo "$api_response" | grep -oE '"tag_name":\s*"[^"]*"' | cut -d'"' -f4)
    fi
    if [[ -z "$LATEST_VERSION" ]]; then
        print_warning "无法获取最新版本信息，使用默认版本 v1.7.1"
        LATEST_VERSION="v1.7.1"
    fi
    print_verbose "最新版本: $LATEST_VERSION"
}

# 下载并安装 tcping
install_tcping() {
    local arch
    arch=$(get_arch)
    print_info "正在为 $arch 架构下载 tcping $LATEST_VERSION..."
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    # 优先国内镜像
    local found_url=""
    for mirror in "${CN_MIRRORS[@]}"; do
        local url="$mirror/$LATEST_VERSION/tcping-linux-$arch.zip"
        print_verbose "尝试国内镜像: $url"
        if curl -sfI "$url" >/dev/null 2>&1; then
            found_url="$url"
            break
        fi
    done
    if [[ -z "$found_url" ]]; then
        found_url="$GITHUB_REPO/releases/download/$LATEST_VERSION/tcping-linux-$arch.zip"
        print_verbose "使用GitHub主站: $found_url"
    fi
    if ! curl -L -o "tcping.zip" "$found_url"; then
        print_error "下载失败"
        cleanup
        exit 1
    fi
    print_verbose "正在解压文件..."
    if ! unzip -q "tcping.zip"; then
        print_error "解压失败"
        cleanup
        exit 1
    fi
    local binary_file
    binary_file=$(find . -name "$TCPING_BIN" -type f | head -1)
    if [[ -z "$binary_file" ]]; then
        print_error "未找到二进制文件"
        cleanup
        exit 1
    fi
    print_verbose "正在安装到 $INSTALL_DIR/$TCPING_BIN..."
    if ! cp "$binary_file" "$INSTALL_DIR/$TCPING_BIN"; then
        print_error "安装失败：无法复制文件到 $INSTALL_DIR"
        cleanup
        exit 1
    fi
    chmod +x "$INSTALL_DIR/$TCPING_BIN"
    cleanup
    print_success "tcping $LATEST_VERSION 安装完成！"
    if command -v "$TCPING_BIN" &> /dev/null; then
        print_info "安装验证："
        "$TCPING_BIN" --version
    else
        print_warning "安装完成，但 $TCPING_BIN 不在 PATH 中"
        print_info "请确保 $INSTALL_DIR 在您的 PATH 环境变量中"
    fi
}

# 卸载 tcping
uninstall_tcping() {
    if [[ -f "$INSTALL_DIR/$TCPING_BIN" ]]; then
        print_info "正在卸载 tcping..."
        if [[ "$FORCE" == false ]]; then
            echo -n "确认卸载 tcping？ [y/N]: "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_info "取消卸载"
                exit 0
            fi
        fi
        rm -f "$INSTALL_DIR/$TCPING_BIN"
        print_success "tcping 已成功卸载"
    else
        print_warning "tcping 未安装"
    fi
}

# 清理临时文件
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        print_verbose "临时文件已清理"
    fi
}

# 主函数
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--uninstall)
                UNINSTALL=true; shift;;
            -f|--force)
                FORCE=true; shift;;
            -v|--verbose)
                VERBOSE=true; shift;;
            -h|--help)
                show_help; exit 0;;
            *)
                print_error "未知选项: $1"; show_help; exit 1;;
        esac
    done
    print_title "TCPing 安装脚本（简体中文版）"
    echo
    check_root
    if [[ "$UNINSTALL" == true ]]; then
        uninstall_tcping
        exit 0
    fi
    check_dependencies
    get_current_version
    get_latest_version
    if [[ -z "$CURRENT_VERSION" ]]; then
        print_info "检测到 tcping 未安装"
        if [[ "$FORCE" == false ]]; then
            echo -n "是否安装 tcping $LATEST_VERSION？ [Y/n]: "
            read -r response
            if [[ "$response" =~ ^[Nn]$ ]]; then
                print_info "取消安装"
                exit 0
            fi
        fi
        install_tcping
    else
        print_info "检测到已安装版本: $CURRENT_VERSION"
        if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
            print_success "您已安装最新版本 $CURRENT_VERSION"
            if [[ "$FORCE" == true ]]; then
                print_info "强制重新安装..."
                install_tcping
            fi
        else
            print_info "发现新版本: $LATEST_VERSION"
            if [[ "$FORCE" == false ]]; then
                echo -n "是否更新到 $LATEST_VERSION？ [Y/n]: "
                read -r response
                if [[ "$response" =~ ^[Nn]$ ]]; then
                    print_info "取消更新"
                    exit 0
                fi
            fi
            install_tcping
        fi
    fi
}

trap cleanup EXIT INT TERM
main "$@"
