#!/bin/bash
set -e

# === Переменные и директории ===
NOW=$(date +"%Y-%m-%d-%H-%M")
BASE_DIR="/opt/n8n-install"
ENV_FILE="$BASE_DIR/.env"
WORKFLOWS_JSON="$BASE_DIR/n8n_workflows.json"
CREDS_JSON="$BASE_DIR/n8n_credentials.json"
ARCHIVE="$BASE_DIR/backups/n8n-backup-$NOW.zip"
LOG_FILE="$BASE_DIR/logs/backup.log"

# === Загрузка переменных из .env ===
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "❗ Файл .env не найден: $ENV_FILE" >> "$LOG_FILE"
  exit 1
fi

# === Проверка токенов ===
if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_USER_ID" ]; then
  echo "❗ BOT_TOKEN или USER_ID не заданы в .env" >> "$LOG_FILE"
  exit 1
fi

# === Запуск ===
echo "🔧 backup_n8n.sh запущен: $NOW" >> "$LOG_FILE"

# === Экспорт Workflows ===
if docker exec n8n-app n8n export:workflow --all --output=/tmp/export.json; then
  docker cp n8n-app:/tmp/export.json "$WORKFLOWS_JSON"
  echo "✅ workflows экспортированы" >> "$LOG_FILE"
else
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_USER_ID" \
    -d text="⚠️ Внимание: в n8n нет ни одного workflow. Бэкап отменён."
  exit 1
fi

# === Экспорт Credentials ===
if docker exec n8n-app n8n export:credentials --all --output=/tmp/creds.json; then
  docker cp n8n-app:/tmp/creds.json "$CREDS_JSON"
  echo "✅ credentials экспортированы" >> "$LOG_FILE"
else
  echo "⚠️ Внимание: credentials отсутствуют, создаю пустой JSON" >> "$LOG_FILE"
  echo '{}' > "$CREDS_JSON"
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d chat_id="$TG_USER_ID" \
    -d text="⚠️ Внимание: в n8n нет ни одного credentials. Бэкап выполнен только для workflows."
fi

# === Архивация ===
zip -j "$ARCHIVE" "$WORKFLOWS_JSON" "$CREDS_JSON" >> "$LOG_FILE" 2>&1

# === Отправка архива в Telegram ===
curl -s -F document=@"$ARCHIVE" \
  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument?chat_id=$TG_USER_ID&caption=Backup n8n ( $NOW )" >> "$LOG_FILE" 2>&1

echo "✅ Архив отправлен в Telegram" >> "$LOG_FILE"

# === Очистка временных файлов ===
rm -f "$WORKFLOWS_JSON" "$CREDS_JSON" "$ARCHIVE"
