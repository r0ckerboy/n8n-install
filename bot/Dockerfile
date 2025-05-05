# Используем минимальный образ node.js
FROM node:18-alpine

# Создаём рабочую директорию
WORKDIR /app

# Копируем package.json и устанавливаем зависимости
COPY package.json ./
RUN npm install --production

# Копируем исходный код бота
COPY . .

# Открываем порт (если понадобится)
EXPOSE 3000

# Запуск бота
CMD ["node", "bot.js"]
