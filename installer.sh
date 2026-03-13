#!/bin/bash

# Redirect Engine VPS Installer
# Usage: curl -sL https://raw.githubusercontent.com/helencarlos36622-svg/redirect-engine/main/installer.sh | bash -s yourdomain.com

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if domain is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Domain name is required${NC}"
    echo "Usage: curl -sL https://raw.githubusercontent.com/helencarlos36622-svg/redirect-engine/main/installer.sh | bash -s yourdomain.com"
    exit 1
fi

DOMAIN=$1
INSTALL_DIR="/var/www/redirect-engine"
REPO_URL="https://github.com/helencarlos36622-svg/redirect-engine.git"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Redirect Engine Installer${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Domain: ${YELLOW}$DOMAIN${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Update system
echo -e "${GREEN}[1/8]${NC} Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# Install required packages
echo -e "${GREEN}[2/8]${NC} Installing Nginx, Certbot, and Git..."
apt-get install -y -qq nginx certbot python3-certbot-nginx git curl

# Clone or update repository
echo -e "${GREEN}[3/8]${NC} Setting up application files..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory exists, updating..."
    cd $INSTALL_DIR
    git pull -q
else
    echo "Cloning repository..."
    git clone -q $REPO_URL $INSTALL_DIR
fi

# Set correct permissions
chown -R www-data:www-data $INSTALL_DIR
chmod -R 755 $INSTALL_DIR

# Configure Nginx
echo -e "${GREEN}[4/8]${NC} Configuring Nginx..."
cat > /etc/nginx/sites-available/redirect-engine << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    root $INSTALL_DIR/dist;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json application/javascript;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Handle SPA routing
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }
}
EOF

# Enable site
if [ -f /etc/nginx/sites-enabled/redirect-engine ]; then
    rm /etc/nginx/sites-enabled/redirect-engine
fi
ln -s /etc/nginx/sites-available/redirect-engine /etc/nginx/sites-enabled/

# Remove default site if exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
fi

# Test Nginx configuration
echo -e "${GREEN}[5/8]${NC} Testing Nginx configuration..."
nginx -t

# Restart Nginx
echo -e "${GREEN}[6/8]${NC} Restarting Nginx..."
systemctl restart nginx
systemctl enable nginx

# Configure firewall
echo -e "${GREEN}[7/8]${NC} Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw --force enable
    ufw allow 'Nginx Full'
    ufw allow OpenSSH
    echo "Firewall configured"
else
    echo "UFW not found, skipping firewall configuration"
fi

# Setup SSL certificate
echo -e "${GREEN}[8/8]${NC} Setting up SSL certificate..."
echo -e "${YELLOW}This will request an SSL certificate from Let's Encrypt${NC}"
echo -e "${YELLOW}Make sure your domain $DOMAIN points to this server's IP address${NC}"
echo ""
read -p "Continue with SSL setup? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --register-unsafely-without-email --redirect

    # Setup auto-renewal
    systemctl enable certbot.timer
    systemctl start certbot.timer

    echo -e "${GREEN}SSL certificate installed successfully!${NC}"
else
    echo -e "${YELLOW}Skipping SSL setup. You can run it later with:${NC}"
    echo "certbot --nginx -d $DOMAIN -d www.$DOMAIN"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Your Redirect Engine is now running at:"
echo -e "${GREEN}https://$DOMAIN${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update your Supabase environment variables"
echo "2. Configure your database connection"
echo "3. Create your admin account"
echo ""
echo -e "${YELLOW}To update the application:${NC}"
echo "cd $INSTALL_DIR && git pull && systemctl reload nginx"
echo ""
echo -e "${YELLOW}To view logs:${NC}"
echo "tail -f /var/log/nginx/access.log"
echo "tail -f /var/log/nginx/error.log"
echo ""
