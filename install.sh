#!/bin/bash
set -e

# Проверка прав
if (( EUID != 0 )); then
    echo "❗ Скрипт должен быть запущен от root: sudo bash <(curl ...)"
    exit 1
fi

# Проверка и установка зависимостей
echo "🔧 Проверка и установка необходимых пакетов..."
for pkg in git curl wget openssl; do
    if ! command -v $pkg &>/dev/null; then
        apt-get update && apt-get install -y $pkg
    fi
done

clear
echo "🌐 Автоматическая установка n8n + Postiz + Short Video Maker (Traefik)"
echo "-----------------------------------------------------------"

# 1. Ввод переменных
read -p "🌐 Введите базовый домен (например: example.com): " BASE_DOMAIN
read -p "📧 Введите email для Let's Encrypt: " EMAIL
read -p "🔐 Введите пароль для Postgres: " POSTGRES_PASSWORD
read -p "🔑 Введите Pexels API ключ для Short Video Maker: " PEXELS_API_KEY
read -p "🤖 Введите Telegram Bot Token: " TG_BOT_TOKEN
read -p "👤 Введите Telegram User ID: " TG_USER_ID
read -p "🗝️ Введите ключ шифрования n8n (Enter для генерации): " N8N_ENCRYPTION_KEY
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    echo "✅ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"
fi

# 2. Установка Docker и Compose
echo "📦 Проверка Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
if ! command -v docker-compose &>/dev/null; then
    curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true
fi

# 3. Клонирование проекта
echo "📥 Клонируем проект..."
rm -rf /opt/n8n-install
git clone https://github.com/r0ckerboy/n8n-beget-install /opt/n8n-install
cd /opt/n8n-install

# 4. Генерация .env
cat > ".env" <<EOF
BASE_DOMAIN=$BASE_DOMAIN
EMAIL=$EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
PEXELS_API_KEY=$PEXELS_API_KEY
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

chmod 600 .env

# 5. Создание директорий
mkdir -p traefik/{acme,logs} postgres-data redis-data videos data backups
touch traefik/acme/acme.json
chmod 600 traefik/acme/acme.json
chown -R 1000:1000 data backups videos

# 6. Конфиг Traefik (traefik.yml)
cat > "traefik.yml" <<EOF
global:
  sendAnonymousUsage: false
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
providers:
  docker:
    exposedByDefault: false
  file:
    filename: /etc/traefik/dynamic.yml
certificatesResolvers:
  letsencrypt:
    acme:
      email: $EMAIL
      storage: /etc/traefik/acme/acme.json
      httpChallenge:
        entryPoint: web
EOF

# 7. Динамический конфиг Traefik (dynamic.yml)
cat > "dynamic.yml" <<EOF
http:
  middlewares:
    compress:
      compress: true
    security-headers:
      headers:
        frameDeny: true
        contentTypeNosniff: true
        browserXssFilter: true
        sslRedirect: true
  routers:
    n8n:
      rule: "Host(\`n8n.$BASE_DOMAIN\`)"
      entryPoints: websecure
      tls:
        certResolver: letsencrypt
      service: n8n
      middlewares: [compress, security-headers]
    postiz:
      rule: "Host(\`postiz.$BASE_DOMAIN\`)"
      entryPoints: websecure
      tls:
        certResolver: letsencrypt
      service: postiz
      middlewares: [compress, security-headers]
    short-video-maker:
      rule: "Host(\`short-video-maker.$BASE_DOMAIN\`)"
      entryPoints: websecure
      tls:
        certResolver: letsencrypt
      service: short-video-maker
      middlewares: [compress, security-headers]
  services:
    n8n:
      loadBalancer:
        servers:
          - url: http://n8n:5678
    postiz:
      loadBalancer:
        servers:
          - url: http://postiz:3000
    short-video-maker:
      loadBalancer:
        servers:
          - url: http://short-video-maker:3123
EOF

