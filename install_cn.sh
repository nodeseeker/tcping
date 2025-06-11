#!/bin/bash

set -euo pipefail  # 严格模式：遇到错误立即退出，未定义变量报错，管道错误传播

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 全局变量
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

# 日志函数（输出到stderr）
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" >&2
}

# 输出函数（输出到stderr避免与函数返回值混淆）
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

# 增强的网络连接检查
check_network() {
    print_info "检查网络连接..."
    
    # 检查基本网络连接
    if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        if ! ping -c 1 -W 5 114.114.114.114 &>/dev/null; then
            error_exit "无法连接到互联网，请检查网络连接"
        fi
    fi
    
    # 检查GitHub连接
    if ! ping -c 1 -W 10 github.com &>/dev/null; then
        print_warning "无法直接连接GitHub，但基本网络正常"
        # 尝试通过代理检查
        if ! curl -s --connect-timeout 10 --max-time 30 "https://api.github.com" >/dev/null; then
            error_exit "无法连接到GitHub API，请检查网络连接或防火墙设置"
        fi
    fi
    
    print_success "网络连接正常"
}

# 检查依赖工具
check_dependencies() {
    local deps=("curl" "unzip" "wget")
    local missing_deps=()
    local available_tools=()
    
    print_info "检查依赖工具..."
    
    # 检查curl和wget，至少需要一个
    local has_downloader=false
    for tool in "curl" "wget"; do
        if command -v "$tool" &>/dev/null; then
            available_tools+=("$tool")
            has_downloader=true
            if [[ "$tool" == "curl" ]]; then
                export DOWNLOADER="curl"
            fi
        fi
    done
    
    if [[ "$has_downloader" == "false" ]]; then
        missing_deps+=("curl或wget")
    else
        # 如果没有curl但有wget，使用wget
        if [[ -z "${DOWNLOADER:-}" ]] && command -v "wget" &>/dev/null; then
            export DOWNLOADER="wget"
        fi
    fi
    
    # 检查unzip
    if ! command -v "unzip" &>/dev/null; then
        missing_deps+=("unzip")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺少依赖工具: ${missing_deps[*]}"
        print_info "请先安装缺少的工具："
        print_info "  Ubuntu/Debian: apt-get install curl wget unzip"
        print_info "  CentOS/RHEL:   yum install curl wget unzip"
        print_info "  Fedora:        dnf install curl wget unzip"
        print_info "  Alpine:        apk add curl wget unzip"
        error_exit "请安装依赖工具后重试"
    fi
    
    print_success "依赖工具检查完成，可用工具: ${available_tools[*]}"
}

