#!/usr/bin/env bash
# 60-diagnose-caddy-fmd.sh — диагностика Caddy ↔ FindMyDevice / FileBrowser.
# НЕ выходит при первой ошибке: цель — собрать максимум информации за один прогон.
# Полный лог пишется в /tmp/caddy-fmd-diagnose-YYYYmmdd-HHMMSS.log — этот лог можно
# скопировать целиком и прислать.
#
# Переопределение через env:
#   STACK_DIR=/opt/stack \
#   FMD_DOMAIN=fmd.example.com \
#   FILES_DOMAIN=files.example.com \
#   FMD_HOST_PORT=8090 \
#       ./60-diagnose-caddy-fmd.sh

set -u

STACK_DIR="${STACK_DIR:-/opt/stack}"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
CADDY_FILE="${STACK_DIR}/caddy/Caddyfile"
FMD_DOMAIN="${FMD_DOMAIN:-fmd.server34.netcraze.club}"
FILES_DOMAIN="${FILES_DOMAIN:-files.server34.netcraze.club}"
FMD_HOST_PORT="${FMD_HOST_PORT:-8090}"
FILES_HOST_PORT="${FILES_HOST_PORT:-8080}"

TS="$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/caddy-fmd-diagnose-${TS}.log"

# Всё, что мы печатаем в stdout, дублируется в лог.
exec > >(tee -a "${LOG}") 2>&1

# ---- helpers ---------------------------------------------------------------

# флаги для эвристического диагноза
HTTPS_FMD_CODE=""
HTTPS_FILES_CODE=""
LOCAL_FMD_OK="?"
LOCAL_FILES_OK="?"
CADDY_TO_FMD_OK="?"
CADDY_TO_FMD_DETAIL=""
CADDY_TO_FILES_OK="?"
FMD_CONTAINER_STATUS=""
CADDY_CONTAINER_STATUS=""
CADDYFILE_HAS_FMD="?"
DNS_FMD_OK="?"
DNS_FILES_OK="?"

section() {
    echo
    echo "================================================================================"
    echo "== $*"
    echo "================================================================================"
}

run() {
    # run "label" cmd args...
    local label="$1"; shift
    echo
    echo "---- ${label}"
    echo "\$ $*"
    "$@" 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "(exit=${rc})"
    fi
    return 0
}

