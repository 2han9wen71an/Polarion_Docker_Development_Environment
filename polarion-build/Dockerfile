# 多架构支持的 Ubuntu 基础镜像
FROM ubuntu:22.04

# 设置构建参数，支持动态版本选择
ARG POLARION_VERSION=""
ARG TARGETARCH
ARG TARGETOS

# 环境变量设置
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNLEVEL=1
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TZ=Asia/Shanghai

# 安装基础软件包和时区配置
RUN apt-get -y update && \
    apt-get -y install sudo unzip expect curl wget mc nano iputils-ping net-tools iproute2 gnupg software-properties-common locales file tzdata && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /polarion_root

# 复制所有 ZIP 文件和脚本
COPY *.zip ./
COPY pl_starter.sh ./
COPY pl_installer.sh ./
COPY auto_installer.exp ./

# 动态检测和解压 Polarion 安装包
RUN echo "检测 Polarion 安装包..." && \
    # 查找 Polarion ZIP 文件
    if [ -n "$POLARION_VERSION" ]; then \
        echo "查找指定版本: $POLARION_VERSION"; \
        POLARION_ZIP=$(find /polarion_root -name "*${POLARION_VERSION}*linux*.zip" | head -1); \
    fi && \
    # 如果未找到指定版本或未指定版本，查找所有可用版本
    if [ -z "$POLARION_ZIP" ]; then \
        POLARION_ZIP=$(find /polarion_root -name "*Polarion*linux*.zip" -o -name "*polarion*linux*.zip" | sort -V | tail -1); \
    fi && \
    # 检查是否找到安装包
    if [ -z "$POLARION_ZIP" ]; then \
        echo "错误: 未找到任何 Polarion ZIP 安装包"; \
        exit 1; \
    fi && \
    echo "使用安装包: $(basename $POLARION_ZIP)" && \
    # 解压安装包
    echo "解压安装包..." && \
    unzip -q "$POLARION_ZIP" && \
    # 查找解压后的目录
    POLARION_DIR=$(find /polarion_root -maxdepth 1 -type d -name "*Polarion*" | head -1) && \
    if [ -z "$POLARION_DIR" ]; then \
        echo "错误: 解压后未找到 Polarion 目录"; \
        exit 1; \
    fi && \
    echo "Polarion 目录: $POLARION_DIR" && \
    # 标准化目录名
    if [ "$POLARION_DIR" != "/polarion_root/Polarion" ]; then \
        mv "$POLARION_DIR" /polarion_root/Polarion; \
    fi && \
    # 复制安装脚本到正确位置
    cp /polarion_root/pl_installer.sh /polarion_root/Polarion/ && \
    cp /polarion_root/auto_installer.exp /polarion_root/Polarion/ && \
    # 设置执行权限
    chmod +x /polarion_root/pl_starter.sh && \
    chmod +x /polarion_root/Polarion/pl_installer.sh && \
    chmod +x /polarion_root/Polarion/auto_installer.exp && \
    echo "版本检测和准备完成"

# 根据架构安装 OpenJDK 11
RUN echo "当前架构: $TARGETARCH" && \
    if [ "$TARGETARCH" = "amd64" ]; then \
        JDK_ARCH="x64"; \
        JDK_URL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.23%2B9/OpenJDK11U-jdk_x64_linux_hotspot_11.0.23_9.tar.gz"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        JDK_ARCH="aarch64"; \
        JDK_URL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.23%2B9/OpenJDK11U-jdk_aarch64_linux_hotspot_11.0.23_9.tar.gz"; \
    else \
        echo "不支持的架构: $TARGETARCH"; \
        exit 1; \
    fi && \
    echo "下载 JDK for $JDK_ARCH..." && \
    wget --no-check-certificate "$JDK_URL" -O openjdk.tar.gz && \
    mkdir -p /usr/lib/jvm && \
    tar -zxf openjdk.tar.gz -C /usr/lib/jvm && \
    rm openjdk.tar.gz

# 配置 Java 环境
RUN JDK_DIR=$(find /usr/lib/jvm -maxdepth 1 -type d -name "jdk-*" | head -1) && \
    echo "JDK 目录: $JDK_DIR" && \
    update-alternatives --install /usr/bin/java java $JDK_DIR/bin/java 100 && \
    update-alternatives --install /usr/bin/jar jar $JDK_DIR/bin/jar 100 && \
    update-alternatives --install /usr/bin/javac javac $JDK_DIR/bin/javac 100 && \
    update-alternatives --set jar $JDK_DIR/bin/jar && \
    update-alternatives --set javac $JDK_DIR/bin/javac && \
    echo "JAVA_HOME=\"$JDK_DIR\"" >> /etc/environment && \
    echo "JDK_HOME=\"$JDK_DIR\"" >> /etc/environment

# 设置 Java 环境变量
ENV JAVA_HOME=/usr/lib/jvm/jdk-11.0.23+9
ENV JDK_HOME=/usr/lib/jvm/jdk-11.0.23+9

# 动态设置 JAVA_HOME
RUN JDK_DIR=$(find /usr/lib/jvm -maxdepth 1 -type d -name "jdk-*" | head -1) && \
    echo "export JAVA_HOME=$JDK_DIR" >> /etc/bash.bashrc && \
    echo "export JDK_HOME=$JDK_DIR" >> /etc/bash.bashrc && \
    echo "JAVA_HOME and JDK_HOME 已设置为: $JDK_DIR"

# 切换到 Polarion 目录进行安装
WORKDIR /polarion_root/Polarion

# 配置系统服务
RUN printf '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d && \
    sed -i "s/^exit 101$/exit 0/" /usr/sbin/policy-rc.d

# 执行 Polarion 安装
RUN ./pl_installer.sh

# 返回根目录
WORKDIR /polarion_root

# 设置 PostgreSQL 路径
ENV PATH="/usr/lib/postgresql/14/bin:${PATH}"

# 设置入口点
ENTRYPOINT ["./pl_starter.sh"]
