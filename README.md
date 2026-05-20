# 🏠 Home Server Automation

Набор bash-скриптов для разворачивания домашнего сервера на **Debian 12 (bookworm)**:

- Crafty Controller 4 — веб-панель Minecraft;
- tModLoader 1.4 (Terraria) сервер;
- FileBrowser Quantum — веб-доступ к каталогам импорта/моды/миры;
- FindMyDevice Server (Nulide) — собственный сервер для Android-приложения FindMyDevice;
- Caddy — реверс-прокси с автоматическим HTTPS (Let's Encrypt) для веб-сервисов.

Все сервисы поднимаются как Docker-контейнеры через единый `docker-compose.yml` в `/opt/stack`.

> ⚠️ **Секретов в репозитории нет.** Скрипты интерактивно спрашивают пароли и пишут их
> в `/opt/stack/.env` (`chmod 600`). Этот файл локальный, в git не коммитьте.

---

## Предварительные требования

- Debian 12 minimal, свежеустановленная.
- Пользователь с правами `sudo` (не `root` напрямую).
- SSH-доступ.
- Желательно: статический/зарезервированный IP в роутере (например, в Keenetic — DHCP-резервация по MAC).

---

## Рекомендуемый порядок запуска

```text
01-base-debian.sh       → перезагрузка
02-install-docker.sh    → выйти и зайти заново (или newgrp docker)
03-check-docker.sh
10-install-crafty.sh
30-install-filebrowser.sh
20-install-terraria.sh
40-install-findmydevice.sh
50-install-caddy-proxy.sh   (после filebrowser и findmydevice — публикует их по HTTPS)
99-status.sh            (в любой момент, чтобы посмотреть статус)
```

Запуск:

```bash
chmod +x home-server/scripts/*.sh
./home-server/scripts/01-base-debian.sh
sudo reboot
# ...после перезагрузки:
./home-server/scripts/02-install-docker.sh
# ...выйти/зайти, чтобы группа docker применилась
./home-server/scripts/03-check-docker.sh
./home-server/scripts/10-install-crafty.sh
./home-server/scripts/30-install-filebrowser.sh
./home-server/scripts/20-install-terraria.sh
./home-server/scripts/40-install-findmydevice.sh
./home-server/scripts/50-install-caddy-proxy.sh
```

---

## Порты

| Сервис         | Порт хоста | Протокол | Назначение                                |
|----------------|-----------:|----------|--------------------------------------------|
| Caddy          | 80, 443    | HTTP/HTTPS | Реверс-прокси с Let's Encrypt для веб-сервисов |
| Crafty панель  | 8443       | HTTPS    | Веб-панель Crafty (самоподписанный TLS)   |
| Minecraft      | 25565–25567| TCP      | Игровые слоты, проброшенные в Crafty      |
| Terraria       | 7777       | TCP      | tModLoader 1.4 сервер                      |
| FileBrowser    | 8080       | **HTTP** | Локально/прямой доступ; публично — через Caddy |
| FindMyDevice   | 8090       | **HTTP** | Локально/прямой доступ; публично — через Caddy |

### Публичные URL через Caddy

После запуска `50-install-caddy-proxy.sh`:

| Публичный URL                                | Куда проксируется   |
|----------------------------------------------|---------------------|
| `https://files.server34.netcraze.club`       | `filebrowser:80`    |
| `https://fmd.server34.netcraze.club`         | `findmydevice:8080` |

### Проброс портов на роутере (Keenetic)

- **Пробросить наружу:** `80/tcp` и `443/tcp` → IP домашнего сервера (нужно для Caddy и Let's Encrypt).
- **Оставить как есть:** Minecraft `25565/tcp`, Terraria `7777/tcp`, Crafty `8443/tcp`.
- **WebDAV** на роутере сейчас вынесен на внешний порт `5083` — это отдельный сервис, через
  Caddy не публикуется. Если потребуется, в будущем можно добавить блок
  `webdav.server34.netcraze.club` в `Caddyfile`, но только когда соответствующий апстрим
  появится в `docker-compose.yml`.
- Лучшая будущая практика: всё, что веб, отдавать наружу только через Caddy на 443,
  а прямые порты приложений (`8080`, `8090` и т.п.) во внешний интернет не пробрасывать.

### DNS

Перед запуском Caddy убедитесь, что поддомены резолвятся в ваш домашний внешний IP
(или в основной домен, который туда указывает):

```bash
nslookup fmd.server34.netcraze.club
nslookup files.server34.netcraze.club
```

Если записей нет — заведите у DNS-провайдера CNAME на основной домен
(`server34.netcraze.club`) или A-записи прямо на внешний IP.

---

## Безопасность — обязательно к прочтению

- **FileBrowser и FindMyDevice по умолчанию работают по HTTP.** Не пробрасывайте 8080/8090
  в интернет «как есть». Варианты:
  - доступ только из локальной сети / VPN (WireGuard, Tailscale, Keenetic VPN-сервер);
  - реверс-прокси (Caddy / Nginx / Traefik) с TLS-сертификатом (Let's Encrypt) и
  публикация только через `https://`.
- В FileBrowser **включите 2FA** до того, как откроете доступ извне.
- Crafty отдаёт HTTPS, но с самоподписанным сертификатом — это нормально для LAN.
  Браузер ругается → Advanced → Proceed.
- Никаких секретов в репозиторий не коммитим: всё, что чувствительное,
  лежит в `/opt/stack/.env` на сервере.
- **После того как Caddy заработал** (`https://files...` и `https://fmd...` отдаются с
  валидным сертификатом), на роутере **уберите WAN-форварды на 8080 и 8090** —
  публиковать их прямо в интернет больше не нужно. Оставьте проброс только
  `80/443` → Caddy. Локально (из дома / по VPN) `8080` и `8090` остаются доступны.

---

## Где что лежит

```
/opt/stack/
├── docker-compose.yml        # единый compose для всех сервисов
├── .env                      # локальные секреты (НЕ в git)
├── crafty/
│   ├── backups/  logs/  servers/  config/  import/
├── terraria/
│   ├── data/  backups/  mods-inbox/
├── filebrowser/
│   └── data/                 # БД и config.yml FileBrowser
├── findmydevice/
│   └── data/                 # objectbox-БД FMD
└── caddy/
    ├── Caddyfile             # конфиг реверс-прокси
    ├── data/                 # сертификаты Let's Encrypt и состояние ACME
    └── config/               # рабочая конфигурация Caddy
```

---

## Статус и логи

```bash
cd /opt/stack
docker compose ps
docker logs --tail=100 crafty
docker logs --tail=100 terraria
docker logs --tail=100 filebrowser
docker logs --tail=100 findmydevice
docker logs --tail=100 caddy
```

Или интерактивная панель `99-status.sh` — статус стека (контейнеры, systemd-сервисы,
порты, сертификаты) и меню рестарт/логи/обновление контейнеров:

```bash
./home-server/scripts/99-status.sh            # разовый запуск
./home-server/scripts/99-status.sh --install  # поставить командой `hs`
```

После `--install` панель вызывается из любого каталога:

```bash
hs            # интерактивное меню
hs --status   # печать полного статуса
hs --uninstall  # убрать команду
```

---

## Траблшутинг

### SSH перестал пускать после смены IP
Адрес мог измениться по DHCP. В роутере (Keenetic) **зарезервируйте DHCP-аренду**
по MAC-адресу сервера, чтобы IP не менялся.

### FileBrowser: «user unauthorized» / не пускает
- Пароль должен быть **не короче 12 символов** — это требование `auth.methods.password.minLength`.
- Сбросить пароль из CLI:
  ```bash
  docker exec -it filebrowser /filebrowser users update admin --password 'НОВЫЙ_ПАРОЛЬ_МИН_12'
  docker restart filebrowser
  ```

### Браузер ругается `ERR_SSL_PROTOCOL_ERROR` на FileBrowser
Вы открываете FileBrowser по `https://`. Сервис отдаёт **HTTP**, а не HTTPS.
Откройте `http://LAN_IP:8080` или поставьте реверс-прокси с TLS.

### Crafty: где дефолтные креды
```bash
cat /opt/stack/crafty/config/default-creds.txt
# либо
docker exec crafty cat /crafty/app/config/default-creds.txt
```

### Minecraft Forge 1.20.1 в Crafty: какой Java
Forge 1.20.1 требует **Java 17**. В настройках сервера в Crafty укажите путь:
```
/usr/lib/jvm/java-17-openjdk-amd64/bin/java
```
(внутри контейнера Crafty Java 17 уже доступна).

### Caddy / FMD отдают 502 или приложение пишет «Ошибка: null»

Запустите единый диагностический скрипт — он проверит DNS, контейнеры, Caddyfile,
сетевую связность Caddy ↔ findmydevice, локальные порты и соберёт логи в один файл:

```bash
./home-server/scripts/60-diagnose-caddy-fmd.sh
```

Можно переопределить домены и порт:

```bash
FMD_DOMAIN=fmd.example.com \
FILES_DOMAIN=files.example.com \
FMD_HOST_PORT=8090 \
    ./home-server/scripts/60-diagnose-caddy-fmd.sh
```

Скрипт ничего не меняет, только читает. В конце печатает короткое резюме и сохраняет
полный лог в `/tmp/caddy-fmd-diagnose-YYYYmmdd-HHMMSS.log` — этот файл можно прислать
целиком, чтобы быстрее разобрать причину.

### FindMyDevice: «не подключается из приложения»
- В Android FMD укажите Server URL **с протоколом**: `http://LAN_IP:8090` (или ваш `https://домен`).
- Если выставлено наружу — обязательно через реверс-прокси с HTTPS, иначе многие
  Android-сборки заблокируют HTTP-трафик (cleartext).
- Свой `config.yml` (если нужен) — скопируйте `config.example.yml` из апстрима
  https://gitlab.com/Nulide/findmydeviceserver и положите в
  `/opt/stack/findmydevice/config.yml`, затем раскомментируйте монтирование в
  `docker-compose.yml` и `docker compose up -d findmydevice`.

### Сборка FMD долго идёт / падает
`docker compose build findmydevice` действительно качает и собирает образ из git.
Повторите при ошибках сети; для отладки — `docker compose build --progress=plain findmydevice`.
