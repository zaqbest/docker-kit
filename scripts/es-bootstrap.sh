#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# es-bootstrap.sh
#
# 幂等的 ES 初始化脚本。每次启动 ES 后跑一次即可，做几件事：
#   1. 等 ES 就绪（curl 探活）
#   2. 把 kibana_system 内置账号密码同步到 env/kibana.env 里的值
#   3. 把 elasticsearch/pipelines/*.json 全部导入为 ingest pipeline
#      （文件名 = pipeline id）
#   4. 预留位：将来可以加 index templates / ILM policies / roles
#
# 幂等的意思：重复跑不会破坏已有状态；kibana_system 密码总是重置到 env 里的值，
# pipeline 用 PUT 语义 —— 已存在的会被覆盖成仓库里的最新版。
#
# 用法：
#   bash scripts/es-bootstrap.sh                      # 默认读根 .env + env/kibana.env
#   ES_URL=https://localhost:9200 bash scripts/es-bootstrap.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 读取根 .env（不 export，只用于本脚本）
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  set -o allexport
  . "$REPO_ROOT/.env"
  set +o allexport
fi

ES_URL="${ES_URL:-https://localhost:${ELASTICSEARCH_HTTP_PORT:-9200}}"
ES_USER="${ES_USER:-elastic}"
# elastic 超管密码：从 env/elasticsearch.env 里读，脚本不写死
ES_PASSWORD="$(grep -E '^ELASTIC_PASSWORD=' "$REPO_ROOT/env/elasticsearch.env" | head -1 | cut -d= -f2- || true)"
ES_PASSWORD="${ES_PASSWORD:-elastic}"

KIBANA_SYSTEM_PASSWORD="$(grep -E '^ELASTICSEARCH_PASSWORD=' "$REPO_ROOT/env/kibana.env" | head -1 | cut -d= -f2- || true)"
KIBANA_SYSTEM_PASSWORD="${KIBANA_SYSTEM_PASSWORD:-kibana_system}"

PIPELINES_DIR="$REPO_ROOT/elasticsearch/pipelines"

log()  { printf '\033[1;34m[es-bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

# curl wrapper：自签证书跳过校验，超管账号
es() {
  curl -sk --fail -u "$ES_USER:$ES_PASSWORD" "$@"
}

wait_ready() {
  log "等待 ES 就绪 ($ES_URL) ..."
  local retries=60
  while (( retries > 0 )); do
    if es "$ES_URL/_cluster/health" >/dev/null 2>&1; then
      log "ES 就绪 ✓"
      return 0
    fi
    sleep 2
    (( retries-- ))
  done
  err "ES 在 120s 内没有就绪，请检查 'docker logs elasticsearch'"
  exit 1
}

reset_kibana_system_password() {
  log "重置 kibana_system 密码（同步到 env/kibana.env 里的值）"
  # ES 用 API 改密码不会走 elasticsearch-reset-password 那条自签证书主机名校验的坑
  local http_code
  http_code=$(curl -sk -o /dev/null -w '%{http_code}' \
    -u "$ES_USER:$ES_PASSWORD" \
    -X POST "$ES_URL/_security/user/kibana_system/_password" \
    -H 'Content-Type: application/json' \
    -d "{\"password\":\"$KIBANA_SYSTEM_PASSWORD\"}")
  if [[ "$http_code" == "200" ]]; then
    log "kibana_system 密码已重置 ✓"
  else
    err "重置密码失败，HTTP $http_code"
    exit 1
  fi
}

import_pipelines() {
  if [[ ! -d "$PIPELINES_DIR" ]]; then
    warn "$PIPELINES_DIR 不存在，跳过 pipeline 导入"
    return 0
  fi
  local count=0
  shopt -s nullglob
  for file in "$PIPELINES_DIR"/*.json; do
    local name
    name="$(basename "$file" .json)"
    log "导入 pipeline: $name"
    if es -X PUT "$ES_URL/_ingest/pipeline/$name" \
         -H 'Content-Type: application/json' \
         --data-binary "@$file" >/dev/null; then
      count=$((count+1))
    else
      err "导入 $name 失败"
      exit 1
    fi
  done
  shopt -u nullglob
  log "共导入 $count 个 pipeline ✓"
}

main() {
  wait_ready
  reset_kibana_system_password
  import_pipelines
  log "bootstrap 完成 🎉"
}

main "$@"
