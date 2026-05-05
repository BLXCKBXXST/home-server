#!/usr/bin/env bash
# 03-check-docker.sh — диагностика: пользователь, сеть, ssh, docker.
set -euo pipefail

echo "==> Пользователь и группы:"
whoami
id

echo "==> hostnamectl:"
hostnamectl || true

echo "==> Сетевые интерфейсы:"
ip -br a || true

echo "==> Маршруты:"
ip route || true

echo "==> Пинг 1.1.1.1:"
ping -c 2 -W 2 1.1.1.1 || true

echo "==> Пинг deb.debian.org:"
ping -c 2 -W 2 deb.debian.org || true

echo "==> Статус ssh:"
systemctl status ssh --no-pager || true

echo "==> Статус docker:"
systemctl status docker --no-pager || true

echo "==> Версии Docker / Compose:"
docker --version || true
docker compose version || true

echo "==> Пробую docker run --rm hello-world..."
if docker run --rm hello-world; then
    echo "OK: docker работает без sudo."
else
    echo "Не удалось без sudo. Пробую через sudo..."
    sudo docker run --rm hello-world || true
fi
