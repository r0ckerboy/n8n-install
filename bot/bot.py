import os
import logging
import docker
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.INFO)

TELEGRAM_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
ALLOWED_USER_ID = int(os.getenv('TELEGRAM_USER_ID'))
DOCKER_SOCKET = os.getenv('DOCKER_SOCKET_PATH', '/var/run/docker.sock')

client = docker.from_env()

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    await update.message.reply_text('Привет! Я бот для управления стеком. Команды: /status, /logs <сервис>')

async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    try:
        containers = client.containers.list(all=True)
        message = 'Статус контейнеров:\n\n'
        for c in containers:
            icon = "✅" if c.status == "running" else "❌"
            message += f'{icon} *{c.name}*: `{c.status}`\n'
        await update.message.reply_text(message, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f'Ошибка: {e}')

async def logs(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id != ALLOWED_USER_ID: return
    if not context.args:
        await update.message.reply_text('Использование: /logs <имя_сервиса>')
        return
    service_name = context.args[0]
    try:
        container = client.containers.get(service_name)
        logs_output = container.logs(tail=15).decode('utf-8')
        message = f'Логи для *{service_name}*:\n\n```\n{logs_output}\n```'
        await update.message.reply_text(message, parse_mode='Markdown')
    except Exception as e:
        await update.message.reply_text(f'Ошибка: {e}')

def main():
    application = Application.builder().token(TELEGRAM_TOKEN).build()
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("status", status))
    application.add_handler(CommandHandler("logs", logs))
    logging.info("Бот запущен...")
    application.run_polling()

if __name__ == '__main__':
    main()
