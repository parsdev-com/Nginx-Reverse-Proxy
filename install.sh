#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

read -p "Enter domain (example.com): " DOMAIN
read -p "Enter local app port (example: 3000): " PORT
read -p "Enter email for Let's Encrypt: " EMAIL

if [ -z "$DOMAIN" ] || [ -z "$PORT" ] || [ -z "$EMAIL" ]; then
  echo "All fields are required"
  exit 1
fi

apt update
apt install -y nginx certbot python3-certbot-nginx

cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    client_max_body_size 100M;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=15768000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN

nginx -t
systemctl reload nginx

certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email $EMAIL \
  -d $DOMAIN

systemctl enable certbot.timer
systemctl start certbot.timer

echo "Done. https://$DOMAIN"
