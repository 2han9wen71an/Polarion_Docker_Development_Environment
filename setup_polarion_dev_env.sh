#!/bin/bash

# Polarion开发环境一键配置脚本
# 功能: 自动配置Polarion开发环境，包括卷挂载、权限修复等
# 特点: 针对开发环境优化，不自动启动服务，允许开发者手动控制

set -e  # 遇到错误立即退出

# ==================== 加载配置 ====================
# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/polarion_common.sh"

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ==================== 日志函数 ====================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}${BOLD}[STEP]${NC} $1"
}

# ==================== 基础检查函数 ====================
check_docker() {
    log_step "检查Docker服务状态..."
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker未运行或无法访问，请启动Docker服务"
        exit 1
    fi
    log_success "Docker服务正常"
}

check_image() {
    log_step "检查Polarion镜像是否存在..."
    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        log_error "Polarion镜像 '$IMAGE_NAME' 不存在，请先构建镜像"
        exit 1
    fi
    log_success "Polarion镜像存在"
}

# ==================== 容器管理函数 ====================
cleanup_existing_container() {
    log_step "检查并清理现有容器..."
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        log_warning "发现现有容器 '$CONTAINER_NAME'，正在停止并删除..."
        
        # 停止容器（如果正在运行）
        if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            docker stop "$CONTAINER_NAME"
            log_info "容器已停止"
        fi
        
        # 删除容器
        docker rm "$CONTAINER_NAME"
        log_success "容器已删除"
    else
        log_info "未发现现有容器"
    fi
}

# ==================== 目录配置函数 ====================
setup_host_directory() {
    log_step "配置宿主机挂载目录..."
    
    # 创建目录
    if [ ! -d "$HOST_MOUNT_DIR" ]; then
        log_info "创建目录 $HOST_MOUNT_DIR"
        sudo mkdir -p "$HOST_MOUNT_DIR"
    else
        log_info "目录 $HOST_MOUNT_DIR 已存在"
    fi
    
    # 设置基本权限
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sudo chown "$(whoami):staff" "$HOST_MOUNT_DIR"
    else
        sudo chown "$(whoami):$(whoami)" "$HOST_MOUNT_DIR"
    fi
    
    log_success "宿主机目录配置完成"
}

