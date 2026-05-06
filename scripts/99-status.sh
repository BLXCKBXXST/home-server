#!/usr/bin/env bash
# 99-status.sh — интерактивное TUI-меню для домашнего стека.
# Без внешних зависимостей (dialog/whiptail не нужны).
# Запуск: bash 99-status.sh  ——  или bash 99-status.sh --status для неинтерактивного режима.
set -uo pipefail

STACK_DIR="/opt/stack"
CADDYFILE="${STACK_DIR}/caddy/Caddyfile"
SVCS=(caddy filebrowser findmydevice crafty terraria)

# Цвета
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m';  BOLD='\033[1m';  NC='\033[0m'

ok()      { echo -e "  ${GREEN}[✔]${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}[⚠]${NC}  $*"; }
fail()    { echo -e "  ${RED}[✘]${NC}  $*"; }
section() { echo; echo -e "${BOLD}${CYAN}══ $* ══${NC}"; }
hdr()     { echo -e "${BOLD}${BLUE}$*${NC}"; }

pause() { echo; read -r -p $'  \033[1m[Enter] вернуться в меню...\033[0m' _; }

# ---------------------------------------------------------------------------
# Блок статуса
# ---------------------------------------------------------------------------

show_status() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │        Home Server Status                │"
    echo "  └──────────────────────────────────────────────────┘"
    echo -e "${NC}"

    section "Сервер"
    echo    "  Хост:   $(hostname 2>/dev/null)  |  $(uptime -p 2>/dev/null || uptime)"
    echo    "  Load:   $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
    if [[ -f /proc/meminfo ]]; then
        MT=$(awk '/MemTotal/{print $2}'     /proc/meminfo)
        MA=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
        MU=$(( (MT-MA)/1024 )); MTM=$(( MT/1024 ))
        echo "  RAM:    ${MU} MB / ${MTM} MB ($(( (MT-MA)*100/MT ))%)"
    fi
    if command -v df >/dev/null 2>&1; then
        read -r _ DT DU _ DP _ < <(df -h "${STACK_DIR}" 2>/dev/null | tail -1)
        echo    "  Disk:   ${DU} / ${DT} (${DP})  — ${STACK_DIR}"
    fi

    section "Сеть"
    LAN="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo    "  LAN IP: ${LAN:-?}"
    if command -v curl >/dev/null 2>&1; then
        WAN="$(curl -4fsS --max-time 5 https://ifconfig.me 2>/dev/null || echo '?')"
        echo "  WAN IP: ${WAN}"
    fi

    section "Контейнеры Docker"
    printf "  ${BOLD}%-18s %-12s %-10s %s${NC}\n" "NAME" "STATUS" "HEALTH" "PORTS"
    echo   "  $(printf '%0.s-' {1..70})"
    for SVC in "${SVCS[@]}"; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${SVC}"; then
            ST="$(docker inspect -f '{{.State.Status}}' "${SVC}" 2>/dev/null || echo '?')"
            HL="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "${SVC}" 2>/dev/null || echo '-')"
            PT="$(docker inspect -f '{{range $p,$v := .NetworkSettings.Ports}}{{$p}}->{{(index $v 0).HostPort}} {{end}}' "${SVC}" 2>/dev/null | tr -s ' ' | sed 's/ $//' || echo '')"
            case "${ST}" in
                running)            C="${GREEN}"  ;;
                restarting|exited)  C="${RED}"    ;;
                *)                  C="${YELLOW}" ;;
            esac
            printf "  %-18s ${C}%-12s${NC} %-10s %s\n" "${SVC}" "${ST}" "${HL}" "${PT}"
        else
            printf "  %-18s ${YELLOW}%-12s${NC}\n" "${SVC}" "not found"
        fi
    done

    section "HTTPS URL (Caddy)"
    CADDY_DOMAINS=()
    if [[ -f "${CADDYFILE}" ]]; then
        while IFS= read -r line; do
            if [[ "${line}" =~ ^([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})[[:space:]]*\{ ]]; then
                CADDY_DOMAINS+=("${BASH_REMATCH[1]}")
            fi
        done < "${CADDYFILE}"
    fi
    for D in fmd.server34.netcraze.club files.server34.netcraze.club; do
        [[ " ${CADDY_DOMAINS[*]:-} " == *" ${D} "* ]] || CADDY_DOMAINS+=("${D}")
    done
    if command -v curl >/dev/null 2>&1; then
        for D in "${CADDY_DOMAINS[@]:-}"; do
            [[ -z "${D:-}" ]] && continue
            CODE="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 8 "https://${D}" 2>/dev/null || echo '000')"
            case "${CODE}" in
                2??)          ok   "https://${D}  → ${CODE}" ;;
                3??)          ok   "https://${D}  → ${CODE} (redirect)" ;;
                4??)          warn "https://${D}  → ${CODE} (auth/not found, сервер отвечает)" ;;
                502|503|504)  fail "https://${D}  → ${CODE} (backend недоступен)" ;;
                000)          fail "https://${D}  → нет ответа" ;;
                *)            warn "https://${D}  → ${CODE}" ;;
            esac
        done
    else
        warn "curl не установлен"
    fi

    section "Локальные порты"
    if command -v ss >/dev/null 2>&1; then
        LP="$(ss -lntp 2>/dev/null | grep -oE ':[0-9]+' | tr -d ':' | sort -un)"
        declare -A PL=([80]="Caddy HTTP" [443]="Caddy HTTPS" [8080]="FileBrowser" [8090]="FMD" [8443]="Crafty" [7777]="Terraria" [25565]="Minecraft" [5083]="WebDAV")
        for P in 80 443 8080 8090 8443 7777 25565 5083; do
            if echo "${LP}" | grep -qx "${P}"; then ok  "${P}/tcp — ${PL[${P}]}"
            else                                    warn "${P}/tcp — ${PL[${P}]} (не слушается)"
            fi
        done
    fi

    section "Caddy сертификаты"
    CD="${STACK_DIR}/caddy/data/caddy/certificates"
    if [[ -d "${CD}" ]]; then
        CNT="$(find "${CD}" -name '*.crt' 2>/dev/null | wc -l)"
        ok "${CNT} сертификатов:"
        find "${CD}" -name '*.crt' 2>/dev/null | while read -r CRT; do
            DN="$(basename "$(dirname "${CRT}")")" 
            EX="$(openssl x509 -enddate -noout -in "${CRT}" 2>/dev/null | cut -d= -f2 || echo '?')"
            echo "    ${DN}  → до ${EX}"
        done
    else
        warn "Директория ${CD} не найдена"
    fi
    echo
}

