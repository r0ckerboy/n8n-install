#!/bin/bash
set -e

# --- КОНФИГУРАЦИЯ ---
INSTALL_DIR="/opt/n8n-install"
REPO_URL="https://github.com/r0ckerboy/n8n-beget-install.git"

# --- ФУНКЦИИ ---
# Функция для надежного запроса ввода от пользователя
prompt_for_input() {
    local prompt_text=\$1
    local var_name=\$2
    local is_secret=\${3:-false}

    while true; do
        if [ "\$is_secret" = true ]; then
            read -p "\$prompt_text" -s "\$var_name"
            echo
        else
            read -p "\$prompt_text" "\$var_name"
        fi

        if [[ -n "\${!var_name}" ]]; then
            break
        else
            echo "❗ Ввод не может быть пустым. Попробуйте снова."
        fi
    done
}

# --- НАЧАЛО СКРИПТА ---
echo "🌐 Автоматическая установка Контент Завода (n8n + Postiz/Gitroom + SVM)"
echo "---------------------------------------------------------------------"

# 1. Проверка прав (должен быть root)
if [[ \$(id -u) -ne 0 ]]; then
   echo "❗ Скрипт должен быть запущен от имени root или через sudo."
   exit 1
fi

# 2. Установка зависимостей (git, docker)
echo "📦 Проверка и установка зависимостей..."
apt-get update >/dev/null
apt-get install -y git curl docker.io docker-compose >/dev/null

# 3. Подготовка директории
echo "📁 Подготовка директории \$INSTALL_DIR..."
mkdir -p \$INSTALL_DIR
cd \$INSTALL_DIR

# 4. Клонирование репозитория
echo "📥 Клонирование файлов проекта..."
# Удаляем старые файлы, чтобы избежать конфликтов
rm -rf .git
git init >/dev/null
git remote add origin \$REPO_URL >/dev/null
git fetch origin >/dev/null
git reset --hard origin/main >/dev/null

# 5. Сбор данных от пользователя
echo "📝 Пожалуйста, введите данные для конфигурации:"
prompt_for_input "   - Введите базовый домен (например, example.com): " BASE_DOMAIN
prompt_for_input "   - Введите ваш email для SSL-сертификатов: " LETSENCRYPT_EMAIL
prompt_for_input "   - Придумайте пароль для базы данных Postgres: " POSTGRES_PASSWORD true
prompt_for_input "   - Введите Pexels API ключ: " PEXELS_API_KEY
prompt_for_input "   - Введите Telegram Bot Token: " TELEGRAM_BOT_TOKEN
prompt_for_input "   - Введите ваш Telegram User ID: " TELEGRAM_USER_ID

# Генерация ключа шифрования n8n
N8N_ENCRYPTION_KEY=\$(openssl rand -hex 32)
echo "🔑 Сгенерирован ключ шифрования для n8n."

# 6. Создание файла .env
echo "📄 Создание файла конфигурации .env..."
cat > .env << EOL
# Переменные окружения для Контент Завода
TZ=Europe/Moscow

# Домены и Email
BASE_DOMAIN=\${BASE_DOMAIN}
LETSENCRYPT_EMAIL=\${LETSENCRYPT_EMAIL}
SUBDOMAIN_N8N=n8n
SUBDOMAIN_POSTIZ=postiz
SUBDOMAIN_SVM=svm
SUBDOMAIN_TRAEFIK=traefik

# База данных Postgres
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}

# Ключи и Токены
N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
PEXELS_API_KEY=\${PEXELS_API_KEY}
TELEGRAM_BOT_TOKEN=\${TELEGRAM_BOT_TOKEN}
TELEGRAM_USER_ID=\${TELEGRAM_USER_ID}
EOL

# 7. Создание docker-compose.yml из шаблона
# Мы просто копируем готовый шаблон, так как он уже идеален и читает все из .env
echo "📦 Создание docker-compose.yml из шаблона..."
cp docker-compose.template.yml docker-compose.yml

# 8. Автоматическое исправление Dockerfile.n8n
echo "🛠️ Автоматическое исправление Dockerfile.n8n для совместимости..."
if grep -q "pip3 install --upgrade pip" "Dockerfile.n8n"; then
    sed -i 's/&& pip3 install --upgrade pip//' Dockerfile.n8n
    echo "   - Проблема совместимости в Dockerfile.n8n исправлена."
else
    echo "   - Dockerfile.n8n уже в порядке."
fi

# 9. Запуск системы!
echo "🚀 Запуск системы через Docker Compose... Это может занять несколько минут."
docker compose up -d --build

echo "✅ Готово! Система запущена."
echo "Через несколько минут ваши сервисы будут доступны по адресам:"
echo "   - n8n:      https://n8n.\${BASE_DOMAIN}"
echo "   - Postiz:   https://postiz.\${BASE_DOMAIN}"
echo "   - SVM:      https://svm.\${BASE_DOMAIN}"
echo "   - Traefik:  https://traefik.\${BASE_DOMAIN}"
EOF
