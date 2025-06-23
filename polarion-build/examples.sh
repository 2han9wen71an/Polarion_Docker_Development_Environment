#!/bin/bash

# Polarion Docker 使用示例脚本

echo "========================================="
echo "Polarion Docker 多架构使用示例"
echo "========================================="

# 检查当前架构
ARCH=$(uname -m)
echo "当前系统架构: $ARCH"

case $ARCH in
    x86_64)
        echo "✅ 支持 x86_64 架构"
        PLATFORM="linux/amd64"
        ;;
    arm64|aarch64)
        echo "✅ 支持 ARM64 架构 (Apple Silicon)"
        PLATFORM="linux/arm64"
        ;;
    *)
        echo "⚠️  未测试的架构，可能需要额外配置"
        PLATFORM="linux/amd64"
        ;;
esac

echo ""
echo "========================================="
echo "构建示例"
echo "========================================="

echo "1. 基本构建（当前架构）:"
echo "   docker build -t polarion:latest ."
echo ""

echo "2. 指定版本构建:"
echo "   docker build --build-arg POLARION_VERSION=\"22_R2\" -t polarion:22-r2 ."
echo ""

echo "3. 多架构构建（需要 buildx）:"
echo "   docker buildx build --platform linux/amd64,linux/arm64 -t polarion:multiarch --push ."
echo ""

echo "4. 使用构建脚本（推荐）:"
echo "   ./build.sh -n polarion -t latest"
echo ""

echo "========================================="
echo "运行示例"
echo "========================================="

echo "1. 基本运行:"
echo "   docker run -d -p 8080:8080 --name polarion polarion:latest \"localhost,127.0.0.1\""
echo ""

echo "2. 使用环境变量:"
echo "   docker run -d -p 8080:8080 -e ALLOWED_HOSTS=\"localhost,127.0.0.1\" --name polarion polarion:latest"
echo ""

echo "3. 持久化数据:"
echo "   docker run -d -p 8080:8080 -v polarion-data:/opt/polarion/data --name polarion polarion:latest \"localhost\""
echo ""

echo "4. 使用 Docker Compose（推荐）:"
echo "   docker-compose up -d"
echo ""

echo "========================================="
echo "管理示例"
echo "========================================="

echo "查看日志:"
echo "   docker logs -f polarion"
echo ""

echo "进入容器:"
echo "   docker exec -it polarion /bin/bash"
echo ""

echo "停止服务:"
echo "   docker stop polarion"
echo ""

echo "重启服务:"
echo "   docker restart polarion"
echo ""

echo "清理资源:"
echo "   docker stop polarion && docker rm polarion"
echo "   docker volume rm polarion-data polarion-logs"
echo ""

echo "========================================="
echo "故障排除"
echo "========================================="

echo "检查容器状态:"
echo "   docker ps -a"
echo ""

echo "检查容器健康状态:"
echo "   docker inspect polarion | grep Health -A 10"
echo ""

echo "查看详细日志:"
echo "   docker logs --details polarion"
echo ""

echo "检查端口占用:"
echo "   netstat -tulpn | grep :8080"
echo "   # 或在 macOS 上:"
echo "   lsof -i :8080"
echo ""

echo "========================================="
echo "访问 Polarion"
echo "========================================="

echo "Web 界面: http://localhost:8080/polarion/"
echo "管理界面: http://localhost:8080/polarion/admin/"
echo ""
echo "默认登录信息请参考 Polarion 官方文档"
echo ""

echo "========================================="
echo "性能调优建议"
echo "========================================="

echo "1. 内存设置（推荐至少 4GB）:"
echo "   docker run -m 4g ..."
echo ""

echo "2. CPU 限制:"
echo "   docker run --cpus=\"2.0\" ..."
echo ""

echo "3. Java 堆内存调优:"
echo "   docker run -e JAVA_OPTS=\"-Xmx3g -Xms1g\" ..."
echo ""

echo "4. 使用 SSD 存储卷以提高性能"
echo ""

echo "========================================="
echo "更多信息"
echo "========================================="
echo "详细文档: README_MULTIARCH.md"
echo "Docker Compose: docker-compose.yml"
echo "构建脚本: build.sh"
echo "========================================="
