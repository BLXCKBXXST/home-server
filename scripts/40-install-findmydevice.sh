#!/usr/bin/env bash
# 40-install-findmydevice.sh — FindMyDevice Server (Nulide / fmd-server) v0.5.0.
# https://gitlab.com/Nulide/findmydeviceserver
# Внутри контейнера сервис слушает HTTP 8080. На хосте 8080 уже занят FileBrowser,
# поэтому по умолчанию пробрасываем 8090:8080 (можно переопределить).
set -euo pipefail

STACK_DIR="/opt/stack"
FMD_DIR="${STACK_DIR}/findmydevice"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
USER_NAME="$(id -un)"

prompt_default() {
    local msg="$1" def="$2" var="$3" ans
    read -r -p "${msg} [${def}]: " ans || true
    printf -v "${var}" '%s' "${ans:-$def}"
}

prompt_default "Хостовый порт для FMD (FMD_HOST_PORT)" "8090" FMD_HOST_PORT

echo "==> Создаю каталоги FMD..."
sudo mkdir -p "${FMD_DIR}/data"
sudo chown -R "${USER_NAME}:${USER_NAME}" "${STACK_DIR}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "==> Создаю ${COMPOSE_FILE}..."
    cat >"${COMPOSE_FILE}" <<'EOF'
services:
EOF
fi

if grep -qE '^[[:space:]]+findmydevice:[[:space:]]*$' "${COMPOSE_FILE}"; then
    echo "==> Сервис findmydevice уже описан — пропускаю добавление."
else
    echo "==> Добавляю сервис findmydevice в ${COMPOSE_FILE}..."
    cat >>"${COMPOSE_FILE}" <<'EOF'

  findmydevice:
    # Сборка из исходников апстрима, тег v0.5.0
    build: https://gitlab.com/Nulide/findmydeviceserver.git#v0.5.0
    container_name: findmydevice
    restart: unless-stopped
    environment:
      - TZ=Asia/Krasnoyarsk
    ports:
      - "${FMD_HOST_PORT}:8080"
    volumes:
      - ./findmydevice/data:/fmd/objectbox/
      # Чтобы подложить свой config, скопируйте config.example.yml из upstream-репо в
      # ./findmydevice/config.yml и раскомментируйте строку ниже:
      # - ./findmydevice/config.yml:/fmd/config.yml:ro
EOF
fi

echo "==> Записываю FMD_HOST_PORT в ${STACK_DIR}/.env..."
ENV_FILE="${STACK_DIR}/.env"
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
if grep -qE '^FMD_HOST_PORT=' "${ENV_FILE}"; then
    sed -i "s|^FMD_HOST_PORT=.*|FMD_HOST_PORT=${FMD_HOST_PORT}|" "${ENV_FILE}"
else
    printf 'FMD_HOST_PORT=%s\n' "${FMD_HOST_PORT}" >>"${ENV_FILE}"
fi

echo "==> docker compose config (валидация)..."
( cd "${STACK_DIR}" && docker compose config >/dev/null )

echo "==> docker compose build findmydevice (это сборка из git, может занять несколько минут)..."
( cd "${STACK_DIR}" && docker compose build findmydevice )

echo "==> docker compose up -d findmydevice..."
( cd "${STACK_DIR}" && docker compose up -d findmydevice )

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qi 'Status: active'; then
    echo "==> UFW активен — открываю ${FMD_HOST_PORT}/tcp..."
    sudo ufw allow "${FMD_HOST_PORT}/tcp" || true
fi

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
LAN_IP="${LAN_IP:-LAN_IP}"

echo
echo "FindMyDevice Server запущен: http://${LAN_IP}:${FMD_HOST_PORT}"
echo "В Android-приложении FMD укажите Server URL:"
echo "  - локально:        http://${LAN_IP}:${FMD_HOST_PORT}"
echo "  - снаружи дома:    https://your.domain.example  (через реверс-прокси с TLS)"
echo
echo "ВНИМАНИЕ: внутри контейнера сервис отдаёт HTTP. Для публичного доступа"
echo "ОБЯЗАТЕЛЬНО ставьте реверс-прокси (Caddy/Nginx) с HTTPS."
