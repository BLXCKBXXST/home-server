#!/usr/bin/env bash
# 10-install-crafty.sh — Crafty Controller 4 (web-панель Minecraft) в /opt/stack.
set -euo pipefail

STACK_DIR="/opt/stack"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
USER_NAME="$(id -un)"

echo "==> Создаю каталоги Crafty..."
sudo mkdir -p "${STACK_DIR}/crafty/backups" \
              "${STACK_DIR}/crafty/logs" \
              "${STACK_DIR}/crafty/servers" \
              "${STACK_DIR}/crafty/config" \
              "${STACK_DIR}/crafty/import"
sudo chown -R "${USER_NAME}:${USER_NAME}" "${STACK_DIR}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "==> Создаю ${COMPOSE_FILE}..."
    cat >"${COMPOSE_FILE}" <<'EOF'
services:
EOF
fi

if grep -qE '^[[:space:]]+crafty:[[:space:]]*$' "${COMPOSE_FILE}"; then
    echo "==> Сервис crafty уже описан в ${COMPOSE_FILE} — пропускаю добавление."
else
    echo "==> Добавляю сервис crafty в ${COMPOSE_FILE}..."
    cat >>"${COMPOSE_FILE}" <<'EOF'

  crafty:
    image: registry.gitlab.com/crafty-controller/crafty-4:latest
    container_name: crafty
    restart: unless-stopped
    environment:
      - TZ=Asia/Krasnoyarsk
    ports:
      - "8443:8443"
      - "25565:25565"
      - "25566:25566"
      - "25567:25567"
    volumes:
      - ./crafty/backups:/crafty/backups
      - ./crafty/logs:/crafty/logs
      - ./crafty/servers:/crafty/servers
      - ./crafty/config:/crafty/app/config
      - ./crafty/import:/crafty/import
EOF
fi

echo "==> docker compose pull crafty..."
( cd "${STACK_DIR}" && docker compose pull crafty )

echo "==> docker compose up -d crafty..."
( cd "${STACK_DIR}" && docker compose up -d crafty )

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
LAN_IP="${LAN_IP:-LAN_IP}"

echo
echo "Crafty запущен. Веб-панель: https://${LAN_IP}:8443"
echo "Браузер предупредит о самоподписанном сертификате — это нормально."
echo
echo "Где взять дефолтные креды (admin / случайный пароль):"
echo "  cat ${STACK_DIR}/crafty/config/default-creds.txt"
echo "или внутри контейнера:"
echo "  docker exec crafty cat /crafty/app/config/default-creds.txt"
