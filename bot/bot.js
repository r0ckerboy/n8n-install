require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');

const bot = new TelegramBot(process.env.TG_BOT_TOKEN, { polling: true });
const send = (msg, opt = {}) => bot.sendMessage(process.env.TG_USER_ID, msg, opt);

bot.onText(/\/status/, () => {
  exec('uptime && docker ps --format "{{.Names}}\t{{.Status}}"', (error, stdout, stderr) => {
    if (error) return send(`❌ Ошибка:\n${stderr}`);
    send(`📊 *Статус системы:*\n\`\`\`\n${stdout}\n\`\`\``, { parse_mode: 'Markdown' });
  });
});

bot.onText(/\/logs/, () => {
  exec('docker logs --tail 100 n8n-app', (error, stdout, stderr) => {
    if (error) return send(`❌ Ошибка логов:\n${stderr}`);
    send(`📝 *Логи n8n:*\n\`\`\`\n${stdout}\n\`\`\``, { parse_mode: 'Markdown' });
  });
});

bot.onText(/\/backup/, () => {
  const cmd = 'docker exec n8n-app n8n export:workflow --all --output=/tmp/workflows.json && docker cp n8n-app:/tmp/workflows.json /tmp/workflows.json';
  exec(cmd, (error, stdout, stderr) => {
    if (error) return send(`❌ Ошибка бэкапа:\n${stderr}`);
    bot.sendDocument(process.env.TG_USER_ID, '/tmp/workflows.json')
      .catch(err => send(`❌ Ошибка отправки файла:\n${err.message}`));
  });
});

bot.onText(/\/update/, () => {
  const cmd = `
    docker pull docker.n8n.io/n8nio/n8n:1.90.2 && \
    docker stop n8n-app && \
    docker rm n8n-app && \
    docker run -d --name n8n-app --restart always --network n8n \
    -l "traefik.enable=true" \
    -l "traefik.http.routers.n8n.rule=Host(\\"${process.env.DOMAIN}\\")" \
    -l "traefik.http.routers.n8n.entrypoints=websecure" \
    -l "traefik.http.routers.n8n.tls.certresolver=le" \
    -l "traefik.http.services.n8n.loadbalancer.server.port=5678" \
    -e N8N_BASIC_AUTH_ACTIVE=false \
    -e N8N_PROTOCOL=https \
    -e N8N_HOST=${process.env.DOMAIN} \
    -e WEBHOOK_URL=https://${process.env.DOMAIN}/ \
    -e NODE_ENV=production \
    -e DB_TYPE=postgresdb \
    -e DB_POSTGRESDB_HOST=n8n-postgres \
    -e DB_POSTGRESDB_PORT=5432 \
    -e DB_POSTGRESDB_DATABASE=n8n \
    -e DB_POSTGRESDB_USER=user \
    -e DB_POSTGRESDB_PASSWORD=${process.env.POSTGRES_PASSWORD} \
    -e N8N_ENCRYPTION_KEY=${process.env.N8N_ENCRYPTION_KEY} \
    -e GENERIC_TIMEZONE=Europe/Amsterdam \
    -e QUEUE_BULL_REDIS_HOST=n8n-redis \
    -e EXECUTIONS_DATA_PRUNE=true \
    -e EXECUTIONS_DATA_MAX_AGE=168 \
    -e N8N_DEFAULT_BINARY_DATA_MODE=filesystem \
    -v /opt/n8n/n8n_data/files:/files \
    -v /opt/n8n/n8n_data/tmp:/tmp \
    -v /opt/n8n/n8n_data/backups:/backups \
    docker.n8n.io/n8nio/n8n:1.90.2
  `;
  exec(cmd, (error, stdout, stderr) => {
    if (error) return send(`❌ Ошибка обновления:\n${stderr}`);
    send('✅ *n8n успешно обновлен!*', { parse_mode: 'Markdown' });
  });
});
