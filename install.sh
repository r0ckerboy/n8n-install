#!/bin/bash

# 👉 ЗАПОЛНИТЕ ЭТИ ПЕРЕМЕННЫЕ:
DOMAIN="ВАШ_ДОМЕН"              # например n8n.example.com
EMAIL="ВАША_ПОЧТА"              # например info@example.com
BASIC_AUTH_USER="ВАШ_ЛОГИН"     # логин для входа в n8n
BASIC_AUTH_PASS="ВАШ_ПАРОЛЬ"    # пароль для входа в n8n
N8N_ENCRYPTION_KEY="ВАШ_КЛЮЧ"   # любой длинный UUID
TG_BOT_TOKEN="ВАШ_ТОКЕН_БОТА"   # токен вашего Telegram бота
TG_USER_ID="ВАШ_TG_ID"          # ваш Telegram user id

# 👉 ПЕРЕД НАЧАЛОМ УБЕДИТЕСЬ, ЧТО В СИСТЕМЕ ЕСТЬ docker И docker-compose!

# 1. Обновляем пакеты
apt update && apt upgrade -y

# 2. Устанавливаем нужные пакеты
apt install -y curl gnupg2 ca-certificates lsb-release nano git unzip ufw

# 3. Ставим Node.js + NVM (если нужно будет)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts

# 4. Создаём папки
mkdir -p /opt/{n8n_data,traefik_data,n8n-admin-tg-bot}

# 5. Устанавливаем Docker образа
docker network create n8n

docker volume create n8n_db_storage
docker volume create n8n_n8n_storage
docker volume create n8n_redis_storage
docker volume create n8n_traefik_data

# 6. Запуск Postgres
docker run -d \
  --name n8n-postgres-1 \
  --restart always \
  --network n8n \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=ftHiLL9WoSf0kfO \
  -e POSTGRES_DB=n8n \
  -v n8n_db_storage:/var/lib/postgresql/data \
  postgres:11

# 7. Запуск Redis
docker run -d \
  --name n8n-redis-1 \
  --restart always \
  --network n8n \
  -v n8n_redis_storage:/data \
  redis:6-alpine

# 8. Запуск Traefik
docker run -d \
  --name n8n-traefik-1 \
  --restart always \
  --network n8n \
  -p 80:80 \
  -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/traefik_data:/etc/traefik \
  traefik:2.10.4 \
  --api.insecure=true \
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  --entrypoints.web.address=:80 \
  --entrypoints.websecure.address=:443 \
  --certificatesresolvers.myresolver.acme.tlschallenge=true \
  --certificatesresolvers.myresolver.acme.email=$EMAIL \
  --certificatesresolvers.myresolver.acme.storage=/etc/traefik/acme.json

# 9. Запуск n8n
docker run -d \
  --name n8n-n8n-1 \
  --restart always \
  --network n8n \
  -l "traefik.enable=true" \
  -l "traefik.http.routers.n8n.rule=Host(\"$DOMAIN\")" \
  -l "traefik.http.routers.n8n.entrypoints=websecure" \
  -l "traefik.http.routers.n8n.tls.certresolver=myresolver" \
  -l "traefik.http.services.n8n.loadbalancer.server.port=5678" \
  -e N8N_BASIC_AUTH_ACTIVE=true \
  -e N8N_BASIC_AUTH_USER=$BASIC_AUTH_USER \
  -e N8N_BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASS \
  -e N8N_HOST=$DOMAIN \
  -e WEBHOOK_URL=https://$DOMAIN/ \
  -e N8N_PROTOCOL=https \
  -e NODE_ENV=production \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=n8n-postgres-1 \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=user \
  -e DB_POSTGRESDB_PASSWORD=ftHiLL9WoSf0kfO \
  -e N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY \
  -e EXECUTIONS_DATA_PRUNE=true \
  -e EXECUTIONS_DATA_MAX_AGE=168 \
  -e QUEUE_BULL_REDIS_HOST=n8n-redis-1 \
  -e N8N_DEFAULT_BINARY_DATA_MODE=filesystem \
  -e GENERIC_TIMEZONE=Asia/Yekaterinburg \
  -v /opt/n8n_data/files:/files \
  -v /opt/n8n_data/tmp:/tmp \
  -v /opt/n8n_data/backups:/backups \
  docker.n8n.io/n8nio/n8n:latest

# 10. Создание Телеграм-бота

cat > /opt/n8n-admin-tg-bot/Dockerfile <<EOF
FROM node:18-alpine
WORKDIR /app
RUN apk add --no-cache docker-cli
COPY package.json .
RUN npm install
COPY bot.js .
COPY .env .
CMD ["npm", "start"]
EOF

