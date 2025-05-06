#!/bin/bash
set -e

### Проверка прав
if (( EUID != 0 )); then
  echo "❗ Скрипт должен быть запущен от root: sudo bash <(curl ...)"
  exit 1
fi

clear
echo "🌐 Установка n8n + Telegram-бота + резервное копирование"
echo "--------------------------------------------------------"

### 1. Ввод переменных
read -p "🌐 Домен (например: n8n.example.com): " DOMAIN
read -p "📧 Email для Let's Encrypt: " EMAIL
read -p "🔐 Пароль для Postgres: " POSTGRES_PASSWORD
read -p "🗝️  Ключ шифрования n8n (Enter для генерации): " N8N_ENCRYPTION_KEY
read -p "🤖 Telegram Bot Token: " TG_BOT_TOKEN
read -p "👤 Telegram User ID (для уведомлений): " TG_USER_ID

# Генерация ключа, если пустой
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
  echo "✅ Сгенерирован ключ: $N8N_ENCRYPTION_KEY"
fi

### 2. Установка Docker и Docker Compose
echo "📦 Установка Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose &>/dev/null; then
  curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true
fi

### 3. Загрузка проекта
echo "📥 Клонируем репозиторий..."
rm -rf /opt/n8n-install
git clone https://github.com/kalininlive/n8n-beget-install.git /opt/n8n-install
cd /opt/n8n-install

### 4. Создание .env файлов
echo "🧪 Создаём .env..."
cat > ".env" <<EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

echo "🧪 Создаём bot/.env..."
cat > "bot/.env" <<EOF
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

### 5. Сборка кастомного образа n8n
echo "🔧 Собираем кастомный образ n8n..."
docker build -f Dockerfile.n8n -t n8n-custom:latest .

### 6. Запуск docker-compose
echo "🚀 Запускаем docker-compose..."
docker compose up -d

### 7. Настройка cron-задачи
echo "⏰ Устанавливаем cron для бэкапа в 02:00..."
chmod +x ./backup_n8n.sh
mkdir -p logs backups
(crontab -l 2>/dev/null; echo "0 2 * * * /bin/bash /opt/n8n-install/backup_n8n.sh >> /opt/n8n-install/logs/backup.log 2>&1") | crontab -

### 8. Уведомление в Telegram
echo "📩 Отправляем сообщение в Telegram..."
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id=$TG_USER_ID \
  -d text="✅ Установка n8n завершена. Открывайте: https://$DOMAIN"

echo "🎉 Установка завершена! Перейдите на https://$DOMAIN"
