#!/bin/sh
# ============================================================
#  Sub-Store 管理脚本（Alpine LXC，无 Docker）
#  用法:
#    sh install-sub-store.sh            # 安装 / 更新
#    sh install-sub-store.sh uninstall  # 卸载
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()  { printf "${RED}[ERR]${NC}   %s\n" "$*"; exit 1; }
step() { printf "\n${CYAN}==> %s${NC}\n" "$*"; }

# ---------- 固定配置 ----------
INSTALL_DIR="/opt/sub-store"
FRONTEND_PORT="${FRONTEND_PORT:-3001}"
BACKEND_PORT="${BACKEND_PORT:-3000}"
BACKEND_PATH="${SUB_STORE_BACKEND_PATH:-}"
CMD_FILE="/usr/local/bin/sub-store"
INIT_FILE="/etc/init.d/substore"
LOG_FILE="/var/log/sub-store.log"
BACKEND_FILE="$INSTALL_DIR/sub-store.bundle.js"

# ---------- 权限检查 ----------
[ "$(id -u)" -eq 0 ] || err "请以 root 用户运行此脚本"

# ============================================================
# 显示信息函数（安装后的 sub-store 命令也调用此函数）
# ============================================================
show_info() {
  # 获取本机 IP（多种方式兜底，避免卡住）
  LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$LOCAL_IP" ] && LOCAL_IP=$(ip addr show 2>/dev/null | awk '/inet / && !/127.0.0.1/{print $2; exit}' | cut -d/ -f1)
  [ -z "$LOCAL_IP" ] && LOCAL_IP="<服务器IP>"

  # 从 init 文件读取实际配置
  ACTUAL_PATH=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$INIT_FILE" 2>/dev/null \
    | cut -d'"' -f2)
  ACTUAL_FPORT=$(grep 'SUB_STORE_FRONTEND_PORT=' "$INIT_FILE" 2>/dev/null \
    | cut -d'"' -f2)
  [ -z "$ACTUAL_FPORT" ] && ACTUAL_FPORT="$FRONTEND_PORT"

  # 检查进程是否在运行（不用 rc-service，避免卡住）
  STATUS="已停止"
  if pgrep -f "sub-store.bundle.js" >/dev/null 2>&1; then
    STATUS="运行中 ✓"
  fi

  printf "\n${GREEN}"
  cat <<BANNER
╔══════════════════════════════════════════════════════════════╗
║                Sub-Store 状态信息                            ║
╠══════════════════════════════════════════════════════════════╣
║  服务状态:  ${STATUS}
║  安装目录:  ${INSTALL_DIR}
║  日志文件:  ${LOG_FILE}
╠══════════════════════════════════════════════════════════════╣
║  前端访问地址:
║    http://${LOCAL_IP}:${ACTUAL_FPORT}
║
║  后端连接地址（填入前端后端设置）:
║    http://${LOCAL_IP}:${ACTUAL_FPORT}${ACTUAL_PATH}
║
║  一键访问链接（推荐收藏）:
║    http://${LOCAL_IP}:${ACTUAL_FPORT}?api=http://${LOCAL_IP}:${ACTUAL_FPORT}${ACTUAL_PATH}
╠══════════════════════════════════════════════════════════════╣
║  服务管理:
║    启动:  rc-service substore start
║    停止:  rc-service substore stop
║    重启:  rc-service substore restart
║    日志:  tail -f ${LOG_FILE}
╠══════════════════════════════════════════════════════════════╣
║  sub-store 命令用法:
║    sub-store           # 显示此信息
║    sub-store update    # 更新到最新版本
║    sub-store uninstall # 卸载
╚══════════════════════════════════════════════════════════════╝
BANNER
  printf "${NC}"
}

# ============================================================
# 卸载
# ============================================================
do_uninstall() {
  step "卸载 Sub-Store"

  log "停止并移除服务..."
  rc-service substore stop 2>/dev/null || true
  rc-update del substore default 2>/dev/null || true
  pkill -f "sub-store.bundle.js" 2>/dev/null || true
  rm -f "$INIT_FILE"

  log "删除文件..."
  rm -rf "$INSTALL_DIR"
  rm -f "$CMD_FILE"
  rm -f "$LOG_FILE"
  rm -f /var/run/sub-store.pid

  log "卸载完成 ✓"
}

