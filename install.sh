#!/bin/bash
set -e

# Проверка запуска от root
if (( EUID != 0 )); then
  echo "❗ Скрипт должен быть запущен от root: sudo bash <(curl ...)"
  exit 1
fi

clear
echo "🌐 Установка n8n + Telegram-бота + резервное копирование"
echo "--------------------------------------------------------"

# === Ввод данных ===
read -p "🌐 Домен (например: n8n.example.com): " DOMAIN
read -p "📧 Email для Let's Encrypt: " EMAIL
read -p "🔐 Пароль для Postgres: " POSTGRES_PASSWORD
read -p "🗝️  Ключ шифрования n8n (Enter для генерации): " N8N_ENCRYPTION_KEY
read -p "🤖 Telegram Bot Token: " TG_BOT_TOKEN
read -p "👤 Telegram User ID (для уведомлений): " TG_USER_ID

# Генерация ключа
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
  echo "✅ Сгенерирован ключ: $N8N_ENCRYPTION_KEY"
fi

# === Установка Docker и Docker Compose ===
echo "📦 Устанавливаем Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose &>/dev/null; then
  curl -SL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true
fi

# === Клонирование репозитория ===
echo "📥 Загружаем проект..."
rm -rf /opt/n8n-install
git clone https://github.com/kalininlive/n8n-beget-install.git /opt/n8n-install
cd /opt/n8n-install

# === Создание .env файлов ===
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

# === Создание директорий ===
echo "📁 Создаём директории logs и backups..."
mkdir -p logs backups
chmod -R 755 logs backups

# === Сборка образов ===
echo "🔧 Сборка Docker образов..."
docker build -f Dockerfile.n8n -t n8n-custom:latest .
docker compose build --no-cache

# === Запуск сервисов ===
echo "🚀 Запускаем docker-compose..."
docker compose up -d

# === Настройка cron ===
echo "⏰ Устанавливаем cron для бэкапа в 02:00..."
chmod +x ./backup_n8n.sh

(crontab -l 2>/dev/null; echo "0 2 * * * /bin/bash /opt/n8n-install/backup_n8n.sh >> /opt/n8n-install/logs/backup.log 2>&1") | crontab - || echo "⚠️ Cron не установлен автоматически. Установите вручную через crontab -e"

# === Финальный лог ===
INSTALL_LOG="/opt/n8n-install/install.log"
{
  echo "✅ Установка завершена $(date)"
  echo "🌍 Домен: $DOMAIN"
  echo "📦 Контейнеры:"
  docker ps --format "  - {{.Names}}: {{.Status}}"
} > "$INSTALL_LOG"

# === Telegram-уведомление ===
echo "📩 Уведомление в Telegram..."
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument \
  -F chat_id=$TG_USER_ID \
  -F document=@"$INSTALL_LOG" \
  -F caption="✅ Установка завершена. Домен: https://$DOMAIN"

echo "🎉 Установка завершена! Открывайте: https://$DOMAIN"
