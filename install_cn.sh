#!/bin/bash


set -euo pipefail  # 严格模式：遇到错误立即退出，未定义变量报错，管道错误传播

# ===== 常量定义 =====
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly GITHUB_REPO="nodeseeker/tcping"
readonly INSTALL_DIR="/usr/local/bin"  # 使用更标准的路径
readonly CONFIG_DIR="/etc/tcping"
readonly TEMP_DIR="/tmp/tcping_install_$$"
readonly LOG_FILE="/var/log/tcping_install.log"
readonly LOCK_FILE="/var/lock/tcping_install.lock"
readonly USER_LOG_FILE="/tmp/tcping_install_${USER}_$(date +%Y%m%d_%H%M%S).log"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# 支持的架构映射 - 扩展更多架构
declare -A ARCH_MAP=(
    ["x86_64"]="amd64"
    ["aarch64"]="arm64"
    ["armv8l"]="arm64"
    ["armv7l"]="arm"
    ["armv6l"]="arm"
    ["armv5tel"]="arm"
    ["i386"]="386"
    ["i686"]="386"
    ["i586"]="386"
    ["mips"]="mips"
    ["mips64"]="mips64"
    ["mipsel"]="mipsle"
    ["mips64el"]="mips64le"
    ["ppc64"]="ppc64"
    ["ppc64le"]="ppc64le"
    ["s390x"]="s390x"
    ["riscv64"]="riscv64"
)

# 支持的操作系统检测
declare -A OS_MAP=(
    ["Linux"]="linux"
    ["Darwin"]="darwin"
    ["FreeBSD"]="freebsd"
    ["OpenBSD"]="openbsd"
    ["NetBSD"]="netbsd"
)

# 全局变量
VERBOSE=false
FORCE=false
DRY_RUN=false
INSTALL_METHOD="binary"  # binary, compile
PROXY_URL=""
DOWNLOADER=""
DETECTED_OS=""
DETECTED_ARCH=""
INSTALL_VERSION=""

# ===== 工具函数 =====

# 锁文件管理
acquire_lock() {
    local timeout=300  # 5分钟超时
    local count=0
    
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        if [[ $count -ge $timeout ]]; then
            error_exit "获取锁文件超时，可能有其他安装进程正在运行"
        fi
        sleep 1
        ((count++))
    done
    
    # 写入PID到锁文件
    echo $$ > "$LOCK_FILE/pid"
    echo "$(date)" > "$LOCK_FILE/timestamp"
}

release_lock() {
    if [[ -d "$LOCK_FILE" ]]; then
        rm -rf "$LOCK_FILE"
    fi
}

# 增强的日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$$] [$level] $message"
    
    # 同时写入多个日志文件
    echo "$log_entry" >> "$USER_LOG_FILE" 2>/dev/null || true
    if [[ -w "$(dirname "$LOG_FILE")" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    # 根据级别输出到不同的流
    case "$level" in
        "ERROR"|"FATAL")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARNING]${NC} $message" >&2
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" >&2
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" >&2
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message" >&2
            fi
            ;;
    esac
}

# 输出函数
print_info() { log "INFO" "$@"; }
print_success() { log "SUCCESS" "$@"; }
print_warning() { log "WARN" "$@"; }
print_error() { log "ERROR" "$@"; }
print_debug() { log "DEBUG" "$@"; }

# 错误处理函数
error_exit() {
    local exit_code=${2:-1}
    print_error "$1"
    cleanup
    exit "$exit_code"
}

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local message=${3:-"Processing"}
    local width=40
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}%s${NC} [" "$message"
    printf "%*s" $filled | tr ' ' '#'
    printf "%*s" $empty | tr ' ' '-'
    printf "] %d%%" $percentage
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 检查命令是否存在（更精确的检查）
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 获取系统信息
get_system_info() {
    print_info "检测系统信息..."
    
    # 检测操作系统
    local os_name=$(uname -s)
    DETECTED_OS="${OS_MAP[$os_name]:-}"
    
    if [[ -z "$DETECTED_OS" ]]; then
        error_exit "不支持的操作系统: $os_name"
    fi
    
    # 检测架构
    local arch_name=$(uname -m)
    DETECTED_ARCH="${ARCH_MAP[$arch_name]:-}"
    
    if [[ -z "$DETECTED_ARCH" ]]; then
        error_exit "不支持的系统架构: $arch_name"
    fi
    
    # 获取发行版信息
    local distro=""
    if [[ -f /etc/os-release ]]; then
        distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    elif [[ -f /etc/redhat-release ]]; then
        distro="redhat"
    elif [[ -f /etc/debian_version ]]; then
        distro="debian"
    fi
    
    print_success "系统信息: $DETECTED_OS/$DETECTED_ARCH ($distro)"
    print_debug "原始系统信息: $(uname -a)"
}

# 检查root权限（支持sudo检查）
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        print_success "检测到root权限"
        return 0
    fi
    
    if command_exists sudo && sudo -n true 2>/dev/null; then
        print_success "检测到sudo权限"
        return 0
    fi
    
    print_error "需要root权限或sudo权限来安装到系统目录"
    print_info "请使用以下方式之一运行："
    print_info "  sudo $0"
    print_info "  su -c '$0'"
    error_exit "权限不足"
}

