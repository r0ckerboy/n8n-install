#!/bin/bash
set -e

# === Конфигурация ===
BACKUP_DIR="/opt/n8n-install/backups"
mkdir -p "$BACKUP_DIR"
NOW=$(date +"%Y-%m-%d-%H-%M")
ARCHIVE_NAME="backup-$NOW.zip"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
BASE_DIR="/opt/n8n-install"
ENV_FILE="$BASE_DIR/.env"
EXPORT_FILE="$BASE_DIR/n8n_workflows.json"
SQL_FILE="$BASE_DIR/db.sql"

# === Загрузка переменных окружения ===
source "$ENV_FILE"
BOT_TOKEN="$TG_BOT_TOKEN"
USER_ID="$TG_USER_ID"
PASSWORD="${BACKUP_PASSWORD:-$(openssl rand -hex 8)}"

# === Обработка ошибок ===
function handle_error {
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$USER_ID" \
    -d text="❌ Ошибка при бэкапе n8n: $1"
  exit 1
}
trap 'handle_error "$BASH_COMMAND"' ERR

# === Экспорт Workflows ===
docker exec n8n n8n export:workflow --output=/data/export.json
docker cp n8n:/data/export.json "$EXPORT_FILE"

# === Сохраняем ключ шифрования ===
echo "$N8N_ENCRYPTION_KEY" > "$BASE_DIR/encryption_key.txt"

# === Бэкап базы Postgres ===
docker exec -e PGPASSWORD=$POSTGRES_PASSWORD postgres pg_dump -U postgres -F p > "$SQL_FILE"

# === Архивация с паролем ===
zip -P "$PASSWORD" -j "$ARCHIVE_PATH" "$EXPORT_FILE" "$BASE_DIR/encryption_key.txt" "$ENV_FILE" "$SQL_FILE"

# === Отправка архива в Telegram ===
curl -s -F document=@"$ARCHIVE_PATH" \
  "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$USER_ID&caption=📦 Зашифрованный бэкап n8n: $NOW"

# === Отправка пароля отдельным сообщением ===
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$USER_ID" \
  -d text="🔐 Пароль к архиву: $PASSWORD"

# === Очистка временных файлов и архива ===
rm -f "$EXPORT_FILE" "$BASE_DIR/encryption_key.txt" "$SQL_FILE" "$ARCHIVE_PATH"

# === Очистка логов старше 7 дней ===
find "$BASE_DIR" -name "*.log" -type f -mtime +7 -delete

echo "✅ Бэкап завершён и очищен."