# ---------------------------------------------------------------------------
# Обновление
# ---------------------------------------------------------------------------

menu_update() {
    clear; hdr "  Обновление образов Docker"
    echo
    echo "  Выбери сервис:"
    echo
    local i=1
    local MENU_SVCS=("${SVCS[@]}" "[все сразу]")
    for S in "${MENU_SVCS[@]}"; do
        printf "    ${BOLD}%d${NC}) %s\n" "${i}" "${S}"; (( i++ ))
    done
    echo "    0) Назад"; echo
    read -r -p "  Выбор: " CH
    [[ "${CH}" == "0" || -z "${CH:-}" ]] && return
    local IDX=$(( CH - 1 ))
    [[ "${IDX}" -lt 0 || "${IDX}" -ge "${#MENU_SVCS[@]}" ]] && { echo "Нет такого пункта"; pause; return; }
    local TARGET="${MENU_SVCS[${IDX}]}"
    echo
    if [[ "${TARGET}" == *"все"* ]]; then
        echo "  ==> docker compose pull && up -d..."
        ( cd "${STACK_DIR}" && docker compose pull && docker compose up -d )
    else
        echo "  ==> docker compose pull ${TARGET} && up -d ${TARGET}..."
        ( cd "${STACK_DIR}" && docker compose pull "${TARGET}" && docker compose up -d "${TARGET}" )
    fi
    pause
}

# ---------------------------------------------------------------------------
# Перезапуск
# ---------------------------------------------------------------------------

menu_restart() {
    clear; hdr "  Перезапуск контейнера"
    echo
    local i=1
    for S in "${SVCS[@]}"; do
        printf "    ${BOLD}%d${NC}) %s\n" "${i}" "${S}"; (( i++ ))
    done
    echo "    0) Назад"; echo
    read -r -p "  Выбор: " CH
    [[ "${CH}" == "0" || -z "${CH:-}" ]] && return
    local IDX=$(( CH - 1 ))
    [[ "${IDX}" -lt 0 || "${IDX}" -ge "${#SVCS[@]}" ]] && { echo "Нет такого пункта"; pause; return; }
    echo
    echo "  ==> docker compose restart ${SVCS[${IDX}]}..."
    ( cd "${STACK_DIR}" && docker compose restart "${SVCS[${IDX}]}" )
    pause
}

# ---------------------------------------------------------------------------
# Логи
# ---------------------------------------------------------------------------

menu_logs() {
    clear; hdr "  Логи контейнера"
    echo
    local i=1
    for S in "${SVCS[@]}"; do
        printf "    ${BOLD}%d${NC}) %s\n" "${i}" "${S}"; (( i++ ))
    done
    echo "    0) Назад"; echo
    read -r -p "  Выбор: " CH
    [[ "${CH}" == "0" || -z "${CH:-}" ]] && return
    local IDX=$(( CH - 1 ))
    [[ "${IDX}" -lt 0 || "${IDX}" -ge "${#SVCS[@]}" ]] && { echo "Нет такого пункта"; pause; return; }
    echo
    read -r -p "  Количество строк [100]: " LINES
    LINES="${LINES:-100}"
    echo "  (Ctrl+C чтобы остановить)"; echo
    docker logs --tail="${LINES}" -f "${SVCS[${IDX}]}" 2>&1 || true
    pause
}

