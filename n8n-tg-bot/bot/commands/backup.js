const { exec } = require('child_process');
const path = require('path');
const fs = require('fs');
const { send } = require('../utils/helpers');
const { dockerCommand } = require('../utils/docker');

async function backupDatabaseOnly() {
  return new Promise((resolve, reject) => {
    exec('/app/backup_scripts/backup_postgres.sh', (error, stdout, stderr) => {
      if (error) return reject(new Error(stderr || error.message));
      resolve(stdout);
    });
  });
}

async function handleBackupCommand(msg) {
  try {
    await send('🔄 Начинаю полный бэкап (n8n + PostgreSQL)...');
    
    // Бэкап PostgreSQL
    await backupDatabaseOnly();
    
    // Бэкап файлов n8n
    await new Promise((resolve, reject) => {
      exec('/app/backup_scripts/backup_n8n.sh', (error, stdout, stderr) => {
        if (error) return reject(new Error(stderr || error.message));
        resolve(stdout);
      });
    });

    await send('✅ Все бэкапы успешно созданы');
  } catch (err) {
    await send(`❌ Ошибка при создании бэкапа: ${err.message}`);
  }
}

module.exports = {
  handleBackupCommand,
  backupDatabaseOnly
};
