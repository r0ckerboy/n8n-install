#!/bin/bash
set -e

# --- ФУНКЦИИ ---

# Функция для вывода цветных сообщений
log_info() {
    echo -e "\e[34mINFO\e[0m: $1"
}

log_success() {
    echo -e "\e[32mSUCCESS\e[0m: $1"
}

log_warning() {
    echo -e "\e[33mWARNING\e[0m: $1"
}

log_error() {
    echo -e "\e[31mERROR\e[0m: $1"
    exit 1
}

# Проверка прав root
check_root() {
    if (( EUID != 0 )); then
        log_error "Скрипт должен быть запущен от имени root: sudo bash $0"
    fi
}

# Установка зависимостей
install_dependencies() {
    log_info "Проверка и установка необходимых пакетов..."
    DEPS=("git" "curl" "docker.io" "docker-compose-v2")
    PACKAGES_TO_INSTALL=()

    for dep in "${DEPS[@]}"; do
        if ! command -v "${dep//-v2/}" &>/dev/null; then
            PACKAGES_TO_INSTALL+=("$dep")
        fi
    done

    if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        log_info "Будут установлены: ${PACKAGES_TO_INSTALL[*]}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        for pkg in "${PACKAGES_TO_INSTALL[@]}"; do
            apt-get install -y --no-install-recommends "$pkg"
        done
    else
        log_success "Все зависимости уже установлены."
    fi
}

# --- ОСНОВНОЙ СКРИПТ ---

clear
log_info "Запуск автоматической установки стека n8n & Co."
echo "----------------------------------------------------"

check_root
install_dependencies

# Клонирование репозитория
INSTALL_DIR="/opt/n8n-stack"
if [ -d "$INSTALL_DIR" ]; then
    log_warning "Директория $INSTALL_DIR уже существует. Удаляем для чистой установки."
    rm -rf "$INSTALL_DIR"
fi
log_info "Клонируем репозиторий в $INSTALL_DIR..."
git clone https://github.com/r0ckerboy/n8n-beget-install.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Сбор данных от пользователя
log_info "Пожалуйста, введите данные для конфигурации:"
read -p "- Базовый домен (например, example.com): " BASE_DOMAIN
read -p "- Email для SSL-сертификатов (Let's Encrypt): " LETSENCRYPT_EMAIL
read -sp "- Придумайте СЛОЖНЫЙ пароль для Postgres: " POSTGRES_PASSWORD
echo
read -p "- API ключ от Pexels: " PEXELS_API_KEY
read -p "- Токен вашего Telegram-бота: " TELEGRAM_BOT_TOKEN
read -p "- ID вашего Telegram-пользователя (получить у @userinfobot): " TELEGRAM_USER_ID

# Генерация ключа шифрования n8n
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
log_success "Сгенерирован ключ шифрования для n8n."

# Создание .env файла из шаблона
cp .env.template .env

# Замена значений в .env
sed -i "s|BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" .env
sed -i "s|LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}|" .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" .env
sed -i "s|N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}|" .env
sed -i "s|PEXELS_API_KEY=.*|PEXELS_API_KEY=${PEXELS_API_KEY}|" .env
sed -i "s|TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" .env
sed -i "s|TELEGRAM_USER_ID=.*|TELEGRAM_USER_ID=${TELEGRAM_USER_ID}|" .env

log_success ".env файл успешно сконфигурирован."

# Создание необходимых директорий и файлов
log_info "Создание директорий и файлов..."
mkdir -p ./data/postgres ./data/redis ./data/n8n ./data/letsencrypt ./data/videos
touch ./data/letsencrypt/acme.json
chmod 600 ./data/letsencrypt/acme.json

# Запуск Docker Compose
log_info "Сборка кастомного образа n8n (это может занять несколько минут)..."
docker compose build n8n

log_info "Запуск всех сервисов в фоновом режиме..."
docker compose up -d

# Настройка cron для бэкапов
log_info "Настройка ежедневного резервного копирования..."
(crontab -l 2>/dev/null | grep -v "backup.sh" ; echo "0 2 * * * cd $INSTALL_DIR && ./backup.sh >> /var/log/backup.log 2>&1") | crontab -

log_success "Cron задача для бэкапов успешно добавлена."

# Финальное сообщение
echo "----------------------------------------------------"
log_success "Установка успешно завершена!"
echo "Доступные сервисы:"
echo " • n8n: https://n8n.${BASE_DOMAIN}"
echo " • Postiz: https://postiz.${BASE_DOMAIN}"
echo " • Short Video Maker: https://svm.${BASE_DOMAIN}"
echo " • Traefik Dashboard: https://traefik.${BASE_DOMAIN}"
echo ""
log_info "Дайте системе 1-2 минуты на полный запуск и генерацию SSL-сертификатов."
