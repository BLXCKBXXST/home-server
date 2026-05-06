#!/usr/bin/env bash
# 99-status.sh — полный осмотр стека: контейнеры, публичные URL, порты, ресурсы.
# Не меняет никаких настроек.
set -uo pipefail

STACK_DIR="/opt/stack"
CADDYFILE="${STACK_DIR}/caddy/Caddyfile"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "  ${YELLOW}[!!]${NC}  $*"; }
fail() { echo -e "  ${RED}[XX]${NC}  $*"; }
section() { echo; echo -e "${BOLD}${CYAN}== $* ==${NC}"; }

# ---------------------------------------------------------------------------
section "Сервер"

HOSTNAME_VAL="$(hostname 2>/dev/null || echo '?')"
UPTIME_VAL="$(uptime -p 2>/dev/null || uptime)"
LOAD_VAL="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')"
echo -e "  Хост:    ${BOLD}${HOSTNAME_VAL}${NC}"
echo    "  Uptime:  ${UPTIME_VAL}"
echo    "  Load:    ${LOAD_VAL}"

# RAM
if [[ -f /proc/meminfo ]]; then
    MEM_TOTAL=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    MEM_AVAIL=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))
    MEM_USED_MB=$(( MEM_USED / 1024 ))
    MEM_TOTAL_MB=$(( MEM_TOTAL / 1024 ))
    MEM_PCT=$(( MEM_USED * 100 / MEM_TOTAL ))
    echo    "  RAM:     ${MEM_USED_MB} MB / ${MEM_TOTAL_MB} MB (${MEM_PCT}%)"
fi

# Disk /opt/stack
if command -v df >/dev/null 2>&1; then
    DISK_LINE="$(df -h "${STACK_DIR}" 2>/dev/null | tail -1)"
    DISK_USED="$(echo "${DISK_LINE}" | awk '{print $3}')"
    DISK_TOTAL="$(echo "${DISK_LINE}" | awk '{print $2}')"
    DISK_PCT="$(echo "${DISK_LINE}"  | awk '{print $5}')"
    echo    "  Disk:    ${DISK_USED} / ${DISK_TOTAL} (${DISK_PCT}) — ${STACK_DIR}"
fi

# ---------------------------------------------------------------------------
section "Сеть"

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo    "  LAN IP:  ${LAN_IP:-?}"

if command -v curl >/dev/null 2>&1; then
    WAN_IP="$(curl -4fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo '?')"
    echo    "  WAN IP:  ${WAN_IP}"
fi

# ---------------------------------------------------------------------------
section "Контейнеры Docker"

if ! command -v docker >/dev/null 2>&1; then
    fail "docker не найден"
else
    printf "  %-20s %-12s %-10s %s\n" "NAME" "STATUS" "HEALTH" "PORTS"
    printf "  %-20s %-12s %-10s %s\n" "--------------------" "------------" "----------" "-----"

    for SVC in caddy filebrowser findmydevice crafty terraria; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${SVC}"; then
            STATUS="$(docker inspect -f '{{.State.Status}}'  "${SVC}" 2>/dev/null || echo '?')"
            HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "${SVC}" 2>/dev/null || echo '?')"
            PORTS="$(docker inspect -f '{{range $p,$v := .NetworkSettings.Ports}}{{$p}}->{{(index $v 0).HostPort}} {{end}}' "${SVC}" 2>/dev/null | tr -s ' ' | sed 's/ $//' || echo '')"
            case "${STATUS}" in
                running)   COLOR="${GREEN}" ;;
                restarting|exited) COLOR="${RED}" ;;
                *) COLOR="${YELLOW}" ;;
            esac
            printf "  %-20s ${COLOR}%-12s${NC} %-10s %s\n" "${SVC}" "${STATUS}" "${HEALTH}" "${PORTS}"
        else
            printf "  %-20s ${YELLOW}%-12s${NC}\n" "${SVC}" "not found"
        fi
    done
fi

# ---------------------------------------------------------------------------
section "HTTPS публичные URL (Caddy)"

