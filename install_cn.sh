#!/usr/bin/env bash
#
# tcping 安装/更新/卸载脚本 (国内版本)
# 用于自动安装、更新或卸载 tcping 工具
# 支持架构：amd64, arm64, 386, arm, loong64
# 国内版本：优先使用国内镜像源，提高下载速度
#
# 使用方法：
#   sudo ./install_cn.sh              # 安装或更新 tcping
#   sudo ./install_cn.sh -u           # 卸载 tcping
#   sudo ./install_cn.sh -f           # 强制安装（跳过确认）
#   sudo ./install_cn.sh -v           # 详细输出
#

set -euo pipefail  # 严格模式：遇到错误立即退出，未定义变量报错，管道错误传播

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
readonly GITHUB_REPO="nodeseeker/tcping"
readonly TEMP_DIR="/tmp/tcping_install"

# 国内镜像源配置（按优先级排序）
readonly MIRROR_SOURCES=(
    "https://gh-proxy.com/https://github.com"
    "https://ghfast.top/https://github.com"
    "https://github.com"
)

# 全局变量
VERBOSE=false
FORCE=false
UNINSTALL=false
CURRENT_VERSION=""
LATEST_VERSION=""

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

print_title() {
    echo -e "${BOLD}${BLUE}$1${NC}"
}

# 显示帮助信息
show_help() {
    cat << EOF
TCPing 安装脚本 (国内版本)

用法: $0 [选项]

选项:
    -u, --uninstall     卸载 tcping
    -f, --force         强制安装（跳过确认）
    -v, --verbose       详细输出
    -h, --help          显示此帮助信息

支持的架构: amd64, arm64, 386, arm, loong64

国内版本特性:
    - 优先使用国内镜像源 (gh-proxy.com, ghfast.top)
    - 自动回退到 GitHub 原始地址
    - 提高下载速度和成功率

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
        echo -n "是否安装缺少的依赖？ [y/N]: "
        
        if [[ "$FORCE" == true ]]; then
            echo "y (强制模式)"
            install_dependencies "${missing_deps[@]}"
        else
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
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        i386|i686)
            echo "386"
            ;;
        armv6l|armv7l|arm*)
            echo "arm"
            ;;
        loongarch64)
            echo "loong64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            print_info "支持的架构: amd64, arm64, 386, arm, loong64"
            exit 1
            ;;
    esac
}

# 获取当前已安装版本
get_current_version() {
    if command -v "$TCPING_BIN" &> /dev/null; then
        # 执行 tcping --version 并解析版本号
        local version_output
        version_output=$("$TCPING_BIN" --version 2>/dev/null || echo "")
        if [[ -n "$version_output" ]]; then
            # 提取版本号，格式类似 "TCPing 版本 v1.7.1"
            CURRENT_VERSION=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        fi
    fi
    
    if [[ -n "$CURRENT_VERSION" ]]; then
        print_verbose "当前安装版本: $CURRENT_VERSION"
    else
        print_verbose "未检测到已安装的 tcping"
    fi
}

# 获取最新版本
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

# 比较版本
compare_versions() {
    local current="$1"
    local latest="$2"
    
    # 移除 v 前缀
    current=${current#v}
    latest=${latest#v}
    
    # 使用 sort 比较版本号
    local higher
    higher=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)
    
    if [[ "$higher" == "$latest" && "$current" != "$latest" ]]; then
        return 1  # 需要更新
    else
        return 0  # 已是最新或更高版本
    fi
}

# 尝试从指定源下载文件
try_download() {
    local download_url="$1"
    local output_file="$2"
    local timeout=30
    
    print_verbose "尝试从源下载: $download_url"
    
    # 使用 curl 下载，设置超时和重试
    if curl -L --connect-timeout 10 --max-time $timeout --retry 2 -o "$output_file" "$download_url" 2>/dev/null; then
        # 验证下载的文件是否为有效的zip文件
        if unzip -t "$output_file" &>/dev/null; then
            print_verbose "下载成功: $(basename "$download_url")"
            return 0
        else
            print_verbose "下载的文件损坏，删除并重试"
            rm -f "$output_file"
            return 1
        fi
    else
        print_verbose "下载失败: $(basename "$download_url")"
        rm -f "$output_file"
        return 1
    fi
}

# 下载并安装 tcping
install_tcping() {
    local arch
    arch=$(get_arch)
    
    print_info "正在为 $arch 架构下载 tcping $LATEST_VERSION..."
    print_info "使用国内镜像源加速下载..."
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # 构造文件名
    local filename="tcping-linux-$arch"
    local output_file="tcping.zip"
    local download_success=false
    
    # 尝试从各个镜像源下载
    for mirror in "${MIRROR_SOURCES[@]}"; do
        local download_url="$mirror/$GITHUB_REPO/releases/download/$LATEST_VERSION/${filename}.zip"
        
        print_info "正在尝试镜像源: $(echo "$mirror" | cut -d'/' -f3)"
        
        if try_download "$download_url" "$output_file"; then
            download_success=true
            print_success "下载成功！使用的镜像源: $(echo "$mirror" | cut -d'/' -f3)"
            break
        else
            print_warning "镜像源 $(echo "$mirror" | cut -d'/' -f3) 下载失败，尝试下一个源..."
        fi
        
        # 等待一秒再尝试下一个源
        sleep 1
    done
    
    if [[ "$download_success" != true ]]; then
        print_error "所有镜像源下载均失败"
        print_info "可能的原因："
        print_info "1. 网络连接问题"
        print_info "2. 版本 $LATEST_VERSION 不存在"
        print_info "3. 架构 $arch 不受支持"
        cleanup
        exit 1
    fi
    
    # 解压文件
    print_verbose "正在解压文件..."
    if ! unzip -q "$output_file"; then
        print_error "解压失败"
        cleanup
        exit 1
    fi
    
    # 查找二进制文件
    local binary_file
    binary_file=$(find . -name "$TCPING_BIN" -type f | head -1)
    
    if [[ -z "$binary_file" ]]; then
        print_error "未找到二进制文件"
        cleanup
        exit 1
    fi
    
    # 安装二进制文件
    print_verbose "正在安装到 $INSTALL_DIR/$TCPING_BIN..."
    if ! cp "$binary_file" "$INSTALL_DIR/$TCPING_BIN"; then
        print_error "安装失败：无法复制文件到 $INSTALL_DIR"
        cleanup
        exit 1
    fi
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/$TCPING_BIN"
    
    # 清理临时文件
    cleanup
    
    print_success "tcping $LATEST_VERSION 安装完成！"
    
    # 验证安装
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
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--uninstall)
                UNINSTALL=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示标题
    print_title "TCPing 安装脚本 (国内版本)"
    echo
    
    # 检查权限
    check_root
    
    # 如果是卸载模式
    if [[ "$UNINSTALL" == true ]]; then
        uninstall_tcping
        exit 0
    fi
    
    # 检查依赖
    check_dependencies
    
    # 获取版本信息
    get_current_version
    get_latest_version
    
    # 检查是否需要安装或更新
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
        
        if compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"; then
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

# 设置清理陷阱
trap cleanup EXIT INT TERM

# 运行主函数
main "$@"
