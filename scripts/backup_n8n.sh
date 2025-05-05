#!/bin/bash

# Папки
BACKUP_DIR="/opt/n8n-install/backups"
LOG_DIR="/opt/n8n-install/logs"
DATA_DIR="/opt/n8n-install/data"

# Имя архива
NOW=$(date +"%Y-%m-%d_%H-%M")
ARCHIVE_NAME="n8n_backup_${NOW}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

# Создание директорий
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Лог-файл
LOG_FILE="${LOG_DIR}/backup.log"

# Файл с ENV (если есть)
ENV_FILE="/opt/n8n-install/.env"

# Шифруем ключ
if [ -f "$ENV_FILE" ]; then
  ENCRYPTION_KEY=$(grep N8N_ENCRYPTION_KEY "$ENV_FILE" | cut -d '=' -f2)
else
  ENCRYPTION_KEY="no_key"
fi

# Архивирование
tar -czf "$ARCHIVE_PATH" \
  /opt/n8n-install/docker-compose.yml \
  /opt/n8n-install/Dockerfile.n8n \
  /opt/n8n-install/.env \
  /opt/n8n-install/data \
  /root/.n8n \
  2>>"$LOG_FILE"

# Отправка в Telegram
BOT_TOKEN=$(grep BOT_TOKEN "$ENV_FILE" | cut -d '=' -f2)
ADMIN_ID=$(grep ADMIN_ID "$ENV_FILE" | cut -d '=' -f2)

/usr/bin/curl -s -F chat_id="$ADMIN_ID" \
  -F document=@"$ARCHIVE_PATH" \
  -F caption="📦 Бэкап n8n (${NOW})\\n🔐 ENCRYPTION_KEY: \`${ENCRYPTION_KEY}\`" \
  "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >> "$LOG_FILE"

# Удаление архива после отправки
rm -f "$ARCHIVE_PATH"
