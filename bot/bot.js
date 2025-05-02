require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const fs = require('fs');
const archiver = require('archiver');

const {
  TG_BOT_TOKEN,
  TG_USER_ID,
  DOMAIN,
  POSTGRES_PASSWORD,
  N8N_ENCRYPTION_KEY
} = process.env;

if (!TG_BOT_TOKEN || !TG_USER_ID || !DOMAIN || !POSTGRES_PASSWORD || !N8N_ENCRYPTION_KEY) {
  console.error('❌ Не заданы необходимые переменные окружения.');
  process.exit(1);
}

const bot = new TelegramBot(TG_BOT_TOKEN, { polling: true });
const send = (msg, opt = {}) => bot.sendMessage(TG_USER_ID, msg, opt);

bot.onText(/\/status/, () => {
  exec('uptime && docker ps --format "{{.Names}}\t{{.Status}}"', (e, o, er) =>
    send(er ? `❌ ${er}` : `📊 *Статус:*\n\`\`\`\n${o}\n\`\`\``, { parse_mode: 'Markdown' })
  );
});

bot.onText(/\/logs/, () => {
  exec('docker logs --tail 100 n8n-app', (e, o, er) =>
    send(er ? `❌ ${er}` : `📝 *Логи n8n:*\n\`\`\`\n${o}\n\`\`\``, { parse_mode: 'Markdown' })
  );
});

bot.onText(/\/backup/, () => {
  const cmd = 'docker exec n8n-app n8n export:workflow --all --separate --output=/tmp/workflows';

  exec(cmd, (e, o, er) => {
    if (er) return send(`❌ Ошибка при экспорте воркфлоу: ${er}`);

    const tmpDir = '/tmp/n8n_backup';
    const backupDirInContainer = '/tmp/workflows';
    const backupDirOnHost = `${tmpDir}/workflows`;

    // Чистим и создаём временные директории
    exec(`rm -rf ${tmpDir} && mkdir -p ${backupDirOnHost}`, () => {
      // Копируем все JSON из контейнера на хост
      exec(`docker cp n8n-app:${backupDirInContainer}/. ${backupDirOnHost}`, () => {
        // Добавим чувствительные файлы (если есть)
        const sensitiveFiles = [
          '/opt/n8n/n8n_data/database.sqlite',
          '/opt/n8n/n8n_data/config',
          '/opt/n8n/n8n_data/postgres_password.txt',
          '/opt/n8n/n8n_data/n8n_encryption_key.txt'
        ];

        sensitiveFiles.forEach(file => {
          if (fs.existsSync(file)) {
            fs.copyFileSync(file, `${tmpDir}/${file.split('/').pop()}`);
          }
        });

        const outputPath = '/tmp/n8n_backup.zip';
        const output = fs.createWriteStream(outputPath);
        const archive = archiver('zip', { zlib: { level: 9 } });

        archive.pipe(output);
        archive.directory(tmpDir, false);
        archive.finalize();

        output.on('close', () => {
          bot.sendDocument(TG_USER_ID, outputPath);
          fs.rmSync(tmpDir, { recursive: true, force: true });
          fs.rmSync(outputPath);
        });
      });
    });
  });
});

bot.onText(/\/update/, () => {
  const cmd = `
    docker pull docker.n8n.io/n8nio/n8n:1.90.2 && \
    docker stop n8n-app && docker rm n8n-app && \
    docker run -d --name n8n-app --restart always --network n8n \
    -l "traefik.enable=true" \
    -l "traefik.http.routers.n8n.rule=Host(\\"${DOMAIN}\\")" \
    -l "traefik.http.routers.n8n.entrypoints=websecure" \
    -l "traefik.http.routers.n8n.tls.certresolver=le" \
    -l "traefik.http.services.n8n.loadbalancer.server.port=5678" \
    -e N8N_BASIC_AUTH_ACTIVE=false \
    -e N8N_PROTOCOL=https \
    -e N8N_HOST=${DOMAIN} \
    -e WEBHOOK_URL=https://${DOMAIN}/ \
    -e NODE_ENV=production \
    -e DB_TYPE=postgresdb \
    -e DB_POSTGRESDB_HOST=n8n-postgres \
    -e DB_POSTGRESDB_PORT=5432 \
    -e DB_POSTGRESDB_DATABASE=n8n \
    -e DB_POSTGRESDB_USER=user \
    -e DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD} \
    -e N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY} \
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
  exec(cmd, (e, o, er) => {
    send(er ? `❌ ${er}` : '✅ *n8n успешно обновлён!*', { parse_mode: 'Markdown' });
  });
});
