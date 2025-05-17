#!/bin/bash
set -euo pipefail

# === Настройка логов ===
LOG_FILE="/opt/n8n-install/backups/debug.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "🟡 backup_n8n.sh начался: $(date '+%Y-%m-%d %H:%M:%S')"

# === Конфигурация ===
BACKUP_DIR="/opt/n8n-install/backups"
mkdir -p "$BACKUP_DIR"
NOW=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE_NAME="n8n-backup-$NOW.zip"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
TEMP_DIR=$(mktemp -d)
BASE_DIR="/opt/n8n-install"
ENV_FILE="$BASE_DIR/.env"

# === Проверка зависимостей ===
check_dependencies() {
  for cmd in docker zip curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "❌ Ошибка: команда $cmd не найдена"
      exit 1
    fi
  done
}

# === Загрузка переменных окружения ===
load_env() {
  if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
  else
    echo "❌ Файл .env не найден"
    exit 1
  fi
}

# === Отправка уведомления в Telegram ===
send_telegram() {
  local message="$1"
  local file="$2"
  
  if [ -z "$file" ]; then
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
      -d chat_id="$TG_USER_ID" \
      -d text="$message"
  else
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
      -F chat_id="$TG_USER_ID" \
      -F document=@"$file" \
      -F caption="$message"
  fi
}

# === Экспорт данных из n8n ===
export_data() {
  local type=$1
  local output_file=$2
  
  echo "🔧 Экспорт $type..."
  if docker exec n8n-app n8n export:$type --all --output="/tmp/n8n_$type.json"; then
    if docker cp "n8n-app:/tmp/n8n_$type.json" "$output_file"; then
      echo "✅ $type успешно экспортированы"
      return 0
    fi
  fi
  
  echo "⚠️ Не удалось экспортировать $type"
  return 1
}

# === Основной процесс ===
main() {
  check_dependencies
  load_env

  # Экспорт workflows
  if ! export_data "workflow" "$TEMP_DIR/workflows.json"; then
    send_telegram "❌ Ошибка: не удалось экспортировать workflows. Бэкап прерван."
    exit 1
  fi

  # Экспорт credentials (опционально)
  if ! export_data "credentials" "$TEMP_DIR/credentials.json"; then
    echo "⚠️ Создаю пустой файл credentials"
    echo '{}' > "$TEMP_DIR/credentials.json"
  fi

  # Бэкап PostgreSQL
  echo "🔧 Создание дампа PostgreSQL..."
  if docker exec n8n-postgres pg_dump -U n8n -d n8n > "$TEMP_DIR/postgres.sql"; then
    echo "✅ Дамп PostgreSQL создан"
  else
    echo "⚠️ Не удалось создать дамп PostgreSQL"
  fi

  # Создание архива
  echo "📦 Создание архива..."
  if zip -jrq "$ARCHIVE_PATH" "$TEMP_DIR"/*; then
    echo "✅ Архив создан: $ARCHIVE_PATH"
    send_telegram "✅ Бэкап n8n успешно завершен ($NOW)" "$ARCHIVE_PATH"
  else
    echo "❌ Ошибка при создании архива"
    send_telegram "❌ Ошибка при создании архива бэкапа"
    exit 1
  fi

  # Очистка
  rm -rf "$TEMP_DIR"
  find "$BACKUP_DIR" -name "n8n-backup-*.zip" -mtime +7 -delete
  echo "🟢 Бэкап успешно завершен: $(date '+%Y-%m-%d %H:%M:%S')"
}

main
