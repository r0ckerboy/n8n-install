#!/bin/bash
set -e

# --- КОНСОЛЬ НЕТРАННЕРА ---
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_NC='\033[0m' # No Color

log_jack_in() { echo -e "${C_CYAN}>_ [ВЗЛОМ ПОРТА]${C_NC} $1"; }
log_preem() { echo -e "${C_GREEN}>_ [ВЫШАК]${C_NC} $1"; }
log_glitch() { echo -e "${C_YELLOW}>_ [ГЛИТЧ]${C_NC} $1"; }
log_flatline() { echo -e "${C_RED}>_ [ФЛЭТЛАЙН]${C_NC} $1"; exit 1; }

# --- ГЛАВНАЯ ПОСЛЕДОВАТЕЛЬНОСТЬ ---
clear
echo -e "${C_CYAN}"
cat << "EOF"
  _   _   _   _   _   _   _     _   _    _   _   _ 
 / \ / \ / \ / \ / \ / \ / \   / \ / \  / \ / \ / \ 
( К | О | Н | Т | Е | Н | Т ) ( З | А )( В | О | Д )    
 \_/ \_/ \_/ \_/ \_/ \_/ \_/   \_/ \_/  \_/ \_/ \_/     

> [СИСТЕМА ОНЛАЙН]: K O N T E N T - З А В О Д
> [СТАТУС]: ЗАГРУЗКА... // NIGHT CITY v2.0.77
EOF
echo -e "${C_NC}"
echo "----------------------------------------------------"

# ВАЖНЫЙ ФИКС: Начинаем из безопасной домашней директории
cd ~

# Проверка доступа уровня "Бог"
if (( EUID != 0 )); then
    log_flatline "Доступ только для корпо-крыс. Нужны права root."
fi

# Установка имплантов
log_jack_in "Сканирую систему на необходимое железо..."
DEPS=("git" "curl" "docker.io" "docker-compose-v2")
PACKAGES_TO_INSTALL=()
for dep in "${DEPS[@]}"; do
    if ! command -v "${dep//-v2/}" &>/dev/null; then
        PACKAGES_TO_INSTALL+=("$dep")
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    log_jack_in "Заливаю новый софт: ${PACKAGES_TO_INSTALL[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}"
else
    log_preem "Системное железо в полном порядке."
fi

# Загрузка чертежей
INSTALL_DIR="/opt/n8n-stack"
if [ -d "$INSTALL_DIR" ]; then
    log_glitch "Обнаружены остаточные данные в $INSTALL_DIR. Зачищаю..."
    rm -rf "$INSTALL_DIR"
fi
log_jack_in "Качаю чертежи из Сети..."
git clone https://github.com/r0ckerboy/n8n-beget-install.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Запрос данных для заказа
log_jack_in "Фиксер требует твои данные для этого дельца:"
read -p "- Твой ДОМЕН (e.g., example.com): " BASE_DOMAIN
read -p "- Мыло для LETSENCRYPT (для шифровки канала): " LETSENCRYPT_EMAIL
read -sp "- Пароль от хранилища данных Postgres: " POSTGRES_PASSWORD
echo
read -p "- API-ключ от Pexels: " PEXELS_API_KEY
read -p "- Токен для Telegram-бота: " TELEGRAM_BOT_TOKEN
read -p "- Твой личный ID в Telegram: " TELEGRAM_USER_ID

# Генерация ключа шифрования
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
log_preem "Сгенерирован ключ шифрования AES-256."

# Создание файла с паролями
cp .env.template .env
sed -i "s|BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" .env
sed -i "s|LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}|" .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" .env
sed -i "s|N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}|" .env
sed -i "s|PEXELS_API_KEY=.*|PEXELS_API_KEY=${PEXELS_API_KEY}|" .env
sed -i "s|TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" .env
sed -i "s|TELEGRAM_USER_ID=.*|TELEGRAM_USER_ID=${TELEGRAM_USER_ID}|" .env
log_preem "Данные доступа скомпилированы и зашифрованы."

# Создание структуры
log_jack_in "Создаю хранилища и дата-крепость..."
mkdir -p ./data/{postgres,redis,n8n,letsencrypt,videos,postiz-uploads}
touch ./data/letsencrypt/acme.json
chmod 600 ./data/letsencrypt/acme.json

# Сборка и запуск
log_jack_in "Компилирую кастомный демон n8n... (может занять время)"
docker compose build n8n
log_jack_in "ПРОБУЖДАЮ ДЕМОНОВ... (ожидайте)"
docker compose up -d

# Настройка бэкапов
log_jack_in "Программирую демона-хранителя (бэкапы каждый день в 02:00)..."
(crontab -l 2>/dev/null | grep -v "backup.sh" ; echo "0 2 * * * cd $INSTALL_DIR && ./backup.sh >> /var/log/backup.log 2>&1") | crontab -
log_preem "Демон-хранитель на страже."

# Финальное сообщение
echo "----------------------------------------------------"
log_preem "СИСТЕМА ОНЛАЙН. Дельце сделано."
echo "Доступные точки входа в Сеть:"
echo -e " > n8n: ${C_YELLOW}https://n8n.${BASE_DOMAIN}${C_NC}"
echo -e " > Postiz (Gitroom): ${C_YELLOW}https://postiz.${BASE_DOMAIN}${C_NC}"
echo -e " > Short Video Maker: ${C_YELLOW}https://svm.${BASE_DOMAIN}${C_NC}"
echo ""
log_jack_in "Дай демонам пару минут на калибровку и установку защищенного соединения."
echo -e "${C_GREEN}Не теряйся в Сети, чумба.${C_NC}"
