#!/bin/bash
set -e

# --- КОНФИГУРАЦИЯ ---
INSTALL_DIR="/opt/n8n-install"
REPO_URL="https://github.com/r0ckerboy/n8n-beget-install.git"

# --- ПРОВЕРКИ ---
# 1. Проверка прав (должен быть root)
if [ "\$(id -u)" -ne 0 ]; then
   echo "❗ Скрипт должен быть запущен от имени root или через sudo."
   exit 1
fi

# 2. Проверка whiptail
if ! command -v whiptail >/dev/null; then
    echo "📦 Устанавливаем необходимый компонент 'whiptail' для интерфейса..."
    apt-get update >/dev/null
    apt-get install -y whiptail >/dev/null
fi

# --- ИНТЕРФЕЙС WHIPTAIL ---
whiptail --title "Мастер установки" --msgbox "Добро пожаловать в мастер установки 'Контент Завода'!\\n\\nСейчас мы соберем все необходимые данные для автоматической настройки." 10 78

# Запрашиваем данные через красивые окна
BASE_DOMAIN=\$(whiptail --title "Шаг 1: Домен" --inputbox "Введите базовый домен (например, example.com):" 10 78 "sto-savto82.ru" 3>&1 1>&2 2>&3)
LETSENCRYPT_EMAIL=\$(whiptail --title "Шаг 2: Email" --inputbox "Введите ваш email для SSL-сертификатов:" 10 78 "user@example.com" 3>&1 1>&2 2>&3)
POSTGRES_PASSWORD=\$(whiptail --title "Шаг 3: Пароль БД" --passwordbox "Придумайте надежный пароль для базы данных Postgres:" 10 78 3>&1 1>&2 2>&3)
PEXELS_API_KEY=\$(whiptail --title "Ша- 4: Pexels API" --inputbox "Введите ваш Pexels API ключ:" 10 78 3>&1 1>&2 2>&3)
TELEGRAM_BOT_TOKEN=\$(whiptail --title "Шаг 5: Telegram Bot" --inputbox "Введите Telegram Bot Token:" 10 78 3>&1 1>&2 2>&3)
TELEGRAM_USER_ID=\$(whiptail --title "Шаг 6: Telegram ID" --inputbox "Введите ваш Telegram User ID:" 10 78 3>&1 1>&2 2>&3)

# Окно подтверждения
if ! whiptail --title "Подтверждение данных" --yesno "Пожалуйста, проверьте введенные данные:\\n\\nДомен: \$BASE_DOMAIN\\nEmail: \$LETSENCRYPT_EMAIL\\nПароль БД: (скрыт)\\nPexels API: ...\${PEXELS_API_KEY: -5}\\nTelegram Token: ...\${TELEGRAM_BOT_TOKEN: -5}\\n\\nПродолжить установку?" 15 78; then
    whiptail --title "Отмена" --msgbox "Установка отменена пользователем." 8 78
    exit 0
fi

# --- ОСНОВНАЯ ЛОГИКА УСТАНОВКИ ---
# Установка зависимостей (git, docker)
echo "📦 Проверка и установка зависимостей (git, docker)..."
apt-get update >/dev/null
apt-get install -y git curl docker.io docker-compose >/dev/null

# Подготовка директории
echo "📁 Подготовка директории \$INSTALL_DIR..."
mkdir -p \$INSTALL_DIR
cd \$INSTALL_DIR

# Клонирование репозитория
echo "📥 Клонирование файлов проекта..."
rm -rf .git
git init >/dev/null; git remote add origin \$REPO_URL >/dev/null; git fetch origin >/dev/null; git reset --hard origin/main >/dev/null

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

# Создание docker-compose.yml из правильного шаблона
echo "📦 Создание docker-compose.yml..."
cp docker-compose.template.yml docker-compose.yml

# Автоматическое исправление Dockerfile.n8n
echo "🛠️ Автоматическое исправление Dockerfile.n8n..."
if grep -q "pip3 install --upgrade pip" "Dockerfile.n8n"; then
    sed -i 's/&& pip3 install --upgrade pip//' Dockerfile.n8n
fi

# Запуск системы!
echo "🚀 Запуск системы через Docker Compose... Это может занять несколько минут."
docker compose up -d --build

# Финальное сообщение
SUCCESS_MSG="✅ Готово! Система запущена.\\n\\nЧерез несколько минут ваши сервисы будут доступны по адресам:\\n\\n- n8n:      https://n8n.\$BASE_DOMAIN\\n- Postiz:   https://postiz.\$BASE_DOMAIN\\n- SVM:      https://svm.\$BASE_DOMAIN\\n- Traefik:  https://traefik.\$BASE_DOMAIN"
whiptail --title "Установка завершена!" --msgbox "\$SUCCESS_MSG" 15 78
EOF
