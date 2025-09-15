#!/bin/bash
set -e

# Защита от CRLF (Windows-форматирования)
if file -b "$0" | grep -q CRLF; then
    echo "❗ Обнаружены CRLF-символы. Исправляем кодировку..."
    sed -i 's/\r$//' "$0"
    exec bash "$0" "$@"
fi

# Проверка прав
if (( EUID != 0 )); then
    echo "❗ Скрипт должен быть запущен от root: sudo bash $0"
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

# Исправленный блок для ключа шифрования
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    echo "✅ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"
fi

# Валидация Pexels API ключа
if [ -z "$PEXELS_API_KEY" ] || [ ${#PEXELS_API_KEY} -lt 20 ]; then
    echo "❗ Pexels API ключ обязателен и должен быть валидным (минимум 20 символов). Получи на https://www.pexels.com/api/"
    exit 1
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
mkdir -p traefik/{acme,logs} postgres-data redis-data videos data backups postiz-data
touch traefik/acme/acme.json
chmod 600 traefik/acme/acme.json
chown -R 1000:1000 data backups videos postiz-data

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
    healthcheck:
      test: ["CMD", "traefik", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3

  n8n:
    image: n8n-custom:latest
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n.$BASE_DOMAIN
      - N8N_PROTOCOL=https
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - ./data:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.rule=Host(\`n8n.$BASE_DOMAIN\`)"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:13
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
      - POSTGRES_MULTIPLE_DATABASES=postiz
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
      - ./init-postgres.sh:/docker-entrypoint-initdb.d/init.sql
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
    command: redis-server --appendonly yes

  postiz:
    image: gitroomhq/postiz-app:latest
    restart: unless-stopped
    environment:
      - DATABASE_URL=postgresql://postgres:\${POSTGRES_PASSWORD}@postgres:5432/postiz
      - REDIS_URL=redis://redis:6379
      - NEXTAUTH_URL=https://postiz.$BASE_DOMAIN
      - NEXTAUTH_SECRET=\$(openssl rand -base64 32)
    volumes:
      - ./postiz-data:/app/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.postiz.entrypoints=websecure"
      - "traefik.http.routers.postiz.rule=Host(\`postiz.$BASE_DOMAIN\`)"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    command: sh -c "npx prisma migrate deploy && npm run start"

  short-video-maker:
    image: gyoridavid/short-video-maker:latest-tiny
    restart: unless-stopped
    environment:
      - PEXELS_API_KEY=\${PEXELS_API_KEY}
      - LOG_LEVEL=debug
      - KOKORO_MODEL_PRECISION=q4
      - CONCURRENCY=1
      - VIDEO_CACHE_SIZE_IN_BYTES=2097152000
      - WHISPER_MODEL=tiny.en
      - voice=af_heart
      - orientation=portrait
      - music=chill
      - captionPosition=bottom
      - musicVolume=high
      - captionBackgroundColor=blue
      - paddingBack=1500
    volumes:
      - ./videos:/app/data/videos
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.short-video-maker.entrypoints=websecure"
      - "traefik.http.routers.short-video-maker.rule=Host(\`short-video-maker.$BASE_DOMAIN\`)"
      - "traefik.http.services.short-video-maker.loadbalancer.server.port=3123"
    depends_on:
      - traefik
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3123/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  bot:
    build: ./bot
    restart: unless-stopped
    environment:
      - TG_BOT_TOKEN=\${TG_BOT_TOKEN}
      - TG_USER_ID=\${TG_USER_ID}
EOF

# Создание init-скрипта для Postgres (отдельная БД для Postiz)
cat > "init-postgres.sh" <<EOF
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" --dbname "\$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE postiz;
    GRANT ALL PRIVILEGES ON DATABASE postiz TO postgres;
EOSQL
EOF
chmod +x init-postgres.sh

# 9. Расширенный скрипт бэкапа (backup_all.sh)
cat > "backup_all.sh" <<'EOF'
#!/bin/bash
set -e
cd /opt/n8n-install
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"
mkdir -p $BACKUP_DIR

# Бэкап n8n
docker exec postgres pg_dump -U postgres n8n > ${BACKUP_DIR}/n8n_${DATE}.sql
if [ $? -ne 0 ]; then
    curl -s -X POST https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage \
        -d chat_id=${TG_USER_ID} \
        -d text="⚠️ Ошибка бэкапа n8n: pg_dump завершился с ошибкой"
    exit 1
fi

# Бэкап Postiz
docker exec postgres pg_dump -U postgres postiz > ${BACKUP_DIR}/postiz_${DATE}.sql
if [ $? -ne 0 ]; then
    curl -s -X POST https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage \
        -d chat_id=${TG_USER_ID} \
        -d text="⚠️ Ошибка бэкапа Postiz: pg_dump завершился с ошибкой"
    exit 1
fi

# Бэкап Redis
docker exec redis redis-cli --rdb /data/dump.rdb
cp ./redis-data/dump.rdb ${BACKUP_DIR}/redis_${DATE}.rdb
if [ $? -ne 0 ]; then
    curl -s -X POST https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage \
        -d chat_id=${TG_USER_ID} \
        -d text="⚠️ Ошибка бэкапа Redis: копирование dump.rdb не удалось"
    exit 1
fi

# Бэкап видео
tar -czf ${BACKUP_DIR}/videos_${DATE}.tar.gz ./videos
if [ $? -ne 0 ]; then
    curl -s -X POST https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage \
        -d chat_id=${TG_USER_ID} \
        -d text="⚠️ Ошибка бэкапа видео: архивация не удалась"
    exit 1
fi

# Ротация: удалить старше 7 дней
find ${BACKUP_DIR} -type f -mtime +7 -delete

# Уведомление об успешном бэкапе
curl -s -X POST https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage \
    -d chat_id=${TG_USER_ID} \
    -d text="✅ Бэкапы созданы: n8n, Postiz, Redis, видео. Путь: ${BACKUP_DIR}"
EOF
chmod +x backup_all.sh

# 10. Сборка и запуск
echo "🚀 Запуск системы..."
docker build -f Dockerfile.n8n -t n8n-custom:latest . || echo "⚠️ Dockerfile.n8n не найден, используем стандартный образ n8n"
docker compose down --remove-orphans || true
docker compose up -d
echo "⏳ Ожидание запуска сервисов (до 2 минут)..."
for i in {1..12}; do
    if docker compose ps | grep -q "running"; then
        break
    fi
    sleep 10
    echo "⏳ Проверка состояния ($i/12)..."
done

# 11. Проверка состояния с OAuth-тестом для Postiz
echo "🔍 Детальная проверка состояния:"
check_service() {
    local service=$1
    local status=$(docker compose ps $service | awk 'NR==2 {print $4}')
    local health=$(docker inspect --format='{{.State.Health.Status}}' $(docker compose ps -q $service) 2>/dev/null || echo "unknown")
    if [ "$status" = "Up" ] && { [ "$health" = "healthy" ] || [ "$health" = "unknown" ]; }; then
        echo "✅ $service работает нормально (health: $health)"
        if [ "$service" = "postiz" ]; then
            sleep 5 && curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health | grep -q 200 && \
                echo "✅ Postiz health OK, настрой OAuth в UI: https://postiz.$BASE_DOMAIN" || \
                echo "⚠️ Postiz API недоступен, проверь конфигурацию или логи"
        elif [ "$service" = "short-video-maker" ]; then
            sleep 5 && curl -s -o /dev/null -w "%{http_code}" http://localhost:3123/health | grep -q 200 && \
                echo "✅ Short Video Maker health OK, Pexels ключ активен" || \
                echo "⚠️ Short Video Maker API недоступен, проверь Pexels ключ"
        fi
        return 0
    else
        echo "❌ $service имеет проблемы (статус: $status, health: $health)"
        echo "=== Логи $service ==="
        docker compose logs $service --tail=20
        return 1
    fi
}
for service in traefik n8n postgres redis postiz short-video-maker; do
    check_service $service
done

# 12. Настройка cron для бэкапов
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/n8n-install/backup_all.sh >> /opt/n8n-install/backup.log 2>&1") | crontab -
echo "✅ Cron настроен: ежедневные бэкапы в ./backups (ротация 7 дней)"

# 13. Уведомление в Telegram
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
    -d chat_id=$TG_USER_ID \
    -d text="✅ Установка завершена! Доступно:
• n8n: https://n8n.$BASE_DOMAIN
• Postiz: https://postiz.$BASE_DOMAIN (настрой OAuth для соцсетей в UI)
• Short Video Maker: https://short-video-maker.$BASE_DOMAIN (параметры: portrait/chill/af_heart/blue)"

# 14. Финальная проверка
echo "🔎 Проверка состояния сервисов..."
for service in n8n postiz short-video-maker; do
    if docker compose ps $service | grep -q "Up"; then
        echo "✅ $service работает нормально"
    else
        echo "❌ $service имеет проблемы. Проверьте логи: docker compose logs $service"
    fi
done

echo "📦 Активные контейнеры:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo "🎉 Установка завершена! Доступные сервисы:"
echo " • n8n: https://n8n.$BASE_DOMAIN"
echo " • Postiz: https://postiz.$BASE_DOMAIN (настрой OAuth для соцсетей в UI)"
echo " • Short Video Maker: https://short-video-maker.$BASE_DOMAIN (тест: POST /api/short-video)"
echo ""
echo "ℹ️ Бэкапы: ./backups (ежедневно, уведомления в Telegram). Логи: docker compose logs [service]"
echo "💡 Для Postiz: Подключи аккаунты (X, Instagram и т.д.) через OAuth в UI."
echo "💡 Для Short Video Maker: Измени voice/orientation/captionBackgroundColor в .env при необходимости."
