#!/usr/bin/env bash
#
# tcping安装脚本
# 用于自动安装、更新或卸载tcping工具
#

set -euo pipefail  # 严格模式：遇到错误立即退出，未定义变量报错，管道错误传播

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# 全局变量和配置
# ----------------------------------------------------------------------------

# 基本配置
readonly SCRIPT_NAME="$(basename "$0")"
readonly GITHUB_REPO="nodeseeker/tcping"
readonly INSTALL_DIR="/usr/bin"
readonly TEMP_DIR="/tmp/tcping_install_$$"
readonly LOG_FILE="/tmp/tcping_install_${USER}.log"

# 支持的架构映射
declare -A ARCH_MAP=(
    ["x86_64"]="amd64"
    ["aarch64"]="arm64"
    ["armv7l"]="arm"
    ["armv6l"]="arm"
    ["i386"]="386"
    ["i686"]="386"
)

# ----------------------------------------------------------------------------
# 日志和输出函数
# ----------------------------------------------------------------------------

# 日志函数（输出到stderr和日志文件）
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" >&2
}

# 彩色输出函数（输出到stderr避免与函数返回值混淆）
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

# ----------------------------------------------------------------------------
# 错误处理和清理函数
# ----------------------------------------------------------------------------

# 错误处理函数
error_exit() {
    print_error "$1"
    cleanup
    exit 1
}

# 清理临时文件
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        print_info "已清理临时目录: $TEMP_DIR"
    fi
}

# 信号处理
trap cleanup EXIT
trap 'error_exit "脚本被用户中断"' INT TERM

# ----------------------------------------------------------------------------
# 帮助和版本信息函数
# ----------------------------------------------------------------------------

# 显示帮助信息
show_help() {
    cat << EOF
用法: $SCRIPT_NAME [选项]

选项:
    -h, --help          显示此帮助信息
    -u, --uninstall     卸载tcping
    -f, --force         强制安装（跳过确认）
    -v, --verbose       详细输出
    --version           显示版本信息

示例:
    $SCRIPT_NAME                    # 交互式安装
    $SCRIPT_NAME --force            # 强制安装
    $SCRIPT_NAME --uninstall        # 卸载tcping

EOF
}

# 显示版本信息
show_version() {
    echo "$SCRIPT_NAME 版本 1.0"
}

# ----------------------------------------------------------------------------
# 系统和环境检查函数
# ----------------------------------------------------------------------------

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要root权限运行。请使用 sudo $SCRIPT_NAME"
    fi
}

# 检查系统架构
detect_architecture() {
    local arch=$(uname -m)
    local mapped_arch="${ARCH_MAP[$arch]:-}"
    
    if [[ -z "$mapped_arch" ]]; then
        error_exit "不支持的系统架构: $arch"
    fi
    
    print_info "检测到系统架构: $arch -> $mapped_arch"
    echo "$mapped_arch"
}

# 检查网络连接
check_network() {
    print_info "检查网络连接..."
    if ! ping -c 1 -W 5 github.com &>/dev/null; then
        error_exit "无法连接到GitHub，请检查网络连接"
    fi
    print_success "网络连接正常"
}

# 检查依赖工具
check_dependencies() {
    local deps=("curl" "unzip")
    local missing_deps=()
    
    print_info "检查依赖工具..."
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺少依赖工具: ${missing_deps[*]}"
        print_info "请先安装缺少的工具："
        print_info "  Ubuntu/Debian: apt-get install ${missing_deps[*]}"
        print_info "  CentOS/RHEL:   yum install ${missing_deps[*]}"
        print_info "  Fedora:        dnf install ${missing_deps[*]}"
        error_exit "请安装依赖工具后重试"
    fi
    
    print_success "依赖工具检查完成"
}

# ----------------------------------------------------------------------------
# 下载和文件处理函数
# ----------------------------------------------------------------------------

