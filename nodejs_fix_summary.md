# Polarion ARM64 Node.js 兼容性修复总结

## 问题描述

在 ARM64 环境下运行 Polarion 时，遇到了 Node.js 兼容性问题：

```
2025-06-22 12:57:56,179 [Thread-118] ERROR class com.polarion.alm.server.util.ChartExporterStartup - Chart renderer says: /opt/polarion/polarion/plugins/com.polarion.alm.ui_3.22.1/node/bin/node: /opt/polarion/polarion/plugins/com.polarion.alm.ui_3.22.1/node/bin/node: cannot execute binary file
2025-06-22 12:57:56,179 [Thread-119] ERROR class com.polarion.alm.server.util.ChartExporterStartup - Chart renderer has terminated for some reason. Exit code = 126
```

这是因为 Polarion 内置的 Node.js 是为 x86_64 架构编译的，无法在 ARM64 环境下运行。

## 解决方案

我们在 `setup_polarion_dev_env.sh` 脚本中添加了 ARM64 Node.js 兼容性修复功能：

### 1. 新增功能

- **Node.js 版本检测**：自动检测当前安装的 Node.js 版本和架构兼容性
- **ARM64 兼容版本下载**：自动下载 Node.js 18.20.4 ARM64 版本
- **智能文件保留**：替换 Node.js 二进制文件的同时保留 Polarion 特定的 JavaScript 文件
- **完整性验证**：验证修复后的 Node.js 是否可以正常运行

### 2. 新增命令行选项

```bash
# 仅修复 Node.js 兼容性
./setup_polarion_dev_env.sh fix-nodejs

# 修复所有 ARM64 兼容性问题（JNA + Node.js）
./setup_polarion_dev_env.sh fix-arm64
```

### 3. 修复过程

1. **检测系统架构**：只在 ARM64 环境下执行修复
2. **检测 Node.js 状态**：
   - 查找 Node.js 安装路径
   - 测试当前 Node.js 是否可以运行
   - 如果可以运行则跳过修复
3. **下载 ARM64 版本**：
   - 从官方源下载 Node.js 18.20.4 ARM64 版本
   - 支持本地缓存，避免重复下载
4. **智能替换**：
   - 备份原有安装
   - 保留 Polarion 特定的 JavaScript 文件和 node_modules
   - 替换 Node.js 二进制文件
   - 恢复 Polarion 特定文件
5. **验证修复**：
   - 测试新的 Node.js 是否可以正常运行
   - 显示版本信息和安装路径

### 4. 保留的重要文件

修复过程中会保留以下 Polarion 特定文件：
- `highcharts-convert-8.0.3.js` - 图表渲染器
- `mj-formula-convert.js` - 公式渲染器
- `node_modules/` - Node.js 依赖包目录

## 修复结果

### 修复前的错误
```
Chart renderer says: /opt/polarion/polarion/plugins/com.polarion.alm.ui_3.22.1/node/bin/node: cannot execute binary file
Exit code = 126
```

### 修复后的状态
```
Node.js v18.20.4
✅ Node.js替换成功
```

现在 Node.js 可以正常运行，不再出现 "cannot execute binary file" 错误。

## 使用方法

### 单独修复 Node.js
```bash
./setup_polarion_dev_env.sh fix-nodejs
```

### 一键修复所有 ARM64 兼容性问题
```bash
./setup_polarion_dev_env.sh fix-arm64
```

### 查看帮助信息
```bash
./setup_polarion_dev_env.sh help
```

## 技术细节

- **目标 Node.js 版本**：18.20.4 LTS（ARM64 兼容）
- **下载源**：https://nodejs.org/dist/
- **缓存目录**：`./nodejs-cache/`
- **备份目录**：`/opt/polarion/polarion/plugins_bak/nodejs_backup_*`
- **支持的架构**：ARM64/aarch64

## 注意事项

1. 修复完成后需要重启 Polarion 服务以使更改生效
2. 原有的 Node.js 安装会被备份到 plugins_bak 目录
3. 只在 ARM64 架构下执行修复，x86_64 环境会自动跳过
4. 支持重复运行，如果已经修复则会跳过

## 集成到完整配置流程

Node.js 修复功能已经集成到完整的开发环境配置流程中：

```bash
# 完整配置（包含 JNA 和 Node.js 修复）
./setup_polarion_dev_env.sh
```

这样确保在 ARM64 环境下一键配置 Polarion 开发环境时，会自动处理所有兼容性问题。