cat > /opt/n8n-admin-tg-bot/package.json <<EOF
{
  "name": "n8n-admin-tg-bot",
  "version": "1.0.0",
  "main": "bot.js",
  "dependencies": {
    "dotenv": "^16.3.1",
    "node-telegram-bot-api": "^0.61.0"
  },
  "scripts": {
    "start": "node bot.js"
  }
}
EOF

cat > /opt/n8n-admin-tg-bot/.env <<EOF
TELEGRAM_BOT_TOKEN=$TG_BOT_TOKEN
TELEGRAM_USER_ID=$TG_USER_ID
EOF

cat > /opt/n8n-admin-tg-bot/bot.js <<EOF
require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: true });
const send = (msg, opt = {}) => bot.sendMessage(process.env.TELEGRAM_USER_ID, msg, opt);

bot.onText(/\/status/, () => {
  exec('uptime && docker ps', (error, stdout, stderr) => {
    if (error) return send(\`❌ Ошибка:\\n\${stderr}\`);
    const trimmed = stdout.slice(0, 4000);
    send(\`📊 *Статус системы:*\\n\`\`\`\n\${trimmed}\`\`\`\`, { parse_mode: 'Markdown' });
  });
});

bot.onText(/\/logs/, () => {
  exec('docker logs --tail 100 n8n-n8n-1', (error, stdout, stderr) => {
    if (error) return send(\`❌ Ошибка логов:\\n\${stderr}\`);
    const trimmed = stdout.slice(-3900);
    send(\`📝 *Логи n8n:*\\n\`\`\`\n\${trimmed}\`\`\`\`, { parse_mode: 'Markdown' });
  });
});

bot.onText(/\/backup/, () => {
  const cmd = 'docker exec n8n-n8n-1 n8n export:workflow --all --output=/tmp/workflows.json && docker cp n8n-n8n-1:/tmp/workflows.json /tmp/workflows.json';
  exec(cmd, (error, stdout, stderr) => {
    if (error) {
      send(\`❌ Ошибка бэкапа:\\n\${stderr}\`);
    } else {
      bot.sendDocument(process.env.TELEGRAM_USER_ID, '/tmp/workflows.json').catch(err => {
        send(\`❌ Ошибка отправки файла:\\n\${err.message}\`);
      });
    }
  });
});

bot.onText(/\/update/, () => {
  exec('docker pull docker.n8n.io/n8nio/n8n:latest && docker stop n8n-n8n-1 && docker rm n8n-n8n-1 && docker run -d --name n8n-n8n-1 --restart always --network n8n -l "traefik.enable=true" -l "traefik.http.routers.n8n.rule=Host(\\"'$DOMAIN'\\")" -l "traefik.http.routers.n8n.entrypoints=websecure" -l "traefik.http.routers.n8n.tls.certresolver=myresolver" -l "traefik.http.services.n8n.loadbalancer.server.port=5678" -e N8N_BASIC_AUTH_ACTIVE=true -e N8N_BASIC_AUTH_USER='$BASIC_AUTH_USER' -e N8N_BASIC_AUTH_PASSWORD='$BASIC_AUTH_PASS' -e N8N_HOST='$DOMAIN' -e WEBHOOK_URL=https://'$DOMAIN'/ -e N8N_PROTOCOL=https -e NODE_ENV=production -e DB_TYPE=postgresdb -e DB_POSTGRESDB_HOST=n8n-postgres-1 -e DB_POSTGRESDB_PORT=5432 -e DB_POSTGRESDB_DATABASE=n8n -e DB_POSTGRESDB_USER=user -e DB_POSTGRESDB_PASSWORD=ftHiLL9WoSf0kfO -e N8N_ENCRYPTION_KEY='$N8N_ENCRYPTION_KEY' -e EXECUTIONS_DATA_PRUNE=true -e EXECUTIONS_DATA_MAX_AGE=168 -e QUEUE_BULL_REDIS_HOST=n8n-redis-1 -e N8N_DEFAULT_BINARY_DATA_MODE=filesystem -e GENERIC_TIMEZONE=Asia/Yekaterinburg -v /opt/n8n_data/files:/files -v /opt/n8n_data/tmp:/tmp -v /opt/n8n_data/backups:/backups docker.n8n.io/n8nio/n8n:latest', (error, stdout, stderr) => {
    if (error) return send(\`❌ Ошибка обновления:\\n\${stderr}\`);
    send('✅ Успешно обновлено n8n!');
  });
});
EOF

# 11. Строим образ бота
cd /opt/n8n-admin-tg-bot
docker build -t n8n-admin-tg-bot .

# 12. Запускаем бота
docker run -d \
  --name n8n-admin-tg-bot \
  --restart always \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  n8n-admin-tg-bot

echo "✅ Установка завершена! Теперь откройте: https://$DOMAIN"
