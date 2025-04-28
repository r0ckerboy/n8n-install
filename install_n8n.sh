#!/usr/bin/env bash
set -euo pipefail

# 0) — Запрашиваем у пользователя параметры
read -p "1) Ваш домен (например: n8n.example.com): " DOMAIN
read -p "2) E-mail для ACME (Let's Encrypt): " EMAIL
read -p "3) Логин BASIC auth для n8n: " BASIC_AUTH_USER
read -s -p "4) Пароль BASIC auth для n8n: " BASIC_AUTH_PASS; echo
read -p "5) Telegram BOT_TOKEN: " TG_BOT_TOKEN
read -p "6) Ваш TG_USER_ID: " TG_USER_ID
read -s -p "7) Пароль для Postgres: " POSTGRES_PASSWORD; echo
read -p "8) Введите через пробел имена статических папок (они будут доступны по https://$DOMAIN/static/<имя>): " -a STATIC_DIRS

# 1) — Устанавливаем систему, Docker и необходимые утилиты
apt update && apt upgrade -y
apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  ufw \
  git \
  nano \
  uuid-runtime \
  openssl

# Устанавливаем Docker, если ещё не установлен
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

# Устанавливаем плагин Docker Compose v2, если нужно
if ! docker compose version &>/dev/null; then
  apt install -y docker-compose-plugin
fi

# 2) — Генерируем ключ шифрования для n8n
if command -v uuidgen &>/dev/null; then
  N8N_ENCRYPTION_KEY=$(uuidgen)
else
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
fi
echo "Сгенерирован N8N_ENCRYPTION_KEY: $N8N_ENCRYPTION_KEY"

# 3) — Настраиваем UFW
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

# 4) — Создаём структуру каталогов
BASE="/opt/n8n"
mkdir -p "$BASE"/{data,traefik,static,bot}
cd "$BASE"
for d in "${STATIC_DIRS[@]}"; do
  mkdir -p "$BASE/static/$d"
done

# Создаём acme.json для Traefik
touch "$BASE/traefik/acme.json"
chmod 600 "$BASE/traefik/acme.json"

# 5) — Генерируем .env
cat > "$BASE/.env" <<EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
BASIC_AUTH_USER=$BASIC_AUTH_USER
BASIC_AUTH_PASS=$BASIC_AUTH_PASS
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF

# 6) — Генерируем docker-compose.yml
cat > "$BASE/docker-compose.yml" <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:2.10.4
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.tlschallenge=true"
      - "--certificatesresolvers.le.acme.email=\${EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/acme.json:/acme.json:rw
    networks:
      - n8n_net

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - n8n_net

  redis:
    image: redis:7-alpine
    volumes:
      - redisdata:/data
    networks:
      - n8n_net

  n8n:
    image: n8nio/n8n:latest
    depends_on:
      - postgres
      - redis
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${BASIC_AUTH_PASS}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=user
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_HOST=${DOMAIN}
      - WEBHOOK_URL=https://${DOMAIN}/
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - GENERIC_TIMEZONE=Europe/Amsterdam
      - QUEUE_BULL_REDIS_HOST=redis
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\\"${DOMAIN}\\")"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=le"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
    volumes:
      - ./data:/home/node/.n8n
    networks:
      - n8n_net

  static:
    image: nginx:alpine
    volumes:
      - ./static:/usr/share/nginx/html:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.static.rule=Host(\\"${DOMAIN}\\") && PathPrefix(\\"/static\\")"
      - "traefik.http.routers.static.entrypoints=websecure"
      - "traefik.http.routers.static.tls.certresolver=le"
      - "traefik.http.services.static.loadbalancer.server.port=80"
    networks:
      - n8n_net

  bot:
    build: ./bot
    env_file:
      - .env
    network_mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

networks:
  n8n_net:

volumes:
  pgdata:
  redisdata:
EOF

# 7) — Генерируем файлы Telegram-бота
cat > "$BASE/bot/Dockerfile" <<EOF
FROM node:18-alpine
WORKDIR /app
RUN apk add --no-cache docker-cli
COPY package.json bot.js .env ./
RUN npm install
CMD ["npm","start"]
EOF

cat > "$BASE/bot/package.json" <<EOF
{
  "name": "n8n-admin-tg-bot",
  "version": "1.0.0",
  "main": "bot.js",
  "dependencies": {
    "dotenv": "^16.3.1",
    "node-telegram-bot-api": "^0.61.0"
  }
}
EOF

cat > "$BASE/bot/bot.js" <<EOF
require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const bot = new TelegramBot(process.env.TG_BOT_TOKEN, { polling: true });
const send = (msg,opt={}) => bot.sendMessage(process.env.TG_USER_ID, msg, opt);

bot.onText(/\\/status/, () => {
  exec('uptime && docker ps --format "{{.Names}}\\t{{.Status}}"', (e,o,er) =>
    send(er ? \`❌ \${er}\` : \`📊 *Статус:*\n\`\`\`\n\${o}\n\`\`\`\`, { parse_mode:'Markdown' })
  );
});

bot.onText(/\\/logs/, () => {
  exec('docker logs --tail 100 n8n', (e,o,er) =>
    send(er ? \`❌ \${er}\` : \`📝 *Логи n8n:*\n\`\`\`\n\${o}\n\`\`\`\`, { parse_mode:'Markdown' })
  );
});

bot.onText(/\\/backup/, () => {
  const cmd = 'docker exec n8n n8n export:workflow --all --output=/tmp/all.json && docker cp n8n:/tmp/all.json /tmp/all.json';
  exec(cmd, (e,o,er) => {
    if (er) return send(\`❌ \${er}\`);
    bot.sendDocument(process.env.TG_USER_ID, '/tmp/all.json');
  });
});

bot.onText(/\\/update/, () => {
  exec('docker pull n8nio/n8n:latest && docker compose up -d n8n', (e,o,er) =>
    send(er ? \`❌ \${er}\` : '✅ *n8n обновлён!*', { parse_mode:'Markdown' })
  );
});
EOF

# 8) — Запускаем стэк
cd "$BASE"
docker compose pull
docker compose up -d

echo
echo "✅ Установка завершена! Перейдите в браузере по адресу: https://$DOMAIN"