run_sh() {
    # run_sh "label" 'shell pipeline string'
    local label="$1"; shift
    echo
    echo "---- ${label}"
    echo "\$ $*"
    bash -c "$*" 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "(exit=${rc})"
    fi
    return 0
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---- A. Окружение ----------------------------------------------------------

section "A. Окружение"
run "date"      date
run "hostname"  hostname
run "whoami"    whoami
run "pwd"       pwd
echo
echo "STACK_DIR     = ${STACK_DIR}"
echo "FMD_DOMAIN    = ${FMD_DOMAIN}"
echo "FILES_DOMAIN  = ${FILES_DOMAIN}"
echo "FMD_HOST_PORT = ${FMD_HOST_PORT}"
echo "LOG           = ${LOG}"

if [[ -f "${COMPOSE_FILE}" ]]; then
    echo "OK: ${COMPOSE_FILE} существует."
else
    echo "ВНИМАНИЕ: ${COMPOSE_FILE} НЕ найден — это, скорее всего, корень всех проблем."
fi

if have docker; then
    run "docker --version"        docker --version
    run "docker compose version"  docker compose version
else
    echo "ВНИМАНИЕ: docker не установлен или не в PATH."
fi

if [[ -f "${COMPOSE_FILE}" ]] && have docker; then
    run_sh "docker compose ps"               "cd '${STACK_DIR}' && docker compose ps"
    run_sh "docker compose config --services" "cd '${STACK_DIR}' && docker compose config --services"
fi

# ---- B. DNS ---------------------------------------------------------------

section "B. DNS / резолвинг доменов"

for d in "${FMD_DOMAIN}" "${FILES_DOMAIN}"; do
    out="$(getent hosts "$d" 2>&1)"; rc=$?
    echo
    echo "---- getent hosts ${d}"
    echo "${out:-<пусто>}"
    if [[ $rc -eq 0 && -n "$out" ]]; then
        [[ "$d" == "${FMD_DOMAIN}"   ]] && DNS_FMD_OK="yes"
        [[ "$d" == "${FILES_DOMAIN}" ]] && DNS_FILES_OK="yes"
    else
        [[ "$d" == "${FMD_DOMAIN}"   ]] && DNS_FMD_OK="no"
        [[ "$d" == "${FILES_DOMAIN}" ]] && DNS_FILES_OK="no"
    fi
done

if have dig; then
    run "dig +short ${FMD_DOMAIN} A"   dig +short "${FMD_DOMAIN}"   A
    run "dig +short ${FILES_DOMAIN} A" dig +short "${FILES_DOMAIN}" A
else
    echo
    echo "(dig не установлен — поставьте 'sudo apt install dnsutils' если нужны NS-детали)"
fi

if have curl; then
    run "внешний IP (ifconfig.me)" curl -4fsS --max-time 5 https://ifconfig.me
    echo
fi

# ---- C. Порты / HTTP-проверки ---------------------------------------------

section "C. Порты и HTTP-проверки"

if have ss; then
    run_sh "ss -lntp | listen 80/443/${FILES_HOST_PORT}/${FMD_HOST_PORT}" \
        "ss -lntp 2>/dev/null | grep -E ':(80|443|${FILES_HOST_PORT}|${FMD_HOST_PORT})\\b' || echo '(нет совпадений)'"
else
    echo "(ss не установлен — пропускаю проверку listen-портов)"
fi

if have curl; then
    out="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${FILES_DOMAIN}" 2>&1)"
    echo
    echo "---- HTTPS https://${FILES_DOMAIN} -> код: ${out}"
    HTTPS_FILES_CODE="$out"
    run "curl -k -I --max-time 10 https://${FILES_DOMAIN}" curl -k -I --max-time 10 "https://${FILES_DOMAIN}"

    out="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${FMD_DOMAIN}" 2>&1)"
    echo
    echo "---- HTTPS https://${FMD_DOMAIN} -> код: ${out}"
    HTTPS_FMD_CODE="$out"
    run "curl -k -I --max-time 10 https://${FMD_DOMAIN}"   curl -k -I --max-time 10 "https://${FMD_DOMAIN}"

    # локальные прямые порты
    out="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:${FMD_HOST_PORT}" 2>&1)"
    echo
    echo "---- HTTP http://127.0.0.1:${FMD_HOST_PORT} -> код: ${out}"
    case "$out" in
        2*|3*|4*) LOCAL_FMD_OK="yes" ;;
        *)        LOCAL_FMD_OK="no"  ;;
    esac
    run "curl -I --max-time 10 http://127.0.0.1:${FMD_HOST_PORT}" curl -I --max-time 10 "http://127.0.0.1:${FMD_HOST_PORT}"

    out="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:${FILES_HOST_PORT}" 2>&1)"
    echo
    echo "---- HTTP http://127.0.0.1:${FILES_HOST_PORT} -> код: ${out} (порт может быть не проброшен — это не fatal)"
    case "$out" in
        2*|3*|4*) LOCAL_FILES_OK="yes" ;;
        *)        LOCAL_FILES_OK="no"  ;;
    esac
else
    echo "ВНИМАНИЕ: curl не установлен — пропускаю HTTP-проверки."
fi

# ---- D. Caddyfile ---------------------------------------------------------

section "D. Caddy конфигурация"

if [[ -f "${CADDY_FILE}" ]]; then
    echo "---- содержимое ${CADDY_FILE}:"
    # чувствительных данных в Caddyfile у нас не бывает, но на всякий случай маскируем email-строки
    sed -E 's/(email[[:space:]]+)[^[:space:]]+/\1***REDACTED***/I' "${CADDY_FILE}"

    if grep -qE "^${FMD_DOMAIN//./\\.}[[:space:]]*\\{" "${CADDY_FILE}" \
       || grep -qE "^[[:space:]]*${FMD_DOMAIN//./\\.}[[:space:]]*\\{" "${CADDY_FILE}"; then
        CADDYFILE_HAS_FMD="yes"
        echo
        echo "OK: блок для ${FMD_DOMAIN} в Caddyfile найден."
        if grep -qE 'reverse_proxy[[:space:]]+findmydevice:8080' "${CADDY_FILE}"; then
            echo "OK: reverse_proxy findmydevice:8080 присутствует."
        else
            echo "ВНИМАНИЕ: reverse_proxy для FMD есть, но не на findmydevice:8080 — проверьте имя сервиса."
            grep -nE 'reverse_proxy' "${CADDY_FILE}" || true
        fi
    else
        CADDYFILE_HAS_FMD="no"
        echo
        echo "ВНИМАНИЕ: блок для ${FMD_DOMAIN} в Caddyfile НЕ найден."
    fi
