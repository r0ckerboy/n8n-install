#!/usr/bin/env bash
set -euo pipefail

# Запрашиваем данные у пользователя
echo "=== 🚀 Установка n8n с ботом для администрирования ==="
DOMAIN="n8n.kalininlive.ru"
EMAIL="info@kalininlive.ru"
TG_BOT_TOKEN="8013093851:AAFYwCrXkIicl6GMXV1cJnEhBOtYhbk5Z_I"
TG_USER_ID="1694739756"
POSTGRES_PASSWORD="Ct^%^6DR5eaftgty7uED"

# 1) Установка зависимостей
echo "→ Установка утилит и мультимедиа пакетов..."
apt update && apt upgrade -y
apt install -y ca-certificates curl gnupg lsb-release ufw uuid-runtime openssl git ffmpeg imagemagick python3 python3-pip libavcodec-extra

# 2) Установка Docker и Docker Compose
echo "→ Установка Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version &>/dev/null; then
  apt install -y docker-compose-plugin
fi

# 3) Генерация ключа для n8n
echo "→ Генерация ключа шифрования..."
N8N_ENCRYPTION_KEY=$(uuidgen || openssl rand -hex 32)
echo "→ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"

# 4) Создаем директории для данных и бэкапов
BASE="/opt/n8n"
echo "→ Создание директорий для данных и бэкапов..."
mkdir -p "$BASE"/n8n_data/{files,tmp,backups}
mkdir -p "$BASE"/static
mkdir -p "$BASE"/cron
mkdir -p "$BASE/traefik_data"  # Создание директории для Traefik
touch "$BASE/traefik_data/acme.json"  # Создание файла acme.json
chmod 600 "$BASE/traefik_data/acme.json"  # Устанавливаем права для файла

# Настроим права на директории
echo "→ Настройка прав на директории..."
chmod 777 "$BASE/n8n_data/tmp"  # Даем права на запись в /tmp
chmod 777 "$BASE/n8n_data/backups"  # Права на бэкапы

# 5) Настройка firewall
echo "→ Настройка firewall..."
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

# 6) Копирование Dockerfile для n8n
cp "$(dirname "$0")/Dockerfile.n8n" "$BASE/Dockerfile.n8n"
cd "$BASE"
docker build -f Dockerfile.n8n -t kalininlive/n8n:yt-dlp .

# 7) Создание Docker-сетей и томов
docker network create n8n || true
docker volume create n8n_db_storage || true
docker volume create n8n_n8n_storage || true
docker volume create n8n_redis_storage || true

# 8) Запуск контейнеров (PostgreSQL, Redis, Traefik, n8n)
echo "→ Запуск контейнеров..."
docker run -d --name n8n-postgres --restart always --network n8n \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB=n8n \
  -v n8n_db_storage:/var/lib/postgresql/data \
  postgres:15-alpine

docker run -d --name n8n-redis --restart always --network n8n \
  -v n8n_redis_storage:/data \
  redis:7-alpine

docker run -d --name n8n-traefik --restart always --network n8n \
  -p 80:80 -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$BASE/traefik_data/acme.json":/acme.json \
  traefik:2.10.4 \
    --providers.docker=true \
    --providers.docker.exposedbydefault=false \
    --entrypoints.web.address=:80 \
    --entrypoints.websecure.address=:443 \
    --certificatesresolvers.le.acme.httpchallenge.entrypoint=web \
    --certificatesresolvers.le.acme.email="$EMAIL" \
    --certificatesresolvers.le.acme.storage=/acme.json

docker run -d --name n8n-static --restart always --network n8n \
  -v "$BASE/static":/usr/share/nginx/html:ro \
  -l "traefik.enable=true" \
  -l "traefik.http.routers.static.rule=Host(\"$DOMAIN\") && PathPrefix(\"/static\")" \
  -l "traefik.http.routers.static.entrypoints=websecure" \
  -l "traefik.http.routers.static.tls.certresolver=le" \
  -l "traefik.http.services.static.loadbalancer.server.port=80" \
  nginx:alpine

docker run -d --name n8n-app --restart always --network n8n \
  -v "$BASE/static":/static \
  -v "$BASE/n8n_data/files":/files \
  -v "$BASE/n8n_data/tmp":/tmp \
  -v "$BASE/n8n_data/backups":/backups \
  -l "traefik.enable=true" \
  -l "traefik.http.routers.n8n.rule=Host(\"$DOMAIN\")" \
  -l "traefik.http.routers.n8n.entrypoints=websecure" \
  -l "traefik.http.routers.n8n.tls.certresolver=le" \
  -l "traefik.http.services.n8n.loadbalancer.server.port=5678" \
  -e N8N_BASIC_AUTH_ACTIVE=false \
  -e N8N_PROTOCOL=https \
  -e N8N_HOST="$DOMAIN" \
  -e WEBHOOK_URL="https://$DOMAIN/" \
  -e NODE_ENV=production \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=n8n-postgres \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=user \
  -e DB_POSTGRESDB_PASSWORD="$POSTGRES_PASSWORD" \
  -e N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY" \
  -e GENERIC_TIMEZONE=Europe/Amsterdam \
  -e QUEUE_BULL_REDIS_HOST=n8n-redis \
  -e EXECUTIONS_DATA_PRUNE=true \
  -e EXECUTIONS_DATA_MAX_AGE=168 \
  -e N8N_DEFAULT_BINARY_DATA_MODE=filesystem \
  kalininlive/n8n:yt-dlp

# 9) Создание и настройка Telegram-бота
echo "→ Настройка Telegram-бота..."
mkdir -p "$BASE/cron"
cp "$BASE/../n8n-install/backup_n8n.sh" "$BASE/cron/backup_n8n.sh"
chmod +x "$BASE/cron/backup_n8n.sh"
echo "TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"" > "$BASE/cron/.env"
echo "TG_USER_ID=\"$TG_USER_ID\"" >> "$BASE/cron/.env"
echo "DOMAIN=\"$DOMAIN\"" >> "$BASE/cron/.env"

# 10) Добавление cron задачи для бэкапов с полным путем
echo "→ Настроим cron для авто-бэкапов..."
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/n8n-install/cron/backup_n8n.sh") | crontab -
echo "→ Проверка текущих cron заданий..."
crontab -l
echo "→ Cron задача добавлена."

# 11) Сохраняем установленные пакеты и отправляем в Telegram
echo "\n📦 Сохраняем списки пакетов..."
if docker ps -q -f name=n8n-app; then
  echo "→ Контейнер n8n запущен. Сохраняем списки пакетов..."
  docker exec -u 0 n8n-app apk info | sort > "$BASE/n8n_data/backups/n8n_installed_apk.txt"
  docker exec -u 0 n8n-app /venv/bin/pip list > "$BASE/n8n_data/backups/n8n_installed_pip.txt"
  {
    echo -n "yt-dlp: "; docker exec -u 0 n8n-app yt-dlp --version
    echo -n "ffmpeg: "; docker exec -u 0 n8n-app ffmpeg -version | head -n 1
    echo -n "python3: "; docker exec -u 0 n8n-app python3 --version
  } > "$BASE/n8n_data/backups/n8n_versions.txt"
  VERSIONS=$(cat "$BASE/n8n_data/backups/n8n_versions.txt")
  curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
       -d chat_id=$TG_USER_ID \
       --data-urlencode "text=✅ Установка завершена\n\n📄 Библиотеки в контейнере:\n$VERSIONS"
  echo "\n📄 Списки сохранены в:"
  echo "→ $BASE/n8n_data/backups/n8n_installed_apk.txt"
  echo "→ $BASE/n8n_data/backups/n8n_installed_pip.txt"
  echo "→ $BASE/n8n_data/backups/n8n_versions.txt"
else
  echo "❌ Контейнер n8n не запущен. Не удалось сохранить списки пакетов."
fi

# 12) Исправление прав на файл настроек n8n
echo "→ Исправляем права на файл настроек n8n..."
sudo chmod 600 /home/node/.n8n/config

# 13) Включаем task runners для n8n
echo "→ Включаем task runners для n8n..."
export N8N_RUNNERS_ENABLED=true

echo "\n📅 Установка завершена! Откройте https://$DOMAIN"