# 增强的版本获取函数
get_latest_version() {
    print_info "获取最新版本信息..."
    
    local api_urls=(
        "https://api.github.com/repos/$GITHUB_REPO/releases/latest"
        "https://github.com/$GITHUB_REPO/releases/latest"
    )
    
    local version_info=""
    local latest_version=""
    
    # 尝试多个API端点
    for api_url in "${api_urls[@]}"; do
        print_info "尝试从 $api_url 获取版本信息..."
        
        if [[ "${DOWNLOADER:-curl}" == "curl" ]]; then
            if version_info=$(curl -s --connect-timeout 15 --max-time 30 \
                --retry 2 --retry-delay 1 \
                -H "User-Agent: tcping-installer/1.0" \
                "$api_url" 2>/dev/null); then
                break
            fi
        else
            if version_info=$(wget -q --timeout=30 --tries=2 \
                --user-agent="tcping-installer/1.0" \
                -O- "$api_url" 2>/dev/null); then
                break
            fi
        fi
        
        print_warning "从 $api_url 获取版本信息失败，尝试下一个端点..."
    done
    
    # 检查是否成功获取到版本信息
    if [[ -z "$version_info" ]]; then
        print_error "无法从任何API端点获取版本信息"
        print_error "请检查网络连接、防火墙设置或GitHub访问权限"
        print_info "可能的解决方案："
        print_info "1. 检查网络连接是否正常"
        print_info "2. 确认可以访问 github.com"
        print_info "3. 检查防火墙或代理设置"
        print_info "4. 稍后重试"
        return 1  # 返回错误状态而不是直接退出
    fi
    
    # 解析版本号
    if echo "$version_info" | grep -q '"tag_name"'; then
        # JSON格式响应
        latest_version=$(echo "$version_info" | grep '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    else
        # HTML格式响应，尝试解析
        latest_version=$(echo "$version_info" | grep -oE 'releases/tag/[^"]*' | head -n1 | sed 's/releases\/tag\///')
    fi
    
    # 验证版本号格式
    if [[ -z "$latest_version" ]] || [[ ! "$latest_version" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        print_error "无法解析版本信息或版本格式无效: '$latest_version'"
        print_info "获取到的原始数据: ${version_info:0:200}..."
        return 1
    fi
    
    print_success "最新版本: $latest_version"
    echo "$latest_version"
    return 0
}

# 构建下载URL
build_download_url() {
    local version="$1"
    local arch="$2"
    
    # 提供多个镜像源
    local mirrors=(
        "https://gh-proxy.com/https://github.com/$GITHUB_REPO/releases/download/$version/tcping-linux-$arch.zip"
        "https://ghproxy.com/https://github.com/$GITHUB_REPO/releases/download/$version/tcping-linux-$arch.zip"
        "https://github.com/$GITHUB_REPO/releases/download/$version/tcping-linux-$arch.zip"
    )
    
    # 返回所有可能的URL
    printf '%s\n' "${mirrors[@]}"
}

# 增强的下载函数
download_file() {
    local urls=("$@")
    local output="${urls[-1]}"  # 最后一个参数是输出文件
    unset 'urls[-1]'  # 移除最后一个元素
    
    print_info "开始下载文件到: $output"
    
    local success=false
    local attempt=0
    
    for url in "${urls[@]}"; do
        ((attempt++))
        print_info "尝试 $attempt: $url"
        
        local download_success=false
        
        if [[ "${DOWNLOADER:-curl}" == "curl" ]]; then
            if curl -L --connect-timeout 30 --max-time 600 \
                --retry 3 --retry-delay 2 \
                -H "User-Agent: tcping-installer/1.0" \
                --progress-bar \
                -o "$output" "$url"; then
                download_success=true
            fi
        else
            if wget --timeout=600 --tries=3 --wait=2 \
                --user-agent="tcping-installer/1.0" \
                --progress=bar:force \
                -O "$output" "$url"; then
                download_success=true
            fi
        fi
        
        if [[ "$download_success" == "true" ]]; then
            # 检查文件大小和完整性
            local file_size=$(stat -c%s "$output" 2>/dev/null || echo "0")
            if [[ $file_size -gt 1000 ]]; then
                # 尝试检查ZIP文件完整性
                if unzip -t "$output" &>/dev/null; then
                    print_success "下载完成: $output (大小: ${file_size} 字节)"
                    success=true
                    break
                else
                    print_warning "下载的文件可能损坏，尝试下一个源..."
                    rm -f "$output"
                fi
            else
                print_warning "下载的文件太小，可能下载失败，尝试下一个源..."
                rm -f "$output"
            fi
        else
            print_warning "从 $url 下载失败，尝试下一个源..."
        fi
    done
    
    if [[ "$success" != "true" ]]; then
        error_exit "所有下载源都失败了"
    fi
}

# 解压文件
extract_file() {
    local zip_file="$1"
    local extract_dir="$2"
    
    print_info "解压文件: $zip_file"
    
    # 检查ZIP文件完整性
    if ! unzip -t "$zip_file" &>/dev/null; then
        error_exit "ZIP文件损坏或格式无效: $zip_file"
    fi
    
    if ! unzip -q "$zip_file" -d "$extract_dir"; then
        error_exit "解压失败: $zip_file"
    fi
    
    print_success "解压完成"
}

# 备份现有版本
backup_existing() {
    local target_file="$INSTALL_DIR/tcping"
    
    if [[ -f "$target_file" ]]; then
        local backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "发现现有的tcping，备份到: $backup_file"
        
        if ! cp "$target_file" "$backup_file"; then
            error_exit "备份失败"
        fi
        
        print_success "备份完成"
    fi
}

# 安装文件
install_file() {
    local source_file="$1"
    local target_file="$INSTALL_DIR/tcping"
    
    print_info "安装tcping到: $target_file"
    
    # 检查源文件是否存在且可执行
    if [[ ! -f "$source_file" ]]; then
        error_exit "源文件不存在: $source_file"
    fi
    
    # 检查源文件是否为有效的可执行文件
    if ! file "$source_file" | grep -q "executable"; then
        print_warning "源文件可能不是有效的可执行文件"
    fi
    
    # 确保目标目录存在
    if [[ ! -d "$INSTALL_DIR" ]]; then
        error_exit "安装目录不存在: $INSTALL_DIR"
    fi
    
    # 复制文件
    if ! cp "$source_file" "$target_file"; then
        error_exit "复制文件失败"
    fi
    
    # 设置权限
    if ! chmod +x "$target_file"; then
        error_exit "设置执行权限失败"
    fi
    
    # 设置所有者
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
    local test_output
    if test_output=$("$target_file" --version 2>&1); then
        print_success "安装验证成功，版本: $test_output"
    elif test_output=$("$target_file" -h 2>&1 | head -n1); then
        print_success "安装验证成功: $test_output"
    else
        print_warning "无法获取版本信息，但文件已安装且可执行"
    fi
    
    # 检查PATH
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        print_warning "$INSTALL_DIR 不在PATH中，可能需要重新登录或手动添加到PATH"
    fi
}

# 卸载函数
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
        
        # 清理备份文件（可选）
        local backup_files=("${target_file}.backup."*)
        if [[ -f "${backup_files[0]}" ]]; then
            echo -n "是否删除备份文件？[y/N]: " >&2
            read -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "${target_file}".backup.*
                print_info "备份文件已删除"
            fi
        fi
    else
        error_exit "卸载失败"
    fi
}

# 主安装函数
install_tcping() {
    print_info "开始安装tcping..."
    
    # 检查各种前置条件
    check_root
    check_dependencies
    check_network
    
    # 检测架构
    local arch
    if ! arch=$(detect_architecture); then
        error_exit "架构检测失败"
    fi
    
    # 获取最新版本（关键修复：检查返回状态）
    local version
    if ! version=$(get_latest_version); then
        error_exit "获取版本信息失败，无法继续安装"
    fi
    
    # 验证版本信息不为空
    if [[ -z "$version" ]]; then
        error_exit "版本信息为空，无法继续安装"
    fi
    
    # 构建下载URL数组
    local download_urls
    readarray -t download_urls < <(build_download_url "$version" "$arch")
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 下载文件
    local zip_file="$TEMP_DIR/tcping-linux-$arch.zip"
    download_file "${download_urls[@]}" "$zip_file"
    
    # 解压文件
    extract_file "$zip_file" "$TEMP_DIR"
    
    # 查找解压出的tcping文件
    local tcping_file
    tcping_file=$(find "$TEMP_DIR" -name "tcping" -type f | head -n1)
    if [[ -z "$tcping_file" ]]; then
        # 尝试查找其他可能的文件名
        tcping_file=$(find "$TEMP_DIR" -name "*tcping*" -type f | head -n1)
        if [[ -z "$tcping_file" ]]; then
            print_error "解压后未找到tcping文件"
            print_info "临时目录内容:"
            ls -la "$TEMP_DIR" >&2 || true
            error_exit "找不到可执行文件"
        fi
    fi
    
    print_info "找到tcping文件: $tcping_file"
    
    # 备份现有版本
    backup_existing
    
    # 安装文件
    install_file "$tcping_file"
    
    # 验证安装
    verify_installation
    
    print_success "tcping安装完成！"
    print_info "现在可以在任何位置使用 'tcping' 命令"
    print_info "使用 'tcping --help' 查看帮助信息"
}

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
    touch "$LOG_FILE" 2>/dev/null || {
        print_warning "无法创建日志文件: $LOG_FILE"
        export LOG_FILE="/dev/null"
    }
    
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
