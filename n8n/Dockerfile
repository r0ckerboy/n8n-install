# Базовый образ n8n (основан на Alpine Linux)
FROM n8nio/n8n:latest

# Переключаемся на root для установки зависимостей
USER root

# Установка системных зависимостей через apk
RUN apk add --no-cache ffmpeg git

# Копируем скрипт в конкретное, известное место
COPY --chown=node:node ../install-community-nodes.sh .
# Делаем его исполняемым
RUN chmod +x /home/node/install-community-nodes.sh

# Возвращаем пользователя node для безопасности
USER node

# Запускаем скрипт установки нод перед стартом основного приложения
# Используем абсолютный путь и добавляем отладку
ENTRYPOINT ["/bin/sh", "-c", "echo '>>> Запускаю скрипт установки нод...' && ls -l /home/node/ && /home/node/install-community-nodes.sh && echo '>>> Скрипт выполнен, запускаю n8n...' && /docker-entrypoint.sh"]
