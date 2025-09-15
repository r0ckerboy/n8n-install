# Базовый образ n8n (основан на Debian)
FROM n8nio/n8n:latest

# Переключаемся на root для установки зависимостей
USER root

# Установка системных зависимостей через apt-get
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

# Копируем и делаем исполняемым скрипт установки community-нод
COPY --chown=node:node install-community-nodes.sh /home/node/
RUN chmod +x /home/node/install-community-nodes.sh

# Возвращаем пользователя node для безопасности
USER node

# Запускаем скрипт установки нод перед стартом основного приложения
# Docker-entrypoint n8n сам вызовет 'tini', поэтому мы просто добавляем наш скрипт перед ним
ENTRYPOINT ["/bin/sh", "-c", "/home/node/install-community-nodes.sh && /docker-entrypoint.sh"]
