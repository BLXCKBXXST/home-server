#!/usr/bin/env bash
# 20-install-terraria.sh — tModLoader 1.4 server (jacobsmile/tmodloader1.4) в /opt/stack.
set -euo pipefail

STACK_DIR="/opt/stack"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
USER_NAME="$(id -un)"

prompt_default() {
    # $1 = сообщение, $2 = значение по умолчанию, $3 = имя переменной
    local msg="$1" def="$2" var="$3" ans
    read -r -p "${msg} [${def}]: " ans || true
    printf -v "${var}" '%s' "${ans:-$def}"
}

prompt_secret_nonempty() {
    # $1 = сообщение, $2 = имя переменной (не отображается, не пустое)
    local msg="$1" var="$2" ans=""
    while [[ -z "${ans}" ]]; do
        read -r -s -p "${msg}: " ans || true
        echo
        if [[ -z "${ans}" ]]; then
            echo "Пароль не может быть пустым."
        fi
    done
    printf -v "${var}" '%s' "${ans}"
}

echo "==> Параметры мира Terraria:"
prompt_default "Имя мира (TMOD_WORLDNAME)" "main" TMOD_WORLDNAME
prompt_default "Макс. игроков (TMOD_MAXPLAYERS)" "8" TMOD_MAXPLAYERS
prompt_default "Размер мира 1=small/2=medium/3=large (TMOD_WORLDSIZE)" "2" TMOD_WORLDSIZE
prompt_default "Сложность 0=classic/1=expert/2=master/3=journey (TMOD_DIFFICULTY)" "1" TMOD_DIFFICULTY
prompt_default "MOTD (TMOD_MOTD)" "Welcome to home Terraria server" TMOD_MOTD
prompt_default "Сообщение при выключении (TMOD_SHUTDOWN_MESSAGE)" "Server is shutting down" TMOD_SHUTDOWN_MESSAGE
prompt_secret_nonempty "Пароль на сервер (TMOD_PASS, не пусто)" TMOD_PASS

echo "==> Создаю каталоги Terraria..."
sudo mkdir -p "${STACK_DIR}/terraria/data" \
              "${STACK_DIR}/terraria/backups" \
              "${STACK_DIR}/terraria/mods-inbox"
sudo chown -R "${USER_NAME}:${USER_NAME}" "${STACK_DIR}/terraria"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "==> Создаю ${COMPOSE_FILE}..."
    cat >"${COMPOSE_FILE}" <<'EOF'
services:
EOF
fi

if grep -qE '^[[:space:]]+terraria:[[:space:]]*$' "${COMPOSE_FILE}"; then
    echo "==> Сервис terraria уже описан в ${COMPOSE_FILE} — обновлю только переменные через .env."
else
    echo "==> Добавляю сервис terraria в ${COMPOSE_FILE}..."
    cat >>"${COMPOSE_FILE}" <<'EOF'

  terraria:
    image: jacobsmile/tmodloader1.4:latest
    container_name: terraria
    restart: unless-stopped
    environment:
      - TZ=Asia/Krasnoyarsk
      - TMOD_SHUTDOWN_MESSAGE=${TMOD_SHUTDOWN_MESSAGE}
      - TMOD_AUTOSAVE_INTERVAL=10
      - TMOD_MOTD=${TMOD_MOTD}
      - TMOD_PASS=${TMOD_PASS}
      - TMOD_MAXPLAYERS=${TMOD_MAXPLAYERS}
      - TMOD_WORLDNAME=${TMOD_WORLDNAME}
      - TMOD_WORLDSIZE=${TMOD_WORLDSIZE}
      - TMOD_DIFFICULTY=${TMOD_DIFFICULTY}
      - TMOD_SECURE=1
      - TMOD_PORT=7777
    ports:
      - "7777:7777/tcp"
    volumes:
      - ./terraria/data:/data
EOF
fi

echo "==> Записываю/обновляю ${STACK_DIR}/.env (только Terraria-переменные)..."
ENV_FILE="${STACK_DIR}/.env"
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"
update_env_var() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" "${ENV_FILE}"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "${ENV_FILE}"
    else
        printf '%s=%s\n' "${key}" "${val}" >>"${ENV_FILE}"
    fi
}
update_env_var TMOD_WORLDNAME "${TMOD_WORLDNAME}"
update_env_var TMOD_MAXPLAYERS "${TMOD_MAXPLAYERS}"
update_env_var TMOD_WORLDSIZE "${TMOD_WORLDSIZE}"
update_env_var TMOD_DIFFICULTY "${TMOD_DIFFICULTY}"
update_env_var TMOD_MOTD "${TMOD_MOTD}"
update_env_var TMOD_SHUTDOWN_MESSAGE "${TMOD_SHUTDOWN_MESSAGE}"
update_env_var TMOD_PASS "${TMOD_PASS}"

echo "==> docker compose config (валидация)..."
( cd "${STACK_DIR}" && docker compose config >/dev/null )

echo "==> docker compose pull terraria..."
( cd "${STACK_DIR}" && docker compose pull terraria )

echo "==> docker compose up -d terraria..."
( cd "${STACK_DIR}" && docker compose up -d terraria )

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -qi 'Status: active'; then
    echo "==> UFW активен — открываю 7777/tcp..."
    sudo ufw allow 7777/tcp || true
fi

LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
LAN_IP="${LAN_IP:-LAN_IP}"

echo
echo "Terraria-сервер запущен на ${LAN_IP}:7777 (TCP)."
echo "Логи:   docker logs --tail=100 terraria"
echo "Статус: docker ps --filter name=terraria"
