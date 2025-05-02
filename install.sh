#!/usr/bin/env bash
set -euo pipefail

echo "=== 🚀 Установка n8n + всё необходимое на $(hostname) ==="

# 👉 Запрашиваем данные у пользователя:
read -p "Введите домен для n8n (например n8n.example.com): " DOMAIN
read -p "Введите email для получения SSL-сертификата: " EMAIL
read -p "Введите токен вашего Telegram-бота: " TG_BOT_TOKEN
read -p "Введите ваш Telegram User ID: " TG_USER_ID
read -p "Введите пароль для базы данных Postgres: " POSTGRES_PASSWORD

# 1) Установка системных утилит + мультимедиа пакетов
apt update && apt upgrade -y
apt install -y ca-certificates curl gnupg lsb-release ufw uuid-runtime openssl git ffmpeg imagemagick python3 python3-pip libavcodec-extra

# 2) Docker + Compose
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version &>/dev/null; then
  apt install -y docker-compose-plugin
fi

# 3) Генерация ключа
N8N_ENCRYPTION_KEY=$(uuidgen || openssl rand -hex 32)
echo "→ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"

# 4) Создаем директории заранее
BASE="/opt/n8n"
STATIC_DIRS=("files" "backups" "public")
mkdir -p "$BASE"/{n8n_data/tmp,n8n_data/files,n8n_data/backups,traefik_data,static,bot}
for d in "${STATIC_DIRS[@]}"; do mkdir -p "$BASE/static/$d"; done
touch "$BASE/traefik_data/acme.json"
chmod 600 "$BASE/traefik_data/acme.json"
chown -R 1000:1000 "$BASE/n8n_data/tmp"

# 5) Firewall
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

# 6) Dockerfile.n8n
cp "$(dirname "$0")/Dockerfile.n8n" "$BASE/Dockerfile.n8n"
cd "$BASE"
echo "→ Собираем образ n8n..."
docker build -f Dockerfile.n8n -t kalininlive/n8n:yt-dlp .

# 7) Docker network + volumes
docker network create n8n || true
docker volume create n8n_db_storage || true
docker volume create n8n_n8n_storage || true
docker volume create n8n_redis_storage || true

# 8) Containers
## Postgres
docker run -d --name n8n-postgres --restart always --network n8n \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB=n8n \
  -v n8n_db_storage:/var/lib/postgresql/data \
  postgres:15-alpine

## Redis
docker run -d --name n8n-redis --restart always --network n8n \
  -v n8n_redis_storage:/data \
  redis:7-alpine

## Traefik
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

## nginx static
docker run -d --name n8n-static --restart always --network n8n \
  -v "$BASE/static":/usr/share/nginx/html:ro \
  -l "traefik.enable=true" \
  -l "traefik.http.routers.static.rule=Host(\"$DOMAIN\") && PathPrefix(\"/static\")" \
  -l "traefik.http.routers.static.entrypoints=websecure" \
  -l "traefik.http.routers.static.tls.certresolver=le" \
  -l "traefik.http.services.static.loadbalancer.server.port=80" \
  nginx:alpine

## n8n
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

# 9) Bot
git clone https://github.com/kalininlive/n8n-beget-install.git "$BASE/tmp-bot"
cp -r "$BASE/tmp-bot/bot"/* "$BASE/bot/"
rm -rf "$BASE/tmp-bot"
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

# 10) Backup cron
echo "→ Настраиваем авто-бэкап..."
mkdir -p "$BASE/cron"
cp "$BASE/../n8n-install/backup_n8n.sh" "$BASE/cron/backup_n8n.sh"
chmod +x "$BASE/cron/backup_n8n.sh"
echo "TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"" > "$BASE/cron/.env"
echo "TG_USER_ID=\"$TG_USER_ID\"" >> "$BASE/cron/.env"
echo "DOMAIN=\"$DOMAIN\"" >> "$BASE/cron/.env"
(crontab -l 2>/dev/null; echo "0 3 * * * $BASE/cron/backup_n8n.sh") | crontab -

# 11) Save installed packages echo
echo "
📆 Сохраняем списки пакетов..."
docker exec -u 0 n8n-app apk info | sort > "$BASE/n8n_data/backups/n8n_installed_apk.txt"
docker exec -u 0 n8n-app /venv/bin/pip list > "$BASE/n8n_data/backups/n8n_installed_pip.txt"
{
  echo -n "yt-dlp: "; docker exec -u 0 n8n-app yt-dlp --version
  echo -n "ffmpeg: "; docker exec -u 0 n8n-app ffmpeg -version | head -n 1
  echo -n "python3: "; docker exec -u 0 n8n-app python3 --version
} > "$BASE/n8n_data/backups/n8n_versions.txt"

echo "
📄 Списки сохранены в:"
echo "→ $BASE/n8n_data/backups/n8n_installed_apk.txt"
echo "→ $BASE/n8n_data/backups/n8n_installed_pip.txt"
echo "→ $BASE/n8n_data/backups/n8n_versions.txt"

echo "
📅 Установка завершена! Откройте https://$DOMAIN"
