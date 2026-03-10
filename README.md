# Sub-Store 部署脚本

在 Alpine Linux LXC 容器中一键部署 [Sub-Store](https://github.com/sub-store-org/Sub-Store)，无需 Docker。

## 特性

- 支持 amd64 / arm64 架构
- 前端反代后端，后端不对外暴露
- 随机安全路径作为鉴权，无需额外配置 Token
- 支持一键安装、更新、卸载
- 安装后注册全局 `sub-store` 命令

## 环境要求

- Alpine Linux 3.17+
- LXC 容器（PVE 或其他平台）
- root 权限

## 安装

```sh
sh install-sub-store.sh
```

安装完成后会输出访问地址和一键链接：

```
╔══════════════════════════════════════════════════════════════╗
║                Sub-Store 状态信息                            ║
╠══════════════════════════════════════════════════════════════╣
║  服务状态:  运行中 ✓
║  安装目录:  /opt/sub-store
║  日志文件:  /var/log/sub-store.log
╠══════════════════════════════════════════════════════════════╣
║  前端访问地址:
║    http://192.168.1.20:3001
║
║  后端连接地址（填入前端后端设置）:
║    http://192.168.1.20:3001/<安全路径>
║
║  一键访问链接（推荐收藏）:
║    http://192.168.1.20:3001?api=http://192.168.1.20:3001/<安全路径>
╠══════════════════════════════════════════════════════════════╣
║  服务管理:
║    启动:  rc-service substore start
║    停止:  rc-service substore stop
║    重启:  rc-service substore restart
║    日志:  tail -f /var/log/sub-store.log
╠══════════════════════════════════════════════════════════════╣
║  sub-store 命令用法:
║    sub-store           # 显示此信息
║    sub-store update    # 更新到最新版本
║    sub-store uninstall # 卸载
╚══════════════════════════════════════════════════════════════╝
```

## 更新

```sh
sub-store update
```

更新时会自动保留原有安全路径，已配置的书签链接不受影响。

## 卸载

```sh
sub-store uninstall
```

卸载会删除以下内容：
- 服务文件 `/etc/init.d/substore`
- 安装目录 `/opt/sub-store`
- 全局命令 `/usr/local/bin/sub-store`
- 日志文件 `/var/log/sub-store.log`

## 目录结构

```
/opt/sub-store/
├── frontend/
│   └── dist/               # 前端静态文件
├── sub-store.bundle.js     # 后端文件
└── install-sub-store.sh    # 脚本副本
```

## 端口说明

| 端口 | 用途 | 对外 |
|------|------|------|
| 3001 | 前端 / 反代入口 | ✅ |
| 3000 | 后端 API | ❌ 仅本地 |

后端只监听 `127.0.0.1:3000`，不对外暴露。外部所有请求通过前端 3001 端口经安全路径反代到后端。

## 自定义变量

执行脚本前可通过环境变量覆盖默认值：

```sh
export FRONTEND_PORT=3001           # 前端端口（默认 3001）
export BACKEND_PORT=3000            # 后端端口（默认 3000）
export SUB_STORE_BACKEND_PATH="/自定义路径"  # 安全路径（默认随机生成）
sh install-sub-store.sh
```

## 访问与使用

### 首次访问

用浏览器打开一键链接（安装完成时输出），前端会自动连接后端，无需手动配置。

建议将此链接保存为书签，换设备访问时直接用同一链接，无需重新配置后端。

### IP 变更后

重新执行 `sub-store` 查看新的访问链接：

```sh
sub-store
```

### 添加订阅

1. 打开前端页面，点击「订阅」→「新建订阅」
2. 填写名称和原始订阅链接
3. 保存后获取转换后的订阅链接，格式如下：

```
# Clash / Mihomo
http://<IP>:3001/download/<订阅名>?target=clash

# Surge
http://<IP>:3001/download/<订阅名>?target=surge

# Quantumult X
http://<IP>:3001/download/<订阅名>?target=quanx
```

## 服务管理

```sh
rc-service substore start    # 启动
rc-service substore stop     # 停止
rc-service substore restart  # 重启
tail -f /var/log/sub-store.log  # 实时日志
```

服务已加入 OpenRC `default` 运行级，容器重启后自动启动。

## 常见问题

**服务启动后立即退出**

查看错误日志：
```sh
cat /var/log/sub-store.log
```

**端口被占用**

```sh
ss -tlnp | grep 3001
pkill -f "sub-store.bundle.js"
rc-service substore start
```

**无法连接后端**

确认服务正在运行：
```sh
sub-store
pgrep -f sub-store.bundle.js
```

**换了 IP 后书签失效**

重新执行 `sub-store` 获取新链接，安全路径不变，只需替换 IP 部分。
