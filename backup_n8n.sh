#!/bin/bash

# Загружаем переменные
source /opt/n8n/cron/.env

TODAY=$(date +%F)
BASE="/opt/n8n"
ZIP_PATH="$BASE/n8n_data/backups/n8n_backup_$TODAY.zip"
TMP_DIR="$BASE/n8n_data/backups/tmp_$TODAY"

mkdir -p "$TMP_DIR"

# Экспорт workflow из контейнера n8n
docker exec -u node n8n-app n8n export:workflow --all --separate --output=/tmp/workflows
docker cp n8n-app:/tmp/workflows/. "$TMP_DIR"

# Копируем БД и конфиг (если есть)
[ -f "$BASE/n8n_data/database.sqlite" ] && cp "$BASE/n8n_data/database.sqlite" "$TMP_DIR"
[ -f "$BASE/n8n_data/config" ] && cp "$BASE/n8n_data/config" "$TMP_DIR"

# Архив
zip -j "$ZIP_PATH" "$TMP_DIR"/*

# Чистим временные файлы
rm -rf "$TMP_DIR"

# Отправка архива в Telegram
curl -F "document=@$ZIP_PATH" \
     -F "caption=📦 Бэкап n8n с $DOMAIN за $TODAY" \
     "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument?chat_id=$TG_USER_ID"

# Удаляем старые архивы
find "$BASE/n8n_data/backups" -type f -name "n8n_backup_*.zip" -mtime +7 -exec rm {} \;