else
    echo "ВНИМАНИЕ: ${CADDY_FILE} не найден — скрипт 50-install-caddy-proxy.sh не отрабатывал?"
    CADDYFILE_HAS_FMD="no"
fi

if have docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx caddy; then
    run "docker exec caddy caddy validate" docker exec caddy caddy validate --config /etc/caddy/Caddyfile
fi

# ---- E. Контейнеры / docker-сети -----------------------------------------

section "E. Контейнеры и docker-сети"

if have docker; then
    for c in caddy findmydevice filebrowser; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
            status="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo '?')"
            health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$c" 2>/dev/null || echo '?')"
            echo "контейнер ${c}: status=${status} health=${health}"
            [[ "$c" == "findmydevice" ]] && FMD_CONTAINER_STATUS="$status"
            [[ "$c" == "caddy"        ]] && CADDY_CONTAINER_STATUS="$status"
        else
            echo "контейнер ${c}: НЕ существует"
            [[ "$c" == "findmydevice" ]] && FMD_CONTAINER_STATUS="missing"
            [[ "$c" == "caddy"        ]] && CADDY_CONTAINER_STATUS="missing"
        fi
    done

    run "docker network ls" docker network ls

    for c in caddy findmydevice filebrowser; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
            run "сети контейнера ${c}" \
                docker inspect "$c" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} (ip={{$v.IPAddress}}, aliases={{$v.Aliases}}){{println}}{{end}}'
        fi
    done

    # Проверка достижимости backend-ов изнутри Caddy
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx caddy; then
        echo
        echo "---- caddy -> findmydevice:8080 (wget из контейнера caddy)"
        out="$(docker exec caddy wget -S -O- --timeout=10 http://findmydevice:8080 2>&1 | head -120)"
        echo "$out"
        CADDY_TO_FMD_DETAIL="$out"
        if echo "$out" | grep -qE 'HTTP/[0-9.]+ [0-9]+'; then
            CADDY_TO_FMD_OK="yes"
        elif echo "$out" | grep -qiE 'bad address|could not resolve|no such host|name does not resolve|name or service not known'; then
            CADDY_TO_FMD_OK="dns"
        elif echo "$out" | grep -qiE 'connection refused|unable to connect'; then
            CADDY_TO_FMD_OK="refused"
        else
            CADDY_TO_FMD_OK="no"
        fi

        echo
        echo "---- caddy -> filebrowser:80 (wget из контейнера caddy)"
        out="$(docker exec caddy wget -S -O- --timeout=10 http://filebrowser:80 2>&1 | head -60)"
        echo "$out"
        if echo "$out" | grep -qE 'HTTP/[0-9.]+ [0-9]+'; then
            CADDY_TO_FILES_OK="yes"
        else
            CADDY_TO_FILES_OK="no"
        fi
    else
        echo "(контейнер caddy не запущен — пропускаю проверки backend-достижимости)"
    fi
fi

# ---- F. Логи --------------------------------------------------------------

section "F. Логи контейнеров"

if have docker; then
    for spec in "caddy:120" "findmydevice:160" "filebrowser:80"; do
        c="${spec%%:*}"; n="${spec##*:}"
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
            run_sh "docker logs --tail=${n} ${c}" "docker logs --tail=${n} ${c} 2>&1"
        else
            echo
            echo "---- docker logs ${c}: контейнер не существует"
        fi
    done
fi

# ---- G. Эвристика ---------------------------------------------------------

section "G. Итог и эвристический диагноз"

cat <<EOF
Сводка:
  HTTPS ${FMD_DOMAIN}            : ${HTTPS_FMD_CODE:-?}
  HTTPS ${FILES_DOMAIN}          : ${HTTPS_FILES_CODE:-?}
  локально 127.0.0.1:${FMD_HOST_PORT}      : ${LOCAL_FMD_OK}
  локально 127.0.0.1:${FILES_HOST_PORT}      : ${LOCAL_FILES_OK}
  caddy -> findmydevice:8080  : ${CADDY_TO_FMD_OK}
  caddy -> filebrowser:80     : ${CADDY_TO_FILES_OK}
  контейнер findmydevice      : ${FMD_CONTAINER_STATUS:-?}
  контейнер caddy             : ${CADDY_CONTAINER_STATUS:-?}
  Caddyfile содержит FMD блок : ${CADDYFILE_HAS_FMD}
  DNS ${FMD_DOMAIN}        : ${DNS_FMD_OK}
  DNS ${FILES_DOMAIN}      : ${DNS_FILES_OK}

