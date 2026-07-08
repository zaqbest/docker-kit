#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# init-swap.sh
#
# 在小内存机器上创建 swap 文件作为 OOM 兜底。JVM 服务（nexus、ES 等）在 GC
# 或启动峰值时可能瞬间申请大量 native 内存，没有 swap 时一撞满就被内核直接
# SIGKILL；有 swap 时内核会先把冷页换出，给 JVM 缓冲时间。
#
# 幂等：已经有 /swapfile 且已挂载就跳过；swappiness 也会检查现值再决定要不要写。
#
# 默认参数：
#   SWAP_SIZE_GB=2       swap 文件大小（GB）。8GB 机器建议 2G，够启动峰值即可。
#   SWAPPINESS=10        只有物理内存快满时才用 swap，日常性能不受影响。
#   SWAP_FILE=/swapfile  swap 文件路径。
#
# 用法（需要 root）:
#   sudo bash scripts/init-swap.sh
#   sudo SWAP_SIZE_GB=4 bash scripts/init-swap.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SWAP_SIZE_GB="${SWAP_SIZE_GB:-2}"
SWAPPINESS="${SWAPPINESS:-10}"
SWAP_FILE="${SWAP_FILE:-/swapfile}"

log()  { printf '\033[1;32m[init-swap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[init-swap]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[init-swap]\033[0m %s\n' "$*" >&2; }

if [[ $EUID -ne 0 ]]; then
  err "需要 root 权限：sudo bash scripts/init-swap.sh"
  exit 1
fi

# ---- 1. 创建 swap 文件 ----------------------------------------------------
if [[ -f "$SWAP_FILE" ]]; then
  log "$SWAP_FILE 已存在，跳过创建"
else
  log "创建 ${SWAP_SIZE_GB}G swap 文件：$SWAP_FILE"
  # fallocate 在 ext4/xfs 上瞬间完成；某些文件系统（如 btrfs）不支持则回落到 dd
  if ! fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE" 2>/dev/null; then
    warn "fallocate 失败（文件系统可能不支持），回落到 dd"
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
  fi
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
fi

# ---- 2. 启用 swap ---------------------------------------------------------
if swapon --show=NAME --noheadings | grep -qx "$SWAP_FILE"; then
  log "$SWAP_FILE 已启用"
else
  swapon "$SWAP_FILE"
  log "$SWAP_FILE 已启用"
fi

# ---- 3. 开机自动挂载 ------------------------------------------------------
if grep -qE "^${SWAP_FILE}[[:space:]]" /etc/fstab; then
  log "/etc/fstab 已有 $SWAP_FILE 条目，跳过"
else
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
  log "已写入 /etc/fstab（下次重启自动挂载）"
fi

# ---- 4. 设置 swappiness ---------------------------------------------------
current_swappiness="$(sysctl -n vm.swappiness)"
if [[ "$current_swappiness" == "$SWAPPINESS" ]]; then
  log "vm.swappiness 已是 $SWAPPINESS，跳过"
else
  sysctl -w "vm.swappiness=$SWAPPINESS" >/dev/null
  # 持久化：写到 /etc/sysctl.d/ 而不是 sysctl.conf，符合现代 systemd 惯例
  echo "vm.swappiness=$SWAPPINESS" > /etc/sysctl.d/99-docker-kit-swap.conf
  log "vm.swappiness: $current_swappiness → $SWAPPINESS（已持久化）"
fi

# ---- 5. 结果 --------------------------------------------------------------
echo
log "完成，当前内存/swap 情况："
free -h
