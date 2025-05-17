require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api');
const { isAuthorized, send } = require('./utils/helpers');
const {
  handleStatusCommand,
  handleLogsCommand,
  handleBackupCommand,
  handleUpdateCommand
} = require('./commands');

const bot = new TelegramBot(process.env.TG_BOT_TOKEN, { polling: true });

// Проверка подключения к Docker при старте
require('./utils/docker').checkDockerConnection()
  .then(() => send('🤖 Бот запущен и подключен к Docker'))
  .catch(err => {
    send(`❌ Ошибка Docker: ${err.message}`);
    process.exit(1);
  });

// Регистрация команд
bot.onText(/\/start/, (msg) => {
  if (!isAuthorized(msg)) return;
  
  const commands = [
    '🤖 Доступные команды:',
    '/status — Статус системы',
    '/logs — Логи n8n',
    '/backup — Полный бэкап (n8n + PostgreSQL)',
    '/update — Обновление n8n',
    '/db_backup — Только бэкап БД'
  ].join('\n');
  
  send(commands);
});

bot.onText(/\/status/, handleStatusCommand);
bot.onText(/\/logs/, handleLogsCommand);
bot.onText(/\/backup/, handleBackupCommand);
bot.onText(/\/update/, handleUpdateCommand);

// Новая команда для бэкапа только БД
bot.onText(/\/db_backup/, async (msg) => {
  if (!isAuthorized(msg)) return;
  
  try {
    await require('./commands/backup').backupDatabaseOnly();
    send('✅ Бэкап PostgreSQL завершен');
  } catch (err) {
    send(`❌ Ошибка бэкапа БД: ${err.message}`);
  }
});
