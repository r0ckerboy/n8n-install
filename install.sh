#!/bin/bash

set -e

### === ПЕРЕМЕННЫЕ === ###
read -p "Введите домен (например n8n.example.com): " DOMAIN
read -p "Введите email (для SSL): " EMAIL
read -p "Введите токен Telegram-бота: " TG_BOT_TOKEN
read -p "Введите ваш Telegram ID: " TG_USER_ID
read -p "Введите пароль от Postgres: " POSTGRES_PASSWORD

ENCRYPTION_KEY=$(uuidgen)
BASE=/opt/n8n-install

### === ПОКАЗЫВАЕМ КЛЮЧ === ###
echo "\n→ Сгенерирован ключ шифрования: $ENCRYPTION_KEY"

### === УСТАНОВКА DEPENDENCIES === ###
echo "→ Устанавливаем curl, git, docker..."
apt update && apt install -y \
  curl git ufw nginx certbot python3-certbot-nginx \
  ca-certificates gnupg lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update && apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

### === КОПИРУЕМ ПЕРЕМЕННЫЕ === ###
mkdir -p $BASE/env
cat <<EOF > $BASE/env/.env
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_USER_ID="$TG_USER_ID"
ENCRYPTION_KEY="$ENCRYPTION_KEY"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
EOF

### === СОЗДАЕМ VOLUMES === ###
mkdir -p $BASE/n8n_data $BASE/db_data $BASE/redis_data $BASE/n8n_data/backups
chown -R 1000:1000 $BASE/n8n_data

### === СТРОИМ КОНТЕЙНЕР === ###
echo "→ Собираем Docker...
docker compose -f $BASE/docker-compose.yml build

echo "→ Запускаем docker-compose..."
docker compose -f $BASE/docker-compose.yml up -d

### === ТЕЛЕГРАМ-БОТ === ###
echo "→ Запускаем Telegram-бота..."
npm install -g pm2
pm install
pm run build || true

pm2 start $BASE/bot/bot.js --name n8n-bot
pm2 save
pm2 startup systemd -u root --hp /root

### === КРОН ЗАДАЧА === ###
echo "→ Настраиваем cron для бэкапа..."
mkdir -p $BASE/cron
cp $BASE/backup_n8n.sh $BASE/cron/backup_n8n.sh
chmod +x $BASE/cron/backup_n8n.sh
cat <<EOF > $BASE/cron/.env
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_USER_ID="$TG_USER_ID"
EOF

if (crontab -l 2>/dev/null; echo "0 3 * * * $BASE/cron/backup_n8n.sh") | crontab -; then
  echo "✅ Cron задача установлена"
else
  echo "❌ Cron не добавился. Сделай это вручную:"
  echo "(crontab -l 2>/dev/null; echo \"0 3 * * * $BASE/cron/backup_n8n.sh\") | crontab -"
fi

### === ЗАВЕРШЕНИЕ === ###
echo "\n✅ Установка завершена. Откройте https://$DOMAIN"
