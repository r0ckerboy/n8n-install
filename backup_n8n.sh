#!/bin/bash
set -e

# === Пути ===
DATE=$(date +"%Y-%m-%d-%H-%M")
DIR="/opt/n8n-install"
BACKUP_DIR="$DIR/backups"
N8N_CONTAINER="n8n-app"
ZIP_NAME="n8n-backup-$DATE.zip"
TMP_PATH="/tmp/$ZIP_NAME"

# === Переменные из .env ===
source "$DIR/.env"
BOT_TOKEN="$TG_BOT_TOKEN"
USER_ID="$TG_USER_ID"

# === Логи ===
LOG_FILE="$DIR/logs/backup.log"
mkdir -p "$DIR/logs"
mkdir -p "$BACKUP_DIR"

# === Логирование ===
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOG_FILE"
}

log "🚀 Запуск резервного копирования"

# === Получение файлов из контейнера ===
log "📥 Экспортируем workflows и credentials"
docker exec "$N8N_CONTAINER" n8n export:workflow --all --output=/data/workflows.json
docker exec "$N8N_CONTAINER" n8n export:credentials --all --decrypted --output=/data/credentials.json

# === Копируем из volume на хост ===
cp "$DIR/data/workflows.json" "$BACKUP_DIR/workflows-$DATE.json"
cp "$DIR/data/credentials.json" "$BACKUP_DIR/credentials-$DATE.json"

# === Создание архива ===
cd "$BACKUP_DIR"
zip -q "$TMP_PATH" "workflows-$DATE.json" "credentials-$DATE.json"

# === Очистка лишнего
rm "workflows-$DATE.json" "credentials-$DATE.json"

# === Отправка в Telegram
log "📤 Отправка архива в Telegram"
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
  -F chat_id="$USER_ID" \
  -F document=@"$TMP_PATH" \
  -F caption="📦 Резервная копия n8n от $DATE"

log "✅ Резервное копирование завершено"
