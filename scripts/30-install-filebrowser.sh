#!/usr/bin/env bash
# 30-install-filebrowser.sh — FileBrowser Quantum (gtstef/filebrowser:stable) на :8080.
set -euo pipefail

STACK_DIR="/opt/stack"
FB_DIR="${STACK_DIR}/filebrowser"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
USER_NAME="$(id -un)"

echo "==> Запрашиваю пароль администратора FileBrowser (минимум 12 символов)..."
FB_PASS=""
while :; do
    read -r -s -p "Пароль admin: " FB_PASS; echo
    read -r -s -p "Повторите:    " FB_PASS2; echo
    if [[ "${FB_PASS}" != "${FB_PASS2}" ]]; then
        echo "Пароли не совпадают."
        continue
    fi
    if [[ "${#FB_PASS}" -lt 12 ]]; then
        echo "Слишком короткий, нужно минимум 12 символов."
        continue
    fi
    break
done

echo "==> Создаю каталоги..."
sudo mkdir -p \
    "${FB_DIR}/data" \
    "${STACK_DIR}/crafty/import" \
    "${STACK_DIR}/crafty/servers" \
    "${STACK_DIR}/terraria/mods-inbox" \
    "${STACK_DIR}/terraria/data"
sudo chown -R "${USER_NAME}:${USER_NAME}" "${STACK_DIR}"

echo "==> Пишу config.yml для FileBrowser Quantum..."
cat >"${FB_DIR}/data/config.yml" <<'EOF'
server:
  port: 80
  database: /home/filebrowser/data/database.db
  cacheDir: /home/filebrowser/data/tmp
  sources:
    - path: /srv/minecraft-import
      name: Minecraft Import
      config:
        defaultEnabled: true
        defaultUserScope: /
    - path: /srv/minecraft-servers
      name: Minecraft Servers
      config:
        defaultEnabled: true
        defaultUserScope: /
    - path: /srv/terraria-mods-inbox
      name: Terraria Mods Inbox
      config:
        defaultEnabled: true
        defaultUserScope: /
    - path: /srv/terraria-data
      name: Terraria Data
      config:
        defaultEnabled: true
        defaultUserScope: /

auth:
  adminUsername: admin
  methods:
    password:
      enabled: true
      minLength: 12
      signup: false
      enforcedOtp: false

frontend:
  name: Home Server Files
EOF

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "==> Создаю ${COMPOSE_FILE}..."
    cat >"${COMPOSE_FILE}" <<'EOF'
services:
EOF
fi

if grep -qE '^[[:space:]]+filebrowser:[[:space:]]*$' "${COMPOSE_FILE}"; then
    echo "==> Сервис filebrowser уже описан — пропускаю добавление."
else
    echo "==> Добавляю сервис filebrowser в ${COMPOSE_FILE}..."
    cat >>"${COMPOSE_FILE}" <<'EOF'

  filebrowser:
    image: gtstef/filebrowser:stable
    container_name: filebrowser
    restart: unless-stopped
    user: "1000:1000"
    environment:
      - TZ=Asia/Krasnoyarsk
      - FILEBROWSER_ADMIN_PASSWORD=${FILEBROWSER_ADMIN_PASSWORD}
    ports:
      # ВНИМАНИЕ: HTTP, не HTTPS. Не пробрасывайте 8080 наружу без 2FA/реверс-прокси с TLS.
      - "8080:80"
    volumes:
      - ./filebrowser/data:/home/filebrowser/data
      - ./crafty/import:/srv/minecraft-import
      - ./crafty/servers:/srv/minecraft-servers
      - ./terraria/mods-inbox:/srv/terraria-mods-inbox
      - ./terraria/data:/srv/terraria-data
EOF
fi

echo "==> Записываю пароль в ${STACK_DIR}/.env..."
ENV_FILE="${STACK_DIR}/.env"
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
if grep -qE '^FILEBROWSER_ADMIN_PASSWORD=' "${ENV_FILE}"; then
    sed -i "s|^FILEBROWSER_ADMIN_PASSWORD=.*|FILEBROWSER_ADMIN_PASSWORD=${FB_PASS}|" "${ENV_FILE}"
else
    printf 'FILEBROWSER_ADMIN_PASSWORD=%s\n' "${FB_PASS}" >>"${ENV_FILE}"
fi

echo "==> docker compose config (валидация)..."
( cd "${STACK_DIR}" && docker compose config >/dev/null )

echo "==> docker compose pull filebrowser..."
( cd "${STACK_DIR}" && docker compose pull filebrowser )

echo "==> docker compose up -d filebrowser..."
( cd "${STACK_DIR}" && docker compose up -d filebrowser )

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qi 'Status: active'; then
    echo "==> UFW активен — открываю 8080/tcp в локальной сети..."
    sudo ufw allow 8080/tcp || true
fi

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
LAN_IP="${LAN_IP:-LAN_IP}"

echo
echo "FileBrowser запущен: http://${LAN_IP}:8080  (логин: admin)"
echo "ВНИМАНИЕ: это HTTP, без шифрования. Не открывайте порт 8080 в интернет"
echo "пока не включите 2FA и/или не поставите реверс-прокси с TLS."
