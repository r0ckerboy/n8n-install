#!/bin/bash

# Параметры из .env
source /opt/n8n-install/.env

BACKUP_DIR="/opt/n8n-install/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/postgres_$DATE.sql.gz"

mkdir -p $BACKUP_DIR

# Бэкап PostgreSQL
echo "Creating PostgreSQL backup..."
docker exec n8n-db pg_dump -U $POSTGRES_USER -d $POSTGRES_DB | gzip > $BACKUP_FILE

if [ $? -eq 0 ]; then
  echo "Backup created: $BACKUP_FILE"
  exit 0
else
  echo "Backup failed"
  exit 1
fi