# 增强的网络连接检查
check_network() {
    print_info "检查网络连接..."
    
    local test_hosts=(
        "8.8.8.8"           # Google DNS
        "1.1.1.1"           # Cloudflare DNS
        "114.114.114.114"   # 114 DNS
        "223.5.5.5"         # 阿里DNS
    )
    
    local connected=false
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" &>/dev/null; then
            connected=true
            print_debug "网络连接测试成功: $host"
            break
        fi
    done
    
    if [[ "$connected" != "true" ]]; then
        error_exit "无法连接到互联网，请检查网络连接"
    fi
    
    # 测试HTTPS连接
    if command_exists curl; then
        if curl -s --connect-timeout 10 --max-time 15 "https://www.google.com" >/dev/null 2>&1 ||
           curl -s --connect-timeout 10 --max-time 15 "https://www.baidu.com" >/dev/null 2>&1; then
            print_success "网络连接正常"
        else
            print_warning "HTTPS连接可能存在问题，但基本网络连接正常"
        fi
    else
        print_success "基本网络连接正常"
    fi
}

# 检查并安装依赖
check_and_install_dependencies() {
    print_info "检查依赖工具..."
    
    local required_tools=("curl" "unzip" "tar")
    local optional_tools=("wget" "jq" "git")
    local missing_required=()
    local missing_optional=()
    
    # 检查必需工具
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_required+=("$tool")
        fi
    done
    
    # 检查可选工具
    for tool in "${optional_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_optional+=("$tool")
        fi
    done
    
    # 安装缺失的必需工具
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        print_info "缺少必需工具: ${missing_required[*]}"
        
        if [[ "$FORCE" == "true" ]] || ask_confirmation "是否自动安装缺失的依赖工具？"; then
            install_dependencies "${missing_required[@]}"
        else
            show_manual_install_instructions "${missing_required[@]}"
            error_exit "请手动安装依赖工具后重试"
        fi
    fi
    
    # 提示可选工具
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        print_info "可选工具未安装: ${missing_optional[*]}"
        print_info "这些工具可以提供更好的功能，但不是必需的"
    fi
    
    # 选择下载工具
    if command_exists curl; then
        DOWNLOADER="curl"
        print_debug "使用下载工具: curl"
    elif command_exists wget; then
        DOWNLOADER="wget"
        print_debug "使用下载工具: wget"
    else
        error_exit "未找到可用的下载工具"
    fi
    
    print_success "依赖检查完成"
}

# 自动安装依赖
install_dependencies() {
    local tools=("$@")
    print_info "自动安装依赖工具: ${tools[*]}"
    
    # 检测包管理器并安装
    if command_exists apt-get; then
        execute_with_retry "apt-get update" 3
        execute_with_retry "apt-get install -y ${tools[*]}" 3
    elif command_exists yum; then
        execute_with_retry "yum install -y ${tools[*]}" 3
    elif command_exists dnf; then
        execute_with_retry "dnf install -y ${tools[*]}" 3
    elif command_exists pacman; then
        execute_with_retry "pacman -S --noconfirm ${tools[*]}" 3
    elif command_exists apk; then
        execute_with_retry "apk add ${tools[*]}" 3
    elif command_exists zypper; then
        execute_with_retry "zypper install -y ${tools[*]}" 3
    else
        print_error "未检测到支持的包管理器"
        show_manual_install_instructions "${tools[@]}"
        error_exit "无法自动安装依赖"
    fi
    
    # 验证安装
    local failed_tools=()
    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            failed_tools+=("$tool")
        fi
    done
    
    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        error_exit "以下工具安装失败: ${failed_tools[*]}"
    fi
    
    print_success "依赖工具安装完成"
}

# 显示手动安装说明
show_manual_install_instructions() {
    local tools=("$@")
    print_info "手动安装说明："
    print_info "Ubuntu/Debian: apt-get install ${tools[*]}"
    print_info "CentOS/RHEL:   yum install ${tools[*]}"
    print_info "Fedora:        dnf install ${tools[*]}"
    print_info "Alpine:        apk add ${tools[*]}"
    print_info "Arch Linux:    pacman -S ${tools[*]}"
    print_info "OpenSUSE:      zypper install ${tools[*]}"
}

# 重试执行命令
execute_with_retry() {
    local cmd="$1"
    local max_attempts=${2:-3}
    local delay=${3:-2}
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        print_debug "执行命令 (尝试 $attempt/$max_attempts): $cmd"
        
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            print_warning "命令失败，${delay}秒后重试..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    print_error "命令执行失败，已达到最大重试次数: $cmd"
    return 1
}

