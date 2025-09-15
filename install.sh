#!/bin/bash

#================================================================================================
#
#   Скрипт "Космодром в Коробке"
#   Автор: Твой бро-нейросеть
#   Версия: 1.0 (Финальная)
#   Описание: Полностью автоматическая установка контент-завода на чистый сервер Ubuntu.
#   Включает: Docker, Docker Compose, Traefik (с авто-SSL), n8n, Postiz,
#   и все необходимые базы данных и кэши в изолированных контейнерах.
#
#================================================================================================

# --- ASCII Art & Intro ---
echo -e '
\033[0;32m
      _______________
     /_______________/|
    /_______________//|
   /_______________///|  Запускаем сборку "Космодрома в Коробке"!
  /_______________////|  Это финальная, полностью автономная
 /_______________/////|  версия. Пристегнись.
/________________////
|_______________|/
\033[0m
'

# --- Переменные и цвета ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Функция установки Docker и Docker Compose ---
install_docker() {
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}Docker или Docker Compose не найдены. Начинаю установку...${NC}"
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release
        
        # Добавление GPG ключа Docker
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Настройка репозитория
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update
        
        # Установка
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Проверка
        if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
            echo -e "${RED}❌ Не удалось установить Docker. Прерываю операцию.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Docker и Docker Compose успешно установлены.${NC}"
    else
        echo -e "${GREEN}✅ Docker и Docker Compose уже на месте.${NC}"
    fi
}

# --- Главный блок скрипта ---
main() {
    # --- Шаг 1: Проверки ---
    echo -e "${YELLOW}🔍 Проверка системы...${NC}"
    if [ "$(id -u)" != "0" ]; then
       echo -e "${RED}❌ Этот скрипт нужно запускать с правами root или через sudo.${NC}" 1>&2
       exit 1
    fi
    install_docker

    # --- Шаг 2: Сбор данных ---
    echo -e "\n${YELLOW}⚙️ Настройка параметров запуска. Вводи только домены, без https:// ${NC}"
    read -p "➡️ Введи домен для n8n (например, n8n.your-domain.com): " N8N_HOST
    read -p "➡️ Введи домен для Postiz (например, postiz.your-domain.com): " POSTIZ_HOST
    read -p "➡️ Введи свой email (нужен для получения SSL-сертификатов от Let's Encrypt): " LETSENCRYPT_EMAIL
    
    if [ -z "$N8N_HOST" ] || [ -z "$POSTIZ_HOST" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
        echo -e "${RED}❌ Все поля обязательны. Запусти скрипт снова.${NC}"
        exit 1
    fi

    # --- Шаг 3: Генерация конфигурации ---
    echo -e "\n${YELLOW}🛠️ Создаю сборочный цех: папки и файлы конфигурации...${NC}"
    
    # Создаем главную директорию
    mkdir -p /opt/content-factory
    cd /opt/content-factory

    # Создаем структуру под-папок
    mkdir -p traefik_data/logs data/{n8n,postgres_n8n,redis_n8n,postiz,postgres_postiz,redis_postiz} videos

    # Генерируем случайные, безопасные пароли
    POSTGRES_N8N_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    POSTGRES_POSTIZ_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    POSTIZ_ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

    # Создаем .env файл с секретами
    cat <<EOF > .env
# --- ОБЩИЕ ---
TZ=Europe/Moscow

# --- TRAEFIK ---
TRAEFIK_ACME_EMAIL=${LETSENCRYPT_EMAIL}

# --- N8N ---
N8N_HOST=${N8N_HOST}
POSTGRES_N8N_DB=n8n
POSTGRES_N8N_USER=n8n
POSTGRES_N8N_PASSWORD=${POSTGRES_N8N_PASSWORD}

# --- POSTIZ ---
POSTIZ_HOST=${POSTIZ_HOST}
POSTIZ_ADMIN_EMAIL=${LETSENCRYPT_EMAIL}
POSTIZ_ADMIN_PASSWORD=${POSTIZ_ADMIN_PASSWORD}
POSTGRES_POSTIZ_DB=postiz
POSTGRES_POSTIZ_USER=postiz
POSTGRES_POSTIZ_PASSWORD=${POSTGRES_POSTIZ_PASSWORD}
EOF

    # Создаем статическую конфигурацию для Traefik
    cat <<EOF > traefik_data/traefik.yml
global:
  checkNewVersion: true
  sendAnonymousUsage: false

log:
  level: INFO
  filePath: "/logs/traefik.log"

api:
  dashboard: true
  insecure: true # Внимание: дашборд будет доступен на порту 8080. В проде лучше защитить!

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
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${LETSENCRYPT_EMAIL}"
      storage: "/letsencrypt/acme.json"
      httpChallenge:
        entryPoint: web
EOF

    # Создаем главный docker-compose.yml
    cat <<EOF > docker-compose.yml
version: '3.9'

services:
  # --- СЕТЕВОЙ ШЛЮЗ: TRAEFIK ---
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      # - "8080:8080" # Раскомментируй, чтобы получить доступ к дашборду Traefik
    volumes:
      - ./traefik_data/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik_data/letsencrypt:/letsencrypt
      - ./traefik_data/logs:/logs
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - proxy
    labels:
      - "traefik.enable=true"

  # --- КОМАНДНЫЙ ЦЕНТР: N8N ---
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=\${N8N_HOST}
      - WEBHOOK_URL=https://\${N8N_HOST}/
      - GENERIC_TIMEZONE=\${TZ}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres_n8n
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_N8N_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_N8N_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_N8N_PASSWORD}
      - QUEUE_BULL_REDIS_HOST=redis_n8n
      - QUEUE_BULL_REDIS_PORT=6379
    volumes:
      - ./data/n8n:/home/node/.n8n
      - ./videos:/videos # Общая папка с видео
    networks:
      - proxy
      - internal
    depends_on:
      - postgres_n8n
      - redis_n8n
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`\${N8N_HOST}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  postgres_n8n:
    image: postgres:15
    container_name: postgres_n8n
    restart: unless-stopped
    environment:
      - POSTGRES_DB=\${POSTGRES_N8N_DB}
      - POSTGRES_USER=\${POSTGRES_N8N_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_N8N_PASSWORD}
    volumes:
      - ./data/postgres_n8n:/var/lib/postgresql/data
    networks:
      - internal

  redis_n8n:
    image: redis:7
    container_name: redis_n8n
    restart: unless-stopped
    networks:
      - internal

  # --- ОТДЕЛ ПУБЛИКАЦИИ: POSTIZ ---
  postiz:
    image: valkeya/postiz:latest
    container_name: postiz
    restart: unless-stopped
    environment:
      - APP_URL=https://\${POSTIZ_HOST}
      - APP_ENV=production
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres_postiz
      - DB_PORT=5432
      - DB_DATABASE=\${POSTGRES_POSTIZ_DB}
      - DB_USERNAME=\${POSTGRES_POSTIZ_USER}
      - DB_PASSWORD=\${POSTGRES_POSTIZ_PASSWORD}
      - REDIS_HOST=redis_postiz
      - REDIS_PORT=6379
    volumes:
      - ./data/postiz:/app/storage
    networks:
      - proxy
      - internal
    depends_on:
      - postgres_postiz
      - redis_postiz
    command: >
      bash -c "php artisan migrate --force &&
               (php artisan p:user:create --name=admin --email=${LETSENCRYPT_EMAIL} --password=${POSTIZ_ADMIN_PASSWORD} --role=Admin || true) &&
               php artisan serve --host=0.0.0.0 --port=8000"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.postiz.rule=Host(\`\${POSTIZ_HOST}\`)"
      - "traefik.http.routers.postiz.entrypoints=websecure"
      - "traefik.http.routers.postiz.tls.certresolver=letsencrypt"
      - "traefik.http.services.postiz.loadbalancer.server.port=8000"

  postgres_postiz:
    image: postgres:15
    container_name: postgres_postiz
    restart: unless-stopped
    environment:
      - POSTGRES_DB=\${POSTGRES_POSTIZ_DB}
      - POSTGRES_USER=\${POSTGRES_POSTIZ_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_POSTIZ_PASSWORD}
    volumes:
      - ./data/postgres_postiz:/var/lib/postgresql/data
    networks:
      - internal

  redis_postiz:
    image: redis:7
    container_name: redis_postiz
    restart: unless-stopped
    networks:
      - internal

  # --- СБОРОЧНЫЙ ЦЕХ: SHORT VIDEO MAKER (шаблон для запуска) ---
  short-video-maker:
    image: ghcr.io/ouo-app/short-video-maker:latest
    volumes:
      - ./videos:/app/videos
    working_dir: /app/videos
    # Этот сервис не имеет портов и не запускается постоянно.
    # Вызывается из n8n командой:
    # docker-compose run --rm short-video-maker --help
    
networks:
  proxy:
    name: proxy
  internal:
    name: internal
    internal: true
EOF

    echo -e "${GREEN}✅ Все файлы конфигурации успешно созданы в /opt/content-factory${NC}"

    # --- Шаг 4: Запуск ---
    echo -e "\n${YELLOW}🚀 Запускаю двигатели... Скачиваю образы и поднимаю сервисы. Это может занять несколько минут...${NC}"
    
    docker-compose up -d

    # --- Финальный вывод ---
    SERVER_IP=$(curl -s ifconfig.me)
    echo -e "\n\n${GREEN}🎉🎉🎉 ПОЕХАЛИ! Твой контент-завод в космосе! 🎉🎉🎉${NC}"
    echo -e "-----------------------------------------------------------------"
    echo -e "           ${YELLOW}!!! ВАЖНО: СЛЕДУЮЩИЙ ШАГ !!!${NC}"
    echo -e "Направь А-записи для твоих доменов на IP-адрес сервера: ${YELLOW}${SERVER_IP}${NC}"
    echo -e "    - ${N8N_HOST} -> ${SERVER_IP}"
    echo -e "    - ${POSTIZ_HOST} -> ${SERVER_IP}"
    echo -e "Как только DNS обновится, SSL-сертификаты будут выпущены автоматически."
    echo -e "-----------------------------------------------------------------"
    echo -e "Вот твои доступы (будут работать после обновления DNS):"
    echo -e "🔹 ${YELLOW}n8n:${NC} https://${N8N_HOST}"
    echo -e "🔹 ${YELLOW}Postiz:${NC} https://${POSTIZ_HOST}"
    echo -e "   - ${YELLOW}Логин:${NC} ${LETSENCRYPT_EMAIL}"
    echo -e "   - ${YELLOW}Пароль:${NC} ${POSTIZ_ADMIN_PASSWORD}"
    echo -e "-----------------------------------------------------------------"
    echo -e "\nДля управления используй команды из папки /opt/content-factory:"
    echo -e "  'docker-compose logs -f' - посмотреть логи"
    echo -e "  'docker-compose down'    - остановить завод"
    echo -e "\n${GREEN}Удачных полетов, бро! Теперь это не просто набор скриптов. Это настоящий продукт.${NC}"
}

# Запуск основной функции
main
