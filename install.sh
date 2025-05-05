#!/usr/bin/env bash
set -euo pipefail

echo "=== 🚀 Установка n8n с Telegram-ботом ==="

read -p "Введите домен (например n8n.example.com): " DOMAIN
read -p "Введите email (для SSL): " EMAIL
read -p "Введите токен Telegram-бота: " TG_BOT_TOKEN
read -p "Введите ваш Telegram ID: " TG_USER_ID
read -p "Введите пароль от Postgres: " POSTGRES_PASSWORD

# Генерация ключа
N8N_ENCRYPTION_KEY=$(uuidgen)
echo "→ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"

# Создание директорий
mkdir -p n8n_data/{files,tmp,backups}
mkdir -p traefik_data
mkdir -p static
mkdir -p cron

touch traefik_data/acme.json
chmod 600 traefik_data/acme.json

# Сохраняем переменные в .env
cat <<EOF > .env
DOMAIN=$DOMAIN
EMAIL=$EMAIL
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
EOF

# Установка зависимостей
echo "→ Устанавливаем зависимости..."
apt update && apt install -y docker.io docker-compose nodejs npm git curl ufw

# Установка pm2
npm install -g pm2

# Установка зависимостей бота
cd bot
npm install
cd ..

# Запуск контейнеров
echo "→ Запускаем контейнеры n8n через docker-compose..."
docker compose up -d --build

# Запуск бота через pm2
echo "→ Запускаем Telegram-бота через pm2..."
pm2 start bot/bot.js --name n8n-bot
pm2 startup
pm2 save

# Копируем скрипт бэкапа
cp backup_n8n.sh cron/backup_n8n.sh
chmod +x cron/backup_n8n.sh

# Создаем .env для cron-скрипта
cat <<EOF > cron/.env
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
DOMAIN=$DOMAIN
EOF

# Установка cron задачи
echo "→ Добавляем cron-задачу для бэкапов..."
(crontab -l 2>/dev/null; echo "0 3 * * * $(pwd)/cron/backup_n8n.sh") | crontab -

# Финальное сообщение в Telegram
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id=$TG_USER_ID \
  --data-urlencode "text=✅ Установка n8n завершена!\n\nДомен: https://$DOMAIN\nКонтейнеры и бот запущены."

echo -e "\n✅ Установка завершена. Открой https://$DOMAIN"