# 询问用户确认
ask_confirmation() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n "$prompt [Y/n]: " >&2
        else
            echo -n "$prompt [y/N]: " >&2
        fi
        
        read -r response
        response=${response:-$default}
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "请输入 y 或 n" >&2
                ;;
        esac
    done
}

# 增强的JSON解析
parse_json_value() {
    local json_data="$1"
    local key="$2"
    local value=""
    
    # 方法1: 使用jq（最可靠）
    if command_exists jq; then
        value=$(echo "$json_data" | jq -r ".$key" 2>/dev/null || echo "")
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    # 方法2: 使用Python
    for python_cmd in python3 python; do
        if command_exists "$python_cmd"; then
            value=$("$python_cmd" -c "
import sys, json
try:
    data = json.loads('''$json_data''')
    print(data.get('$key', ''))
except:
    pass
" 2>/dev/null || echo "")
            if [[ -n "$value" ]]; then
                echo "$value"
                return 0
            fi
        fi
    done
    
    # 方法3: 使用Node.js
    if command_exists node; then
        value=$(node -e "
try {
    const data = JSON.parse(\`$json_data\`);
    console.log(data.$key || '');
} catch(e) {}
" 2>/dev/null || echo "")
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    # 方法4: 基础文本处理（最后的备选方案）
    value=$(echo "$json_data" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/" | head -n1)
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi
    
    return 1
}

# 获取最新版本（增强版）
get_latest_version() {
    print_info "获取最新版本信息..."
    
    local api_urls=(
        "https://api.github.com/repos/$GITHUB_REPO/releases/latest"
        "https://proxy.api.030101.xyz/https://api.github.com/repos/$GITHUB_REPO/releases/latest"
    )
    
    # 如果设置了代理，添加代理URL
    if [[ -n "$PROXY_URL" ]]; then
        api_urls=("${PROXY_URL}/https://api.github.com/repos/$GITHUB_REPO/releases/latest" "${api_urls[@]}")
    fi
    
    local version_info=""
    local latest_version=""
    
    for api_url in "${api_urls[@]}"; do
        print_debug "尝试从 $api_url 获取版本信息..."
        
        # 使用选定的下载工具
        case "$DOWNLOADER" in
            "curl")
                version_info=$(curl -s --connect-timeout 15 --max-time 30 \
                    --retry 2 --retry-delay 1 \
                    -H "User-Agent: tcping-installer/$SCRIPT_VERSION" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -H "X-GitHub-Api-Version: 2022-11-28" \
                    "$api_url" 2>/dev/null || echo "")
                ;;
            "wget")
                version_info=$(wget -q --timeout=30 --tries=2 \
                    --user-agent="tcping-installer/$SCRIPT_VERSION" \
                    --header="Accept: application/vnd.github.v3+json" \
                    --header="X-GitHub-Api-Version: 2022-11-28" \
                    -O- "$api_url" 2>/dev/null || echo "")
                ;;
        esac
        
        # 验证响应
        if [[ -n "$version_info" ]] && echo "$version_info" | grep -q '"tag_name"'; then
            # 检查是否是错误响应
            if echo "$version_info" | grep -q '"message".*"API rate limit exceeded"'; then
                print_warning "API频率限制，尝试下一个端点..."
                continue
            fi
            
            # 解析版本号
            if latest_version=$(parse_json_value "$version_info" "tag_name"); then
                if [[ -n "$latest_version" ]]; then
                    # 验证版本格式
                    if [[ "$latest_version" =~ ^v?[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9\.\-]+)*$ ]]; then
                        print_success "获取到最新版本: $latest_version"
                        echo "$latest_version"
                        return 0
                    else
                        print_warning "版本号格式无效: $latest_version"
                    fi
                fi
            fi
        else
            print_debug "从 $api_url 获取失败或响应无效"
        fi
    done
    
    error_exit "无法获取版本信息，请检查网络连接或稍后重试"
}

# 构建下载URL（支持多个镜像）
build_download_urls() {
    local version="$1"
    local os="$2"
    local arch="$3"
    
    local filename="tcping-${os}-${arch}"
    
    # 主要下载源 - 使用最可靠的镜像
    local urls=(
        "https://gh-proxy.com/https://github.com/$GITHUB_REPO/releases/download/$version/${filename}.zip"
        "https://ghfast.top/https://github.com/$GITHUB_REPO/releases/download/$version/${filename}.zip"
        "https://github.com/$GITHUB_REPO/releases/download/$version/${filename}.zip"
    )
    
    # 如果设置了代理，添加代理URL到最前面
    if [[ -n "$PROXY_URL" ]]; then
        urls=("${PROXY_URL}/https://github.com/$GITHUB_REPO/releases/download/$version/${filename}.zip" "${urls[@]}")
    fi
    
    printf '%s\n' "${urls[@]}"
}

# 增强的下载函数
download_file() {
    local urls=("$@")
    local output="${urls[-1]}"
    unset 'urls[-1]'
    
    print_info "下载文件到: $output"
    
    local total_urls=${#urls[@]}
    local current_url=0
    
    for url in "${urls[@]}"; do
        ((current_url++))
        print_info "尝试源 $current_url/$total_urls: $(basename "$url")"
        
        print_debug "完整URL: $url"
        
        local download_success=false
        local temp_file="${output}.tmp"
        local start_time=$(date +%s)
        
        # 使用临时文件避免部分下载
        case "$DOWNLOADER" in
            "curl")
                print_debug "使用curl下载..."
                if curl -L --connect-timeout 30 --max-time 300 \
                    --retry 2 --retry-delay 3 \
                    -H "User-Agent: tcping-installer/$SCRIPT_VERSION" \
                    --fail \
                    --location-trusted \
                    --progress-bar \
                    -o "$temp_file" "$url" 2>&1; then
                    download_success=true
                fi
                ;;
            "wget")
                print_debug "使用wget下载..."
                if wget --timeout=300 --tries=2 --wait=3 \
                    --user-agent="tcping-installer/$SCRIPT_VERSION" \
                    --progress=bar:force \
                    --show-progress \
                    -O "$temp_file" "$url" 2>&1; then
                    download_success=true
                fi
                ;;
        esac
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        if [[ "$download_success" == "true" ]]; then
            print_debug "下载耗时: ${duration}秒"
            # 验证下载文件
            if validate_downloaded_file "$temp_file" "$url"; then
                mv "$temp_file" "$output"
                print_success "下载完成: $output"
                return 0
            else
                rm -f "$temp_file"
                print_warning "下载的文件验证失败，尝试下一个源..."
            fi
        else
            rm -f "$temp_file"
            print_warning "从源 $current_url 下载失败，尝试下一个源..."
            
            # 如果是网络超时，稍作等待
            if [[ $duration -ge 30 ]]; then
                print_info "网络较慢，等待3秒后继续..."
                sleep 3
            fi
        fi
    done
    
    error_exit "所有下载源都失败了，请检查网络连接或稍后重试"
}

# 验证下载的文件
validate_downloaded_file() {
    local file="$1"
    local url="$2"
    
    # 检查文件是否存在
    if [[ ! -f "$file" ]]; then
        print_debug "文件不存在: $file"
        return 1
    fi
    
    # 检查文件大小
    local file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")
    if [[ $file_size -lt 1000 ]]; then
        print_debug "文件太小: ${file_size}字节"
        return 1
    fi
    
    # 检查文件类型
    local file_type=$(file "$file" 2>/dev/null || echo "")
    
    if [[ "$url" == *.zip ]]; then
        if ! echo "$file_type" | grep -q "Zip archive"; then
            print_debug "不是有效的ZIP文件: $file_type"
            return 1
        fi
        
        # 检查ZIP文件完整性
        if ! unzip -t "$file" &>/dev/null; then
            print_debug "ZIP文件损坏"
            return 1
        fi
    elif [[ "$url" == *.tar.gz ]]; then
        if ! echo "$file_type" | grep -q "gzip compressed"; then
            print_debug "不是有效的tar.gz文件: $file_type"
            return 1
        fi
        
        # 检查tar.gz文件完整性
        if ! tar -tzf "$file" &>/dev/null; then
            print_debug "tar.gz文件损坏"
            return 1
        fi
    fi
    
    print_debug "文件验证成功: $file (${file_size}字节)"
    return 0
}

# 解压文件（支持多种格式）
extract_file() {
    local archive_file="$1"
    local extract_dir="$2"
    
    print_info "解压文件: $archive_file"
    
    mkdir -p "$extract_dir"
    
    local file_type=$(file "$archive_file")
    
    if echo "$file_type" | grep -q "Zip archive"; then
        if ! unzip -q "$archive_file" -d "$extract_dir"; then
            error_exit "ZIP解压失败: $archive_file"
        fi
    elif echo "$file_type" | grep -q "gzip compressed"; then
        if ! tar -xzf "$archive_file" -C "$extract_dir"; then
            error_exit "tar.gz解压失败: $archive_file"
        fi
    else
        error_exit "不支持的文件格式: $file_type"
    fi
    
    print_success "解压完成"
}

# 查找可执行文件
find_executable() {
    local search_dir="$1"
    local executable_name="tcping"
    
    print_debug "在目录中查找可执行文件: $search_dir"
    
    # 查找所有可能的可执行文件
    local candidates=()
    
    # 直接查找tcping文件
    while IFS= read -r -d '' file; do
        candidates+=("$file")
    done < <(find "$search_dir" -name "$executable_name" -type f -print0 2>/dev/null)
    
    # 查找包含tcping的文件
    if [[ ${#candidates[@]} -eq 0 ]]; then
        while IFS= read -r -d '' file; do
            candidates+=("$file")
        done < <(find "$search_dir" -name "*${executable_name}*" -type f -print0 2>/dev/null)
    fi
    
    # 验证候选文件
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            local file_info=$(file "$candidate")
            if echo "$file_info" | grep -q "executable"; then
                print_debug "找到可执行文件: $candidate"
                echo "$candidate"
                return 0
            fi
        fi
    done
    
    # 如果没找到，列出目录内容用于调试
    print_debug "目录内容:"
    ls -la "$search_dir" >&2 || true
    
    return 1
}

# 备份现有版本
backup_existing() {
    local target_file="$INSTALL_DIR/tcping"
    
    if [[ -f "$target_file" ]]; then
        local current_version=""
        if current_version=$("$target_file" --version 2>/dev/null | head -n1); then
            print_info "当前版本: $current_version"
        fi
        
        local backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "备份现有版本到: $backup_file"
        
        if ! cp "$target_file" "$backup_file"; then
            error_exit "备份失败"
        fi
        
        # 设置备份文件权限
        chmod 755 "$backup_file"
        
        print_success "备份完成"
        
        # 清理旧的备份文件（保留最近5个）
        cleanup_old_backups "$target_file"
    fi
}

# 清理旧备份文件
cleanup_old_backups() {
    local target_file="$1"
    local backup_pattern="${target_file}.backup.*"
    local keep_count=5
    
    # 获取所有备份文件，按时间排序
    local backup_files=()
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$(dirname "$target_file")" -name "$(basename "$target_file").backup.*" -type f -print0 2>/dev/null | sort -z)
    
    # 如果备份文件超过保留数量，删除最旧的
    if [[ ${#backup_files[@]} -gt $keep_count ]]; then
        local delete_count=$((${#backup_files[@]} - keep_count))
        print_info "清理 $delete_count 个旧备份文件..."
        
        for ((i=0; i<delete_count; i++)); do
            rm -f "${backup_files[i]}"
            print_debug "删除旧备份: ${backup_files[i]}"
        done
    fi
}

# 安装文件
install_file() {
    local source_file="$1"
    local target_file="$INSTALL_DIR/tcping"
    
    print_info "安装tcping到: $target_file"
    
    # 验证源文件
    if [[ ! -f "$source_file" ]]; then
        error_exit "源文件不存在: $source_file"
    fi
    
    # 检查文件是否为可执行文件
    local file_info=$(file "$source_file")
    if ! echo "$file_info" | grep -q "executable"; then
        print_warning "文件可能不是有效的可执行文件: $file_info"
    fi
    
    # 确保安装目录存在
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_info "创建安装目录: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR" || error_exit "创建安装目录失败"
    fi
    
    # 检查磁盘空间
    local required_space=$(stat -c%s "$source_file" 2>/dev/null || echo "0")
    local available_space=$(df "$INSTALL_DIR" | awk 'NR==2 {print $4*1024}')
    
    if [[ $required_space -gt $available_space ]]; then
        error_exit "磁盘空间不足，需要 $required_space 字节，可用 $available_space 字节"
    fi
    
    # 如果是dry run模式，只显示操作不执行
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] 将要复制: $source_file -> $target_file"
        print_info "[DRY RUN] 将要设置权限: 755"
        print_info "[DRY RUN] 将要设置所有者: root:root"
        return 0
    fi
    
    # 复制文件
    if ! cp "$source_file" "$target_file"; then
        error_exit "复制文件失败"
    fi
    
    # 设置权限
    if ! chmod 755 "$target_file"; then
        error_exit "设置执行权限失败"
    fi
    
    # 设置所有者（仅在root用户下）
    if [[ $EUID -eq 0 ]]; then
        if ! chown root:root "$target_file"; then
            print_warning "设置文件所有者失败，但不影响使用"
        fi
    fi
    
    print_success "安装完成"
}

# 验证安装
verify_installation() {
    local target_file="$INSTALL_DIR/tcping"
    
    print_info "验证安装..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] 跳过安装验证"
        return 0
    fi
    
    # 检查文件存在性
    if [[ ! -f "$target_file" ]]; then
        error_exit "安装验证失败: 文件不存在"
    fi
    
    # 检查可执行权限
    if [[ ! -x "$target_file" ]]; then
        error_exit "安装验证失败: 文件不可执行"
    fi
    
    # 检查文件大小
    local file_size=$(stat -c%s "$target_file" 2>/dev/null || echo "0")
    if [[ $file_size -lt 1000 ]]; then
        error_exit "安装验证失败: 文件大小异常 ($file_size 字节)"
    fi
    
    # 测试运行
    print_info "测试可执行性..."
    local test_output=""
    local test_success=false
    
    # 尝试多种方式测试
    local test_commands=(
        "--version"
        "--help"
        "-h"
        "-v"
    )
    
    for cmd in "${test_commands[@]}"; do
        if test_output=$("$target_file" "$cmd" 2>&1); then
            test_success=true
            print_success "安装验证成功，版本信息: $(echo "$test_output" | head -n1)"
            break
        fi
    done
    
    if [[ "$test_success" != "true" ]]; then
        # 尝试直接运行看是否有输出
        if test_output=$("$target_file" 2>&1 | head -n3); then
            print_success "安装验证成功，程序可以正常运行"
        else
            print_warning "无法获取版本信息，但文件已安装且可执行"
        fi
    fi
    
    # 检查PATH
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        print_warning "$INSTALL_DIR 不在PATH环境变量中"
        print_info "请将以下行添加到您的shell配置文件 (~/.bashrc, ~/.zshrc 等):"
        print_info "export PATH=\"$INSTALL_DIR:\$PATH\""
        print_info "或者重新登录以刷新PATH环境变量"
    fi
    
    # 创建符号链接（可选）
    create_symlinks "$target_file"
}

# 创建符号链接
create_symlinks() {
    local target_file="$1"
    local common_paths=("/usr/bin" "/usr/local/bin")
    
    for path in "${common_paths[@]}"; do
        if [[ "$path" != "$INSTALL_DIR" ]] && [[ -d "$path" ]] && [[ -w "$path" ]]; then
            local symlink="$path/tcping"
            if [[ ! -e "$symlink" ]]; then
                # 自动创建符号链接，不询问用户
                if ln -sf "$target_file" "$symlink" 2>/dev/null; then
                    print_success "创建符号链接: $symlink"
                else
                    print_debug "创建符号链接失败: $symlink"
                fi
            fi
        fi
    done
}

# 卸载功能
uninstall_tcping() {
    local target_file="$INSTALL_DIR/tcping"
    local config_files=()
    local backup_files=()
    
    print_info "开始卸载tcping..."
    
    # 检查是否已安装
    if [[ ! -f "$target_file" ]]; then
        print_warning "tcping未安装或已被删除"
        return 0
    fi
    
    # 显示当前版本信息
    if command -v tcping >/dev/null 2>&1; then
        local current_version=$(tcping --version 2>/dev/null | head -n1 || echo "未知版本")
        print_info "当前安装的版本: $current_version"
    fi
    
    # 询问确认
    if ! ask_confirmation "确定要卸载tcping吗？"; then
        print_info "卸载已取消"
        return 0
    fi
    
    # 查找相关文件
    print_info "查找相关文件..."
    
    # 查找配置文件
    if [[ -d "$CONFIG_DIR" ]]; then
        while IFS= read -r -d '' file; do
            config_files+=("$file")
        done < <(find "$CONFIG_DIR" -type f -print0 2>/dev/null)
    fi
    
    # 查找备份文件
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$(dirname "$target_file")" -name "$(basename "$target_file").backup.*" -type f -print0 2>/dev/null)
    
    # 查找符号链接
    local symlinks=()
    local search_paths=("/usr/bin" "/usr/local/bin" "/bin")
    for path in "${search_paths[@]}"; do
        local symlink="$path/tcping"
        if [[ -L "$symlink" ]] && [[ "$(readlink "$symlink")" == "$target_file" ]]; then
            symlinks+=("$symlink")
        fi
    done
    
    # 显示将要删除的文件
    print_info "将要删除的文件:"
    print_info "  主程序: $target_file"
    
    if [[ ${#config_files[@]} -gt 0 ]]; then
        print_info "  配置文件: ${config_files[*]}"
    fi
    
    if [[ ${#symlinks[@]} -gt 0 ]]; then
        print_info "  符号链接: ${symlinks[*]}"
    fi
    
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        print_info "  备份文件: ${backup_files[*]}"
        if ask_confirmation "是否同时删除备份文件？"; then
            for backup in "${backup_files[@]}"; do
                rm -f "$backup"
                print_debug "删除备份文件: $backup"
            done
        fi
    fi
    
    # 删除主程序文件
    if rm -f "$target_file"; then
        print_success "主程序已删除"
    else
        error_exit "删除主程序失败"
    fi
    
    # 删除符号链接
    for symlink in "${symlinks[@]}"; do
        if rm -f "$symlink"; then
            print_success "删除符号链接: $symlink"
        else
            print_warning "删除符号链接失败: $symlink"
        fi
    done
    
    # 删除配置目录（如果为空）
    if [[ -d "$CONFIG_DIR" ]]; then
        if ask_confirmation "是否删除配置目录？"; then
            if rmdir "$CONFIG_DIR" 2>/dev/null; then
                print_success "配置目录已删除"
            else
                print_info "配置目录不为空，保留"
            fi
        fi
    fi
    
    print_success "tcping卸载完成"
}

# 更新功能
update_tcping() {
    print_info "检查tcping更新..."
    
    local current_version=""
    local target_file="$INSTALL_DIR/tcping"
    
    # 检查是否已安装
    if [[ ! -f "$target_file" ]]; then
        print_error "tcping未安装，请使用安装选项"
        return 1
    fi
    
    # 获取当前版本
    if current_version=$("$target_file" --version 2>/dev/null | head -n1); then
        print_info "当前版本: $current_version"
    else
        print_warning "无法获取当前版本信息"
        current_version="unknown"
    fi
    
    # 获取最新版本
    local latest_version
    if ! latest_version=$(get_latest_version); then
        error_exit "无法获取最新版本信息"
    fi
    
    # 比较版本
    if [[ "$current_version" == "$latest_version" ]]; then
        print_success "已经是最新版本: $latest_version"
        return 0
    fi
    
    print_info "发现新版本: $latest_version"
    
    if ask_confirmation "是否更新到最新版本？"; then
        # 设置要安装的版本
        INSTALL_VERSION="$latest_version"
        # 执行安装（会自动备份当前版本）
        install_tcping
    else
        print_info "更新已取消"
    fi
}

# 主安装函数
install_tcping() {
    print_info "开始安装tcping..."
    
    # 获取系统信息
    get_system_info
    
    # 检查权限
    check_permissions
    
    # 检查依赖
    check_and_install_dependencies
    
    # 检查网络
    check_network
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    print_debug "临时目录: $TEMP_DIR"
    
    # 获取版本信息
    local version="$INSTALL_VERSION"
    if [[ -z "$version" ]]; then
        print_info "获取最新版本信息..."
        if ! version=$(get_latest_version); then
            error_exit "版本信息获取失败，停止安装流程"
        fi
    fi
    
    print_info "准备安装版本: $version"
    
    # 构建下载URL
    local download_urls
    readarray -t download_urls < <(build_download_urls "$version" "$DETECTED_OS" "$DETECTED_ARCH")
    
    print_info "可用下载源: ${#download_urls[@]} 个"
    if [[ "$VERBOSE" == "true" ]]; then
        for url in "${download_urls[@]}"; do
            print_debug "  - $url"
        done
    fi
    
    # 下载文件
    local downloaded_file=""
    local success=false
    
    # 优先尝试zip格式，然后尝试tar.gz格式
    for ext in "zip" "tar.gz"; do
        local filtered_urls=()
        for url in "${download_urls[@]}"; do
            if [[ "$url" == *."$ext" ]]; then
                filtered_urls+=("$url")
            fi
        done
        
        if [[ ${#filtered_urls[@]} -gt 0 ]]; then
            downloaded_file="$TEMP_DIR/tcping-${DETECTED_OS}-${DETECTED_ARCH}.${ext}"
            print_info "尝试下载 $ext 格式文件..."
            
            # 限制每种格式最多尝试3个源，避免过长等待
            local limited_urls=("${filtered_urls[@]:0:3}")
            
            if download_file "${limited_urls[@]}" "$downloaded_file"; then
                success=true
                break
            else
                print_warning "$ext 格式下载失败，尝试其他格式..."
            fi
        fi
    done
    
    if [[ "$success" != "true" ]]; then
        error_exit "所有格式的下载都失败了"
    fi
    
    # 解压文件
    local extract_dir="$TEMP_DIR/extracted"
    extract_file "$downloaded_file" "$extract_dir"
    
    # 查找可执行文件
    local executable_file
    if ! executable_file=$(find_executable "$extract_dir"); then
        error_exit "在解压文件中未找到tcping可执行文件"
    fi
    
    print_success "找到可执行文件: $executable_file"
    
    # 备份现有版本
    backup_existing
    
    # 安装文件
    install_file "$executable_file"
    
    # 验证安装
    verify_installation
    
    print_success "tcping安装完成！"
    print_info "版本: $version"
    print_info "安装路径: $INSTALL_DIR/tcping"
    print_info "使用 'tcping --help' 查看帮助信息"
    
    # 显示使用示例
    show_usage_examples
}

# 显示使用示例
show_usage_examples() {
    print_info ""
    print_info "使用示例:"
    print_info "  tcping www.google.com 80      # 测试HTTP端口"
    print_info "  tcping www.google.com 443     # 测试HTTPS端口"
    print_info "  tcping 8.8.8.8 53             # 测试DNS端口"
    print_info "  tcping -c 10 localhost 22     # 测试10次SSH端口"
}

# 清理函数
cleanup() {
    local exit_code=$?
    
    print_debug "开始清理..."
    
    # 清理临时目录
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        print_debug "清理临时目录: $TEMP_DIR"
    fi
    
    # 释放锁文件
    release_lock
    
    # 如果是异常退出，显示日志位置
    if [[ $exit_code -ne 0 ]]; then
        print_error "脚本异常退出，错误码: $exit_code"
        print_info "详细日志请查看: $USER_LOG_FILE"
        if [[ -f "$LOG_FILE" ]]; then
            print_info "系统日志: $LOG_FILE"
        fi
    fi
    
    print_debug "清理完成"
}

# 信号处理
handle_signal() {
    local signal=$1
    print_warning "收到信号: $signal"
    print_info "正在安全退出..."
    cleanup
    exit 130
}

# 注册信号处理器
trap cleanup EXIT
trap 'handle_signal INT' INT
trap 'handle_signal TERM' TERM
trap 'handle_signal QUIT' QUIT

# 显示帮助信息
show_help() {
    cat << 'EOF'
tcping 自动安装脚本

用法:
    ./install.sh [选项]

选项:
    -h, --help              显示此帮助信息
    -v, --verbose           详细输出模式
    -f, --force             强制安装（跳过确认）
    -u, --uninstall         卸载tcping
    --update                更新到最新版本
    --version               显示脚本版本
    --dry-run               模拟运行（不实际安装）
    --proxy <URL>           设置代理URL
    --install-dir <DIR>     指定安装目录（默认: /usr/local/bin）
    --install-version <VER> 安装指定版本

示例:
    ./install.sh                              # 交互式安装最新版本
    ./install.sh --force                      # 强制安装（跳过所有确认）
    ./install.sh --verbose                    # 详细输出模式
    ./install.sh --uninstall                  # 卸载tcping
    ./install.sh --update                     # 更新到最新版本
    ./install.sh --install-version v1.0.0     # 安装指定版本
    ./install.sh --proxy https://proxy.com    # 使用代理
    ./install.sh --dry-run                    # 模拟安装

环境变量:
    HTTP_PROXY              HTTP代理设置
    HTTPS_PROXY             HTTPS代理设置
    NO_PROXY                不使用代理的主机列表

EOF
}

# 显示版本信息
show_version() {
    echo "tcping安装脚本 版本 $SCRIPT_VERSION"
    echo "作者: 优化版本"
    echo "仓库: https://github.com/$GITHUB_REPO"
}

# 解析命令行参数
parse_arguments() {
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -u|--uninstall)
                ACTION="uninstall"
                shift
                ;;
            --update)
                ACTION="update"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --proxy)
                if [[ -n "${2:-}" ]]; then
                    PROXY_URL="$2"
                    shift 2
                else
                    error_exit "选项 --proxy 需要提供URL参数"
                fi
                ;;
            --install-dir)
                if [[ -n "${2:-}" ]]; then
                    INSTALL_DIR="$2"
                    shift 2
                else
                    error_exit "选项 --install-dir 需要提供目录参数"
                fi
                ;;
            --install-version)
                if [[ -n "${2:-}" ]]; then
                    INSTALL_VERSION="$2"
                    shift 2
                else
                    error_exit "选项 --install-version 需要提供版本参数"
                fi
                ;;
            --)
                shift
                break
                ;;
            -*)
                error_exit "未知选项: $1"
                ;;
            *)
                error_exit "不支持的参数: $1"
                ;;
        esac
    done
}

# 初始化
initialize() {
    # 检查Shell版本
    if [[ -z "${BASH_VERSION:-}" ]] || [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
        error_exit "此脚本需要Bash 4.0或更高版本"
    fi
    
    # 设置环境变量代理
    if [[ -n "${HTTP_PROXY:-}" ]] && [[ -z "$PROXY_URL" ]]; then
        print_debug "使用HTTP_PROXY环境变量: $HTTP_PROXY"
    fi
    
    if [[ -n "${HTTPS_PROXY:-}" ]] && [[ -z "$PROXY_URL" ]]; then
        print_debug "使用HTTPS_PROXY环境变量: $HTTPS_PROXY"
    fi
    
    # 创建日志目录
    local log_dir=$(dirname "$USER_LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true
    
    # 记录启动信息
    print_info "tcping安装脚本启动 (版本: $SCRIPT_VERSION)"
    print_info "用户日志: $USER_LOG_FILE"
    print_debug "Shell: $BASH_VERSION"
    print_debug "系统: $(uname -a)"
    
    # 获取锁
    acquire_lock
}

# 主函数
main() {
    local ACTION="install"  # 默认动作
    
    # 初始化
    initialize
    
    # 解析参数
    parse_arguments "$@"
    
    # 设置详细输出
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
        print_debug "启用详细输出模式"
    fi
    
    # 显示配置信息
    if [[ "$VERBOSE" == "true" ]]; then
        print_debug "配置信息:"
        print_debug "  动作: $ACTION"
        print_debug "  安装目录: $INSTALL_DIR"
        print_debug "  强制模式: $FORCE"
        print_debug "  模拟运行: $DRY_RUN"
        print_debug "  代理: ${PROXY_URL:-未设置}"
        print_debug "  指定版本: ${INSTALL_VERSION:-最新版本}"
    fi
    
    # 执行对应的动作
    case "$ACTION" in
        "install")
            # 安装前确认
            if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
                echo "此脚本将自动下载并安装tcping工具。" >&2
                echo "安装目录: $INSTALL_DIR" >&2
                if [[ -n "$INSTALL_VERSION" ]]; then
                    echo "安装版本: $INSTALL_VERSION" >&2
                else
                    echo "安装版本: 最新版本" >&2
                fi
                echo "" >&2
                
                if ! ask_confirmation "是否继续安装？"; then
                    print_info "安装已取消"
                    exit 0
                fi
            fi
            
            install_tcping
            ;;
        "uninstall")
            uninstall_tcping
            ;;
        "update")
            update_tcping
            ;;
        *)
            error_exit "未知动作: $ACTION"
            ;;
    esac
    
    print_success "脚本执行完成"
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi