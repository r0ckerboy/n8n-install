#!/usr/bin/env bash
set -euo pipefail

echo "=== Установка n8n ==="

# 👉 Запрашиваем данные у пользователя
read -p "Введите домен для n8n (например n8n.example.com): " DOMAIN
read -p "Введите email для получения SSL-сертификата: " EMAIL
read -p "Введите токен вашего Telegram-бота: " TG_BOT_TOKEN
read -p "Введите ваш Telegram User ID: " TG_USER_ID
read -p "Введите пароль для базы Postgres: " POSTGRES_PASSWORD

# Список статических директорий
STATIC_DIRS=("files" "backups" "public")

# Установка утилит
apt update && apt upgrade -y
apt install -y ca-certificates curl gnupg lsb-release ufw uuid-runtime openssl git

# Установка Docker и Compose
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version &>/dev/null; then
  apt install -y docker-compose-plugin
fi

# Генерация ключа шифрования
if command -v uuidgen &>/dev/null; then
  N8N_ENCRYPTION_KEY=$(uuidgen)
else
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
fi
echo "→ Ключ шифрования: $N8N_ENCRYPTION_KEY"

# Настройка брандмауэра
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

# Создание директорий
BASE="/opt/n8n"
mkdir -p "$BASE"/{n8n_data,traefik_data,static,bot}
for d in "${STATIC_DIRS[@]}"; do mkdir -p "$BASE/static/$d"; done
touch "$BASE/traefik_data/acme.json"
chmod 600 "$BASE/traefik_data/acme.json"

# Docker сеть и тома
docker network create n8n || true
docker volume create n8n_db_storage || true
docker volume create n8n_n8n_storage || true
docker volume create n8n_redis_storage || true

# Запуск Postgres
docker run -d --name n8n-postgres --restart always --network n8n \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB=n8n \
  -v n8n_db_storage:/var/lib/postgresql/data \
  postgres:15-alpine

# Запуск Redis
docker run -d --name n8n-redis --restart always --network n8n \
  -v n8n_redis_storage:/data \
  redis:7-alpine

# Запуск Traefik
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

# Запуск nginx для статики
docker run -d --name n8n-static --restart always --network n8n \
  -v "$BASE/static":/usr/share/nginx/html:ro \
  -l "traefik.enable=true" \
  -l "traefik.http.routers.static.rule=Host(\"$DOMAIN\") && PathPrefix(\"/static\")" \
  -l "traefik.http.routers.static.entrypoints=websecure" \
  -l "traefik.http.routers.static.tls.certresolver=le" \
  -l "traefik.http.services.static.loadbalancer.server.port=80" \
  nginx:alpine

# Запуск n8n
docker run -d --name n8n-app --restart always --network n8n \
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
  -v "$BASE/n8n_data/files":/files \
  -v "$BASE/n8n_data/tmp":/tmp \
  -v "$BASE/n8n_data/backups":/backups \
  docker.n8n.io/n8nio/n8n:1.90.2

# Подтягиваем папку бота с GitHub
cd "$BASE"
git clone https://github.com/kalininlive/n8n-beget-install.git tmp-bot
cp -r tmp-bot/bot/* bot/
rm -rf tmp-bot

# Сборка и запуск Telegram-бота
cd "$BASE/bot"
docker build -t n8n-admin-tg-bot .
docker run -d --name n8n-admin-tg-bot --restart always --network host \
  -e TG_BOT_TOKEN="$TG_BOT_TOKEN" \
  -e TG_USER_ID="$TG_USER_ID" \
  -e DOMAIN="$DOMAIN" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  n8n-admin-tg-bot

echo
echo "✅ Установка завершена! Перейдите на https://$DOMAIN"
