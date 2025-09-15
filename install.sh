#!/bin/bash
set -e

# --- NETRUNNER'S CONSOLE ---
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_NC='\033[0m' # No Color

log_jack_in() { echo -e "${C_CYAN}>_ [JACKING IN]${C_NC} $1"; }
log_preem() { echo -e "${C_GREEN}>_ [PREEM]${C_NC} $1"; }
log_glitch() { echo -e "${C_YELLOW}>_ [GLITCH DETECTED]${C_NC} $1"; }
log_flatline() { echo -e "${C_RED}>_ [FLATLINED]${C_NC} $1"; exit 1; }

# --- MAIN SEQUENCE ---
clear
echo -e "${C_CYAN}"
cat << "EOF"
 __   __   ___  __       __   ___  __       __  
/  ` /  \ |__  |__) \ / /__` |__  |__) \ / /__` 
\__, \__/ |___ |  \  |  .__/ |___ |  \  |  .__/ 
                                                
EOF
echo -e "INITIALIZING NETRUNNER STACK // NIGHT CITY v2.0.77${C_NC}"
echo "----------------------------------------------------"

# Check root access
if (( EUID != 0 )); then
    log_flatline "Corpo-rats only. Root access required."
fi

# Install dependencies
log_jack_in "Scanning for required chrome..."
DEPS=("git" "curl" "docker.io" "docker-compose-v2")
PACKAGES_TO_INSTALL=()
for dep in "${DEPS[@]}"; do
    if ! command -v "${dep//-v2/}" &>/dev/null; then
        PACKAGES_TO_INSTALL+=("$dep")
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    log_jack_in "Injecting new software: ${PACKAGES_TO_INSTALL[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}"
else
    log_preem "System chrome is up to date."
fi

# Clone repository
INSTALL_DIR="/opt/n8n-stack"
if [ -d "$INSTALL_DIR" ]; then
    log_glitch "Residue detected in $INSTALL_DIR. Wiping..."
    rm -rf "$INSTALL_DIR"
fi
log_jack_in "Downloading schematics from the Net..."
git clone https://github.com/r0ckerboy/n8n-beget-install.git "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Get user data
log_jack_in "Fixer requires auth-data for this gig:"
read -p "- Your DOMAIN_ID (e.g., example.com): " BASE_DOMAIN
read -p "- LETSENCRYPT Email (for secure handshake): " LETSENCRYPT_EMAIL
read -sp "- ICE Passkey for Postgres daemon: " POSTGRES_PASSWORD
echo
read -p "- Pexels API Credstick: " PEXELS_API_KEY
read -p "- Telegram Bot Access Token: " TELEGRAM_BOT_TOKEN
read -p "- Your personal Telegram Net-ID: " TELEGRAM_USER_ID

# Generate encryption key
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
log_preem "Generated AES-256 encryption key."

# Create .env file
cp .env.template .env
sed -i "s|BASE_DOMAIN=.*|BASE_DOMAIN=${BASE_DOMAIN}|" .env
sed -i "s|LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}|" .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" .env
sed -i "s|N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}|" .env
sed -i "s|PEXELS_API_KEY=.*|PEXELS_API_KEY=${PEXELS_API_KEY}|" .env
sed -i "s|TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}|" .env
sed -i "s|TELEGRAM_USER_ID=.*|TELEGRAM_USER_ID=${TELEGRAM_USER_ID}|" .env
log_preem "Auth-data compiled and secured."

# Create directories
log_jack_in "Allocating memory shards and data-fortress..."
mkdir -p ./data/{postgres,redis,n8n,letsencrypt,videos}
touch ./data/letsencrypt/acme.json
chmod 600 ./data/letsencrypt/acme.json

# Build and run
log_jack_in "Compiling custom n8n daemon... (might take a while)"
docker compose build n8n
log_jack_in "AWAKENING DAEMONS... (stand by)"
docker compose up -d

# Setup cron
log_jack_in "Programming backup subroutine (daily, 0200 hours)..."
(crontab -l 2>/dev/null | grep -v "backup.sh" ; echo "0 2 * * * cd $INSTALL_DIR && ./backup.sh >> /var/log/backup.log 2>&1") | crontab -
log_preem "Backup daemon is online."

# Final message
echo "----------------------------------------------------"
log_preem "SYSTEM ONLINE. Gig complete."
echo "Available Net access points:"
echo -e " > n8n: ${C_YELLOW}https://n8n.${BASE_DOMAIN}${C_NC}"
echo -e " > Postiz (Gitroom): ${C_YELLOW}https://postiz.${BASE_DOMAIN}${C_NC}"
echo -e " > Short Video Maker: ${C_YELLOW}https://svm.${BASE_DOMAIN}${C_NC}"
echo -e " > Traefik ICE Console: ${C_YELLOW}https://traefik.${BASE_DOMAIN}${C_NC}"
echo ""
log_jack_in "Allow daemons 1-2 minutes to calibrate and establish secure connection."
echo -e "${C_GREEN}Stay safe on the Net, choom.${C_NC}"
