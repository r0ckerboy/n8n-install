FROM node:18-alpine

WORKDIR /app

# Установка зависимостей
COPY package.json ./
RUN npm install

# Копирование кода
COPY bot.js .

# Копирование .env (будет передано как volume или через docker-compose)
COPY .env .env

CMD ["npm", "start"]
