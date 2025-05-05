#!/bin/bash

set -e

### 1. Ввод переменных от пользователя

clear
echo "=== 🚀 Установка n8n с Telegram-ботом ==="
read -p "Введите домен (например n8n.example.com): " DOMAIN
read -p "Введите email (для SSL): " EMAIL
read -p "Введите токен Telegram-бота: " TG_BOT_TOKEN
read -p "Введите ваш Telegram ID: " TG_USER_ID
read -p "Введите пароль от Postgres: " DB_PASSWORD

UUID=$(cat /proc/sys/kernel/random/uuid)
echo "→ Сгенерирован ключ шифрования: $UUID"

### 2. Подготовка директорий

BASE="/opt/n8n-install"
mkdir -p "$BASE/n8n_data" "$BASE/traefik_data" "$BASE/cron"
chmod 600 "$BASE/traefik_data/acme.json" 2>/dev/null || touch "$BASE/traefik_data/acme.json" && chmod 600 "$BASE/traefik_data/acme.json"

### 3. Создание .env
cat <<EOF > .env
DOMAIN=$DOMAIN
EMAIL=$EMAIL
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
DB_PASSWORD=$DB_PASSWORD
ENCRYPTION_KEY=$UUID
EOF

### 4. Установка зависимостей

echo "→ Устанавливаем зависимости..."
sudo apt update
sudo apt install -y curl git ufw nodejs npm

### 5. Проверка Docker Compose
if ! docker compose version &>/dev/null; then
  echo "❌ Docker не найден. Установите Docker вручную: https://docs.docker.com/engine/install/ubuntu/"
  exit 1
fi

### 6. Сборка и запуск контейнеров

echo "→ Сборка и запуск n8n..."
docker compose build

echo "→ Запуск контейнеров..."
docker compose up -d

### 7. Установка и запуск Telegram-бота

echo "→ Запускаем Telegram-бота..."
npm install -g pm2
pm install
pm install node-telegram-bot-api
pm install archiver
pm install axios
pm install winston

pm2 start bot/bot.js --name n8n-bot
pm2 save
pm2 startup systemd -u root --hp /root

### 8. Крон задача для бэкапа

echo "→ Настраиваем cron для авто-бэкапов..."
cp "$BASE/backup_n8n.sh" "$BASE/cron/backup_n8n.sh"
chmod +x "$BASE/cron/backup_n8n.sh"
echo "TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"" > "$BASE/cron/.env"
echo "TG_USER_ID=\"$TG_USER_ID\"" >> "$BASE/cron/.env"

(crontab -l 2>/dev/null; echo "0 3 * * * $BASE/cron/backup_n8n.sh") | crontab - || echo "❗ Не удалось добавить cron-задачу"

### 9. Сохранение библиотек и версий

echo "📦 Сохраняем списки пакетов..."
docker exec -u 0 n8n-app apk info | sort > "$BASE/n8n_data/backups/n8n_installed_apk.txt" || true
docker exec -u 0 n8n-app /venv/bin/pip list > "$BASE/n8n_data/backups/n8n_installed_pip.txt" || true
{
  echo -n "yt-dlp: "; docker exec -u 0 n8n-app yt-dlp --version
  echo -n "ffmpeg: "; docker exec -u 0 n8n-app ffmpeg -version | head -n 1
  echo -n "python3: "; docker exec -u 0 n8n-app python3 --version
} > "$BASE/n8n_data/backups/n8n_versions.txt" || true

VERSIONS=$(cat "$BASE/n8n_data/backups/n8n_versions.txt")

curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
     -d chat_id=$TG_USER_ID \
     --data-urlencode "text=✅ Установка завершена!\n\n📄 Библиотеки:\n$VERSIONS\n\n🕒 Автобэкап: 03:00 каждый день (если cron добавлен)\n🌐 Панель: https://$DOMAIN"

### 10. Завершение

echo "✅ Установка завершена. Проверьте https://$DOMAIN в браузере."
echo "🟢 Telegram-бот запущен и добавлен в автозагрузку"
echo "🕒 Cron задача: бэкап каждый день в 03:00"
echo "📦 Списки пакетов сохранены в $BASE/n8n_data/backups/"
