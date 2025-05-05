const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;

const bot = new TelegramBot(token, { polling: true });

function isAuthorized(msg) {
  return String(msg.chat.id) === String(userId);
}

bot.onText(/\/start/, (msg) => {
  if (!isAuthorized(msg)) return;
  bot.sendMessage(msg.chat.id, '🤖 Доступные команды: /status /logs /backups /update');
});

bot.onText(/\/status/, async (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const uptime = execSync('uptime -p').toString().trim();
    const containers = execSync('docker ps --format "{{.Names}} ({{.Status}})"').toString().trim();
    bot.sendMessage(msg.chat.id, `🟢 Сервер работает
⏱ Uptime: ${uptime}

📦 Контейнеры:
${containers}`);
  } catch (err) {
    bot.sendMessage(msg.chat.id, '❌ Ошибка при получении статуса');
  }
});

bot.onText(/\/logs/, async (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const logs = execSync('docker logs --tail=50 n8n-app').toString();
    bot.sendMessage(msg.chat.id, `📝 Логи n8n:
\`\`\`
${logs}
\`\`\``, { parse_mode: 'Markdown' });
  } catch (err) {
    bot.sendMessage(msg.chat.id, '❌ Не удалось получить логи');
  }
});

bot.onText(/\/backups/, async (msg) => {
  if (!isAuthorized(msg)) return;
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupName = `n8n_backup_${timestamp}.tar.gz`;
  const backupPath = `/tmp/${backupName}`;

  try {
    const files = [];
    if (fs.existsSync('/home/node/.n8n/workflows.json')) files.push('/home/node/.n8n/workflows.json');
    if (fs.existsSync('/home/node/.n8n/credentials.json')) files.push('/home/node/.n8n/credentials.json');

    if (files.length === 0) {
      bot.sendMessage(msg.chat.id, '❌ Нет доступных данных для бэкапа');
      return;
    }

    execSync(`tar -czf ${backupPath} ${files.join(' ')}`);
    bot.sendDocument(msg.chat.id, backupPath, {}, {
      filename: backupName,
      contentType: 'application/gzip'
    }).then(() => fs.unlinkSync(backupPath));
  } catch (err) {
    bot.sendMessage(msg.chat.id, '❌ Ошибка при создании бэкапа');
  }
});

bot.onText(/\/update/, async (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const latest = execSync('npm view n8n version').toString().trim();
    const current = execSync('docker exec n8n-app n8n -v').toString().trim();

    if (latest === current) {
      bot.sendMessage(msg.chat.id, `✅ У вас уже последняя версия n8n (${current})`);
    } else {
      bot.sendMessage(msg.chat.id, `⏬ Обновляю n8n c ${current} до ${latest}...`);
      execSync('docker pull n8nio/n8n');
      execSync('docker compose stop n8n');
      execSync('docker compose rm -f n8n');
      execSync('docker compose up -d --no-deps --build n8n');
      bot.sendMessage(msg.chat.id, `✅ n8n обновлён до версии ${latest}`);
    }
  } catch (err) {
    bot.sendMessage(msg.chat.id, '❌ Обновление завершилось с ошибкой');
  }
});
