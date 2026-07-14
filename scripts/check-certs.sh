#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-certs.sh
#
# 检查 certs/ 目录下 TLS 证书的有效期，输出剩余天数并给出续期提示。
#
# 退出码：
#   0  —— 证书剩余天数 > WARN_DAYS（默认 30），一切正常
#   1  —— 证书剩余天数 <= WARN_DAYS 但 > 0，应尽快续期
#   2  —— 证书已过期或读不到证书文件
#
# 用法：
#   ./scripts/check-certs.sh                # 默认阈值 30 天
#   WARN_DAYS=45 ./scripts/check-certs.sh   # 自定义阈值
#   ./scripts/check-certs.sh --quiet        # 只输出关键信息（适合 crontab）
#
# 建议：可以加进 shell rc，登录 shell 时提醒一下：
#   [[ -o interactive ]] && ~/PanDevelop/tools/docker-kit/scripts/check-certs.sh --quiet
# ---------------------------------------------------------------------------

set -euo pipefail

# --- 参数 ------------------------------------------------------------------
WARN_DAYS="${WARN_DAYS:-30}"
QUIET=false
for arg in "$@"; do
    case "$arg" in
        -q|--quiet) QUIET=true ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
    esac
done

# --- 定位 certs 目录（脚本可从任意路径调用）--------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CERT_FILE="$REPO_ROOT/certs/server.crt"
KEY_FILE="$REPO_ROOT/certs/server.key"

# --- 颜色（仅 stdout 是 tty 时启用）----------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_GREEN=$'\033[32m'
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
    C_RED=""; C_YELLOW=""; C_GREEN=""; C_BOLD=""; C_DIM=""; C_RESET=""
fi

log() { $QUIET || echo "$@"; }

# --- 前置检查 --------------------------------------------------------------
if [[ ! -f "$CERT_FILE" ]]; then
    echo "${C_RED}✗ 找不到证书文件：$CERT_FILE${C_RESET}" >&2
    exit 2
fi
if [[ ! -f "$KEY_FILE" ]]; then
    echo "${C_YELLOW}⚠ 找不到私钥文件：$KEY_FILE${C_RESET}" >&2
fi
if ! command -v openssl >/dev/null 2>&1; then
    echo "${C_RED}✗ 未找到 openssl，请先安装${C_RESET}" >&2
    exit 2
fi

# --- 解析证书 --------------------------------------------------------------
# subject / issuer / SAN 都用一次 openssl 拿全，节省调用
CERT_INFO=$(openssl x509 -in "$CERT_FILE" -noout \
    -subject -issuer -startdate -enddate -ext subjectAltName 2>/dev/null)

SUBJECT=$(sed -n 's/^subject=//p'         <<<"$CERT_INFO")
ISSUER=$(sed  -n 's/^issuer=//p'          <<<"$CERT_INFO")
NOT_BEFORE=$(sed -n 's/^notBefore=//p'    <<<"$CERT_INFO")
NOT_AFTER=$(sed  -n 's/^notAfter=//p'     <<<"$CERT_INFO")
# SAN 在 openssl 输出里跨两行，取第一行 "X509v3 Subject Alternative Name:" 之后那一行
SAN=$(sed -n '/Subject Alternative Name/{n;s/^ *//;p;}' <<<"$CERT_INFO")

# 私钥与证书是否匹配（比较公钥 modulus 的 SHA256）
KEY_MATCH="?"
if [[ -f "$KEY_FILE" ]]; then
    CRT_HASH=$(openssl x509 -in "$CERT_FILE" -noout -pubkey 2>/dev/null | openssl sha256 | awk '{print $NF}')
    KEY_HASH=$(openssl pkey -in "$KEY_FILE" -pubout 2>/dev/null | openssl sha256 | awk '{print $NF}')
    if [[ "$CRT_HASH" == "$KEY_HASH" ]]; then
        KEY_MATCH="match"
    else
        KEY_MATCH="MISMATCH"
    fi
