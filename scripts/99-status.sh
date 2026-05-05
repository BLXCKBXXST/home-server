#!/usr/bin/env bash
# 99-status.sh — быстрый осмотр стека в /opt/stack.
set -euo pipefail

STACK_DIR="/opt/stack"

echo "==> hostnamectl:"
hostnamectl || true
echo
echo "==> Сетевые адреса:"
ip -br a || true
echo
echo "==> Docker:"
docker --version || true
docker compose version || true
echo
echo "==> Контейнеры стека (${STACK_DIR}):"
if [[ -f "${STACK_DIR}/docker-compose.yml" ]]; then
    ( cd "${STACK_DIR}" && docker compose ps ) || true
else
    echo "  ${STACK_DIR}/docker-compose.yml не найден."
fi
echo
echo "==> Все запущенные контейнеры:"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
echo
echo "Подсказка: посмотреть последние логи сервиса —"
echo "  docker logs --tail=100 <name>    (например: crafty, terraria, filebrowser, findmydevice)"
