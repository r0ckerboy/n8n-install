const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

// === Переменные окружения ===
const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;

if (!token || !userId) {
  console.error("❌ Не заданы переменные TG_BOT_TOKEN и TG_USER_ID.");
  process.exit(1);
}

const bot = new TelegramBot(token, { polling: true });

function isAuthorized(msg) {
  return String(msg.chat.id) === String(userId);
}

function send(text) {
  bot.sendMessage(userId, text, { parse_mode: 'Markdown' });
}

// /start
bot.onText(/\/start/, (msg) => {
  if (!isAuthorized(msg)) return;
  send(`🤖 Доступные команды:
  /status — Статус контейнеров
  /logs — Логи n8n
  /backups — Сделать бэкап
  /update — Обновить n8n (сначала делает бэкап)`);
});

// /status
bot.onText(/\/status/, (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const uptime = execSync('uptime -p').toString().trim();
    const containers = execSync('docker ps --format "{{.Names}} ({{.Status}})"').toString().trim();
    send(`🟢 Сервер работает\n⏱ Uptime: ${uptime}\n\n📦 Контейнеры:\n${containers}`);
  } catch (err) {
    send('❌ Ошибка при получении статуса');
  }
});

// /logs
bot.onText(/\/logs/, (msg) => {
  if (!isAuthorized(msg)) return;
  exec('docker logs --tail=100 n8n-app', (error, stdout, stderr) => {
    if (error) {
      send(`❌ Ошибка:\n\`\`\`\n${error.message}\n\`\`\``);
      return;
    }

    const MAX_LEN = 3900;
    const trimmed = stdout.length > MAX_LEN ? stdout.slice(-MAX_LEN) : stdout;

    if (stdout.length > MAX_LEN) {
      const logPath = '/tmp/n8n_logs.txt';
      fs.writeFileSync(logPath, stdout);
      bot.sendDocument(userId, logPath, {}, { caption: '📝 Логи n8n (последние 100 строк)' });
    } else {
      send(`📝 Логи n8n:\n\`\`\`\n${trimmed}\n\`\`\``);
    }
  });
});

// /backups
bot.onText(/\/backups/, (msg) => {
  if (!isAuthorized(msg)) return;
  const backupScriptPath = path.resolve('/opt/n8n-install/backup_n8n.sh');
  send('📦 Запускаю резервное копирование...');
  exec(`/bin/bash ${backupScriptPath}`, (error, stdout, stderr) => {
    if (error) {
      send(`❌ Ошибка:\n\`\`\`\n${error.message}\n\`\`\``);
    } else {
      send('✅ Бэкап завершён. Архив будет отправлен ботом.');
    }
  });
});

// /update
bot.onText(/\/update/, (msg) => {
  if (!isAuthorized(msg)) return;
  const backupScriptPath = path.resolve('/opt/n8n-install/backup_n8n.sh');

  send('🔄 Сначала создаю бэкап...');
  exec(`/bin/bash ${backupScriptPath}`, (error) => {
    if (error) {
      send(`❌ Ошибка бэкапа:\n\`\`\`\n${error.message}\n\`\`\`\nОбновление прервано.`);
      return;
    }

    send('⬇️ Обновляю n8n...');
    try {
      const latest = execSync('npm view n8n version').toString().trim();
      const current = execSync('docker exec n8n-app n8n -v').toString().trim();

      if (latest === current) {
        send(`✅ У вас уже последняя версия n8n (${current})`);
      } else {
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
