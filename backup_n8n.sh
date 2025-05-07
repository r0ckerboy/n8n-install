#!/bin/sh
mkdir -p /opt/n8n-install/logs
exec > /opt/n8n-install/backups/debug.log 2>&1
echo "🟡 backup_n8n.sh начался: $(date)"
set -e
set -x

# === Конфигурация ===
BACKUP_DIR="/opt/n8n-install/backups"
mkdir -p "$BACKUP_DIR"
NOW=$(date +"%Y-%m-%d-%H-%M")
ARCHIVE_NAME="n8n-backup-$NOW.zip"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
BASE_DIR="/opt/n8n-install"
ENV_FILE="$BASE_DIR/.env"
EXPORT_WORKFLOWS="$BASE_DIR/n8n_workflows.json"
EXPORT_CREDS="$BASE_DIR/n8n_credentials.json"

# === Загрузка переменных окружения ===
. "$ENV_FILE"
BOT_TOKEN="$TG_BOT_TOKEN"
USER_ID="$TG_USER_ID"

# === Сообщение, уведомление в TG ===
send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$USER_ID" \
    -d text="$1"
}

# === Отладка запуска ===
echo "🔧 backup_n8n.sh запущен: $NOW" >> "$BACKUP_DIR/debug.log"

# === Экспорт Workflows ===
docker exec n8n-app n8n export:workflow --all --output=/tmp/export.json || true

if docker cp n8n-app:/tmp/export.json "$EXPORT_WORKFLOWS"; then
  echo "✅ workflows экспортированы"
else
  echo "⚠️ Внимание: workflow не найдены"
  send_telegram "⚠️ Внимание: в n8n нет ни одного workflow. Бэкап отменён."
  exit 1
fi

# === Экспорт Credentials ===
docker exec n8n-app n8n export:credentials --all --output=/tmp/creds.json || true

if docker cp n8n-app:/tmp/creds.json "$EXPORT_CREDS"; then
  echo "✅ credentials экспортированы"
else
  echo "⚠️ Внимание: credentials отсутствуют, создаю пустой JSON"
  echo '{}' > "$EXPORT_CREDS"
  send_telegram "⚠️ Внимание: в n8n нет ни одного credentials. Бэкап выполнен только для workflows."
fi

# === Создание архива без пароля ===
zip -j "$ARCHIVE_PATH" "$EXPORT_WORKFLOWS" "$EXPORT_CREDS"

# === Отправка архива в Telegram ===
curl -s -F "document=@$ARCHIVE_PATH" \
  "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$USER_ID&caption=Backup%20n8n%20(%20$NOW%20)" \
  && echo "✅ Архив отправлен в Telegram" >> "$BACKUP_DIR/debug.log"

# === Очистка временных файлов ===
rm -f "$EXPORT_WORKFLOWS" "$EXPORT_CREDS" "$ARCHIVE_PATH"

