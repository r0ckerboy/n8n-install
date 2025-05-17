FROM node:18-alpine

WORKDIR /app

# Установка зависимостей для бэкапов
RUN apk add --no-cache \
    docker-cli \
    postgresql-client \
    bash

# Копируем файлы
COPY package*.json ./
RUN npm install

COPY . .

# Права на скрипты бэкапа
RUN chmod +x /app/backup_scripts/*.sh

CMD ["node", "bot/bot.js"]