# ============================================================
# 安装 / 更新
# ============================================================
do_install() {
  IS_UPDATE=0
  if [ -f "$BACKEND_FILE" ]; then
    IS_UPDATE=1
    step "检测到已有安装，执行更新"
    rc-service substore stop 2>/dev/null || true
    pkill -f "sub-store.bundle.js" 2>/dev/null || true
    sleep 1
    # 更新时保留原有安全路径
    BACKEND_PATH=$(grep 'SUB_STORE_FRONTEND_BACKEND_PATH=' "$INIT_FILE" 2>/dev/null \
      | sed 's/.*="\(.*\)"/\1/')
    log "保留原有安全路径: $BACKEND_PATH"
  else
    step "全新安装 Sub-Store"
  fi

  # 自动生成安全路径（仅首次安装）
  if [ -z "$BACKEND_PATH" ]; then
    BACKEND_PATH="/$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)"
    log "已生成安全路径: $BACKEND_PATH"
  fi

  # ---- 1. 安装依赖 ----
  step "1. 安装依赖"
  apk update
  apk add --no-cache nodejs curl unzip
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  log "Node.js 版本: $(node -v)"

  # ---- 2. 创建目录 ----
  step "2. 准备目录"
  mkdir -p "$INSTALL_DIR/frontend/dist"

  # ---- 3. 下载后端 ----
  step "3. 下载后端"
  log "正在下载 sub-store.bundle.js ..."
  curl -fsSL \
    "https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js" \
    -o "$BACKEND_FILE" \
    || err "后端下载失败"
  log "后端下载完成"

  # ---- 4. 下载前端 ----
  step "4. 下载前端"
  log "正在下载前端 dist.zip ..."
  curl -fsSL \
    "https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip" \
    -o /tmp/dist.zip \
    || err "前端下载失败"

  rm -rf "$INSTALL_DIR/frontend/dist"
  mkdir -p "$INSTALL_DIR/frontend/dist"
  unzip -q /tmp/dist.zip -d /tmp/sub-store-fe
  rm -f /tmp/dist.zip

  if [ -d /tmp/sub-store-fe/dist ]; then
    mv /tmp/sub-store-fe/dist/* "$INSTALL_DIR/frontend/dist/"
  else
    mv /tmp/sub-store-fe/* "$INSTALL_DIR/frontend/dist/"
  fi
  rm -rf /tmp/sub-store-fe
  log "前端解压完成"

  # ---- 5. 创建 init 服务 ----
  step "5. 配置 OpenRC 服务"
  cat > "$INIT_FILE" <<INITEOF
#!/sbin/openrc-run

name="Sub-Store"
description="Sub-Store Backend Service"
command="/usr/bin/node"
command_args="${BACKEND_FILE}"
command_user="root"
pidfile="/var/run/sub-store.pid"

export SUB_STORE_FRONTEND_BACKEND_PATH="${BACKEND_PATH}"
export SUB_STORE_BACKEND_CRON="0 0 * * *"
export SUB_STORE_FRONTEND_PATH="${INSTALL_DIR}/frontend/dist"
export SUB_STORE_FRONTEND_HOST="0.0.0.0"
export SUB_STORE_FRONTEND_PORT="${FRONTEND_PORT}"
export SUB_STORE_DATA_BASE_PATH="${INSTALL_DIR}"
export SUB_STORE_BACKEND_API_HOST="127.0.0.1"
export SUB_STORE_BACKEND_API_PORT="${BACKEND_PORT}"

depend() {
    need net
    after firewall
}

start_pre() {
    ulimit -n 32767
    echo "[\$(date)] 启动：Node \$(node -v)" > "${LOG_FILE}"
}

start() {
    ebegin "Starting Sub-Store"
    start-stop-daemon --start \
        --user "\$command_user" \
        --exec "\$command" \
        --pidfile "\$pidfile" \
        --make-pidfile \
        --background \
        -- \
        \$command_args >> "${LOG_FILE}" 2>&1
    eend \$?
}

stop() {
    ebegin "Stopping Sub-Store"
    start-stop-daemon --stop \
        --pidfile "\$pidfile" \
        --exec "\$command"
    eend \$?
    rm -f "\$pidfile"
}
INITEOF
  chmod +x "$INIT_FILE"
  log "服务文件写入完成"

  # ---- 6. 安装 sub-store 命令 ----
  step "6. 安装 sub-store 命令"
  # 在安装目录保留脚本副本
  cp "$0" "$INSTALL_DIR/install-sub-store.sh" 2>/dev/null || true
  chmod +x "$INSTALL_DIR/install-sub-store.sh" 2>/dev/null || true

  # 写独立 wrapper：默认显示信息，支持 update/uninstall 子命令
  cat > "$CMD_FILE" <<'WRAPPER'
#!/bin/sh
SCRIPT_PATH="/opt/sub-store/install-sub-store.sh"
case "${1:-}" in
  update)    sh "$SCRIPT_PATH" ;;
  uninstall) sh "$SCRIPT_PATH" uninstall ;;
  *)         sh "$SCRIPT_PATH" info ;;
esac
WRAPPER
  chmod +x "$CMD_FILE"
  log "已注册全局命令: sub-store"
  log "  sub-store           # 显示状态和访问链接"
  log "  sub-store update    # 更新到最新版本"
  log "  sub-store uninstall # 卸载"

  # ---- 7. 启动服务 ----
  step "7. 启动服务"
  rm -f /var/run/sub-store.pid
  if [ ! -d /run/openrc ]; then
    mkdir -p /run/openrc
    touch /run/openrc/softlevel
  fi

  rc-update add substore default 2>/dev/null || true
  rc-service substore start || err "服务启动失败，请查看: $LOG_FILE"

  # ---- 8. 等待就绪 ----
  log "等待服务启动..."
  RETRY=0
  until curl -sf "http://127.0.0.1:${FRONTEND_PORT}/" >/dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    [ "$RETRY" -ge 15 ] && { warn "服务未及时响应，请查看: $LOG_FILE"; break; }
    sleep 2
  done
  [ "$RETRY" -lt 15 ] && log "服务就绪 ✓"

  if [ "$IS_UPDATE" -eq 1 ]; then
    log "更新完成 ✓"
  else
    log "安装完成 ✓"
  fi

  show_info
}

# ============================================================
# 入口
# ============================================================
case "${1:-}" in
  uninstall)
    do_uninstall
    ;;
  info)
    show_info
    ;;
  *)
    do_install
    ;;
esac
