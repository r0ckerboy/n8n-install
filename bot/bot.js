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

// Проверка ID пользователя
bot.on('message', (msg) => {
  if (msg.chat.id.toString() !== TG_USER_ID) {
    // Игнорируем сообщения от других пользователей
    return bot.sendMessage(msg.chat.id, "❌ У вас нет прав для использования этого бота.");
  }
});

// Команда /status
bot.onText(/\/status/, () => {
  exec('uptime && docker ps --format "{{.Names}}\t{{.Status}}"', (e, o, er) => 
    send(er ? `❌ ${er}` : `📊 *Статус:*\n\`\`\`\n${o}\n\`\`\``, { parse_mode: 'Markdown' })
  );
});

// Команда /logs
bot.onText(/\/logs/, () => {
  exec('docker logs --tail 100 n8n-app', (e, o, er) => 
    send(er ? `❌ ${er}` : `📝 *Логи n8n:*\n\`\`\`\n${o}\n\`\`\``, { parse_mode: 'Markdown' })
  );
});

// Команда /backup
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
          fs.copyFileSync(file, `${tmpBackupDir}/${path.basename(file)}`);
        }
      }

      const output = fs.createWriteStream(archivePath);
      const archive = archiver('zip', { zlib: { level: 9 } });

      archive.pipe(output);
      archive.directory(tmpBackupDir, false);
      archive.finalize();

      output.on('close', () => {
        send(`✅ Бэкап завершен и архивирован.\nСсылка для скачивания: \n\`\`\`\n${archivePath}\n\`\`\``);
      });
    });
  });
});

// Команда /update
bot.onText(/\/update/, () => {
  exec('docker pull kalininlive/n8n:yt-dlp && docker-compose down && docker-compose up -d', (e, o, er) => 
    send(er ? `❌ Ошибка при обновлении: ${er}` : `✅ Обновление завершено:\n\`\`\`\n${o}\n\`\`\``, { parse_mode: 'Markdown' })
  );
});
