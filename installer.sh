#!/bin/bash

set -euo pipefail

# Redirect Engine VPS Installer
# Usage:
#   bash installer.sh yourdomain.com
#   or
#   curl -sL https://raw.githubusercontent.com/helencarlos36622-svg/redirect-engine/main/installer.sh | bash -s -- yourdomain.com

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${1:-}" ]; then
    echo -e "${RED}Error: Domain name is required${NC}"
    echo "Usage: curl -sL https://raw.githubusercontent.com/helencarlos36622-svg/redirect-engine/main/installer.sh | bash -s -- yourdomain.com"
    exit 1
fi

DOMAIN="$1"
INSTALL_DIR="/var/www/redirect-engine"
REPO_URL="https://github.com/helencarlos36622-svg/redirect-engine.git"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Redirect Engine Installer${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "Domain: ${YELLOW}${DOMAIN}${NC}"
echo

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="${ID:-unknown}"
else
    echo -e "${RED}Cannot detect OS type${NC}"
    exit 1
fi

case "$OS" in
    ubuntu|debian)
        PKG_INSTALL="apt-get install -y -qq"
        PKG_UPDATE="apt-get update -qq"
        PKG_UPGRADE="apt-get upgrade -y -qq"
        WEB_USER="www-data"
        NGINX_CONF="/etc/nginx/conf.d/redirect-engine.conf"
        ;;
    centos|rhel|rocky|almalinux)
        PKG_INSTALL="yum install -y -q"
        PKG_UPDATE="yum makecache -q"
        PKG_UPGRADE="yum update -y -q"
        WEB_USER="nginx"
        NGINX_CONF="/etc/nginx/conf.d/redirect-engine.conf"
        ;;
    fedora)
        PKG_INSTALL="dnf install -y -q"
        PKG_UPDATE="dnf makecache -q"
        PKG_UPGRADE="dnf update -y -q"
        WEB_USER="nginx"
        NGINX_CONF="/etc/nginx/conf.d/redirect-engine.conf"
        ;;
    *)
        echo -e "${RED}Unsupported OS: ${OS}${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}[1/8]${NC} Updating system packages..."
eval "$PKG_UPDATE"
eval "$PKG_UPGRADE"

echo -e "${GREEN}[2/8]${NC} Installing Nginx, Certbot, Git, and Curl..."
case "$OS" in
    ubuntu|debian)
        eval "$PKG_INSTALL nginx certbot python3-certbot-nginx git curl"
        ;;
    centos|rhel|rocky|almalinux)
        yum install -y -q epel-release || true
        eval "$PKG_INSTALL nginx certbot python3-certbot-nginx git curl"
        ;;
    fedora)
        eval "$PKG_INSTALL nginx certbot python3-certbot-nginx git curl"
        ;;
esac

echo -e "${GREEN}[3/8]${NC} Setting up application files..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Previous installation detected. Removing and reinstalling..."
    rm -rf "$INSTALL_DIR"
fi

mkdir -p /var/www
echo "Cloning repository..."
git clone -q "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

chown -R "$WEB_USER:$WEB_USER" "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"

echo -e "${GREEN}[4/8]${NC} Configuring Nginx..."

if [ ! -d "$INSTALL_DIR/dist" ]; then
    echo -e "${RED}Error: $INSTALL_DIR/dist not found${NC}"
    echo "Make sure your repository contains a dist folder."
    exit 1
fi

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    root $INSTALL_DIR/dist;
    index index.html;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json application/xml+rss;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

if [ -f /etc/nginx/conf.d/default.conf ]; then
    rm -f /etc/nginx/conf.d/default.conf
fi

echo -e "${GREEN}[5/8]${NC} Testing Nginx configuration..."
nginx -t

echo -e "${GREEN}[6/8]${NC} Restarting Nginx..."
systemctl enable nginx
systemctl restart nginx

echo -e "${GREEN}[7/8]${NC} Configuring firewall..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow OpenSSH || true
    ufw allow 'Nginx Full' || true
    ufw --force enable
    echo "Firewall configured with UFW"
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --permanent --add-service=https || true
    firewall-cmd --reload || true
    echo "Firewall configured with firewalld"
else
    echo "No supported firewall manager found, skipping firewall configuration"
fi

echo -e "${GREEN}[8/8]${NC} SSL Configuration..."
echo
echo -e "${YELLOW}Choose your SSL setup:${NC}"
echo "1) Using Cloudflare (recommended if using Cloudflare proxy)"
echo "2) Let's Encrypt (for direct server SSL)"
echo "3) Skip SSL setup"
echo
read -p "Enter your choice (1-3): " -n 1 -r
echo
echo

if [[ "$REPLY" == "1" ]]; then
    echo -e "${GREEN}Cloudflare SSL Mode Selected${NC}"
    echo
    echo -e "${YELLOW}Make sure you have:${NC}"
    echo "1. Set Cloudflare SSL/TLS mode to 'Full' or 'Full (strict)'"
    echo "2. Created Origin Certificate in Cloudflare (optional for Full strict)"
    echo "3. DNS records (@ and www) pointing to this server"
    echo
    echo -e "${GREEN}Your site will use Cloudflare's SSL certificate${NC}"
    echo "No additional SSL setup needed on this server"

elif [[ "$REPLY" == "2" ]]; then
    echo -e "${YELLOW}Setting up Let's Encrypt...${NC}"
    echo -e "${YELLOW}Make sure your domain ${DOMAIN} points directly to this server${NC}"
    echo
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
        systemctl enable certbot.timer || true
        systemctl start certbot.timer || true
        echo -e "${GREEN}Let's Encrypt SSL certificate installed!${NC}"
    else
        echo -e "${YELLOW}Skipped. Run later: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}${NC}"
    fi
else
    echo -e "${YELLOW}SSL setup skipped${NC}"
    echo "Run later with: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
fi

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "Your Redirect Engine is now running at:"
echo -e "${GREEN}https://${DOMAIN}${NC}"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update your Supabase environment variables"
echo "2. Configure your database connection"
echo "3. Create your admin account"
echo
echo -e "${YELLOW}To update the application:${NC}"
echo "cd ${INSTALL_DIR} && git pull && systemctl reload nginx"
echo
echo -e "${YELLOW}To view logs:${NC}"
echo "tail -f /var/log/nginx/access.log"
echo "tail -f /var/log/nginx/error.log"
echo
