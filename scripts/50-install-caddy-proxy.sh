#!/usr/bin/env bash
# 50-install-caddy-proxy.sh — Caddy reverse proxy с автоматическим HTTPS (Let's Encrypt)
# для FileBrowser и FindMyDevice. Caddy слушает 80/443 на хосте, проксирует во
# внутреннюю docker-сеть к контейнерам filebrowser:80 и findmydevice:8080.
set -euo pipefail

STACK_DIR="/opt/stack"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
CADDY_DIR="${STACK_DIR}/caddy"
USER_NAME="$(id -un)"

prompt_default() {
    local msg="$1" def="$2" var="$3" ans
    read -r -p "${msg} [${def}]: " ans || true
    printf -v "${var}" '%s' "${ans:-$def}"
}

prompt_default "Домен для FindMyDevice" "fmd.server34.netcraze.club" FMD_DOMAIN
prompt_default "Домен для FileBrowser"  "files.server34.netcraze.club" FILES_DOMAIN

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "ОШИБКА: ${COMPOSE_FILE} не найден. Сначала установите filebrowser и findmydevice." >&2
    exit 1
fi

echo "==> Создаю каталоги Caddy..."
sudo mkdir -p "${CADDY_DIR}/data" "${CADDY_DIR}/config"
sudo chown -R "${USER_NAME}:${USER_NAME}" "${CADDY_DIR}"

echo "==> Бэкаплю compose-файл..."
cp -a "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

echo "==> Пишу Caddyfile..."
cat >"${CADDY_DIR}/Caddyfile" <<EOF
${FMD_DOMAIN} {
    encode gzip
    reverse_proxy findmydevice:8080
}

${FILES_DOMAIN} {
    encode gzip
    reverse_proxy filebrowser:80
}
EOF

if grep -qE '^[[:space:]]+caddy:[[:space:]]*$' "${COMPOSE_FILE}"; then
    echo "==> Сервис caddy уже описан — пропускаю добавление."
else
    echo "==> Добавляю сервис caddy в ${COMPOSE_FILE}..."
    cat >>"${COMPOSE_FILE}" <<'EOF'

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    depends_on:
      - findmydevice
      - filebrowser
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy/data:/data
      - ./caddy/config:/config
EOF
fi

echo "==> docker compose config (валидация)..."
( cd "${STACK_DIR}" && docker compose config >/dev/null )

echo "==> docker compose pull caddy..."
( cd "${STACK_DIR}" && docker compose pull caddy )

echo "==> docker compose up -d caddy..."
( cd "${STACK_DIR}" && docker compose up -d caddy )

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qi 'Status: active'; then
    echo "==> UFW активен — открываю 80/tcp и 443/tcp..."
    sudo ufw allow 80/tcp  || true
    sudo ufw allow 443/tcp || true
fi

cat <<EOF

================================================================================
Caddy reverse proxy запущен.

Публичные URL:
  https://${FMD_DOMAIN}    -> findmydevice:8080
  https://${FILES_DOMAIN}  -> filebrowser:80

Дальнейшие шаги:
  1. Убедитесь, что DNS A/CNAME записи для поддоменов указывают на ваш домашний
     внешний IP (или на основной домен, который туда указывает):
       nslookup ${FMD_DOMAIN}
       nslookup ${FILES_DOMAIN}
  2. На роутере Keenetic пробросьте порты 80/tcp и 443/tcp на этот сервер
     (Minecraft 25565, Terraria 7777, Crafty 8443 — оставьте как есть).
  3. Откройте https://${FMD_DOMAIN} и https://${FILES_DOMAIN} в браузере.
     Caddy сам выпустит TLS-сертификаты Let's Encrypt при первом обращении.
  4. Логи Caddy:  docker logs -f caddy

Подсказка: ошибка ERR_SSL_PROTOCOL_ERROR обычно значит, что вы стучитесь по
HTTPS в backend без TLS или не на тот порт. Caddy сам делает TLS наружу,
а внутрь ходит по plain HTTP — это нормально.

После того как всё заработает через Caddy, на роутере можно (и нужно) убрать
прямые WAN-форварды на 8080 (FileBrowser) и 8090 (FMD) — они больше не нужны.
================================================================================
EOF
