#!/bin/bash

# Polarion通用配置加载脚本
# 此脚本被所有Polarion相关脚本引用，提供统一的配置管理

# ==================== 配置文件路径检测 ====================
# 自动检测配置文件位置
detect_config_file() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    local config_candidates=(
        "$script_dir/polarion_config.conf"
        "$script_dir/../polarion_config.conf"
        "$(pwd)/polarion_config.conf"
        "/opt/polarion_config.conf"
        "$HOME/.polarion_config.conf"
    )
    
    for config_file in "${config_candidates[@]}"; do
        if [ -f "$config_file" ]; then
            echo "$config_file"
            return 0
        fi
    done
    
    return 1
}

# ==================== 配置加载函数 ====================
load_polarion_config() {
    local config_file
    
    # 如果指定了配置文件路径，使用指定的
    if [ -n "$POLARION_CONFIG_FILE" ] && [ -f "$POLARION_CONFIG_FILE" ]; then
        config_file="$POLARION_CONFIG_FILE"
    else
        # 自动检测配置文件
        config_file=$(detect_config_file)
        if [ $? -ne 0 ]; then
            echo "错误: 找不到Polarion配置文件 (polarion_config.conf)" >&2
            echo "请确保配置文件存在于以下位置之一:" >&2
            echo "  - 脚本同目录" >&2
            echo "  - 脚本上级目录" >&2
            echo "  - 当前工作目录" >&2
            echo "  - /opt/polarion_config.conf" >&2
            echo "  - ~/.polarion_config.conf" >&2
            exit 1
        fi
    fi
    
    # 加载配置文件
    if ! source "$config_file"; then
        echo "错误: 无法加载配置文件: $config_file" >&2
        exit 1
    fi
    
    # 设置全局变量，供其他脚本使用
    export POLARION_CONFIG_LOADED="true"
    export POLARION_CONFIG_FILE_PATH="$config_file"
    
    # 验证必需的配置项
    validate_config
}

# ==================== 配置验证函数 ====================
validate_config() {
    local required_vars=(
        "CONTAINER_NAME"
        "IMAGE_NAME"
        "HOST_MOUNT_DIR"
        "CONTAINER_MOUNT_DIR"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "错误: 配置文件中缺少必需的配置项:" >&2
        printf "  - %s\n" "${missing_vars[@]}" >&2
        echo "请检查配置文件: $POLARION_CONFIG_FILE_PATH" >&2
        exit 1
    fi
}

# ==================== 容器状态检查函数 ====================
container_exists() {
    docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

container_running() {
    docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"
}

# ==================== 容器状态验证函数 ====================
ensure_container_running() {
    if ! container_running; then
        echo "错误: 容器 $CONTAINER_NAME 未运行" >&2
        if container_exists; then
            echo "请先启动容器: docker start $CONTAINER_NAME" >&2
        else
            echo "请先创建并启动容器" >&2
        fi
        exit 1
    fi
}

# ==================== 日志输出函数 ====================
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1" >&2
}

# ==================== 配置信息显示函数 ====================
show_config_info() {
    echo "=== Polarion配置信息 ==="
    echo "配置文件: $POLARION_CONFIG_FILE_PATH"
    echo "容器名称: $CONTAINER_NAME"
    echo "镜像名称: $IMAGE_NAME"
    echo "挂载目录: $HOST_MOUNT_DIR -> $CONTAINER_MOUNT_DIR"
    echo "网络模式: $NETWORK_MODE"
    echo "========================"
}

# ==================== 自动加载配置 ====================
# 如果配置尚未加载，自动加载
if [ "$POLARION_CONFIG_LOADED" != "true" ]; then
    load_polarion_config
fi