# ---------------------------------------------------------------------------
# Подсказки
# ---------------------------------------------------------------------------

menu_tips() {
    clear; hdr "  Полезные команды"
    cat <<'TIPS'

  ── Docker ────────────────────────────────────────────
  cd /opt/stack && docker compose ps
  docker compose up -d <name>
  docker compose stop <name>
  docker compose restart <name>
  docker compose pull <name> && docker compose up -d <name>
  docker compose logs -f <name>
  docker exec -it <name> sh
  docker system prune -f

  ── Caddy ────────────────────────────────────────────
  cat /opt/stack/caddy/Caddyfile
  docker exec caddy caddy validate --config /etc/caddy/Caddyfile
  docker exec caddy caddy reload  --config /etc/caddy/Caddyfile

  ── SSH / UFW ──────────────────────────────────────
  sudo systemctl status ssh
  sudo ufw status numbered
  sudo ufw allow <port>/tcp
  sudo ufw delete <N>

  ── Minecraft Forge 1.20.1 ───────────────────────
  Java: /usr/lib/jvm/java-17-openjdk-amd64/bin/java
  (в настройках сервера в Crafty)

  ── ADB базовое ───────────────────────────────────
  adb devices -l                         # список устройств
  adb shell                              # shell на устройстве
  adb reboot                             # перезагрузка
  adb tcpip 5555                         # перевести adb в TCP на порту 5555
  adb connect 192.168.1.10:5555          # подключиться по сети (замени IP)
  adb install app.apk                    # установка APK
  adb logcat                             # поток логов

  ── FMD Android ────────────────────────────────
  # Базовые разрешения (через ADB, однократно при подключенном телефоне)
  adb shell pm grant de.nulide.findmydevice android.permission.READ_PHONE_STATE
  adb shell pm grant de.nulide.findmydevice android.permission.ACCESS_FINE_LOCATION
  adb shell pm grant de.nulide.findmydevice android.permission.ACCESS_BACKGROUND_LOCATION
  adb shell pm grant de.nulide.findmydevice android.permission.READ_CONTACTS
  adb shell pm grant de.nulide.findmydevice android.permission.SEND_SMS
  adb shell pm grant de.nulide.findmydevice android.permission.RECEIVE_SMS

  # Для блокировки экрана (режим пропавшего устройства)
  adb shell pm grant de.nulide.findmydevice android.permission.WRITE_SECURE_SETTINGS

  # Для автозапуска после перезагрузки
  adb shell pm grant de.nulide.findmydevice android.permission.RECEIVE_BOOT_COMPLETED
TIPS
    pause
}

# ---------------------------------------------------------------------------
# Очистка
# ---------------------------------------------------------------------------

menu_prune() {
    clear; hdr "  Очистка Docker"
    echo
    echo "  Удаляет неиспользуемые образы/контейнеры/сети. Volumes НЕ трогает."
    read -r -p "  Продолжить? (y/N): " CONF
    if [[ "${CONF,,}" == "y" ]]; then
        docker system prune -f && ok "Готово."
    else
        echo "  Отмена."
    fi
    pause
}

# ---------------------------------------------------------------------------
# Главное меню
# ---------------------------------------------------------------------------

main_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}"
        echo "  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "  ┃    🐺  Home Server Manager                 ┃"
        echo "  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
        echo -e "${NC}"
        echo -e "    ${BOLD}1${NC}) 📊  Полный статус стека"
        echo -e "    ${BOLD}2${NC}) ⬇️   Обновить образ (docker pull)"
        echo -e "    ${BOLD}3${NC}) 🔄  Перезапустить контейнер"
        echo -e "    ${BOLD}4${NC}) 📜  Логи контейнера"
        echo -e "    ${BOLD}5${NC}) 🧹  Очистить неиспользуемые образы Docker"
        echo -e "    ${BOLD}6${NC}) 💡  Полезные команды / подсказки"
        echo -e "    ${BOLD}0${NC}) ❌  Выход"
        echo
        read -r -p "  Выбор: " OPT
        case "${OPT}" in
            1) show_status; pause ;;
            2) menu_update  ;;
            3) menu_restart ;;
            4) menu_logs    ;;
            5) menu_prune   ;;
            6) menu_tips    ;;
            0) echo; exit 0 ;;
            *) ;;
        esac
    done
}

# Неинтерактивный режим: bash 99-status.sh --status
if [[ "${1:-}" == "--status" || "${1:-}" == "-s" ]]; then
    show_status; exit 0
fi

main_menu