# 获取最新版本信息
get_latest_version() {
    print_info "获取最新版本信息..."
    
    local api_url="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    local version_info
    
    if ! version_info=$(curl -s --connect-timeout 10 "$api_url"); then
        error_exit "无法获取版本信息，请检查网络连接"
    fi
    
    local latest_version=$(echo "$version_info" | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    
    if [[ -z "$latest_version" ]]; then
        error_exit "无法解析版本信息"
    fi
    
    print_success "最新版本: $latest_version"
    echo "$latest_version"
}

# 构建下载URL
build_download_url() {
    local version="$1"
    local arch="$2"
    echo "https://github.com/$GITHUB_REPO/releases/download/$version/tcping-linux-$arch.zip"
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"
    
    print_info "下载文件: $url"
    
    if ! curl -L --connect-timeout 30 --max-time 300 -o "$output" "$url"; then
        error_exit "下载失败: $url"
    fi
    
    # 检查文件大小
    local file_size=$(stat -c%s "$output" 2>/dev/null || echo "0")
    if [[ $file_size -lt 1000 ]]; then
        error_exit "下载的文件太小，可能下载失败"
    fi
    
    print_success "下载完成: $output (大小: ${file_size} 字节)"
}

# 解压文件
extract_file() {
    local zip_file="$1"
    local extract_dir="$2"
    
    print_info "解压文件: $zip_file"
    
    if ! unzip -q "$zip_file" -d "$extract_dir"; then
        error_exit "解压失败: $zip_file"
    fi
    
    print_success "解压完成"
}

# ----------------------------------------------------------------------------
# 安装和版本管理函数
# ----------------------------------------------------------------------------

# 获取当前已安装的tcping版本
get_installed_version() {
    local target_file="$INSTALL_DIR/tcping"
    
    if [[ ! -f "$target_file" || ! -x "$target_file" ]]; then
        echo ""
        return
    fi
    
    # 尝试使用不同的参数获取版本
    local version=""
    
    # 尝试使用 --version 参数，优先获取完整版本字符串中的版本号部分
    if "$target_file" --version &>/dev/null; then
        # 提取格式为 x.y.z 的版本号
        version=$("$target_file" --version 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -n1 || echo "")
        
        # 如果上面没有找到版本号，则直接使用第一行输出作为版本
        if [[ -z "$version" ]]; then
            version=$("$target_file" --version 2>&1 | head -n1 | sed 's/^[^0-9]*\([0-9]\)/\1/' || echo "")
        fi
    fi
    
    # 如果上面的方法都失败了，尝试使用 -V 参数
    if [[ -z "$version" ]]; then
        if "$target_file" -V &>/dev/null; then
            version=$("$target_file" -V 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -n1 || echo "")
        fi
    fi
    
    echo "$version"
}

# 检查已安装版本
check_installed_version() {
    local target_file="$INSTALL_DIR/tcping"
    local latest_version="$1"
    
    if [[ -f "$target_file" ]]; then
        # 检查当前已安装版本
        local installed_version=$(get_installed_version)
        local display_version
        
        # 获取完整版本信息作为显示
        if [[ -x "$target_file" ]]; then
            display_version=$("$target_file" --version 2>&1 | head -n1 || echo "")
        fi
        
        if [[ -z "$display_version" ]]; then
            display_version="${installed_version:-未知版本}"
        fi
        
        # 如果能够获取版本号且版本相同，则跳过更新
        if [[ -n "$installed_version" && "$installed_version" == "$latest_version" ]]; then
            print_success "已安装的tcping版本 $display_version 已是最新版本，无需更新"
            exit 0
        fi
        
        print_info "已安装版本: $display_version, 最新版本: $latest_version"
        print_warning "发现现有的tcping，将被新版本替换"
    fi
}

# 安装文件
install_file() {
    local source_file="$1"
    local target_file="$INSTALL_DIR/tcping"
    
    print_info "安装tcping到: $target_file"
    
    # 检查源文件是否存在
    if [[ ! -f "$source_file" ]]; then
        error_exit "源文件不存在: $source_file"
    fi
    
    # 复制文件并设置权限
    if ! cp "$source_file" "$target_file"; then
        error_exit "复制文件失败"
    fi
    
    if ! chmod +x "$target_file"; then
        error_exit "设置执行权限失败"
    fi
    
    if ! chown root:root "$target_file"; then
        error_exit "设置文件所有者失败"
    fi
    
    print_success "安装完成"
}

# 验证安装
verify_installation() {
    local target_file="$INSTALL_DIR/tcping"
    
    print_info "验证安装..."
    
    if [[ ! -f "$target_file" ]]; then
        error_exit "安装验证失败: 文件不存在"
    fi
    
    if [[ ! -x "$target_file" ]]; then
        error_exit "安装验证失败: 文件不可执行"
    fi
      # 测试运行
    if ! "$target_file" --version &>/dev/null; then
        print_warning "无法获取版本信息，但文件已安装"
    else
        # 优先获取完整版本信息作为显示
        local version_output=$("$target_file" --version 2>&1 | head -n1 || echo "")
        if [[ -z "$version_output" || "$version_output" == *"未知版本"* ]]; then
            version_output="未知版本"
        fi
        print_success "安装验证成功，版本: $version_output"
    fi
}

# ----------------------------------------------------------------------------
# 卸载函数
# ----------------------------------------------------------------------------

# 卸载tcping
uninstall_tcping() {
    local target_file="$INSTALL_DIR/tcping"
    
    print_info "开始卸载tcping..."
    
    if [[ ! -f "$target_file" ]]; then
        print_warning "tcping未安装或已被删除"
        return 0
    fi
    
    # 询问确认
    if [[ "${FORCE:-false}" != "true" ]]; then
        echo -n "确定要卸载tcping吗？[y/N]: " >&2
        read -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "卸载已取消"
            return 0
        fi
    fi
    
    # 删除文件
    if rm -f "$target_file"; then
        print_success "tcping已成功卸载"
    else
        error_exit "卸载失败"
    fi
}

# ----------------------------------------------------------------------------
# 安装主流程
# ----------------------------------------------------------------------------

# 主安装函数
install_tcping() {
    print_info "开始安装tcping..."
    
    # 检查各种前置条件
    check_root
    check_dependencies
    check_network
    
    # 检测架构
    local arch=$(detect_architecture)
    
    # 获取最新版本
    local version=$(get_latest_version)
    
    # 提取版本号（去除v前缀）
    local clean_version=$(echo "$version" | sed 's/^v//')
    
    # 检查已安装版本
    check_installed_version "$clean_version"
    
    # 构建下载URL
    local download_url=$(build_download_url "$version" "$arch")
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 下载文件
    local zip_file="$TEMP_DIR/tcping-linux-$arch.zip"
    download_file "$download_url" "$zip_file"
    
    # 解压文件
    extract_file "$zip_file" "$TEMP_DIR"
    
    # 查找解压出的tcping文件
    local tcping_file=$(find "$TEMP_DIR" -name "tcping" -type f | head -n1)
    if [[ -z "$tcping_file" ]]; then
        error_exit "解压后未找到tcping文件"
    fi
    
    # 安装文件
    install_file "$tcping_file"
    
    # 验证安装
    verify_installation
    
    print_success "tcping安装完成！"
    print_info "现在可以在任何位置使用 'tcping' 命令"
    print_info "使用 'tcping --help' 查看帮助信息"
}

# ----------------------------------------------------------------------------
# 主函数和入口点
# ----------------------------------------------------------------------------

# 主函数
main() {
    local uninstall=false
    local force=false
    local verbose=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -u|--uninstall)
                uninstall=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 设置全局变量
    if [[ "$force" == "true" ]]; then
        export FORCE=true
    fi
    
    if [[ "$verbose" == "true" ]]; then
        set -x
    fi
    
    # 创建日志文件
    touch "$LOG_FILE"
    
    print_info "tcping自动安装脚本启动"
    print_info "日志文件: $LOG_FILE"
    
    if [[ "$uninstall" == "true" ]]; then
        check_root
        uninstall_tcping
    else
        # 安装前确认
        if [[ "${FORCE:-false}" != "true" ]]; then
            echo "此脚本将自动下载并安装最新版本的tcping工具。" >&2
            echo -n "是否继续？[Y/n]: " >&2
            read -r
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                print_info "安装已取消"
                exit 0
            fi
        fi
        
        install_tcping
    fi
    
    print_success "脚本执行完成"
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
