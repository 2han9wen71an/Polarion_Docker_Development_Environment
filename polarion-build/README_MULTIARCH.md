# Polarion Docker 多架构支持

这个改进版的 Dockerfile 支持多架构构建和动态版本检测，可以在 x86_64 和 ARM64 (Apple Silicon) 架构上运行。

## 主要特性

### 🏗️ 多架构支持
- **x86_64 (AMD64)**: 传统 Intel/AMD 处理器
- **ARM64 (AArch64)**: Apple Silicon (M1/M2/M3) 和 ARM 服务器

### 🔄 动态版本检测
- 自动扫描目录中的 Polarion ZIP 安装包
- 支持指定特定版本或自动选择最新版本
- 无需修改 Dockerfile 即可支持不同版本

### 📦 智能包管理
- 根据目标架构自动选择合适的 JDK 版本
- 优化的依赖安装和缓存清理

## 快速开始

### 1. 准备安装包
将 Polarion 安装包放在 Dockerfile 同目录下：
```
polarion-build/
├── Dockerfile
├── PolarionALM_22_R2_linux.zip  # 或其他版本的 ZIP 包
├── pl_starter.sh
├── pl_installer.sh
├── auto_installer.exp
└── build.sh
```

**注意**: 目录名称已从 "Polarion 22 R2" 更改为 "polarion-build"，以支持构建不同版本的 Polarion，而不局限于特定版本。

### 2. 使用构建脚本（推荐）
```bash
# 赋予执行权限
chmod +x build.sh

# 多架构构建
./build.sh -n my-polarion -t latest

# 指定版本构建
./build.sh -v "22_R2" -t 22-r2

# 仅构建当前架构（更快）
./build.sh --single-arch

# 构建并推送到仓库
./build.sh --push -n myregistry/polarion
```

### 3. 手动构建

#### 多架构构建
```bash
# 创建 buildx builder
docker buildx create --name polarion-builder --use

# 构建多架构镜像
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t polarion:latest \
  --push .
```

#### 单架构构建
```bash
# 当前架构构建
docker build -t polarion:latest .

# 指定版本构建
docker build \
  --build-arg POLARION_VERSION="22_R2" \
  -t polarion:22-r2 .
```

## 构建参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `POLARION_VERSION` | 指定 Polarion 版本 | 自动检测 |
| `TARGETARCH` | 目标架构 | 自动检测 |
| `TARGETOS` | 目标操作系统 | linux |

## 运行容器

```bash
# 基本运行
docker run -d \
  -p 8080:8080 \
  --name polarion \
  polarion:latest \
  "localhost,127.0.0.1"

# 使用环境变量
docker run -d \
  -p 8080:8080 \
  -e ALLOWED_HOSTS="localhost,127.0.0.1,your-domain.com" \
  --name polarion \
  polarion:latest

# 持久化数据
docker run -d \
  -p 8080:8080 \
  -v polarion-data:/opt/polarion/data \
  --name polarion \
  polarion:latest \
  "localhost,127.0.0.1"
```

## 版本检测逻辑

Dockerfile 会按以下顺序查找安装包：

1. **指定版本**: 如果设置了 `POLARION_VERSION` 构建参数，优先查找匹配的文件
2. **自动检测**: 扫描所有 `*Polarion*linux*.zip` 文件
3. **版本排序**: 按文件名排序，选择最新版本

### 支持的文件名格式
- `PolarionALM_22_R2_linux.zip`
- `PolarionALM_23_R1_linux.zip`
- `polarion-2024-linux.zip`
- 任何包含 "Polarion" 和 "linux" 的 ZIP 文件

## 架构特定配置

### JDK 下载
- **x86_64**: OpenJDK11U-jdk_x64_linux_hotspot
- **ARM64**: OpenJDK11U-jdk_aarch64_linux_hotspot

### 包管理
- 自动清理 APT 缓存以减小镜像大小
- 根据架构优化依赖安装

## 故障排除

### 常见问题

1. **找不到安装包**
   ```
   错误: 未找到任何 Polarion ZIP 安装包
   ```
   - 确保 ZIP 文件在正确目录
   - 检查文件名包含 "Polarion" 和 "linux"

2. **架构不匹配**
   ```
   不支持的架构: xxx
   ```
   - 检查 Docker 版本是否支持目标架构
   - 使用 `--single-arch` 选项构建当前架构

3. **buildx 不可用**
   ```
   Docker buildx 不可用
   ```
   - 升级 Docker 到最新版本
   - 或使用传统 `docker build` 命令

### 调试构建
```bash
# 查看构建日志
docker buildx build --progress=plain .

# 检查中间层
docker run -it --rm <intermediate-image-id> /bin/bash
```

## 性能优化

### 构建优化
- 使用 `.dockerignore` 排除不必要文件
- 利用 Docker 层缓存
- 多阶段构建（如需要）

### 运行优化
- 合理分配内存和 CPU 资源
- 使用数据卷持久化重要数据
- 配置适当的健康检查

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个多架构 Dockerfile！

## 许可证

与原项目保持一致的许可证。
