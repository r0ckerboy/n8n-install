const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const fs = require('fs');
require('dotenv').config();

const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;
const bot = new TelegramBot(token, { polling: true });

function isAuthorized(msg) {
  return String(msg.chat.id) === String(userId);
}

function send(text) {
  bot.sendMessage(userId, text, { parse_mode: 'Markdown' });
}

// /start — список команд
bot.onText(/\/start/, (msg) => {
  if (!isAuthorized(msg)) return;
  send('🤖 Доступные команды:\n/status — Статус контейнеров\n/logs — Логи n8n\n/backups — Бэкап вручную\n/update — Обновление n8n');
});

// /status — аптайм и контейнеры
bot.onText(/\/status/, () => {
  try {
    const uptime = execSync('uptime -p').toString().trim();
    const containers = execSync('docker ps --format "{{.Names}} ({{.Status}})"').toString().trim();
    send(`🟢 Сервер работает\n⏱ Uptime: ${uptime}\n\n📦 Контейнеры:\n${containers}`);
  } catch (err) {
    send('❌ Ошибка при получении статуса');
  }
});

// /logs — логи n8n
bot.onText(/\/logs/, () => {
  try {
    const logs = execSync('docker logs --tail=50 n8n-app').toString();
    send(`📝 Логи n8n:\n\`\`\`\n${logs}\n\`\`\``);
  } catch (err) {
    send('❌ Не удалось получить логи');
  }
});

// /backups — запуск backup_n8n.sh
bot.onText(/\/backups/, () => {
  try {
    execSync('/opt/n8n-install/scripts/backup_n8n.sh');
    send('📦 Бэкап запущен. Ожидайте файл в Telegram...');
  } catch (err) {
    send(`❌ Ошибка при запуске backup:\n\`\`\`\n${err.message}\n\`\`\``);
  }
});

// /update — обновление n8n
bot.onText(/\/update/, () => {
  try {
    const latest = execSync('npm view n8n version').toString().trim();
    const current = execSync('docker exec n8n-app n8n -v').toString().trim();

    if (latest === current) {
      send(`✅ У вас уже последняя версия n8n (${current})`);
    } else {
      send(`⏬ Обновляю n8n с ${current} до ${latest}...`);
      execSync('docker pull n8nio/n8n');
      execSync('docker compose stop n8n');
      execSync('docker compose rm -f n8n');
      execSync('docker compose up -d --no-deps --build n8n');
      send(`✅ n8n обновлён до версии ${latest}`);
    }
  } catch (err) {
    send('❌ Обновление завершилось с ошибкой');
  }
});
