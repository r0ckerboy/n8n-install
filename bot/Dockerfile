FROM node:20-alpine

# Устанавливаем нужные пакеты для bash, curl и работы с Docker CLI
RUN apk add --no-cache \
  bash \
  curl \
  docker-cli \
  coreutils \
  procps \
  zip \
  tzdata \
  && cp /usr/share/zoneinfo/Europe/Moscow /etc/localtime \
  && echo "Europe/Moscow" > /etc/timezone

# Устанавливаем рабочую директорию
WORKDIR /app

# Копируем зависимости и устанавливаем их
COPY package*.json ./
RUN npm install

# Копируем исходники
COPY . .

# Запускаем бота
CMD ["node", "bot.js"]
