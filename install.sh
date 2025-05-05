#!/bin/bash
set -e

### 0. Проверка прав
if (( EUID != 0 )); then
  echo "❗ Скрипт должен быть запущен от root: sudo ./install.sh"
  exit 1
fi

### 1. Ввод пользовательских данных
clear
echo "📦 Установка n8n + Telegram-бота + SSL + Traefik"
echo "---------------------------------------------"

read -p "🌐 Введите домен для n8n (например: n8n.example.com): " DOMAIN
read -p "📧 Введите email для SSL (Let's Encrypt): " EMAIL
read -p "🔐 Введите пароль для базы данных Postgres: " POSTGRES_PASSWORD
read -p "🤖 Введите Telegram Bot Token: " TG_BOT_TOKEN
read -p "👤 Введите Telegram User ID: " TG_USER_ID

ENCRYPTION_KEY=$(openssl rand -base64 32)

echo ""
echo "✅ Введённые данные:"
echo "Домен:              $DOMAIN"
echo "Email (SSL):        $EMAIL"
echo "Postgres пароль:    $POSTGRES_PASSWORD"
echo "ENCRYPTION_KEY:     $ENCRYPTION_KEY"
echo "TG Bot Token:       $TG_BOT_TOKEN"
echo "TG User ID:         $TG_USER_ID"

### 2. Сохраняем .env
cat > .env <<EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
ENCRYPTION_KEY=$ENCRYPTION_KEY
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

### 3. Установка зависимостей
echo "→ Устанавливаем зависимости..."
apt update
apt install -y curl git ufw nodejs npm

### 4. Установка Docker и Compose
if ! command -v docker &>/dev/null; then
  echo "→ Docker не найден — устанавливаем..."
  curl -fsSL https://get.docker.com | sh
fi

echo "→ Запускаем Docker..."
systemctl enable docker
systemctl start docker

if ! docker info &>/dev/null; then
  echo "❌ Docker daemon не запущен"
  exit 1
fi

if docker compose version &>/dev/null; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  echo "→ Устанавливаем docker-compose плагин..."
  apt install -y docker-compose-plugin docker-compose
  COMPOSE_CMD="docker compose"
fi

echo "→ Используется: $COMPOSE_CMD"

### 5. Запуск n8n и сервисов
echo "→ Сборка и запуск n8n..."
$COMPOSE_CMD build
$COMPOSE_CMD up -d

### 6. Установка и запуск Telegram-бота
echo "→ Устанавливаем и запускаем Telegram-бота..."
npm install -g pm2
cd ./bot
npm install
pm2 start bot.js --name n8n-bot --env TG_BOT_TOKEN="$TG_BOT_TOKEN" --env TG_USER_ID="$TG_USER_ID"
pm2 save
pm2 startup systemd -u root --hp /root
cd ..

### 7. Настройка cron для бэкапа
echo "→ Настраиваем cron для авто-бэкапа..."
cp ./backup_n8n.sh ./cron/backup_n8n.sh
chmod +x ./cron/backup_n8n.sh
echo "TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"" > ./cron/.env
echo "TG_USER_ID=\"$TG_USER_ID\"" >> ./cron/.env
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/n8n-install/cron/backup_n8n.sh") | crontab - || echo "⚠️ Не удалось добавить cron-задачу"

### 8. Финал
echo ""
echo "✅ Установка завершена!"
echo "🌐 Открой: https://$DOMAIN"
echo "📩 Уведомление будет отправлено в Telegram"
