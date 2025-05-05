#!/bin/bash
set -e

### 0. Проверка прав
if (( EUID != 0 )); then
  echo "❗ Скрипт должен быть запущен от root: sudo ./install.sh"
  exit 1
fi

clear
echo "📦 Установка n8n + Telegram-бота + авто-бэкапа (чистовая версия)"
echo "--------------------------------------------------------------"

### 1. Ввод переменных от пользователя
read -p "🌐 Введите домен для n8n (например: n8n.example.com): " DOMAIN
read -p "📧 Введите email для SSL-сертификата Let's Encrypt: " EMAIL
read -p "🔐 Введите пароль для базы данных Postgres: " POSTGRES_PASSWORD
read -p "🗝️  Введите ключ шифрования для n8n (или нажмите Enter для генерации): " N8N_ENCRYPTION_KEY
read -p "🤖 Введите Telegram Bot Token: " TG_BOT_TOKEN
read -p "👤 Введите Telegram User ID (для уведомлений): " TG_USER_ID

# Автогенерация ключа, если пользователь не ввёл
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
  echo "✅ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"
fi

BASE="/opt/n8n-install"
mkdir -p "$BASE"
cd "$BASE"

### 2. Проверка и установка Docker + Compose
echo "🔍 Проверяем docker..."
if ! command -v docker &>/dev/null; then
  echo "→ Docker не найден — устанавливаем..."
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose &>/dev/null; then
  echo "→ Устанавливаем Docker Compose..."
  curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true
fi

### 3. Копирование файлов проекта
echo "📁 Копируем проект..."
cp -r /mnt/data/n8n-beget-install-main/n8n-beget-install-main/* "$BASE"

### 4. Создание .env файлов
echo "📝 Создаем переменные окружения..."

cat > "$BASE/.env" <<EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
EOF

cat > "$BASE/bot/.env" <<EOF
BOT_TOKEN=$TG_BOT_TOKEN
USER_ID=$TG_USER_ID
EOF

### 5. Сборка кастомного образа n8n
echo "🔧 Собираем кастомный образ n8n..."
docker build -f Dockerfile.n8n -t n8n-custom:latest .

### 6. Запуск docker compose
echo "🚀 Запускаем docker compose..."
docker compose up -d

### 7. Настройка cron для backup
echo "⏰ Настраиваем cron для backup..."
chmod +x "$BASE/backup_n8n.sh"
(crontab -l 2>/dev/null; echo "0 3 * * * $BASE/backup_n8n.sh >> $BASE/backup.log 2>&1") | crontab -

### 8. Уведомление в Telegram
echo "📨 Отправляем уведомление в Telegram..."
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id=$TG_USER_ID \
  -d text="✅ Установка n8n завершена. Домен: https://$DOMAIN"

echo "✅ Установка завершена. Открыть: https://$DOMAIN"
