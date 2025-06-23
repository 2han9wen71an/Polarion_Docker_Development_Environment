# Polarion开发环境配置指南

## 概述
这是一个一键式的Polarion开发环境配置脚本，整合了之前所有的功能，专门针对开发环境进行了优化。

## 主要特点
- ✅ 一键配置完整的开发环境
- ✅ 自动处理卷挂载和权限问题
- ✅ 针对PostgreSQL的特殊权限要求进行优化
- ✅ 不自动启动服务，允许开发者手动控制
- ✅ **全局别名系统** - 可在任何目录使用简短命令
- ✅ 自动检测shell类型并配置别名
- ✅ 提供完整的开发工作流程指导
- ✅ 支持权限修复功能

## 快速开始

### 1. 运行配置脚本
```bash
./setup_polarion_dev_env.sh
```

### 2. 进入开发容器
```bash
docker exec -it polarion22r1 bash
```

### 3. 启动服务（使用全局别名 - 推荐）
```bash
# 检查服务状态
polarion-status

# 启动PostgreSQL数据库
postgresql-start

# 启动Polarion应用
polarion-start
```

### 3. 启动服务（传统方式 - 进入容器执行）
```bash
# 进入容器
polarion-shell

# 在容器内执行
sudo service postgresql start
sudo service apache2 start
sudo service polarion start
```

### 4. 访问Polarion
打开浏览器访问：http://localhost:8080/polarion

## 脚本功能

### 完整配置
```bash
./setup_polarion_dev_env.sh
```
执行完整的开发环境配置流程：
- 检查Docker和镜像
- 清理现有容器
- 配置挂载目录
- 初始化Polarion数据
- 修复所有权限问题
- 创建开发容器

### 仅修复权限
```bash
./setup_polarion_dev_env.sh fix-permissions
```
仅修复现有环境的权限问题，适用于：
- 权限配置出错时
- 升级系统后权限变化
- 手动修改文件后需要重置权限

### 仅创建全局别名
```bash
./setup_polarion_dev_env.sh create-aliases
```
仅创建全局shell别名，适用于：
- 别名丢失或损坏时
- 需要重新配置全局命令时
- 更换shell或配置文件时

### 查看帮助
```bash
./setup_polarion_dev_env.sh help
```

## 全局别名系统

配置完成后，会自动创建全局shell别名，让你可以在**任何目录**直接使用简短命令控制容器内的服务：

### 全局别名列表
- **`polarion-status`** - 检查所有服务状态
- **`polarion-start`** - 启动Polarion服务
- **`polarion-stop`** - 停止Polarion服务
- **`polarion-restart`** - 重启Polarion服务
- **`postgresql-start`** - 启动PostgreSQL服务
- **`postgresql-stop`** - 停止PostgreSQL服务
- **`polarion-shell`** - 进入容器
- **`polarion-exec`** - 执行容器内命令
- **`polarion-logs`** - 智能日志查看器（支持多种日志类型）

### 全局别名使用示例
```bash
# 检查服务状态（可在任何目录执行）
polarion-status

# 启动/停止PostgreSQL
postgresql-start
postgresql-stop

# 启动/停止/重启Polarion
polarion-start
polarion-stop
polarion-restart

# 进入容器
polarion-shell

# 执行容器内命令
polarion-exec ps aux
polarion-exec tail -f /opt/polarion/data/logs/main/polarion.log

# 查看日志（智能日志查看器）
polarion-logs              # 交互模式，选择日志类型
polarion-logs main         # 查看主日志
polarion-logs error        # 查看错误日志
polarion-logs startup      # 查看启动日志
polarion-logs list         # 列出所有日志文件
```

### 别名配置说明
- 别名会自动添加到你的shell配置文件（如 `~/.zshrc`, `~/.bashrc`）
- 支持自动检测shell类型（bash/zsh/fish）
- 使用绝对路径，避免路径依赖问题
- 配置完成后需要重新加载shell配置：`source ~/.zshrc`

## 开发工作流程

### 推荐工作流程（使用全局别名）
1. **启动开发环境**
   ```bash
   ./setup_polarion_dev_env.sh
   ```

