 #!/bin/bash
 set -e

+### 0. Проверка прав
+if (( EUID != 0 )); then
+  echo "❗ Скрипт должен быть запущен от root: sudo ./install.sh"
+  exit 1
+fi

 ### 1. Ввод переменных от пользователя
 …

 ### 4. Установка базовых утилит
 echo "→ Устанавливаем зависимости..."
 sudo apt update
 sudo apt install -y curl git ufw nodejs npm

-### 5. Проверка Docker Compose
-if ! docker compose version &>/dev/null; then
-  echo "❌ Docker не найден. Установите Docker вручную: https://docs.docker.com/engine/install/ubuntu/"
-  exit 1
-fi
+### 5. Проверка и установка Docker Engine + Docker Compose
+
+# 5.1 Docker CLI
+if ! command -v docker &>/dev/null; then
+  echo "→ Docker CLI не найден — устанавливаю Docker Engine…"
+  curl -fsSL https://get.docker.com | sh
+fi
+
+# 5.2 Запуск Docker-демона
+echo "→ Включаю и запускаю службу docker…"
+systemctl enable docker 2>/dev/null || true
+systemctl start  docker 2>/dev/null || true
+
+# 5.3 Проверка доступа к демону
+if ! docker info &>/dev/null; then
+  echo "❌ Не удалось подключиться к Docker daemon."
+  echo "   Проверьте статус: systemctl status docker"
+  exit 1
+fi
+
+# 5.4 Docker Compose: v2 (плагин) или v1 (бинарь)
+if docker compose version &>/dev/null; then
+  COMPOSE_CMD="docker compose"
+elif command -v docker-compose &>/dev/null; then
+  COMPOSE_CMD="docker-compose"
+else
+  echo "→ Docker Compose не найден — ставлю плагин и бинарь…"
+  apt update
+  apt install -y docker-compose-plugin docker-compose
+  COMPOSE_CMD="docker compose"
+fi
+
+echo "→ Будем использовать: $COMPOSE_CMD"

 ### 6. Сборка и запуск контейнеров
 echo "→ Сборка и запуск n8n..."
-$COMPOSE_CMD build
+$COMPOSE_CMD build
 echo "→ Запуск контейнеров..."
-$COMPOSE_CMD up -d
+$COMPOSE_CMD up -d

### 7. Установка и запуск Telegram-бота

echo "→ Запускаем Telegram-бота..."
npm install -g pm2
pm install
pm install node-telegram-bot-api
pm install archiver
pm install axios
pm install winston

pm2 start bot/bot.js --name n8n-bot
pm2 save
pm2 startup systemd -u root --hp /root

### 8. Крон задача для бэкапа

echo "→ Настраиваем cron для авто-бэкапов..."
cp "$BASE/backup_n8n.sh" "$BASE/cron/backup_n8n.sh"
chmod +x "$BASE/cron/backup_n8n.sh"
echo "TG_BOT_TOKEN=\"$TG_BOT_TOKEN\"" > "$BASE/cron/.env"
echo "TG_USER_ID=\"$TG_USER_ID\"" >> "$BASE/cron/.env"

(crontab -l 2>/dev/null; echo "0 3 * * * $BASE/cron/backup_n8n.sh") | crontab - || echo "❗ Не удалось добавить cron-задачу"

### 9. Сохранение библиотек и версий

echo "📦 Сохраняем списки пакетов..."
docker exec -u 0 n8n-app apk info | sort > "$BASE/n8n_data/backups/n8n_installed_apk.txt" || true
docker exec -u 0 n8n-app /venv/bin/pip list > "$BASE/n8n_data/backups/n8n_installed_pip.txt" || true
{
  echo -n "yt-dlp: "; docker exec -u 0 n8n-app yt-dlp --version
  echo -n "ffmpeg: "; docker exec -u 0 n8n-app ffmpeg -version | head -n 1
  echo -n "python3: "; docker exec -u 0 n8n-app python3 --version
} > "$BASE/n8n_data/backups/n8n_versions.txt" || true

VERSIONS=$(cat "$BASE/n8n_data/backups/n8n_versions.txt")

curl -s -X POST https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage \
     -d chat_id=$TG_USER_ID \
     --data-urlencode "text=✅ Установка завершена!\n\n📄 Библиотеки:\n$VERSIONS\n\n🕒 Автобэкап: 03:00 каждый день (если cron добавлен)\n🌐 Панель: https://$DOMAIN"

### 10. Завершение

echo "✅ Установка завершена. Проверьте https://$DOMAIN в браузере."
echo "🟢 Telegram-бот запущен и добавлен в автозагрузку"
echo "🕒 Cron задача: бэкап каждый день в 03:00"
echo "📦 Списки пакетов сохранены в $BASE/n8n_data/backups/"
