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
  const exportCmd = 'docker exec n8n-app n8n export:workflow --all --separate --output=/tmp/workflows';
  exec(exportCmd, (e, o, er) => {
    if (er) return send(`❌ Ошибка при экспорте: ${er}`);

    const tmpBackupDir = '/tmp/n8n_backup';
    const archivePath = '/tmp/n8n_backup.zip';

    fs.rmSync(tmpBackupDir, { recursive: true, force: true });
    fs.rmSync(archivePath, { force: true });
    fs.mkdirSync(tmpBackupDir, { recursive: true });

    exec('docker cp n8n-app:/tmp/workflows/. ' + tmpBackupDir, (e2) => {
      if (e2) return send(`❌ Не удалось скопировать файлы: ${e2}`);

      const extraFiles = [
        '/opt/n8n/n8n_data/database.sqlite',
        '/opt/n8n/n8n_data/config',
        '/opt/n8n/n8n_data/postgres_password.txt',
        '/opt/n8n/n8n_data/n8n_encryption_key.txt'
      ];

      for (const file of extraFiles) {
        if (fs.existsSync(file)) {
          const fileName = file.split('/').pop();
          fs.copyFileSync(file, `${tmpBackupDir}/${fileName}`);
        }
      }

      const output = fs.createWriteStream(archivePath);
      const archive = archiver('zip', { zlib: { level: 9 } });
      archive.pipe(output);
      archive.directory(tmpBackupDir, false);
      archive.finalize();

      output.on('close', () => {
        bot.sendDocument(TG_USER_ID, archivePath, {}, {
          filename: 'n8n_backup.zip',
          contentType: 'application/zip'
        }).then(() => {
          fs.rmSync(tmpBackupDir, { recursive: true, force: true });
          fs.rmSync(archivePath);
        }).catch(err => {
          send(`❌ Ошибка при отправке архива: ${err.message}`);
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

const { exec } = require('child_process');

bot.onText(/\/backup/, (msg) => {
  const chatId = msg.chat.id;
  bot.sendMessage(chatId, 'Запускаю бэкап…');

  exec('/opt/n8n-install/backup_n8n.sh', (error, stdout, stderr) => {
    if (error) {
      bot.sendMessage(chatId, `Ошибка при бэкапе:\n${error.message}`);
      console.error('Backup error:', error);
      return;
    }
    if (stderr) {
      bot.sendMessage(chatId, `Скрипт вернул stderr:\n${stderr}`);
      console.warn('Backup stderr:', stderr);
      return;
    }
    bot.sendMessage(chatId, `Бэкап успешно завершён:\n${stdout}`);
  });
});
