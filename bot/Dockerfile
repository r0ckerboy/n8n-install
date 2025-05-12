FROM node:18-alpine

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

# Установка Docker CLI
RUN apk add --no-cache docker-cli

CMD ["node", "bot.js"]
