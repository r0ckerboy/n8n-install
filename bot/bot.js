const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

// === Переменные окружения ===
const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;

if (!token || !userId) {
  console.error("❌ Не заданы необходимые переменные окружения.");
  process.exit(1);
}

const bot = new TelegramBot(token, { polling: true });

function isAuthorized(msg) {
  return String(msg.chat.id) === String(userId);
}

function send(text) {
  bot.sendMessage(userId, text, { parse_mode: 'Markdown' });
}
// Проверка при старте бота
try {
  dockerCommand('ps');
  send('🤖 Бот запущен и подключен к Docker');
} catch (err) {
  send(`❌ Ошибка подключения к Docker: ${err.message}`);
  process.exit(1);
}
// /start — список команд
bot.onText(/\/start/, (msg) => {
  if (!isAuthorized(msg)) return;
  send('🤖 Доступные команды:\n/status — Статус контейнеров\n/logs — Логи n8n\n/backups — Бэкап вручную\n/update — Обновление n8n');
});

const bot = new TelegramBot(token, { polling: true });

// Добавляем обработку ошибок Docker
function dockerCommand(cmd) {
  try {
    return execSync(`docker ${cmd}`, { timeout: 10000 }).toString().trim();
  } catch (err) {
    console.error(`Docker error: ${err.message}`);
    throw new Error(`Docker command failed: ${cmd}`);
  }
}

// Обновленный /status
bot.onText(/\/status/, (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const uptime = execSync('uptime -p').toString().trim();
    const containers = dockerCommand('ps --format "{{.Names}} ({{.Status}})"');
    send(`🟢 Сервер работает\n⏱ Uptime: ${uptime}\n\n📦 Контейнеры:\n${containers}`);
  } catch (err) {
    send(`❌ Ошибка Docker: ${err.message}\nПроверьте: sudo systemctl status docker`);
  }
});

// Обновленный /logs
bot.onText(/\/logs/, (msg) => {
  if (!isAuthorized(msg)) return;
  try {
    const logs = dockerCommand('logs --tail=100 n8n');
    send(`📝 Логи n8n:\n\`\`\`\n${logs.slice(-3900)}\n\`\`\``);
  } catch (err) {
    send(`❌ Не удалось получить логи: ${err.message}`);
  }
});
      // Логи слишком длинные — сохраняем во временный файл и отправляем
      const fs = require('fs');
      const logPath = '/tmp/n8n_logs.txt';
      fs.writeFileSync(logPath, stdout);

      bot.sendDocument(userId, logPath, {}, {
        caption: '📝 Логи n8n (последние 100 строк)'
      });
    } else {
      send(`📝 Логи n8n:\n\`\`\`\n${trimmed}\n\`\`\``);
    }
  });
});

// /backups — запускает backup_n8n.sh
bot.onText(/\/backups/, (msg) => {
  if (!isAuthorized(msg)) return;

  send('📦 Запускаю резервное копирование n8n...');

  const backupScriptPath = path.resolve('/opt/n8n-install/backup_n8n.sh');

  exec(`/bin/bash ${backupScriptPath}`, (error, stdout, stderr) => {
    if (error) {
      send(`❌ Ошибка при запуске backup:\n\`\`\`\n${error.message}\n\`\`\``, { parse_mode: 'Markdown' });
      return;
    }

    if (stderr && stderr.trim()) {
      send(`⚠️ В процессе бэкапа были предупреждения:\n\`\`\`\n${stderr}\n\`\`\``, { parse_mode: 'Markdown' });
      return;
    }

    send('✅ Бэкап завершён. Проверьте Telegram — архив должен быть отправлен автоматически.');
  });
});
bot.onText(/\/update/, (msg) => {
  if (!isAuthorized(msg)) return;
  

// /update — сначала backup, потом обновление n8n
bot.onText(/\/update/, (msg) => {
  if (!isAuthorized(msg)) return;

  send('⏳ Сначала делаю резервную копию перед обновлением...');

  const backupScriptPath = path.resolve('/opt/n8n-install/backup_n8n.sh');

  exec(`/bin/bash ${backupScriptPath}`, (error, stdout, stderr) => {
    if (error) {
      send(`❌ Ошибка при запуске backup:\n\`\`\`\n${error.message}\n\`\`\`\nОбновление прервано.`, { parse_mode: 'Markdown' });
      return;
    }

    send('✅ Бэкап завершён. Начинаю обновление n8n...');

    try {
      const latest = execSync('npm view n8n version').toString().trim();
      const current = execSync('docker exec n8n-app n8n -v').toString().trim();

      if (latest === current) {
        send(`✅ У вас уже последняя версия n8n (${current})`);
      } else {
        send(`⏬ Обновляю n8n с ${current} до ${latest}...`);
        execSync('docker pull n8nio/n8n');
        execSync('docker-compose stop n8n');
        execSync('docker-compose rm -f n8n');
        execSync('docker-compose up -d --no-deps --build n8n');
        send(`✅ n8n обновлён до версии ${latest}`);
      }
    } catch (err) {
      send('❌ Обновление завершилось с ошибкой');
    }
  });
});