2. **重新加载shell配置**
   ```bash
   source ~/.zshrc  # 或 source ~/.bashrc
   ```

3. **检查服务状态（可在任何目录执行）**
   ```bash
   polarion-status
   ```

4. **启动必要服务**
   ```bash
   postgresql-start
   polarion-start
   ```

5. **开发和调试**
   - 在宿主机 `/opt/polarion` 目录中修改文件
   - 修改会立即反映到容器中
   - 根据需要重启相应服务：`polarion-restart`

6. **停止服务**
   ```bash
   polarion-stop
   postgresql-stop
   ```

### 传统工作流程（进入容器）
1. **启动开发环境**
   ```bash
   ./setup_polarion_dev_env.sh
   ```

2. **进入容器**
   ```bash
   polarion-shell
   ```

3. **启动必要服务**
   ```bash
   sudo service postgresql start
   sudo service apache2 start
   sudo service polarion start
   ```

4. **开发和调试**
   - 在宿主机 `/opt/polarion` 目录中修改文件
   - 修改会立即反映到容器中
   - 根据需要重启相应服务

5. **停止服务**
   ```bash
   sudo service polarion stop
   sudo service apache2 stop
   sudo service postgresql stop
   ```

### 服务控制命令
在容器内可以使用以下命令控制服务：

```bash
# PostgreSQL
sudo service postgresql start|stop|restart|status

# Apache
sudo service apache2 start|stop|restart|status

# Polarion
sudo service polarion start|stop|restart|status
```

## 目录结构

### 宿主机目录
- **配置目录**: `/opt/polarion/etc/`
- **数据目录**: `/opt/polarion/data/`
- **日志目录**: `/opt/polarion/data/logs/`
- **插件目录**: `/opt/polarion/polarion/plugins/`
- **PostgreSQL数据**: `/opt/polarion/data/postgres-data/`

### 容器内目录
所有目录都挂载到容器内的 `/opt/polarion/` 对应位置。

## 权限说明

### PostgreSQL特殊权限
- PostgreSQL数据目录权限：**750** (必须)
- PostgreSQL文件权限：**640**
- 这是PostgreSQL的安全要求，不能设置为777

### 其他目录权限
- 配置目录：**777** (开发需要)
- 工作空间目录：**777** (开发需要)
- 日志目录：**777** (开发需要)

## 常见问题

### Q: 容器启动后无法访问Polarion
A: 检查服务是否已启动：
```bash
docker exec -it polarion22r1 bash
sudo service postgresql status
sudo service apache2 status
sudo service polarion status
```

### Q: PostgreSQL启动失败
A: 通常是权限问题，运行权限修复：
```bash
./setup_polarion_dev_env.sh fix-permissions
```

### Q: 修改配置文件后不生效
A: 重启相应的服务：
```bash
docker exec -it polarion22r1 sudo service polarion restart
```

### Q: 如何查看日志
A: 
```bash
# 容器日志
docker logs polarion22r1

# Polarion应用日志
docker exec -it polarion22r1 tail -f /opt/polarion/data/logs/main/polarion.log

# PostgreSQL日志
docker exec -it polarion22r1 tail -f /opt/polarion/data/postgres-data/log.out
```

## 开发提示

1. **文件修改**: 直接在宿主机 `/opt/polarion` 目录中修改文件
2. **配置更改**: 修改配置后记得重启相应服务
3. **插件开发**: 插件文件放在 `/opt/polarion/polarion/plugins/` 目录
4. **数据备份**: 重要数据建议定期备份 `/opt/polarion/data/` 目录
5. **资源管理**: 开发完成后停止服务以释放系统资源

## 故障排除

如果遇到问题，按以下顺序排查：

1. **检查Docker状态**
   ```bash
   docker ps
   docker logs polarion22r1
   ```

2. **检查权限**
   ```bash
   ./setup_polarion_dev_env.sh fix-permissions
   ```

3. **重新配置环境**
   ```bash
   ./setup_polarion_dev_env.sh
   ```

4. **查看详细日志**
   ```bash
   docker exec -it polarion22r1 bash
   tail -f /opt/polarion/data/logs/main/polarion.log
   ```