# Читаем домены из Caddyfile автоматически
CADDY_DOMAINS=()
if [[ -f "${CADDYFILE}" ]]; then
    while IFS= read -r line; do
        # строки вида "domain.example.com {"
        if [[ "${line}" =~ ^([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})[[:space:]]*\{ ]]; then
            CADDY_DOMAINS+=("${BASH_REMATCH[1]}")
        fi
    done < "${CADDYFILE}"
fi

# Дополнительно всегда проверяем известные домены
for D in fmd.server34.netcraze.club files.server34.netcraze.club; do
    [[ " ${CADDY_DOMAINS[*]:-} " == *" ${D} "* ]] || CADDY_DOMAINS+=("${D}")
done

if ! command -v curl >/dev/null 2>&1; then
    warn "curl не установлен — проверка URL недоступна"
else
    for DOMAIN in "${CADDY_DOMAINS[@]:-}"; do
        [[ -z "${DOMAIN}" ]] && continue
        HTTP_CODE="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 8 "https://${DOMAIN}" 2>/dev/null || echo '000')"
        URL_STR="https://${DOMAIN}"
        case "${HTTP_CODE}" in
            2??) ok  "${URL_STR}  → HTTP ${HTTP_CODE}" ;;
            3??) ok  "${URL_STR}  → HTTP ${HTTP_CODE} (redirect)" ;;
            4??) warn "${URL_STR}  → HTTP ${HTTP_CODE} (client error, но сервер отвечает)" ;;
            502|503|504) fail "${URL_STR}  → HTTP ${HTTP_CODE} (backend недоступен)" ;;
            000) fail "${URL_STR}  → нет ответа (timeout/TLS/DNS)" ;;
            *)   warn "${URL_STR}  → HTTP ${HTTP_CODE}" ;;
        esac
    done
fi

# ---------------------------------------------------------------------------
section "Локальные порты"

declare -A PORT_LABELS=(
    [80]="Caddy HTTP"
    [443]="Caddy HTTPS"
    [8080]="FileBrowser"
    [8090]="FMD"
    [8443]="Crafty"
    [7777]="Terraria"
    [25565]="Minecraft"
    [5083]="WebDAV"
)

if command -v ss >/dev/null 2>&1; then
    LISTEN_PORTS="$(ss -lntp 2>/dev/null | grep -oE ':[0-9]+' | tr -d ':' | sort -un)"
    for PORT in 80 443 8080 8090 8443 7777 25565 5083; do
        LABEL="${PORT_LABELS[${PORT}]:-port}"
        if echo "${LISTEN_PORTS}" | grep -qx "${PORT}"; then
            ok  "${PORT}/tcp  — ${LABEL}"
        else
            warn "${PORT}/tcp  — ${LABEL}  (не слушается)"
        fi
    done
else
    warn "ss не найден, пропускаю проверку портов"
fi

# ---------------------------------------------------------------------------
section "Caddy сертификаты"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx caddy; then
    CERT_OUT="$(docker exec caddy caddy environ 2>/dev/null | grep -i 'acme\|cert' || true)"
    DATA_DIR="${STACK_DIR}/caddy/data/caddy/certificates"
    if [[ -d "${DATA_DIR}" ]]; then
        CERT_COUNT="$(find "${DATA_DIR}" -name '*.crt' 2>/dev/null | wc -l)"
        ok "Сертификатов в ${DATA_DIR}: ${CERT_COUNT} шт."
        find "${DATA_DIR}" -name '*.crt' 2>/dev/null | while read -r CRT; do
            DOMAIN_NAME="$(basename "$(dirname "${CRT}")")" 
            EXPIRY="$(openssl x509 -enddate -noout -in "${CRT}" 2>/dev/null | cut -d= -f2 || echo '?')"
            echo    "    ${DOMAIN_NAME}  → до ${EXPIRY}"
        done
    else
        warn "Директория сертификатов не найдена: ${DATA_DIR}"
    fi
else
    warn "Контейнер caddy не запущен — пропускаю проверку сертификатов"
fi

# ---------------------------------------------------------------------------
echo
echo -e "${BOLD}Подсказка:${NC} логи сервиса —"
echo    "  docker logs --tail=100 <name>    (caddy | filebrowser | findmydevice | crafty | terraria)"
echo
