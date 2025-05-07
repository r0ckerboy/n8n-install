const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

// === Загрузка переменных окружения ===
require('dotenv').config();

const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;

if (!token || !userId) {
  console.error("❌ TG_BOT_TOKEN или TG_USER_ID не заданы в .env");
  process.exit(1);
}

const bot = new TelegramBot(token, { polling: true });

function isAuthorized(msg) {
  return String(msg.chat.id) === String(userId);
}

function send(text) {
  bot.sendMessage(userId, text, { parse_mode: 'Markdown' });
}

// === /start — справка ===
bot.onText(/\/start/, (msg) => {
  if (!isAuthorized(msg)) return;
  send(
    '🤖 *Доступные команды:*\n' +
    '/status — Статус контейнеров\n' +
    '/logs — Логи n8n\n' +
    '/backups — Резервная копия\n' +
    '/update — Обновление n8n'
  );
});

// === /status — аптайм и контейнеры ===
bot.onText(/\/status/, (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const uptime = execSync('uptime -p').toString().trim();
    const containers = execSync('docker ps --format "{{.Names}} ({{.Status}})"').toString().trim();
    send(`🟢 *Сервер работает*\n⏱ Uptime: ${uptime}\n\n📦 Контейнеры:\n${containers}`);
  } catch {
    send('❌ Ошибка при получении статуса');
  }
});

// === /logs — последние логи n8n ===
bot.onText(/\/logs/, (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const logs = execSync('docker logs --tail=50 n8n-app').toString();
    send(`📝 *Логи n8n:*\n\`\`\`\n${logs}\n\`\`\``);
  } catch {
    send('❌ Не удалось получить логи n8n');
  }
});

// === /backups — запуск backup_n8n.sh ===
bot.onText(/\/backups/, (msg) => {
  if (!isAuthorized(msg)) return;

  send('📦 Запускаю резервное копирование...');

  const backupScriptPath = path.resolve('/opt/n8n-install/backup_n8n.sh');

  exec(`/bin/bash ${backupScriptPath}`, (error, stdout, stderr) => {
    if (error) {
      send(`❌ Ошибка:\n\`\`\`\n${error.message}\n\`\`\``);
      return;
    }
    if (stderr && stderr.trim()) {
      send(`⚠️ Предупреждения:\n\`\`\`\n${stderr}\n\`\`\``);
      return;
    }

    send(`✅ Бэкап завершён.`);
  });
});

// === /update — обновление n8n после бэкапа ===
bot.onText(/\/update/, (msg) => {
  if (!isAuthorized(msg)) return;

  send('🔄 Сначала создаю бэкап...');

  const backupScriptPath = path.resolve('/opt/n8n-install/backup_n8n.sh');

  exec(`/bin/bash ${backupScriptPath}`, (error) => {
    if (error) {
      send(`❌ Ошибка бэкапа:\n\`\`\`\n${error.message}\n\`\`\`\nОбновление прервано.`);
      return;
    }

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
});
