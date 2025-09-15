#!/bin/bash
set -e

# Этот скрипт выполняется при каждом запуске контейнера.
# n8n будет устанавливать ноды, только если их еще нет.

echo "INFO: Установка community-нод для n8n..."

npm install n8n-nodes-telegram
npm install n8n-nodes-ssh

echo "SUCCESS: Community-ноды установлены."```

#### `backup.sh` (Единый скрипт бэкапа)
*   **Что изменено:** Теперь бэкапит все сервисы, архивирует в `tar.gz`, отправляет в Telegram и производит ротацию старых бэкапов.

```bash
#!/bin/bash
set -euo pipefail

# --- КОНФИГУРАЦИЯ ---
BACKUP_DIR="/opt/n8n-stack/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
BACKUP_FILENAME="stack-backup-${TIMESTAMP}.tar.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"
TEMP_DIR=$(mktemp -d)
ENV_FILE="/opt/n8n-stack/.env"

# Загрузка переменных окружения для доступа к токенам
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# --- ФУНКЦИИ ---

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

send_telegram_message() {
  if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_USER_ID}" ]; then
    log "Пропущены переменные Telegram, уведомление не отправлено."
    return
  fi
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_USER_ID}" \
    -d text="$1" \
    -d parse_mode="Markdown" > /dev/null
}

send_telegram_document() {
    if [ -z "${TELEGRAM_BOT_TOKEN}" ] || [ -z "${TELEGRAM_USER_ID}" ]; then
      log "Пропущены переменные Telegram, файл не отправлен."
      return
    fi
    curl -s -F "chat_id=${TELEGRAM_USER_ID}" \
        -F document=@"${2}" \
        -F caption="${1}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" > /dev/null
}

cleanup() {
  log "Очистка временной директории ${TEMP_DIR}"
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

# --- ОСНОВНОЙ ПРОЦЕСС ---

log "🚀 Начало процесса резервного копирования..."
mkdir -p "$BACKUP_DIR"

# 1. Бэкап базы данных PostgreSQL
log "📦 Создание дампа PostgreSQL..."
docker compose exec -T postgres pg_dumpall -U "${POSTGRES_USER}" > "${TEMP_DIR}/postgres_dump.sql"

# 2. Бэкап данных n8n (конфиги, workflows)
log "📦 Копирование данных n8n..."
cp -r /opt/n8n-stack/data/n8n "${TEMP_DIR}/n8n_data"

# 3. Бэкап данных Redis
log "📦 Копирование RDB файла Redis..."
docker compose exec redis redis-cli SAVE
cp /opt/n8n-stack/data/redis/dump.rdb "${TEMP_DIR}/redis_dump.rdb"

# 4. Копирование файла .env
log "📦 Копирование файла .env..."
cp "$ENV_FILE" "${TEMP_DIR}/"

# 5. Создание архива
log "🗜️ Архивирование данных в ${BACKUP_PATH}..."
tar -czf "${BACKUP_PATH}" -C "${TEMP_DIR}" .

# 6. Отправка в Telegram
log "📤 Отправка архива в Telegram..."
send_telegram_document "✅ Бэкап стека *${TIMESTAMP}* успешно создан." "${BACKUP_PATH}"

# 7. Ротация старых бэкапов (удаляем файлы старше 7 дней)
log "🔄 Ротация старых бэкапов..."
find "${BACKUP_DIR}" -type f -name "*.tar.gz" -mtime +7 -delete

log "✅ Процесс резервного копирования успешно завершен."
