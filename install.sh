#!/bin/bash
# Используем bash, но добавляем защиту для 100% совместимости
set -e

# --- ПРОВЕРКА И ПЕРЕЗАПУСК ЧЕРЕЗ BASH ---
# Гарантирует, что скрипт всегда выполняется в bash, даже если вызван через sh
if [ -z "$BASH_VERSION" ]; then
    echo "Перезапуск скрипта с использованием bash..."
    exec bash "$0" "$@"
fi

# --- КОНФИГУРАЦИЯ ---
INSTALL_DIR="/opt/n8n-install"

# --- ФУНКЦИИ-ГЕНЕРАТОРЫ ФАЙЛОВ ---

# Создает исправленный Dockerfile.n8n
create_dockerfile() {
cat <<EOF > "${INSTALL_DIR}/Dockerfile.n8n"
# Базовый образ n8n
FROM n8nio/n8n:latest

USER root

# Установка системных зависимостей через apk (Alpine)
# Версия без проблемной команды обновления pip
RUN apk add --no-cache --virtual .build-deps \\
    bash \\
    curl \\
    git \\
    make \\
    g++ \\
    gcc \\
    python3 \\
    py3-pip \\
    libffi-dev \\
    openssl-dev \\
    ffmpeg

# Установка Python-библиотек с кэшированием
# Если у вас есть requirements.txt, раскомментируйте следующие строки
# COPY requirements.txt .
# RUN if [ -f requirements.txt ]; then \\
#         pip3 install --no-cache-dir -r requirements.txt; \\
#     fi

# Основные npm-пакеты (устанавливаем глобально в образ)
RUN npm install -g n8n-nodes-base n8n-nodes-chatgpt-tools

USER node
EOF
}

