#!/bin/bash

# Загружаем переменные
source /opt/n8n/cron/.env

TODAY=$(date +%F)
BASE="/opt/n8n"
ZIP_PATH="$BASE/n8n_data/backups/n8n_backup_$TODAY.zip"
TMP_DIR="$BASE/n8n_data/backups/tmp_$TODAY"

mkdir -p "$TMP_DIR"

# 🛠 Экспорт workflow из контейнера n8n
docker exec -u node n8n-app n8n export:workflow --all --separate --output=/tmp/workflows || true
docker cp n8n-app:/tmp/workflows/. "$TMP_DIR" 2>/dev/null || true

# 📦 Копируем БД и конфиг (если есть)
[ -f "$BASE/n8n_data/database.sqlite" ] && cp "$BASE/n8n_data/database.sqlite" "$TMP_DIR"
[ -f "$BASE/n8n_data/config" ] && cp "$BASE/n8n_data/config" "$TMP_DIR"

# 📦 Архивируем
if ls "$TMP_DIR"/* >/dev/null 2>&1; then
  zip -j "$ZIP_PATH" "$TMP_DIR"/*

  # Отправка архива в Telegram
  curl -F "document=@$ZIP_PATH" \
       -F "caption=📦 Бэкап n8n с $DOMAIN за $TODAY" \
       "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument?chat_id=$TG_USER_ID"
else
  # Нет файлов — только текст
  curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
    -d chat_id="$TG_USER_ID" \
    -d text="ℹ️ Бэкап за $TODAY: не найдено данных для сохранения."
fi

# 🧹 Очистка
rm -rf "$TMP_DIR"

# Удаляем старые архивы
find "$BASE/n8n_data/backups" -type f -name "n8n_backup_*.zip" -mtime +7 -exec rm {} \;

# Завершающее сообщение
curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
  -d chat_id="$TG_USER_ID" \
  -d text="✅ Скрипт бэкапа завершён на $DOMAIN"
