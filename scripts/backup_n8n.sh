#!/bin/bash

BACKUP_DIR="/opt/n8n-install/backups"
LOG_DIR="/opt/n8n-install/logs"
VOLUME_DIR="/home/node/.n8n"  # путь внутри контейнера (volume)
NOW=$(date +"%Y-%m-%d_%H-%M")
ARCHIVE_NAME="n8n_data_backup_${NOW}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"
LOG_FILE="${LOG_DIR}/backup.log"
ENV_FILE="/opt/n8n-install/.env"

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Получаем токен и ID
BOT_TOKEN=$(grep BOT_TOKEN "$ENV_FILE" | cut -d '=' -f2)
ADMIN_ID=$(grep ADMIN_ID "$ENV_FILE" | cut -d '=' -f2)

if [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_ID" ]; then
  echo "❗ BOT_TOKEN или ADMIN_ID не найдены в .env" >> "$LOG_FILE"
  exit 1
fi

# Проверка наличия файлов
WORKFLOWS="/home/node/.n8n/workflows.json"
CREDENTIALS="/home/node/.n8n/credentials.json"

if [[ -f "$WORKFLOWS" || -f "$CREDENTIALS" ]]; then
  FILES_TO_BACKUP=()
  [[ -f "$WORKFLOWS" ]] && FILES_TO_BACKUP+=("$WORKFLOWS")
  [[ -f "$CREDENTIALS" ]] && FILES_TO_BACKUP+=("$CREDENTIALS")

  tar -czf "$ARCHIVE_PATH" "${FILES_TO_BACKUP[@]}" >> "$LOG_FILE" 2>&1

  curl -s -F chat_id="$ADMIN_ID"        -F document=@"$ARCHIVE_PATH"        -F caption="📦 Бэкап n8n workflows и credentials (${NOW})"        "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >> "$LOG_FILE" 2>&1

  rm -f "$ARCHIVE_PATH"
else
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"        -d chat_id="$ADMIN_ID"        -d text="❌ Нет сохранённых workflows и credentials на момент ${NOW}" >> "$LOG_FILE" 2>&1
fi