Возможные причины (от наиболее вероятной к наименее):
EOF

# Эвристика
if [[ "${DNS_FMD_OK}" == "no" ]]; then
    echo "  • DNS для ${FMD_DOMAIN} не резолвится. Создайте A или CNAME запись на ваш внешний IP."
fi

if [[ "${CADDYFILE_HAS_FMD}" == "no" ]]; then
    echo "  • В Caddyfile нет блока для ${FMD_DOMAIN}. Запустите ./50-install-caddy-proxy.sh заново"
    echo "    и укажите домен ${FMD_DOMAIN}, либо отредактируйте ${CADDY_FILE} вручную."
fi

if [[ "${FMD_CONTAINER_STATUS}" == "missing" ]]; then
    echo "  • Контейнер findmydevice не существует. Запустите ./40-install-findmydevice.sh,"
    echo "    либо: cd ${STACK_DIR} && docker compose up -d findmydevice"
elif [[ -n "${FMD_CONTAINER_STATUS}" && "${FMD_CONTAINER_STATUS}" != "running" ]]; then
    echo "  • Контейнер findmydevice не в состоянии running (status=${FMD_CONTAINER_STATUS})."
    echo "    Смотрите блок логов findmydevice выше; типично — упала сборка или конфиг."
fi

if [[ "${CADDY_TO_FMD_OK}" == "dns" ]]; then
    echo "  • Caddy внутри контейнера НЕ резолвит имя 'findmydevice'. Это значит, что"
    echo "    findmydevice либо не существует, либо находится в другой docker-сети, либо"
    echo "    его имя сервиса в docker-compose.yml не 'findmydevice'."
    echo "    Проверьте 'docker compose config --services' выше — реальное имя сервиса"
    echo "    нужно использовать в Caddyfile (reverse_proxy <имя_сервиса>:8080)."
elif [[ "${CADDY_TO_FMD_OK}" == "refused" ]]; then
    echo "  • Caddy достучался до имени findmydevice, но порт 8080 отказывает в соединении."
    echo "    Скорее всего, FMD внутри контейнера не слушает 8080 или упал. Смотрите"
    echo "    логи findmydevice; проверьте, что в его контейнере приложение реально стартует"
    echo "    и слушает 0.0.0.0:8080 (не 127.0.0.1)."
elif [[ "${CADDY_TO_FMD_OK}" == "no" ]]; then
    echo "  • Caddy -> findmydevice:8080 не вернул валидного HTTP-ответа. Смотрите вывод"
    echo "    'caddy -> findmydevice:8080' выше — там точная причина."
fi

if [[ "${LOCAL_FMD_OK}" == "yes" && "${CADDY_TO_FMD_OK}" != "yes" ]]; then
    echo "  • Локально http://127.0.0.1:${FMD_HOST_PORT} работает, а caddy внутри сети не достучался —"
    echo "    значит, контейнеры caddy и findmydevice в РАЗНЫХ docker-сетях. Проверьте,"
    echo "    что оба сервиса описаны в одном ${COMPOSE_FILE} и используют одну сеть"
    echo "    (по умолчанию docker compose создаёт сеть проекта автоматически)."
fi

if [[ "${LOCAL_FMD_OK}" == "no" && "${FMD_CONTAINER_STATUS}" != "running" ]]; then
    echo "  • И локально, и через Caddy FMD недоступен, контейнер не running — это проблема"
    echo "    самого findmydevice (сборка/конфиг), а не реверс-прокси."
fi

case "${HTTPS_FMD_CODE}" in
    2??|3??)
        echo "  • HTTPS ${FMD_DOMAIN} вернул ${HTTPS_FMD_CODE} — Caddy уже работает."
        echo "    Если приложение FMD на телефоне всё равно пишет 'Ошибка: null', укажите"
        echo "    в нём Server URL РОВНО как 'https://${FMD_DOMAIN}' — без порта, без хвостового"
        echo "    '/' и без 'http://'."
        ;;
    502|503|504)
        echo "  • HTTPS ${FMD_DOMAIN} вернул ${HTTPS_FMD_CODE} — TLS работает, но backend (findmydevice)"
        echo "    Caddy не отвечает. См. выше блок 'caddy -> findmydevice:8080' и логи findmydevice."
        ;;
esac

echo
echo "Полный лог сохранён: ${LOG}"
echo "Перешлите его целиком, если потребуется помощь."
