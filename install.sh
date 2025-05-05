#!/usr/bin/env bash
set -euo pipefail

echo -e "=== 🚀 Установка n8n с Telegram-ботом ===\n"

# 1) Проверка docker и docker compose
if ! command -v docker &> /dev/null; then
  echo "❌ Docker не найден. Установите Docker вручную: https://docs.docker.com/engine/install/ubuntu/"
  exit 1
fi

if ! docker compose version &> /dev/null; then
  echo "❌ Docker Compose (v2) не найден. Установите его вручную: https://docs.docker.com/compose/install/linux/"
  exit 1
fi

# 2) Загрузка переменных
if [ -f .env ]; then
  echo "→ Используем .env файл"
  source .env
else
  read -p "Введите домен (например n8n.example.com): " DOMAIN
  read -p "Введите email (для SSL): " EMAIL
  read -p "Введите токен Telegram-бота: " TG_BOT_TOKEN
  read -p "Введите ваш Telegram ID: " TG_USER_ID
  read -p "Введите пароль от Postgres: " POSTGRES_PASSWORD
  N8N_ENCRYPTION_KEY=$(uuidgen)
  echo "→ Сгенерирован ключ шифрования: $N8N_ENCRYPTION_KEY"

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

# 4) Установка pm2 и зависимостей для бота
echo "→ Устанавливаем pm2 и зависимости бота..."
npm install -g pm2
cd bot && npm install && cd ..

# 5) Запуск docker-compose
echo "→ Запускаем n8n контейнеры..."
docker compose up -d --build

# 6) Запуск бота через pm2
echo "→ Запускаем Telegram-бота через pm2..."
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

# 8) Добавление cron
echo "→ Устанавливаем cron-задачу для бэкапов..."
(crontab -l 2>/dev/null; echo "0 3 * * * $(pwd)/cron/backup_n8n.sh") | crontab -

# 9) Отправка уведомления
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id=$TG_USER_ID \
  --data-urlencode "text=✅ Установка завершена!\n\n🌐 https://$DOMAIN\nБот и сервисы запущены."

echo -e "\n🎉 Готово! Открой: https://$DOMAIN"
