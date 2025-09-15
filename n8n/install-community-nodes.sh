#!/bin/bash
set -e
echo "INFO: Установка community-нод для n8n..."
npm install n8n-nodes-telegram
npm install n8n-nodes-ssh
echo "SUCCESS: Community-ноды установлены."
