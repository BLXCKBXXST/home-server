#!/usr/bin/env bash
# 02-install-docker.sh — установка Docker CE + compose-plugin на Debian 12 (bookworm).
set -euo pipefail

echo "==> [1/7] Удаляю старые пакеты Docker (если есть)..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y "$pkg" 2>/dev/null || true
done

echo "==> [2/7] Устанавливаю предзависимости..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg

echo "==> [3/7] Добавляю GPG-ключ Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "==> [4/7] Прописываю репозиторий Docker (deb822)..."
ARCH="$(dpkg --print-architecture)"
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: bookworm
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "==> [5/7] Устанавливаю docker-ce + плагины..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> [6/7] Включаю docker и добавляю $USER в группу docker..."
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

echo "==> [7/7] Тест: docker run --rm hello-world (через sudo, т.к. группа применится после relogin)..."
sudo docker run --rm hello-world || true

echo
echo "Готово. Выйдите из системы и зайдите снова (или 'newgrp docker'),"
echo "чтобы запускать docker без sudo."
