#!/bin/bash

# Polarion Docker 多架构构建脚本
# 支持 x86_64 和 ARM64 架构

set -e

# 默认配置
DEFAULT_IMAGE_NAME="polarion"
DEFAULT_TAG="latest"
DEFAULT_PLATFORM="linux/amd64,linux/arm64"

# 显示帮助信息
show_help() {
    cat << EOF
Polarion Docker 多架构构建脚本

用法: $0 [选项]

选项:
    -n, --name NAME         Docker 镜像名称 (默认: $DEFAULT_IMAGE_NAME)
    -t, --tag TAG          Docker 镜像标签 (默认: $DEFAULT_TAG)
    -v, --version VERSION  指定 Polarion 版本 (可选，自动检测)
    -p, --platform PLATFORM 目标平台 (默认: $DEFAULT_PLATFORM)
    --single-arch          仅构建当前架构
    --push                 构建后推送到仓库
    --no-cache             不使用构建缓存
    -h, --help             显示此帮助信息

示例:
    # 构建多架构镜像
    $0 -n my-polarion -t v22.2

    # 构建指定版本
    $0 -v "22_R2" -t 22-r2

    # 仅构建当前架构
    $0 --single-arch

    # 构建并推送
    $0 --push -n myregistry/polarion

支持的架构:
    - linux/amd64 (x86_64)
    - linux/arm64 (Apple Silicon)
EOF
}

# 解析命令行参数
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
TAG="$DEFAULT_TAG"
POLARION_VERSION=""
PLATFORM="$DEFAULT_PLATFORM"
PUSH=false
NO_CACHE=false
SINGLE_ARCH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            IMAGE_NAME="$2"
            shift 2
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -v|--version)
            POLARION_VERSION="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        --single-arch)
            SINGLE_ARCH=true
            shift
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检测当前架构
CURRENT_ARCH=$(uname -m)
case $CURRENT_ARCH in
    x86_64)
        CURRENT_PLATFORM="linux/amd64"
        ;;
    arm64|aarch64)
        CURRENT_PLATFORM="linux/arm64"
        ;;
    *)
        echo "警告: 未识别的架构 $CURRENT_ARCH，使用默认平台"
        CURRENT_PLATFORM="linux/amd64"
        ;;
esac

# 如果选择单架构构建，使用当前架构
if [ "$SINGLE_ARCH" = true ]; then
    PLATFORM="$CURRENT_PLATFORM"
    echo "单架构构建模式，目标平台: $PLATFORM"
fi

# 检查 Docker buildx
if ! docker buildx version >/dev/null 2>&1; then
    echo "错误: Docker buildx 不可用，多架构构建需要 buildx 支持"
    echo "请升级 Docker 或使用 --single-arch 选项"
    exit 1
fi

# 检查可用的 ZIP 文件
echo "检查可用的 Polarion 安装包..."
ZIP_FILES=($(find . -name "*Polarion*linux*.zip" -o -name "*polarion*linux*.zip" 2>/dev/null))

if [ ${#ZIP_FILES[@]} -eq 0 ]; then
    echo "错误: 未找到任何 Polarion ZIP 安装包"
    echo "请确保在当前目录中有 Polarion 安装包文件"
    exit 1
fi

echo "找到以下安装包:"
for file in "${ZIP_FILES[@]}"; do
    echo "  - $(basename "$file")"
done

# 构建参数
BUILD_ARGS=""
if [ -n "$POLARION_VERSION" ]; then
    BUILD_ARGS="--build-arg POLARION_VERSION=$POLARION_VERSION"
    echo "指定版本: $POLARION_VERSION"
fi

# 构建选项
BUILD_OPTIONS=""
if [ "$NO_CACHE" = true ]; then
    BUILD_OPTIONS="$BUILD_OPTIONS --no-cache"
fi

if [ "$PUSH" = true ]; then
    BUILD_OPTIONS="$BUILD_OPTIONS --push"
else
    BUILD_OPTIONS="$BUILD_OPTIONS --load"
fi

# 完整镜像名
FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"

echo "========================================="
echo "Polarion Docker 构建配置"
echo "========================================="
echo "镜像名称: $FULL_IMAGE_NAME"
echo "目标平台: $PLATFORM"
echo "当前架构: $CURRENT_ARCH ($CURRENT_PLATFORM)"
echo "推送镜像: $PUSH"
echo "使用缓存: $([ "$NO_CACHE" = true ] && echo "否" || echo "是")"
echo "========================================="

# 确认构建
read -p "是否继续构建? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "构建已取消"
    exit 0
fi

# 创建 buildx builder（如果不存在）
BUILDER_NAME="polarion-builder"
if ! docker buildx ls | grep -q "$BUILDER_NAME"; then
    echo "创建 buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use
else
    echo "使用现有 builder: $BUILDER_NAME"
    docker buildx use "$BUILDER_NAME"
fi

# 执行构建
echo "开始构建 Docker 镜像..."
echo "命令: docker buildx build --platform $PLATFORM $BUILD_ARGS $BUILD_OPTIONS -t $FULL_IMAGE_NAME ."

docker buildx build \
    --platform "$PLATFORM" \
    $BUILD_ARGS \
    $BUILD_OPTIONS \
    -t "$FULL_IMAGE_NAME" \
    .

if [ $? -eq 0 ]; then
    echo "========================================="
    echo "构建成功完成!"
    echo "镜像: $FULL_IMAGE_NAME"
    echo "平台: $PLATFORM"
    
    if [ "$PUSH" = true ]; then
        echo "镜像已推送到仓库"
    else
        echo "镜像已加载到本地 Docker"
        echo ""
        echo "运行镜像:"
        echo "docker run -d --name polarion --net=host -e ALLOWED_HOSTS="0.0.0.0" $FULL_IMAGE_NAME"
    fi
    echo "========================================="
else
    echo "构建失败!"
    exit 1
fi
