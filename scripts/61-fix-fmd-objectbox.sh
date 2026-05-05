#!/usr/bin/env bash
# 61-fix-fmd-objectbox.sh — Исправляет краш FindMyDevice Server из-за несовместимости
# библиотеки ObjectBox C 4.x с objectbox-go v1.7.0 (использовалась в FMD v0.5.0).
#
# Причина: при сборке образа из тега v0.5.0 устанавливается последняя версия
# objectbox C library (4.2.0), которая несовместима со старым Go-биндингом.
# Результат: panic при старте → контейнер в restart loop → Caddy получает 502.
#
# Стратегия:
#   Шаг 1. Пересобрать из ветки main (там обновлён objectbox-go, поддерживает C lib 4.x).
#   Шаг 2. Если main не поднялся — создаём локальный Dockerfile, который пинит
#           objectbox C lib на версию 0.18.1 и строит v0.5.0 из источника.
#
# ДАННЫЕ НЕ ТРОГАЮТСЯ: volume ./findmydevice/data монтируется снаружи контейнера.
set -uo pipefail

STACK_DIR="/opt/stack"
COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
FMD_DIR="${STACK_DIR}/findmydevice"
FMD_FALLBACK_DOCKERFILE="${FMD_DIR}/Dockerfile"

# -------------------------------------------------------------------

die() { echo "ОШИБКА: $*" >&2; exit 1; }

check_running() {
    local status
    status="$(docker inspect -f '{{.State.Status}}' findmydevice 2>/dev/null || echo missing)"
    [[ "${status}" == "running" ]]
}

# -------------------------------------------------------------------

echo "================================================================"
echo "= FMD ObjectBox Fix"
echo "================================================================"

[[ -f "${COMPOSE_FILE}" ]] || die "${COMPOSE_FILE} не найден."

echo
echo "==> Бэкапим ${COMPOSE_FILE}..."
cp -a "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

echo "==> Останавливаем и удаляем сломанный контейнер findmydevice..."
cd "${STACK_DIR}"
docker compose stop findmydevice 2>/dev/null || true
docker compose rm -f  findmydevice 2>/dev/null || true

echo "==> Удаляем кэш старого образа (с несовместимой objectbox C lib 4.x)..."
docker rmi stack-findmydevice 2>/dev/null || true

# -------------------------------------------------------------------
# ШАГ 1: Пересобрать из main
# -------------------------------------------------------------------

echo
echo "==> [ШАГ 1] Переключаем build на main (objectbox-go 1.8.0+, поддерживает C lib 4.x)..."

if grep -qE 'findmydeviceserver\.git#' "${COMPOSE_FILE}"; then
    # убираем любой #тег, оставляем только git URL
    sed -i -E 's|(build: https://gitlab\.com/Nulide/findmydeviceserver\.git)#[^[:space:]]*|\1|g' \
        "${COMPOSE_FILE}"
    echo "    OK: тег убран — будет использован main."
else
    echo "    build строка уже без тега или не найдена — пропускаем правку."
fi

echo "==> docker compose build --no-cache findmydevice (может занять 5–15 мин)..."
if docker compose build --no-cache findmydevice; then
    echo "==> Сборка успешна. Запускаем контейнер..."
    docker compose up -d findmydevice
    echo "==> Ждём 20 с..."
    sleep 20

    echo "==> Логи findmydevice (последние 40 строк):"
    docker logs --tail=40 findmydevice 2>&1 || true

    if check_running; then
        echo
        echo "✅ [ШАГ 1] findmydevice работает на main!"
        echo "   Проверь локально:  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090"
        echo "   И снаружи:         curl -s -o /dev/null -w '%{http_code}\n' https://fmd.server34.netcraze.club/api/v1/version"
        echo
        echo "Если всё ОК — на роутере Keenetic можно убрать WAN-форвард на 8090."
        exit 0
    else
        echo "⚠️  Контейнер запустился, но не в running. Смотри логи выше."
        echo "   Переходим к Шагу 2 (локальный Dockerfile)..."
    fi
else
    echo "⚠️  Сборка из main не удалась. Переходим к Шагу 2..."
fi

# -------------------------------------------------------------------
# ШАГ 2: Локальный Dockerfile, пинящий objectbox C lib на 0.18.1
# -------------------------------------------------------------------

echo
echo "==> [ШАГ 2] Создаём локальный Dockerfile для FMD v0.5.0 с objectbox C 0.18.1..."

mkdir -p "${FMD_DIR}/data"

cat > "${FMD_FALLBACK_DOCKERFILE}" << 'DOCKERFILE'
# Кастомный Dockerfile для FMD v0.5.0 с фиксированной objectbox C lib 0.18.1.
# Нужен, потому что стандартный upstream-Dockerfile ставит последнюю (несовместимую) версию.
FROM golang:1.21-bookworm AS builder

ARG FMD_TAG=v0.5.0
ARG OBJECTBOX_VERSION=0.18.1

# Системные зависимости
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Клонируем FMD v0.5.0
RUN git clone --depth 1 --branch ${FMD_TAG} \
    https://gitlab.com/Nulide/findmydeviceserver.git /go/src/findmydeviceserver

WORKDIR /go/src/findmydeviceserver

# Устанавливаем objectbox C library нужной версии (0.18.1) вместо latest
RUN bash <(curl -fsSL https://raw.githubusercontent.com/objectbox/objectbox-c/main/download.sh) \
    --quiet ${OBJECTBOX_VERSION}

# Копируем .so в стандартный путь, обновляем ld cache
RUN cp /usr/local/lib/libobjectbox.so* /usr/lib/ 2>/dev/null || true && ldconfig

# Собираем
RUN go build -o /fmd/server ./cmd/fmdserver/...

# ---- финальный образ ----
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /fmd/server /fmd/server
COPY --from=builder /usr/lib/libobjectbox.so* /usr/lib/
RUN ldconfig

RUN mkdir -p /fmd/objectbox
VOLUME ["/fmd/objectbox"]
EXPOSE 8080

CMD ["/fmd/server"]
DOCKERFILE

echo "==> Обновляем docker-compose.yml: build из ./findmydevice/ (локальный Dockerfile)..."
# Заменяем строку build на context локальной папки
if grep -q 'build: https://gitlab.com/Nulide/findmydeviceserver.git' "${COMPOSE_FILE}"; then
    sed -i 's|build: https://gitlab.com/Nulide/findmydeviceserver.git|build: ./findmydevice|g' \
        "${COMPOSE_FILE}"
    echo "    OK: build переключён на ./findmydevice (локальный Dockerfile)."
fi

echo "==> docker compose build --no-cache findmydevice (локальный Dockerfile, с objectbox 0.18.1)..."
docker compose build --no-cache findmydevice

echo "==> docker compose up -d findmydevice..."
docker compose up -d findmydevice

echo "==> Ждём 20 с..."
sleep 20

echo "==> Логи findmydevice (последние 40 строк):"
docker logs --tail=40 findmydevice 2>&1 || true

if check_running; then
    echo
    echo "✅ [ШАГ 2] findmydevice работает (локальный Dockerfile, objectbox 0.18.1)!"
    echo "   Проверь локально:  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8090"
    echo "   И снаружи:         curl -s -o /dev/null -w '%{http_code}\n' https://fmd.server34.netcraze.club/api/v1/version"
else
    echo
    echo "❌ Контейнер не в running после Шага 2."
    echo "   Смотри логи выше. Вероятно, проблема в самом приложении FMD (конфиг/данные),"
    echo "   а не в objectbox. Пришли лог — разберёмся дальше."
    exit 1
fi
