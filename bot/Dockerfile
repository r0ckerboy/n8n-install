FROM node:20-alpine

# Установка нужных утилит
RUN apk add --no-cache \
  zip \
  bash \
  curl \
  docker-cli \
  coreutils \
  procps

# Создание рабочей директории
WORKDIR /app

# Копирование зависимостей и установка
COPY package*.json ./
RUN npm install

# Копирование кода
COPY . .

# Запуск бота
CMD ["npm", "start"]