# Создает docker-compose.yml
create_compose_file() {
cat <<EOF > "${INSTALL_DIR}/docker-compose.yml"
services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=\${LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt-data:/letsencrypt"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(\`\${SUBDOMAIN_TRAEFIK}.\${BASE_DOMAIN}\`)"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt"
    networks:
      - web

  postgres:
    image: postgres:15
    container_name: postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=\${POSTGRES_DB}
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - internal

  redis:
    image: redis:alpine
    container_name: redis
    restart: unless-stopped
    volumes:
      - redis-data:/data
    networks:
      - internal

  n8n:
    build:
      context: .
      dockerfile: Dockerfile.n8n
    container_name: n8n
    restart: unless-stopped
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - N8N_HOST=\${SUBDOMAIN_N8N}.\${BASE_DOMAIN}
      - WEBHOOK_URL=https://\${SUBDOMAIN_N8N}.\${BASE_DOMAIN}/
      - GENERIC_TIMEZONE=\${TZ}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
    volumes:
      - n8n-data:/home/node/.n8n
    depends_on:
      - postgres
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`\${SUBDOMAIN_N8N}.\${BASE_DOMAIN}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
    networks:
      - web
      - internal

  postiz:
    image: gitroomhq/gitroom
    container_name: postiz
    restart: unless-stopped
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      - redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.postiz.rule=Host(\`\${SUBDOMAIN_POSTIZ}.\${BASE_DOMAIN}\`)"
      - "traefik.http.routers.postiz.entrypoints=websecure"
      - "traefik.http.routers.postiz.tls.certresolver=letsencrypt"
      - "traefik.http.services.postiz.loadbalancer.server.port=3000"
    networks:
      - web
      - internal

  short-video-maker:
    image: r0ckerboy/short-video-maker:latest
    container_name: short-video-maker
    restart: unless-stopped
    environment:
      - PEXELS_API_KEY=\${PEXELS_API_KEY}
      - TELEGRAM_BOT_TOKEN=\${TELEGRAM_BOT_TOKEN}
      - TELEGRAM_USER_ID=\${TELEGRAM_USER_ID}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.svm.rule=Host(\`\${SUBDOMAIN_SVM}.\${BASE_DOMAIN}\`)"
      - "traefik.http.routers.svm.entrypoints=websecure"
      - "traefik.http.routers.svm.tls.certresolver=letsencrypt"
      - "traefik.http.services.svm.loadbalancer.server.port=8001"
    networks:
      - web

volumes:
  postgres-data:
  n8n-data:
  letsencrypt-data:
  redis-data:

networks:
  web:
  internal:
EOF
}

# --- НАЧАЛО СКРИПТА ---
main() {
    # Проверка прав (должен быть root)
    if [ "\$(id -u)" -ne 0 ]; then
       whiptail --title "Ошибка" --msgbox "Скрипт должен быть запущен от имени root или через sudo." 8 78
       exit 1
    fi

    # Проверка и установка whiptail
    if ! command -v whiptail >/dev/null; then
        echo "📦 Устанавливаем необходимый компонент 'whiptail' для интерфейса..."
        apt-get update >/dev/null
        apt-get install -y whiptail >/dev/null
    fi

    whiptail --title "Мастер установки" --msgbox "Добро пожаловать в мастер установки 'Контент Завода'!\\n\\nСейчас мы соберем все необходимые данные для автоматической настройки." 10 78

    # Сбор данных
    BASE_DOMAIN=\$(whiptail --title "Шаг 1: Домен" --inputbox "Введите базовый домен (например, example.com):" 10 78 "sto-savto82.ru" 3>&1 1>&2 2>&3)
    LETSENCRYPT_EMAIL=\$(whiptail --title "Шаг 2: Email" --inputbox "Введите ваш email для SSL-сертификатов:" 10 78 "user@example.com" 3>&1 1>&2 2>&3)
    POSTGRES_PASSWORD=\$(whiptail --title "Шаг 3: Пароль БД" --passwordbox "Придумайте надежный пароль для базы данных Postgres:" 10 78 3>&1 1>&2 2>&3)
    PEXELS_API_KEY=\$(whiptail --title "Шаг 4: Pexels API" --inputbox "Введите ваш Pexels API ключ:" 10 78 3>&1 1>&2 2>&3)
    TELEGRAM_BOT_TOKEN=\$(whiptail --title "Шаг 5: Telegram Bot" --inputbox "Введите Telegram Bot Token:" 10 78 3>&1 1>&2 2>&3)
    TELEGRAM_USER_ID=\$(whiptail --title "Шаг 6: Telegram ID" --inputbox "Введите ваш Telegram User ID:" 10 78 3>&1 1>&2 2>&3)

    # Проверка, что ввод не пустой
    if [ -z "\$BASE_DOMAIN" ] || [ -z "\$LETSENCRYPT_EMAIL" ] || [ -z "\$POSTGRES_PASSWORD" ]; then
        whiptail --title "Ошибка" --msgbox "Домен, email и пароль БД не могут быть пустыми. Установка прервана." 8 78
        exit 1
    fi
    
    # Окно подтверждения
    if ! whiptail --title "Подтверждение данных" --yesno "Пожалуйста, проверьте введенные данные:\\n\\nДомен: \$BASE_DOMAIN\\nEmail: \$LETSENCRYPT_EMAIL\\nПароль БД: (скрыт)\\nPexels API: ...\${PEXELS_API_KEY: -5}\\nTelegram Token: ...\${TELEGRAM_BOT_TOKEN: -5}\\n\\nПродолжить установку?" 15 78; then
        whiptail --title "Отмена" --msgbox "Установка отменена пользователем." 8 78
        exit 0
    fi

    # Установка зависимостей
    echo "📦 Проверка и установка зависимостей (docker, docker-compose)..."
    apt-get update >/dev/null
    apt-get install -y curl docker.io docker-compose >/dev/null

    # Подготовка директории
    echo "📁 Подготовка директории \$INSTALL_DIR..."
    mkdir -p \$INSTALL_DIR
    cd \$INSTALL_DIR

    # Генерация ключа шифрования n8n
    N8N_ENCRYPTION_KEY=\$(openssl rand -hex 32)
    echo "🔑 Сгенерирован ключ шифрования для n8n."

    # Создание файла .env
    echo "📄 Создание файла конфигурации .env..."
    cat > .env << EOL
TZ=Europe/Moscow
BASE_DOMAIN=\${BASE_DOMAIN}
LETSENCRYPT_EMAIL=\${LETSENCRYPT_EMAIL}
SUBDOMAIN_N8N=n8n
SUBDOMAIN_POSTIZ=postiz
SUBDOMAIN_SVM=svm
SUBDOMAIN_TRAEFIK=traefik
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
PEXELS_API_KEY=\${PEXELS_API_KEY}
TELEGRAM_BOT_TOKEN=\${TELEGRAM_BOT_TOKEN}
TELEGRAM_USER_ID=\${TELEGRAM_USER_ID}
EOL

    # ГЕНЕРАЦИЯ ФАЙЛОВ НА ЛЕТУ
    echo "🛠️ Генерация конфигурационных файлов..."
    create_dockerfile
    create_compose_file

    # Запуск системы!
    echo "🚀 Запуск системы через Docker Compose... Это может занять несколько минут."
    docker compose up -d --build

    # Финальное сообщение
    SUCCESS_MSG="✅ Готово! Система запущена.\\n\\nЧерез несколько минут ваши сервисы будут доступны по адресам:\\n\\n- n8n:      https://n8n.\$BASE_DOMAIN\\n- Postiz:   https://postiz.\$BASE_DOMAIN\\n- SVM:      https://svm.\$BASE_DOMAIN\\n- Traefik:  https://traefik.\$BASE_DOMAIN"
    whiptail --title "Установка завершена!" --msgbox "\$SUCCESS_MSG" 15 78
}

# Вызов основной функции
main
