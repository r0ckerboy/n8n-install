#!/bin/bash
set -e

# Папки и переменные
BACKUP_DIR="/opt/n8n-install/backups"
mkdir -p "$BACKUP_DIR"
NOW=$(date +"%Y-%m-%d-%H-%M")
ARCHIVE_NAME="backup-$NOW.zip"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

BASE_DIR="/opt/n8n-install"
ENV_FILE="$BASE_DIR/.env"
EXPORT_FILE="$BASE_DIR/n8n_workflows.json"
SQL_FILE="$BASE_DIR/db.sql"

# Загружаем переменные окружения
source "$ENV_FILE"
BOT_TOKEN="$TG_BOT_TOKEN"
USER_ID="$TG_USER_ID"

# 1. Экспорт workflows
echo "📤 Экспортируем workflows..."
docker exec n8n n8n export:workflow --output=/data/export.json
docker cp n8n:/data/export.json "$EXPORT_FILE"

# 2. Ключ шифрования
echo "$N8N_ENCRYPTION_KEY" > "$BASE_DIR/encryption_key.txt"

# 3. Бэкап базы
docker exec -e PGPASSWORD=$POSTGRES_PASSWORD postgres pg_dump -U postgres -F p > "$SQL_FILE"

# 4. Архивируем
zip -j "$ARCHIVE_PATH" "$EXPORT_FILE" "$BASE_DIR/encryption_key.txt" "$ENV_FILE" "$SQL_FILE"

# 5. Отправка в Telegram
echo "📨 Отправляем архив в Telegram..."
curl -s -F document=@"$ARCHIVE_PATH" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$USER_ID&caption=📦 Бэкап n8n: $NOW"

# 6. Очистка
rm -f "$EXPORT_FILE" "$BASE_DIR/encryption_key.txt" "$SQL_FILE" "$ARCHIVE_PATH"

echo "✅ Бэкап завершён и удалён локально."
