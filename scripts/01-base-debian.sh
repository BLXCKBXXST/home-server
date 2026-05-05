#!/usr/bin/env bash
# 01-base-debian.sh — базовая настройка Debian 12 для домашнего сервера.
# Идемпотентный: можно запускать повторно.
set -euo pipefail

echo "==> [1/8] Запрашиваю sudo..."
sudo -v

echo "==> [2/8] apt update + full-upgrade..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt full-upgrade -y

echo "==> [3/8] Устанавливаю базовые пакеты..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
    ufw jq openssl rsync git nano htop tree unzip zip tar wget \
    net-tools dnsutils iproute2 iputils-ping traceroute ncdu sudo openssh-server

echo "==> [4/8] Часовой пояс Asia/Krasnoyarsk..."
sudo timedatectl set-timezone Asia/Krasnoyarsk

echo "==> [5/8] Включаю SSH..."
sudo systemctl enable --now ssh

echo "==> [6/8] Локаль en_US.UTF-8..."
if ! locale -a 2>/dev/null | grep -qi '^en_US\.utf8$'; then
    sudo sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
    if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
        echo 'en_US.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
    fi
    sudo locale-gen en_US.UTF-8
fi
sudo update-locale LANG=en_US.UTF-8

echo "==> [7/8] Состояние системы:"
hostnamectl || true
ip -br a || true
ip route || true

echo "==> [8/8] Готово. Рекомендуется перезагрузить машину: sudo reboot"
