const { execSync } = require('child_process');

function dockerCommand(cmd) {
  try {
    return execSync(`docker ${cmd}`, { 
      timeout: 15000,
      env: {
        ...process.env,
        DOCKER_HOST: process.env.DOCKER_HOST || 'unix:///var/run/docker.sock'
      }
    }).toString().trim();
  } catch (err) {
    throw new Error(`Docker command failed: ${cmd}\n${err.message}`);
  }
}

async function checkDockerConnection() {
  try {
    await dockerCommand('ps');
    return true;
  } catch (err) {
    throw new Error(`Не удалось подключиться к Docker. Проверьте:\n1. Запущен ли Docker\n2. Права пользователя\n3. Переменную DOCKER_HOST`);
  }
}

module.exports = {
  dockerCommand,
  checkDockerConnection
};