fi

# --- 计算剩余天数 -----------------------------------------------------------
# macOS 的 date 不认 GNU 的 -d，做双分支兼容
if date --version >/dev/null 2>&1; then
    # GNU date (Linux)
    NOT_AFTER_TS=$(date -d "$NOT_AFTER" +%s)
else
    # BSD date (macOS) —— openssl 输出格式形如 "Oct  8 23:59:59 2026 GMT"
    NOT_AFTER_TS=$(TZ=UTC date -jf "%b %e %H:%M:%S %Y %Z" "$NOT_AFTER" +%s)
fi
NOW_TS=$(date +%s)
DAYS_LEFT=$(( (NOT_AFTER_TS - NOW_TS) / 86400 ))

# --- 输出 -----------------------------------------------------------------
log ""
log "${C_BOLD}证书信息：${C_RESET} $CERT_FILE"
log "  ${C_DIM}Subject :${C_RESET} $SUBJECT"
log "  ${C_DIM}Issuer  :${C_RESET} $ISSUER"
log "  ${C_DIM}SAN     :${C_RESET} $SAN"
log "  ${C_DIM}Valid   :${C_RESET} $NOT_BEFORE  →  $NOT_AFTER"
if [[ "$KEY_MATCH" == "match" ]]; then
    log "  ${C_DIM}Key     :${C_RESET} ${C_GREEN}✓ 与证书匹配${C_RESET}"
elif [[ "$KEY_MATCH" == "MISMATCH" ]]; then
    log "  ${C_DIM}Key     :${C_RESET} ${C_RED}✗ 与证书不匹配！${C_RESET}"
fi
log ""

# --- 判定状态 --------------------------------------------------------------
if (( DAYS_LEFT < 0 )); then
    echo "${C_RED}${C_BOLD}✗ 证书已过期 $(( -DAYS_LEFT )) 天！${C_RESET}"
    echo "  请立即续期，参考本脚本尾部的续期步骤。" >&2
    exit 2
elif (( DAYS_LEFT <= WARN_DAYS )); then
    echo "${C_YELLOW}${C_BOLD}⚠ 证书还剩 $DAYS_LEFT 天，建议续期（阈值 $WARN_DAYS 天）。${C_RESET}"
    if ! $QUIET; then
        cat <<'EOF'

------------------------------------------------------------------------------
续期步骤（Cloudflare DNS-01，需要一个 CF API Token）
------------------------------------------------------------------------------
一次性安装：
    curl -sSfL https://get.acme.sh | sh -s email=acme@zaqbest.com

设置 Cloudflare 凭据（放到 ~/.zshrc 或 ~/.bashrc 里更省事）：
    export CF_Token='你的_Cloudflare_API_Token'         # Zone.Zone:Read + Zone.DNS:Edit
    export CF_Account_ID='你的_Cloudflare_Account_ID'   # Dashboard 右侧栏

签发 / 续签：
    ~/.acme.sh/acme.sh --issue \
      --dns dns_cf \
      -d zaqbest.com -d '*.zaqbest.com' \
      --keylength 2048 \
      --server letsencrypt

安装到本仓库 certs/（把命令里的路径改成你本地绝对路径）：
    ~/.acme.sh/acme.sh --install-cert -d zaqbest.com \
      --key-file       "$(pwd)/certs/server.key" \
      --fullchain-file "$(pwd)/certs/server.crt" \
      --reloadcmd      "docker compose -f docker-compose-nginx.yml    restart nginx    ; \
                        docker compose -f docker-compose-trojan-go.yml restart trojan-go"

装完再跑一次本脚本确认。
------------------------------------------------------------------------------
EOF
    fi
    exit 1
else
    log "${C_GREEN}${C_BOLD}✓ 证书剩余 $DAYS_LEFT 天，健康。${C_RESET}"
    $QUIET && echo "certs OK ($DAYS_LEFT days left)"
    exit 0
fi
