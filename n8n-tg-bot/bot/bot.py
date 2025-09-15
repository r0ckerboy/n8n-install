import os
import logging
import docker
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

# Настройка логирования
logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)

# Получение токенов из переменных окружения
TELEGRAM_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
ALLOWED_USER_ID = int(os.getenv('TELEGRAM_USER_ID'))
DOCKER_SOCKET = os.getenv('DOCKER_SOCKET_PATH', '/var/run/docker.sock')

client = docker.from_env()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Отправляет приветственное сообщение."""
    if update.effective_user.id != ALLOWED_USER_ID:
        return
    await update.message.reply_text('Привет! Я бот для управления вашим стеком. Доступные команды: /status, /logs <имя_сервиса>')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Показывает статус Docker контейнеров."""
    if update.effective_user.id != ALLOWED_USER_ID:
        return
    
    try:
        containers = client.containers.list(all=True)
        if not containers:
            await update.message.reply_text('Контейнеры не найдены.')
            return

        message = 'Статус контейнеров:\n\n'
        for container in containers:
            status_icon = "✅" if container.status == "running" else "❌"
            message += f'{status_icon} *{container.name}*: `{container.status}`\n'
        
        await update.message.reply_text(message, parse_mode='Markdown')

    except Exception as e:
        await update.message.reply_text(f'Ошибка при получении статуса: {e}')

async def logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Показывает последние 15 строк логов для указанного сервиса."""
    if update.effective_user.id != ALLOWED_USER_ID:
        return
    
    if not context.args:
        await update.message.reply_text('Использование: /logs <имя_сервиса>')
        return
    
    service_name = context.args[0]
    try:
        container = client.containers.get(service_name)
        logs_output = container.logs(tail=15).decode('utf-8')
        message = f'Последние 15 строк логов для *{service_name}*:\n\n```\n{logs_output}\n```'
        await update.message.reply_text(message, parse_mode='Markdown')

    except docker.errors.NotFound:
        await update.message.reply_text(f'Сервис `{service_name}` не найден.')
    except Exception as e:
        await update.message.reply_text(f'Ошибка при получении логов: {e}')


def main():
    """Запуск бота."""
    application = Application.builder().token(TELEGRAM_TOKEN).build()

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("status", status))
    application.add_handler(CommandHandler("logs", logs))

    logging.info("Бот запущен...")
    application.run_polling()

if __name__ == '__main__':
    main()
