# Базовый образ n8n (основан на Alpine Linux)
FROM n8nio/n8n:latest

# Устанавливаем рабочую директорию, чтобы быть уверенными в путях
WORKDIR /home/node

# Переключаемся на root для установки зависимостей
USER root

# Установка системных зависимостей через apk
RUN apk add --no-cache ffmpeg git

# Копируем скрипт установки community-нод
COPY --chown=node:node install-community-nodes.sh .

# Делаем его исполняемым
RUN chmod +x ./install-community-nodes.sh

# Возвращаем пользователя node для безопасности
USER node

# Запускаем скрипт установки нод перед стартом основного приложения
ENTRYPOINT ["/bin/sh", "-c", "./install-community-nodes.sh && /docker-entrypoint.sh"]
