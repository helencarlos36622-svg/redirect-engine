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

# Detect OS and package manager
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Cannot detect OS type${NC}"
    exit 1
fi

# Update system
echo -e "${GREEN}[1/8]${NC} Updating system packages..."
case $OS in
    ubuntu|debian)
        apt-get update -qq
        apt-get upgrade -y -qq
        ;;
    centos|rhel|rocky|almalinux)
        yum update -y -q
        ;;
    fedora)
        dnf update -y -q
        ;;
    *)
        echo -e "${RED}Unsupported OS: $OS${NC}"
        exit 1
        ;;
esac

# Install required packages
echo -e "${GREEN}[2/8]${NC} Installing Nginx, Certbot, and Git..."
case $OS in
    ubuntu|debian)
        apt-get install -y -qq nginx certbot python3-certbot-nginx git curl
        ;;
    centos|rhel|rocky|almalinux)
        # Enable EPEL for certbot
        yum install -y -q epel-release
        yum install -y -q nginx certbot python3-certbot-nginx git curl
        ;;
    fedora)
        dnf install -y -q nginx certbot python3-certbot-nginx git curl
        ;;
esac

# Clone or update repository
echo -e "${GREEN}[3/8]${NC} Setting up application files..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Previous installation detected. Removing and reinstalling..."
    rm -rf $INSTALL_DIR
fi

echo "Cloning repository..."
git clone -q $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR

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
echo -e "${GREEN}[8/8]${NC} SSL Configuration..."
echo ""
echo -e "${YELLOW}Choose your SSL setup:${NC}"
echo "1) Using Cloudflare (recommended if using Cloudflare proxy)"
echo "2) Let's Encrypt (for direct server SSL)"
echo "3) Skip SSL setup"
echo ""
read -p "Enter your choice (1-3): " -n 1 -r
echo
echo ""

if [[ $REPLY == "1" ]]; then
    echo -e "${GREEN}Cloudflare SSL Mode Selected${NC}"
    echo ""
    echo -e "${YELLOW}Make sure you have:${NC}"
    echo "1. Set Cloudflare SSL/TLS mode to 'Full' or 'Full (strict)'"
    echo "2. Created Origin Certificate in Cloudflare (optional for Full strict)"
    echo "3. DNS records (@ and *) pointing to this server"
    echo ""
    echo -e "${GREEN}Your site will use Cloudflare's SSL certificate${NC}"
    echo "No additional SSL setup needed on this server"

elif [[ $REPLY == "2" ]]; then
    echo -e "${YELLOW}Setting up Let's Encrypt...${NC}"
    echo -e "${YELLOW}Make sure your domain $DOMAIN points directly to this server${NC}"
    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --register-unsafely-without-email --redirect
        systemctl enable certbot.timer
        systemctl start certbot.timer
        echo -e "${GREEN}Let's Encrypt SSL certificate installed!${NC}"
    else
        echo -e "${YELLOW}Skipped. Run later: certbot --nginx -d $DOMAIN${NC}"
    fi
else
    echo -e "${YELLOW}SSL setup skipped${NC}"
    echo "Run later with: certbot --nginx -d $DOMAIN -d www.$DOMAIN"
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