# ==================== 数据初始化函数 ====================
initialize_polarion_data() {
    log_step "初始化Polarion数据..."
    
    # 检查是否已有数据
    if [ -d "$HOST_MOUNT_DIR/data" ] && [ "$(ls -A $HOST_MOUNT_DIR/data 2>/dev/null)" ]; then
        log_info "检测到现有数据，跳过初始化"
        return 0
    fi
    
    log_info "启动临时容器进行数据初始化..."
    
    # 启动临时容器
    docker run -d --name "${CONTAINER_NAME}_temp" \
        --net="$NETWORK_MODE" \
        -e ALLOWED_HOSTS="$ALLOWED_HOSTS" \
        "$IMAGE_NAME"
    
    log_info "等待Polarion初始化完成（这可能需要几分钟）..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        sleep 10
        attempt=$((attempt + 1))
        
        # 检查是否有基本的目录结构生成
        if docker exec "${CONTAINER_NAME}_temp" test -d /opt/polarion/data 2>/dev/null; then
            log_success "基础数据结构已生成"
            break
        fi
        
        log_info "等待中... ($attempt/$max_attempts)"
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_warning "等待超时，但继续执行数据复制"
    fi
    
    # 复制数据到宿主机
    log_info "复制Polarion数据到宿主机..."
    
    # 清空宿主机目录（如果有内容）
    if [ "$(ls -A $HOST_MOUNT_DIR 2>/dev/null)" ]; then
        log_warning "清空现有目录内容"
        sudo rm -rf "${HOST_MOUNT_DIR:?}"/*
    fi
    
    # 复制数据
    docker cp "${CONTAINER_NAME}_temp:$CONTAINER_MOUNT_DIR/." "$HOST_MOUNT_DIR/"
    
    # 清理临时容器
    log_info "清理临时容器..."
    docker stop "${CONTAINER_NAME}_temp" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}_temp" >/dev/null 2>&1 || true
    
    log_success "数据初始化完成"
}



















# ==================== 权限修复函数 ====================
get_polarion_user_info() {
    log_info "获取容器内polarion用户信息..."
    
    local polarion_uid=999  # 默认值
    local polarion_gid=33   # 默认值 (www-data)
    
    # 启动临时容器获取用户信息
    local temp_container="${CONTAINER_NAME}_info"
    docker run -d --name "$temp_container" "$IMAGE_NAME" sleep 30 >/dev/null 2>&1 || true
    
    if docker ps -a --format "table {{.Names}}" | grep -q "^${temp_container}$"; then
        sleep 2  # 等待容器启动
        if polarion_uid=$(docker exec "$temp_container" id -u polarion 2>/dev/null); then
            polarion_gid=$(docker exec "$temp_container" id -g polarion 2>/dev/null)
            log_info "获取用户信息: UID=$polarion_uid, GID=$polarion_gid"
        else
            log_warning "无法获取polarion用户信息，使用默认值"
        fi
        
        # 清理临时容器
        docker stop "$temp_container" >/dev/null 2>&1 || true
        docker rm "$temp_container" >/dev/null 2>&1 || true
    fi
    
    echo "$polarion_uid:$polarion_gid"
}

fix_all_permissions() {
    log_step "修复所有目录权限..."
    
    # 获取用户信息
    local user_info
    user_info=$(get_polarion_user_info)
    local polarion_uid=$(echo "$user_info" | cut -d: -f1)
    local polarion_gid=$(echo "$user_info" | cut -d: -f2)
    
    log_info "设置权限为 UID:GID = $polarion_uid:$polarion_gid"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS系统
        log_info "检测到macOS系统，配置开发环境权限..."
        
        # 设置基本权限
        sudo chown -R "$(whoami):staff" "$HOST_MOUNT_DIR"
        sudo chmod -R 755 "$HOST_MOUNT_DIR"
        
        # PostgreSQL数据目录特殊权限（必须是750）
        if [ -d "$HOST_MOUNT_DIR/data/postgres-data" ]; then
            sudo chmod 750 "$HOST_MOUNT_DIR/data/postgres-data"
            sudo chmod -R 750 "$HOST_MOUNT_DIR/data/postgres-data"
            find "$HOST_MOUNT_DIR/data/postgres-data" -type f -exec sudo chmod 640 {} \; 2>/dev/null || true
            log_success "PostgreSQL数据目录权限已设置为750"
        fi
        
        # 其他目录宽松权限（开发环境需要）
        [ -d "$HOST_MOUNT_DIR/etc" ] && sudo chmod -R 777 "$HOST_MOUNT_DIR/etc"
        [ -d "$HOST_MOUNT_DIR/data/workspace" ] && sudo chmod -R 777 "$HOST_MOUNT_DIR/data/workspace"
        [ -d "$HOST_MOUNT_DIR/data/logs" ] && sudo chmod -R 777 "$HOST_MOUNT_DIR/data/logs"
        
    else
        # Linux系统
        log_info "检测到Linux系统，配置开发环境权限..."
        
        # 设置基本权限
        sudo chown -R "$polarion_uid:$polarion_gid" "$HOST_MOUNT_DIR"
        sudo chmod -R 755 "$HOST_MOUNT_DIR"
        
        # PostgreSQL数据目录特殊权限
        if [ -d "$HOST_MOUNT_DIR/data/postgres-data" ]; then
            sudo chmod 750 "$HOST_MOUNT_DIR/data/postgres-data"
            sudo chmod -R 750 "$HOST_MOUNT_DIR/data/postgres-data"
            find "$HOST_MOUNT_DIR/data/postgres-data" -type f -exec sudo chmod 640 {} \; 2>/dev/null || true
            log_success "PostgreSQL数据目录权限已设置为750"
        fi
        
        # 其他目录宽松权限
        [ -d "$HOST_MOUNT_DIR/etc" ] && sudo chmod -R 777 "$HOST_MOUNT_DIR/etc"
        [ -d "$HOST_MOUNT_DIR/data/workspace" ] && sudo chmod -R 777 "$HOST_MOUNT_DIR/data/workspace"
        [ -d "$HOST_MOUNT_DIR/data/logs" ] && sudo chmod -R 777 "$HOST_MOUNT_DIR/data/logs"
    fi
    
    # 清理锁文件
    log_info "清理锁文件和PID文件..."
    [ -f "$HOST_MOUNT_DIR/data/workspace/.metadata/.lock" ] && sudo rm -f "$HOST_MOUNT_DIR/data/workspace/.metadata/.lock"
    [ -f "$HOST_MOUNT_DIR/data/workspace/.metadata/server.pid" ] && sudo rm -f "$HOST_MOUNT_DIR/data/workspace/.metadata/server.pid"
    [ -f "$HOST_MOUNT_DIR/data/postgres-data/postmaster.pid" ] && sudo rm -f "$HOST_MOUNT_DIR/data/postgres-data/postmaster.pid"
    
    log_success "权限修复完成"
}

# ==================== 开发容器创建函数 ====================
create_dev_container() {
    log_step "创建开发环境容器..."

    log_info "启动带卷挂载的Polarion开发容器..."

    # 创建开发容器（不自动启动服务）
    docker run -d --name "$CONTAINER_NAME" \
        --net="$NETWORK_MODE" \
        -e ALLOWED_HOSTS="$ALLOWED_HOSTS" \
        -e POLARION_DEV_MODE="true" \
        -v "$HOST_MOUNT_DIR:$CONTAINER_MOUNT_DIR" \
        "$IMAGE_NAME" \
        tail -f /dev/null  # 保持容器运行但不启动服务

    log_success "开发容器已创建并启动"
}

# ==================== 验证配置函数 ====================
verify_dev_setup() {
    log_step "验证开发环境配置..."

    # 检查容器状态
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
        log_success "容器运行正常"
    else
        log_error "容器未正常运行"
        return 1
    fi

    # 检查挂载目录
    if [ -d "$HOST_MOUNT_DIR" ] && [ "$(ls -A $HOST_MOUNT_DIR)" ]; then
        log_success "挂载目录包含数据"
        log_info "目录大小: $(du -sh $HOST_MOUNT_DIR | cut -f1)"
    else
        log_error "挂载目录为空"
        return 1
    fi

    # 检查关键目录权限
    if [ -d "$HOST_MOUNT_DIR/data/postgres-data" ]; then
        local pg_perms=$(stat -f "%Lp" "$HOST_MOUNT_DIR/data/postgres-data" 2>/dev/null || stat -c "%a" "$HOST_MOUNT_DIR/data/postgres-data" 2>/dev/null)
        if [[ "$pg_perms" == "750" ]]; then
            log_success "PostgreSQL目录权限正确 (750)"
        else
            log_warning "PostgreSQL目录权限: $pg_perms (应该是750)"
        fi
    fi

    # 测试容器内文件访问
    if docker exec "$CONTAINER_NAME" test -f /opt/polarion/etc/polarion.properties; then
        log_success "容器内可以访问配置文件"
    else
        log_warning "容器内无法访问配置文件"
    fi

    log_success "开发环境验证完成"
}

# ==================== Shell配置检测函数 ====================
detect_shell_config() {
    local shell_name=$(basename "$SHELL")
    local config_file=""

    case "$shell_name" in
        "bash")
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS默认使用.bash_profile
                config_file="$HOME/.bash_profile"
                [ ! -f "$config_file" ] && config_file="$HOME/.bashrc"
            else
                config_file="$HOME/.bashrc"
            fi
            ;;
        "zsh")
            config_file="$HOME/.zshrc"
            ;;
        "fish")
            config_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            config_file="$HOME/.profile"
            ;;
    esac

    echo "$config_file"
}

# ==================== 全局Alias创建函数 ====================
create_global_aliases() {
    log_step "创建全局shell别名..."

    # 获取当前项目的绝对路径
    local project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local shortcuts_dir="$project_dir/bin"

    # 确保快捷方式目录存在
    if [ ! -d "$shortcuts_dir" ]; then
        mkdir -p "$shortcuts_dir"
        log_info "创建快捷方式目录: $shortcuts_dir"
    fi

    # 创建快捷脚本
    log_info "创建快捷脚本..."

    # polarion-status 脚本
    cat > "$shortcuts_dir/polarion-status" << 'EOF'
#!/bin/bash
# 检查Polarion服务状态

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

echo "=== Polarion开发环境状态 ==="
echo

# 检查容器状态
echo "容器状态:"
if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^${CONTAINER_NAME}"; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "$CONTAINER_NAME"
    echo "✅ 容器运行正常"
else
    echo "❌ 容器未运行"
    echo "启动容器: docker start $CONTAINER_NAME"
    exit 1
fi

echo
echo "服务状态:"

# 检查PostgreSQL状态
echo -n "PostgreSQL: "
if docker exec "$CONTAINER_NAME" pgrep -f postgres >/dev/null 2>&1; then
    echo "✅ 运行中"
else
    echo "❌ 未运行"
fi

# 检查Apache状态
echo -n "Apache: "
if docker exec "$CONTAINER_NAME" pgrep -f apache2 >/dev/null 2>&1; then
    echo "✅ 运行中"
else
    echo "❌ 未运行"
fi

# 检查Polarion状态
echo -n "Polarion: "
if docker exec "$CONTAINER_NAME" pgrep -f "polarion-server" >/dev/null 2>&1; then
    echo "✅ 运行中"
else
    echo "❌ 未运行"
fi

echo
echo "快捷命令:"
echo "  启动PostgreSQL: postgresql-start"
echo "  启动Polarion: polarion-start"
echo "  进入容器: polarion-shell"
echo "  执行命令: polarion-exec <命令>"
EOF

    # polarion-start 脚本
    cat > "$shortcuts_dir/polarion-start" << 'EOF'
#!/bin/bash
# 启动Polarion服务

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

echo "启动Polarion服务..."
docker exec -it "$CONTAINER_NAME" "$POLARION_INIT_SCRIPT" start
EOF

    # polarion-stop 脚本
    cat > "$shortcuts_dir/polarion-stop" << 'EOF'
#!/bin/bash
# 停止Polarion服务

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

echo "停止Polarion服务..."
docker exec -it "$CONTAINER_NAME" "$POLARION_INIT_SCRIPT" stop
EOF

    # postgresql-start 脚本
    cat > "$shortcuts_dir/postgresql-start" << 'EOF'
#!/bin/bash
# 启动PostgreSQL服务

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

echo "启动PostgreSQL服务..."
docker exec -it "$CONTAINER_NAME" "$POSTGRESQL_INIT_SCRIPT" start
EOF

    # postgresql-stop 脚本
    cat > "$shortcuts_dir/postgresql-stop" << 'EOF'
#!/bin/bash
# 停止PostgreSQL服务

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

echo "停止PostgreSQL服务..."
docker exec -it "$CONTAINER_NAME" "$POSTGRESQL_INIT_SCRIPT" stop
EOF

    # polarion-shell 脚本
    cat > "$shortcuts_dir/polarion-shell" << 'EOF'
#!/bin/bash
# 进入容器

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

echo "进入容器 $CONTAINER_NAME..."
docker exec -it "$CONTAINER_NAME" bash
EOF

    # polarion-exec 脚本
    cat > "$shortcuts_dir/polarion-exec" << 'EOF'
#!/bin/bash
# 执行容器内命令

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

if [ $# -eq 0 ]; then
    echo "用法: $0 <命令>"
    echo "示例: $0 ps aux"
    echo "示例: $0 /opt/polarion/bin/polarion.init log"
    exit 1
fi

# 确保容器正在运行
ensure_container_running

echo "执行容器内命令: $*"
docker exec -it "$CONTAINER_NAME" "$@"
EOF

    # polarion-logs 脚本
    cat > "$shortcuts_dir/polarion-logs" << 'EOF'
#!/bin/bash
# 查看Polarion日志 - 智能查找最新日志文件

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

# 显示可用的日志类型
show_log_menu() {
    echo "=== Polarion日志查看器 ==="
    echo "请选择要查看的日志类型："
    echo "1) 主日志 (log4j-*.log)"
    echo "2) 错误日志 (log4j-errors-*.log)"
    echo "3) 启动日志 (log4j-startup-*.log)"
    echo "4) 作业日志 (log4j-jobs-*.log)"
    echo "5) 监控日志 (log4j-monitoring-*.log)"
    echo "6) 事务日志 (log4j-tx-*.log)"
    echo "7) 许可日志 (log4j-licensing-*.log)"
    echo "8) PostgreSQL日志"
    echo "9) 列出所有日志文件"
    echo "0) 退出"
    echo
}

# 获取最新的日志文件
get_latest_log() {
    local pattern="$1"
    local log_dir="/opt/polarion/data/logs/main"

    # 在容器内查找最新的日志文件
    docker exec "$CONTAINER_NAME" find "$log_dir" -name "$pattern" -type f -exec ls -t {} + 2>/dev/null | head -1
}

# 查看指定类型的日志
view_log() {
    local log_type="$1"
    local pattern="$2"
    local latest_log

    echo "正在查找最新的${log_type}..."
    latest_log=$(get_latest_log "$pattern")

    if [ -n "$latest_log" ]; then
        echo "查看日志: $latest_log"
        echo "按 Ctrl+C 退出日志查看"
        echo "----------------------------------------"
        docker exec -it "$CONTAINER_NAME" tail -f "$latest_log"
    else
        echo "未找到${log_type}文件"
        return 1
    fi
}

# 列出所有日志文件
list_all_logs() {
    echo "=== 所有可用的日志文件 ==="
    docker exec "$CONTAINER_NAME" ls -la /opt/polarion/data/logs/main/ 2>/dev/null || echo "无法访问日志目录"
}

# 主逻辑
if [ $# -eq 0 ]; then
    # 交互模式
    while true; do
        show_log_menu
        read -p "请选择 (0-9): " choice
        echo

        case $choice in
            1)
                view_log "主日志" "log4j-*.log"
                ;;
            2)
                view_log "错误日志" "log4j-errors-*.log"
                ;;
            3)
                view_log "启动日志" "log4j-startup-*.log"
                ;;
            4)
                view_log "作业日志" "log4j-jobs-*.log"
                ;;
            5)
                view_log "监控日志" "log4j-monitoring-*.log"
                ;;
            6)
                view_log "事务日志" "log4j-tx-*.log"
                ;;
            7)
                view_log "许可日志" "log4j-licensing-*.log"
                ;;
            8)
                echo "查看PostgreSQL日志..."
                docker exec -it "$CONTAINER_NAME" tail -f /opt/polarion/data/postgres-data/log.out
                ;;
            9)
                list_all_logs
                echo
                ;;
            0)
                echo "退出日志查看器"
                exit 0
                ;;
            *)
                echo "无效选择，请重新输入"
                echo
                ;;
        esac
    done
else
    # 命令行参数模式
    case "$1" in
        "main"|"")
            view_log "主日志" "log4j-*.log"
            ;;
        "error"|"errors")
            view_log "错误日志" "log4j-errors-*.log"
            ;;
        "startup")
            view_log "启动日志" "log4j-startup-*.log"
            ;;
        "jobs")
            view_log "作业日志" "log4j-jobs-*.log"
            ;;
        "monitoring")
            view_log "监控日志" "log4j-monitoring-*.log"
            ;;
        "tx"|"transaction")
            view_log "事务日志" "log4j-tx-*.log"
            ;;
        "licensing")
            view_log "许可日志" "log4j-licensing-*.log"
            ;;
        "postgres"|"postgresql")
            echo "查看PostgreSQL日志..."
            docker exec -it "$CONTAINER_NAME" tail -f /opt/polarion/data/postgres-data/log.out
            ;;
        "list")
            list_all_logs
            ;;
        "help"|"-h")
            echo "用法: $0 [日志类型]"
            echo "日志类型:"
            echo "  main        - 主日志 (默认)"
            echo "  error       - 错误日志"
            echo "  startup     - 启动日志"
            echo "  jobs        - 作业日志"
            echo "  monitoring  - 监控日志"
            echo "  tx          - 事务日志"
            echo "  licensing   - 许可日志"
            echo "  postgres    - PostgreSQL日志"
            echo "  list        - 列出所有日志文件"
            echo
            echo "示例:"
            echo "  $0           # 交互模式"
            echo "  $0 main      # 查看主日志"
            echo "  $0 error     # 查看错误日志"
            echo "  $0 list      # 列出所有日志"
            ;;
        *)
            echo "未知的日志类型: $1"
            echo "使用 '$0 help' 查看帮助"
            exit 1
            ;;
    esac
fi
EOF

    # polarion-restart 脚本
    cat > "$shortcuts_dir/polarion-restart" << 'EOF'
#!/bin/bash
# 重启Polarion服务

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 确保容器正在运行
ensure_container_running

echo "重启Polarion服务..."
docker exec -it "$CONTAINER_NAME" "$POLARION_INIT_SCRIPT" restart
EOF

    # polarion-config 脚本（配置管理工具）
    # 创建简化但功能完整的配置管理工具
    cat > "$shortcuts_dir/polarion-config" << 'EOF'
#!/bin/bash
# Polarion配置管理工具

# 加载Polarion通用配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/polarion_common.sh"

# 显示帮助信息
show_help() {
    echo "Polarion配置管理工具"
    echo
    echo "用法: $0 [命令] [选项]"
    echo
    echo "命令:"
    echo "  show              - 显示当前配置"
    echo "  edit              - 编辑配置文件"
    echo "  validate          - 验证配置文件"
    echo "  get <键>          - 获取配置项值"
    echo "  switch <容器名>   - 切换到指定容器"
    echo "  help              - 显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 show                           # 显示当前配置"
    echo "  $0 get CONTAINER_NAME             # 获取容器名称"
    echo "  $0 switch polarion23              # 切换到polarion23容器"
}

# 显示当前配置
show_config() {
    echo "=== Polarion配置信息 ==="
    echo "配置文件: $POLARION_CONFIG_FILE_PATH"
    echo "配置版本: ${CONFIG_VERSION:-未知}"
    echo "最后更新: ${CONFIG_LAST_UPDATED:-未知}"
    echo
    echo "=== 容器配置 ==="
    echo "容器名称: $CONTAINER_NAME"
    echo "镜像名称: $IMAGE_NAME"
    echo "网络模式: $NETWORK_MODE"
    echo "允许主机: $ALLOWED_HOSTS"
    echo
    echo "=== 挂载配置 ==="
    echo "主机目录: $HOST_MOUNT_DIR"
    echo "容器目录: $CONTAINER_MOUNT_DIR"
    echo
    echo "=== 环境变量 ==="
    echo "Java选项: ${JAVA_OPTS:-未设置}"
    echo "时区设置: ${TZ:-未设置}"
    echo
    echo "=== 备份配置 ==="
    echo "备份目录: $BACKUP_DIR"
    echo "保留天数: $BACKUP_RETENTION_DAYS"
    echo
    echo "=== 容器状态 ==="
    if container_exists; then
        if container_running; then
            echo "容器状态: ✅ 运行中"
        else
            echo "容器状态: ⏸️ 已停止"
        fi
    else
        echo "容器状态: ❌ 不存在"
    fi
}

# 编辑配置文件
edit_config() {
    local editor="${EDITOR:-nano}"
    if command -v "$editor" >/dev/null 2>&1; then
        "$editor" "$POLARION_CONFIG_FILE_PATH"
        echo "配置文件已编辑，请运行 'polarion-config validate' 验证配置"
    else
        echo "错误: 编辑器 '$editor' 不可用"
        echo "请设置 EDITOR 环境变量或安装 nano/vim"
        exit 1
    fi
}

# 验证配置文件
validate_config_file() {
    echo "验证配置文件: $POLARION_CONFIG_FILE_PATH"

    # 重新加载配置
    if source "$POLARION_CONFIG_FILE_PATH" 2>/dev/null; then
        echo "✅ 配置文件语法正确"
    else
        echo "❌ 配置文件语法错误"
        return 1
    fi

    # 验证必需配置项
    local required_vars=("CONTAINER_NAME" "IMAGE_NAME" "HOST_MOUNT_DIR" "CONTAINER_MOUNT_DIR")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "❌ 缺少必需的配置项:"
        printf "   - %s\n" "${missing_vars[@]}"
        return 1
    else
        echo "✅ 所有必需配置项都已设置"
    fi

    echo "✅ 配置验证完成"
}

# 获取配置项
get_config() {
    local key="$1"

    if [ -z "$key" ]; then
        echo "错误: 请指定配置键"
        echo "用法: $0 get <键>"
        exit 1
    fi

    local value="${!key}"
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "配置项 '$key' 未设置或为空"
        exit 1
    fi
}

# 切换容器（简化版本）
switch_container() {
    local new_container="$1"

    if [ -z "$new_container" ]; then
        echo "错误: 请指定容器名称"
        echo "用法: $0 switch <容器名>"
        exit 1
    fi

    # 检查容器是否存在
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${new_container}$"; then
        echo "警告: 容器 '$new_container' 不存在"
        echo "是否仍要切换配置? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "操作已取消"
            exit 0
        fi
    fi

    # 简单的配置更新（需要手动编辑）
    echo "要切换到容器 '$new_container'，请："
    echo "1. 运行: polarion-config edit"
    echo "2. 修改 CONTAINER_NAME=\"$new_container\""
    echo "3. 保存并退出"
    echo "4. 运行: polarion-config validate"
}

# 主程序
case "${1:-show}" in
    show)
        show_config
        ;;
    edit)
        edit_config
        ;;
    validate)
        validate_config_file
        ;;
    get)
        get_config "$2"
        ;;
    switch)
        switch_container "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "错误: 未知命令 '$1'"
        echo "运行 '$0 help' 查看帮助信息"
        exit 1
        ;;
esac
EOF

    # 设置执行权限
    chmod +x "$shortcuts_dir"/*

    # 配置全局alias
    log_info "配置全局shell别名..."

    local config_file=$(detect_shell_config)
    local shell_name=$(basename "$SHELL")

    log_info "检测到shell: $shell_name"
    log_info "配置文件: $config_file"

    # 创建alias配置内容
    local alias_content=""

    if [ "$shell_name" = "fish" ]; then
        # Fish shell使用不同的语法
        alias_content="
# Polarion开发环境别名 (由setup_polarion_dev_env.sh自动生成)
alias polarion-status '$shortcuts_dir/polarion-status'
alias polarion-start '$shortcuts_dir/polarion-start'
alias polarion-stop '$shortcuts_dir/polarion-stop'
alias polarion-restart '$shortcuts_dir/polarion-restart'
alias postgresql-start '$shortcuts_dir/postgresql-start'
alias postgresql-stop '$shortcuts_dir/postgresql-stop'
alias polarion-shell '$shortcuts_dir/polarion-shell'
alias polarion-exec '$shortcuts_dir/polarion-exec'
alias polarion-logs '$shortcuts_dir/polarion-logs'
alias polarion-config '$shortcuts_dir/polarion-config'
"
    else
        # Bash/Zsh语法
        alias_content="
# Polarion开发环境别名 (由setup_polarion_dev_env.sh自动生成)
alias polarion-status='$shortcuts_dir/polarion-status'
alias polarion-start='$shortcuts_dir/polarion-start'
alias polarion-stop='$shortcuts_dir/polarion-stop'
alias polarion-restart='$shortcuts_dir/polarion-restart'
alias postgresql-start='$shortcuts_dir/postgresql-start'
alias postgresql-stop='$shortcuts_dir/postgresql-stop'
alias polarion-shell='$shortcuts_dir/polarion-shell'
alias polarion-exec='$shortcuts_dir/polarion-exec'
alias polarion-logs='$shortcuts_dir/polarion-logs'
alias polarion-config='$shortcuts_dir/polarion-config'
"
    fi

    # 检查是否已经存在Polarion别名配置
    if [ -f "$config_file" ] && grep -q "# Polarion开发环境别名" "$config_file"; then
        log_warning "检测到现有的Polarion别名配置，正在更新..."

        # 创建临时文件
        local temp_file=$(mktemp)

        # 删除旧的Polarion别名配置
        sed '/# Polarion开发环境别名/,/^$/d' "$config_file" > "$temp_file"

        # 添加新的别名配置
        echo "$alias_content" >> "$temp_file"

        # 替换原文件
        mv "$temp_file" "$config_file"

        log_success "别名配置已更新"
    else
        log_info "添加新的别名配置..."

        # 确保配置文件存在
        touch "$config_file"

        # 添加别名配置
        echo "$alias_content" >> "$config_file"

        log_success "别名配置已添加到 $config_file"
    fi
    log_success "全局别名配置完成"

    # 显示配置信息
    echo
    log_info "已创建以下全局别名:"
    echo "  polarion-status    - 检查服务状态"
    echo "  polarion-start     - 启动Polarion服务"
    echo "  polarion-stop      - 停止Polarion服务"
    echo "  polarion-restart   - 重启Polarion服务"
    echo "  postgresql-start   - 启动PostgreSQL服务"
    echo "  postgresql-stop    - 停止PostgreSQL服务"
    echo "  polarion-shell     - 进入容器"
    echo "  polarion-exec      - 执行容器内命令"
    echo "  polarion-logs      - 查看Polarion日志"
    echo "  polarion-config    - 配置管理工具"
    echo
    log_info "快捷脚本位置: $shortcuts_dir"
    echo
    log_warning "重要提示:"
    echo "  请重新加载shell配置以使别名生效:"
    if [ "$shell_name" = "fish" ]; then
        echo "    source $config_file"
    else
        echo "    source $config_file"
        echo "  或者重新打开终端"
    fi
    echo
    log_info "使用示例:"
    echo "  polarion-status                    # 检查服务状态"
    echo "  postgresql-start                   # 启动数据库"
    echo "  polarion-start                     # 启动Polarion"
    echo "  polarion-exec ps aux               # 执行容器内命令"
    echo "  polarion-logs                      # 查看日志"
}

# ==================== 开发环境使用说明 ====================
show_dev_usage_info() {
    echo
    echo -e "${GREEN}${BOLD}=== Polarion开发环境配置完成 ===${NC}"
    echo
    echo -e "${CYAN}容器信息:${NC}"
    echo "  名称: $CONTAINER_NAME"
    echo "  镜像: $IMAGE_NAME"
    echo "  网络: --net=$NETWORK_MODE"
    echo "  环境变量: ALLOWED_HOSTS=$ALLOWED_HOSTS"
    echo "  卷挂载: $HOST_MOUNT_DIR:$CONTAINER_MOUNT_DIR"
    echo "  模式: 开发模式（服务未自动启动）"
    echo
    echo -e "${CYAN}开发环境管理命令:${NC}"
    echo "  查看容器状态: docker ps"
    echo "  进入容器: docker exec -it $CONTAINER_NAME bash"
    echo "  查看容器日志: docker logs $CONTAINER_NAME"
    echo "  停止容器: docker stop $CONTAINER_NAME"
    echo "  启动容器: docker start $CONTAINER_NAME"
    echo "  重启容器: docker restart $CONTAINER_NAME"
    echo
    echo -e "${CYAN}全局别名命令（推荐使用）:${NC}"
    echo "  检查服务状态: polarion-status"
    echo "  启动PostgreSQL: postgresql-start"
    echo "  停止PostgreSQL: postgresql-stop"
    echo "  启动Polarion: polarion-start"
    echo "  停止Polarion: polarion-stop"
    echo "  重启Polarion: polarion-restart"
    echo "  进入容器: polarion-shell"
    echo "  执行容器命令: polarion-exec <命令>"
    echo "  查看日志: polarion-logs"
    echo
    echo -e "${CYAN}容器内服务控制命令:${NC}"
    echo "  启动PostgreSQL: sudo service postgresql start"
    echo "  停止PostgreSQL: sudo service postgresql stop"
    echo "  启动Apache: sudo service apache2 start"
    echo "  停止Apache: sudo service apache2 stop"
    echo "  启动Polarion: sudo service polarion start"
    echo "  停止Polarion: sudo service polarion stop"
    echo "  查看Polarion状态: sudo service polarion status"
    echo
    echo -e "${CYAN}开发工作流程（使用全局别名）:${NC}"
    echo "  1. 检查状态: polarion-status"
    echo "  2. 启动PostgreSQL: postgresql-start"
    echo "  3. 启动Polarion: polarion-start"
    echo "  4. 访问: http://localhost:8080/polarion"
    echo "  5. 开发完成后停止: polarion-stop"
    echo
    echo -e "${CYAN}传统工作流程（进入容器）:${NC}"
    echo "  1. 进入容器: polarion-shell"
    echo "  2. 启动PostgreSQL: sudo service postgresql start"
    echo "  3. 启动Apache: sudo service apache2 start"
    echo "  4. 启动Polarion: sudo service polarion start"
    echo "  5. 访问: http://localhost:8080/polarion"
    echo
    echo -e "${CYAN}开发目录:${NC}"
    echo "  宿主机目录: $HOST_MOUNT_DIR"
    echo "  配置文件: $HOST_MOUNT_DIR/etc/"
    echo "  数据目录: $HOST_MOUNT_DIR/data/"
    echo "  日志目录: $HOST_MOUNT_DIR/data/logs/"
    echo "  插件目录: $HOST_MOUNT_DIR/polarion/plugins/"
    echo
    echo -e "${CYAN}开发提示:${NC}"
    echo "  • 可以直接在宿主机 $HOST_MOUNT_DIR 目录中修改文件"
    echo "  • 修改会立即反映到容器中"
    echo "  • 重启相应服务以应用配置更改"
    echo "  • PostgreSQL数据目录权限已优化，请勿随意修改"
    echo "  • 开发完成后记得停止服务以释放资源"
    echo
    echo -e "${CYAN}ARM64兼容性:${NC}"
    local arch=$(uname -m)
    if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
        echo "  • 检测到ARM64架构，已智能检测并修复JNA和Node.js兼容性"
        echo "  • 自动升级不兼容的JNA库到5.7.0+版本"
        echo "  • 自动替换不兼容的Node.js为ARM64版本(18.x LTS)"
        echo "  • 如遇JNA相关问题，可运行: $0 fix-jna"
        echo "  • 如遇Node.js相关问题，可运行: $0 fix-nodejs"
        echo "  • 一键修复所有ARM64问题: $0 fix-arm64"
    else
        echo "  • 当前为x86_64架构，无需ARM64兼容性修复"
        echo "  • 如在ARM64环境下运行，脚本会自动处理兼容性问题"
    fi
    echo
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  • 服务未自动启动，需要手动控制"
    echo "  • 首次启动可能需要较长时间进行初始化"
    echo "  • 如遇权限问题，可重新运行此脚本修复"
    echo "  • ARM64环境下如遇JNA相关错误，运行: $0 fix-jna"
    echo "  • ARM64环境下如遇Node.js相关错误，运行: $0 fix-nodejs"
    echo "  • ARM64环境下一键修复所有兼容性问题: $0 fix-arm64"
    echo
}

# ==================== 主函数 ====================
main() {
    # 检查命令行参数
    case "${1:-}" in
        "help"|"-h"|"--help")
            echo "Polarion开发环境一键配置脚本"
            echo
            echo "用法:"
            echo "  $0                     # 完整配置开发环境"
            echo "  $0 fix-permissions    # 仅修复权限问题"
            echo "  $0 create-aliases     # 仅创建全局别名"
            echo "  $0 fix-jna            # 仅修复ARM64环境下的JNA库兼容性"
            echo "  $0 fix-nodejs         # 仅修复ARM64环境下的Node.js兼容性"
            echo "  $0 fix-arm64          # 修复ARM64环境下的所有兼容性问题(JNA+Node.js)"
            echo "  $0 help               # 显示此帮助信息"
            echo
            echo "说明:"
            echo "  完整配置: 创建开发容器，配置挂载，修复权限，创建全局别名"
            echo "  修复权限: 仅修复现有环境的权限问题"
            echo "  创建别名: 创建全局shell别名，可在任何目录使用Polarion命令"
            echo "  修复JNA: 在ARM64环境下智能检测并升级JNA库到兼容版本(5.7.0+)"
            echo "  修复Node.js: 在ARM64环境下替换Node.js为ARM64兼容版本(18.x LTS)"
            echo "  修复ARM64: 一键修复ARM64环境下的JNA和Node.js兼容性问题"
            exit 0
            ;;
        "fix-permissions")
            echo
            log_info "=== 修复Polarion开发环境权限 ==="
            echo
            check_docker
            fix_all_permissions
            log_success "权限修复完成！"
            exit 0
            ;;
        "create-aliases")
            echo
            log_info "=== 创建全局别名 ==="
            echo
            check_docker
            create_global_aliases
            log_success "全局别名创建完成！"
            echo
            log_info "现在可以在任何目录使用以下命令："
            log_info "  polarion-status - 检查服务状态"
            log_info "  polarion-start - 启动Polarion"
            log_info "  postgresql-start - 启动PostgreSQL"
            exit 0
            ;;
        "fix-jna")
            echo
            log_info "=== 修复ARM64环境下的JNA库兼容性 ==="
            echo
            check_docker
            if [ -f "$SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh" ]; then
                "$SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh"
                if [ $? -eq 0 ]; then
                    log_success "JNA库兼容性修复完成！"
                    echo
                    log_warning "重要提示："
                    log_info "  请重启Polarion服务以使新的JNA库生效："
                    log_info "  方法1: polarion-restart（如果容器正在运行）"
                    log_info "  方法2: 手动重启Polarion服务"
                else
                    log_error "JNA库兼容性修复失败！"
                    exit 1
                fi
            else
                log_error "JNA修复脚本不存在: $SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh"
                exit 1
            fi
            exit 0
            ;;
        "fix-nodejs")
            echo
            log_info "=== 修复ARM64环境下的Node.js兼容性 ==="
            echo
            check_docker
            if [ -f "$SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh" ]; then
                "$SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh"
                if [ $? -eq 0 ]; then
                    log_success "Node.js兼容性修复完成！"
                    echo
                    log_warning "重要提示："
                    log_info "  请重启Polarion服务以使新的Node.js生效："
                    log_info "  方法1: polarion-restart（如果容器正在运行）"
                    log_info "  方法2: 手动重启Polarion服务"
                else
                    log_error "Node.js兼容性修复失败！"
                    exit 1
                fi
            else
                log_error "Node.js修复脚本不存在: $SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh"
                exit 1
            fi
            exit 0
            ;;
        "fix-arm64")
            echo
            log_info "=== 修复ARM64环境下的所有兼容性问题 ==="
            echo
            check_docker

            # 修复JNA库兼容性
            log_step "1/2 修复JNA库兼容性..."
            local jna_result=0
            if [ -f "$SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh" ]; then
                "$SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh"
                jna_result=$?
            else
                log_warning "JNA修复脚本不存在，跳过JNA兼容性修复"
            fi

            # 修复Node.js兼容性
            log_step "2/2 修复Node.js兼容性..."
            local nodejs_result=0
            if [ -f "$SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh" ]; then
                "$SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh"
                nodejs_result=$?
            else
                log_warning "Node.js修复脚本不存在，跳过Node.js兼容性修复"
            fi

            # 汇总结果
            echo
            log_info "=== ARM64兼容性修复结果 ==="
            if [ $jna_result -eq 0 ]; then
                log_success "✅ JNA库兼容性修复成功"
            else
                log_error "❌ JNA库兼容性修复失败"
            fi

            if [ $nodejs_result -eq 0 ]; then
                log_success "✅ Node.js兼容性修复成功"
            else
                log_error "❌ Node.js兼容性修复失败"
            fi

            if [ $jna_result -eq 0 ] && [ $nodejs_result -eq 0 ]; then
                log_success "🎉 ARM64兼容性修复全部完成！"
                echo
                log_warning "重要提示："
                log_info "  请重启Polarion服务以使所有修复生效："
                log_info "  方法1: polarion-restart（如果容器正在运行）"
                log_info "  方法2: 手动重启Polarion服务"
                exit 0
            else
                log_error "ARM64兼容性修复部分失败，请检查上述错误信息"
                exit 1
            fi
            ;;
        "")
            # 默认完整流程
            ;;
        *)
            log_error "未知参数: $1"
            echo "使用 '$0 help' 查看帮助信息"
            exit 1
            ;;
    esac

    echo
    log_info "=== Polarion开发环境一键配置脚本 ==="
    echo

    # 执行完整配置流程
    check_docker
    check_image
    cleanup_existing_container
    setup_host_directory
    initialize_polarion_data
    fix_all_permissions
    create_dev_container

    # 等待容器稳定
    sleep 5

    # ARM64环境下修复JNA库兼容性
    log_step "检查ARM64环境下的JNA库兼容性..."
    if [ -f "$SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh" ]; then
        "$SCRIPT_DIR/Polarion_Arm64_Compatibility/jna/fix_jna_arm64.sh" || log_warning "JNA库兼容性修复失败，但继续执行"
    else
        log_info "JNA修复脚本不存在，跳过JNA兼容性修复"
    fi

    # ARM64环境下修复Node.js兼容性
    log_step "检查ARM64环境下的Node.js兼容性..."
    if [ -f "$SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh" ]; then
        "$SCRIPT_DIR/Polarion_Arm64_Compatibility/node/fix_nodejs_arm64.sh" || log_warning "Node.js兼容性修复失败，但继续执行"
    else
        log_info "Node.js修复脚本不存在，跳过Node.js兼容性修复"
    fi

    # 验证配置
    if verify_dev_setup; then
        # 创建全局别名
        create_global_aliases
        show_dev_usage_info
        log_success "开发环境配置完成！"
    else
        log_error "开发环境配置验证失败，请检查日志"
        exit 1
    fi
}

# ==================== 错误处理 ====================
cleanup_on_error() {
    log_error "脚本执行失败，正在清理..."
    # 清理可能的临时容器
    docker stop "${CONTAINER_NAME}_temp" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}_temp" 2>/dev/null || true
    docker stop "${CONTAINER_NAME}_info" 2>/dev/null || true
    docker rm "${CONTAINER_NAME}_info" 2>/dev/null || true
    exit 1
}

trap 'cleanup_on_error' ERR

# ==================== 脚本入口 ====================
main "$@"