# 8. Обновленный docker-compose.yml
cat > "docker-compose.yml" <<EOF
services:
  traefik:
    image: traefik:v2.10
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./traefik.yml:/etc/traefik/traefik.yml
      - ./dynamic.yml:/etc/traefik/dynamic.yml
      - ./traefik/acme:/etc/traefik/acme
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"

  n8n:
    image: n8n-custom:latest
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n.$BASE_DOMAIN
      - N8N_PROTOCOL=https
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ./data:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.rule=Host(\`n8n.$BASE_DOMAIN\`)"
    depends_on:
      - postgres

  postgres:
    image: postgres:13
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:6
    restart: unless-stopped
    volumes:
      - ./redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  postiz:
    image: gitroomhq/postiz-app:latest
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/n8n
      - REDIS_URL=redis://redis:6379
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.postiz.entrypoints=websecure"
      - "traefik.http.routers.postiz.rule=Host(\`postiz.$BASE_DOMAIN\`)"
    depends_on:
      - postgres
      - redis

  short-video-maker:
    image: gyoridavid/short-video-maker:latest-tiny
    restart: unless-stopped
    environment:
      - PEXELS_API_KEY=${PEXELS_API_KEY}
      - LOG_LEVEL=debug
    volumes:
      - ./videos:/app/data/videos
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.short-video-maker.entrypoints=websecure"
      - "traefik.http.routers.short-video-maker.rule=Host(\`short-video-maker.$BASE_DOMAIN\`)"
      - "traefik.http.services.short-video-maker.loadbalancer.server.port=3123"
    depends_on:
      - traefik

  bot:
    build: ./bot
    restart: unless-stopped
    environment:
      - TG_BOT_TOKEN=${TG_BOT_TOKEN}
      - TG_USER_ID=${TG_USER_ID}
EOF

# 9. Сборка и запуск с улучшенной проверкой
echo "🚀 Запуск системы..."
docker build -f Dockerfile.n8n -t n8n-custom:latest .
# Очистка предыдущих контейнеров (если есть)
docker compose down --remove-orphans || true
# Запуск с ожиданием готовности
docker compose up -d
echo "⏳ Ожидание запуска сервисов (до 2 минут)..."
for i in {1..12}; do
    if docker compose ps | grep -q "running"; then
        break
    fi
    sleep 10
    echo "⏳ Проверка состояния ($i/12)..."
done

# 10. Улучшенная проверка состояния
echo "🔍 Детальная проверка состояния:"
check_service() {
    local service=$1
    local status=$(docker compose ps $service | awk 'NR==2 {print $4}')
    if [ "$status" = "running" ]; then
        echo "✅ $service работает нормально"
        return 0
    else
        echo "❌ $service имеет проблемы (статус: $status)"
        echo "=== Логи $service ==="
        docker compose logs $service --tail=20
        return 1
    fi
}
check_service traefik
check_service n8n
check_service postgres
check_service redis
check_service postiz
check_service short-video-maker

# 11. Настройка cron
chmod +x ./backup_n8n.sh
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/n8n-install/backup_n8n.sh >> /opt/n8n-install/backup.log 2>&1") | crontab -

# 12. Уведомление в Telegram
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
    -d chat_id=$TG_USER_ID \
    -d text="✅ Установка завершена! Доступно:
• n8n: https://n8n.$BASE_DOMAIN
• Postiz: https://postiz.$BASE_DOMAIN
• Short Video Maker: https://short-video-maker.$BASE_DOMAIN"

# 13. Финальная проверка
echo "🔎 Проверка состояния сервисов..."
for service in n8n postiz short-video-maker; do
    if docker compose ps $service | grep -q "running"; then
        echo "✅ $service работает нормально"
    else
        echo "❌ $service имеет проблемы. Проверьте логи: docker compose logs $service"
    fi
done

# 14. Финальный вывод
echo "📦 Активные контейнеры:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo "🎉 Установка завершена! Доступные сервисы:"
echo " • n8n: https://n8n.$BASE_DOMAIN"
echo " • Postiz: https://postiz.$BASE_DOMAIN"
echo " • Short Video Maker: https://short-video-maker.$BASE_DOMAIN"
echo ""
echo "ℹ️ Если какие-то сервисы недоступны, проверьте логи командой:"
echo " docker compose logs [n8n|postiz|short-video-maker]"
