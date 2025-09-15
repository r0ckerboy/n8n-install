# Базовый образ n8n (основан на Alpine Linux)
FROM n8nio/n8n:latest

# Переключаемся на root для установки зависимостей
USER root

# Установка системных зависимостей через apk (менеджер пакетов Alpine)
# --no-cache не создает лишний кэш, что делает образ меньше
RUN apk add --no-cache \
    ffmpeg \
    git

# Копируем и делаем исполняемым скрипт установки community-нод
COPY --chown=node:node install-community-nodes.sh /home/node/
RUN chmod +x /home/node/install-community-nodes.sh

# Возвращаем пользователя node для безопасности
USER node

# Запускаем скрипт установки нод перед стартом основного приложения
ENTRYPOINT ["/bin/sh", "-c", "/home/node/install-community-nodes.sh && /docker-entrypoint.sh"]
