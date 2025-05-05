#!/usr/bin/env bash
set -euo pipefail

echo "=== 🚀 Установка n8n с Telegram-ботом ==="

# 1) Установка Docker и Docker Compose
echo "→ Устанавливаем Docker..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Проверка Docker
if ! docker compose version &>/dev/null; then
  echo "❌ Docker Compose не установлен! Прервано."
  exit 1
fi

# 2) Запрос параметров или использование .env
if [ -f .env ]; then
  echo "→ Используем .env файл"
  source .env
else
  read -p "Домен (например n8n.example.com): " DOMAIN
  read -p "Email (для SSL): " EMAIL
  read -p "Telegram bot token: " TG_BOT_TOKEN
  read -p "Ваш Telegram ID: " TG_USER_ID
  read -p "Пароль от Postgres: " POSTGRES_PASSWORD
  N8N_ENCRYPTION_KEY=$(uuidgen)
  echo "→ Сгенерирован ключ: $N8N_ENCRYPTION_KEY"

  cat <<EOF > .env
DOMAIN=$DOMAIN
EMAIL=$EMAIL
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
EOF
fi

# 3) Создание директорий
mkdir -p n8n_data/{files,tmp,backups}
mkdir -p traefik_data
mkdir -p static
mkdir -p cron
touch traefik_data/acme.json
chmod 600 traefik_data/acme.json

# 4) Установка PM2 и зависимостей бота
echo "→ Устанавливаем NodeJS и PM2..."
sudo apt install -y nodejs npm
npm install -g pm2
cd bot && npm install && cd ..

# 5) Запуск docker compose
echo "→ Запуск docker compose..."
docker compose up -d --build

# 6) Запуск Telegram-бота через PM2
echo "→ Запускаем Telegram-бота..."
pm2 start bot/bot.js --name n8n-bot
pm2 save
pm2 startup | bash

# 7) Копия скрипта бэкапа
cp backup_n8n.sh cron/backup_n8n.sh
chmod +x cron/backup_n8n.sh
cat <<EOF > cron/.env
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
DOMAIN=$DOMAIN
EOF

# 8) Установка cron-задачи
echo "→ Устанавливаем cron-задачу на 03:00..."
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/n8n-install/cron/backup_n8n.sh") | crontab -

# 9) Telegram уведомление
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id=$TG_USER_ID \
  --data-urlencode "text=✅ Установка n8n завершена!\nhttps://$DOMAIN"

echo "✅ Всё готово. Открой https://$DOMAIN"
