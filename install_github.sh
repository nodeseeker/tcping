#!/usr/bin/env bash
#
# tcping 安装/更新/卸载脚本
# 用于自动安装、更新或卸载 tcping 工具
# 支持架构：amd64, arm64, 386, arm, loong64
#
# 使用方法：
#   sudo ./install.sh              # 安装或更新 tcping
#   sudo ./install.sh -u           # 卸载 tcping
#   sudo ./install.sh -f           # 强制安装（跳过确认）
#   sudo ./install.sh -v           # 详细输出
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
readonly GITHUB_API="https://api.github.com/repos/2959916298/tcping"
readonly GITHUB_REPO="https://github.com/2959916298/tcping"
readonly TEMP_DIR="/tmp/tcping_install"

# 全局变量
VERBOSE=false
FORCE=false
UNINSTALL=false
CURRENT_VERSION=""
LATEST_TAG=""
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

# =====================
# 下载器探测与下载（curl/wget 二选一，自动回退，缺哪个都能跑）
# =====================
DOWNLOADER=""

pick_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        DOWNLOADER=""
    fi
    print_verbose "下载器: ${DOWNLOADER:-无}"
}

# do_download URL OUTFILE — 下载到文件，失败返回非 0
do_download() {
    case "$DOWNLOADER" in
        curl) curl -fsSL --retry 2 --connect-timeout 10 -o "$2" "$1" ;;
        wget) wget -q -T 15 -O "$2" "$1" ;;
        *)    print_error "需要 curl 或 wget 才能下载"; return 1 ;;
    esac
}

# dl_stdout URL — 输出到标准输出（API/文本抓取用）
dl_stdout() {
    case "$DOWNLOADER" in
        curl) curl -fsSL --retry 2 -m 15 "$1" 2>/dev/null ;;
        wget) wget -qO- -T 15 "$1" 2>/dev/null ;;
        *)    return 1 ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
TCPing 安装脚本

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

# 检查系统依赖（下载器 curl/wget 二选一；解压用 tar+gzip，均为基础系统组件）
check_dependencies() {
    local missing_deps=()
    local install_list=()

    pick_downloader
    if [[ -z "$DOWNLOADER" ]]; then
        missing_deps+=("curl 或 wget")
        install_list+=("curl")
    fi
    if ! command -v tar >/dev/null 2>&1; then
        missing_deps+=("tar")
        install_list+=("tar")
    fi
    if ! command -v gzip >/dev/null 2>&1; then
        missing_deps+=("gzip")
        install_list+=("gzip")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "缺少依赖: ${missing_deps[*]}"
        # 按发行版给出安装命令提示
        if command -v apt-get >/dev/null 2>&1; then
            print_info "安装: sudo apt-get install -y ${install_list[*]}"
        elif command -v dnf >/dev/null 2>&1; then
            print_info "安装: sudo dnf install -y ${install_list[*]}"
        elif command -v yum >/dev/null 2>&1; then
            print_info "安装: sudo yum install -y ${install_list[*]}"
        elif command -v apk >/dev/null 2>&1; then
            print_info "安装: sudo apk add ${install_list[*]}"
        elif command -v pacman >/dev/null 2>&1; then
            print_info "安装: sudo pacman -S --noconfirm ${install_list[*]}"
        fi

        echo -n "是否自动安装缺少的依赖？ [y/N]: "
        if [[ "$FORCE" == true ]]; then
            echo "y (强制模式)"
            install_dependencies "${install_list[@]}"
        else
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                install_dependencies "${install_list[@]}"
            else
                print_error "缺少必要依赖，无法继续安装"
                exit 1
            fi
        fi
    else
        print_verbose "依赖检查通过"
    fi
    pick_downloader  # 自动安装依赖后重新探测
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
    api_response=$(dl_stdout "$GITHUB_API/releases/latest" || true)
    
    if [[ -n "$api_response" ]]; then
        LATEST_TAG=$(echo "$api_response" | grep -oE '"tag_name":\s*"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [[ -z "$LATEST_TAG" ]]; then
        print_warning "无法获取最新版本信息，使用默认版本 v1.9.9"
        LATEST_TAG="v1.9.9"
    fi
    
    # LATEST_TAG 可能带时间戳后缀（如 v1.9.10-20261030-205159）；
    # 版本比较只取 semver 部分，否则 sort -V 永远判带时间戳的更新，每次都提示更新
    LATEST_VERSION=$(echo "$LATEST_TAG" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    print_verbose "最新 tag: $LATEST_TAG"
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

# 下载并安装 tcping
install_tcping() {
    local arch
    arch=$(get_arch)
    
    print_info "正在为 $arch 架构下载 tcping $LATEST_VERSION..."
    print_info "下载器: ${DOWNLOADER}"
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # 构造下载 URL - GitHub 支持 releases/latest/download 直链，
    # 与 tag 无关（时间戳 tag 也兼容），无需依赖 API 获取的版本号
    local download_url="$GITHUB_REPO/releases/latest/download/tcping-linux-$arch.tar.gz"
    local output_file="tcping-linux-$arch.tar.gz"
    
    print_verbose "下载 URL: $download_url"
    
    # 下载文件（tar.gz：tar+gzip 是基础系统组件，省 unzip 依赖）
    if ! do_download "$download_url" "$output_file"; then
        print_error "下载失败"
        cleanup
        exit 1
    fi
    
    # 校验压缩包完整性
    if ! tar -tzf "$output_file" >/dev/null 2>&1; then
        print_error "下载的压缩包损坏"
        cleanup
        exit 1
    fi
    
    # 解压文件
    print_verbose "正在解压文件..."
    if ! tar -xzf "$output_file"; then
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
    print_title "TCPing 安装脚本"
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

