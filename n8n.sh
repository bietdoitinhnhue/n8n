#!/bin/bash

# n8n Auto-Install Script - by ChatGPT
# OS: Ubuntu/Debian. Sudo/root user required.

echo "=== n8n All-in-One Installer ==="
echo "Domain/subdomain của bạn (đã trỏ A record về IP VPS này):"
read -p "VD: n8n.yourdomain.com: " N8N_DOMAIN

if [[ ! $N8N_DOMAIN =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
    echo "❌ Domain không hợp lệ!"
    exit 1
fi

# Update hệ thống & cài đặt cơ bản
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl gnupg2 ca-certificates lsb-release nginx ufw

# Bật firewall cơ bản
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# Cài NodeJS LTS và npm mới nhất
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs build-essential

# Cập nhật npm bản mới nhất
sudo npm install -g npm@latest

# Cài n8n mới nhất (official stable)
sudo npm install -g n8n

# Tạo user riêng để chạy n8n (khuyến nghị)
sudo useradd -m -d /home/n8n -s /bin/bash n8n
sudo mkdir -p /home/n8n/.n8n
sudo chown -R n8n:n8n /home/n8n
sudo chmod 700 /home/n8n/.n8n

# Tạo .env cho n8n
cat <<EOF | sudo tee /home/n8n/.n8n/.env
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -hex 8)
WEBHOOK_URL=https://$N8N_DOMAIN/
VUE_APP_URL_BASE_API=https://$N8N_DOMAIN/
EOF

sudo chown n8n:n8n /home/n8n/.n8n/.env

# Tạo systemd service cho n8n
cat <<EOF | sudo tee /etc/systemd/system/n8n.service
[Unit]
Description=n8n automation
After=network.target

[Service]
Type=simple
User=n8n
EnvironmentFile=/home/n8n/.n8n/.env
ExecStart=/usr/bin/n8n
Restart=always
WorkingDirectory=/home/n8n
LimitNOFILE=16384

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable n8n
sudo systemctl start n8n

# Cấu hình nginx reverse proxy
sudo tee /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name $N8N_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
sudo nginx -t && sudo systemctl reload nginx

# Cài Let's Encrypt và xin SSL
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx --non-interactive --agree-tos --redirect -d $N8N_DOMAIN -m admin@$N8N_DOMAIN

echo "✅ Xong! n8n đã chạy tại: https://$N8N_DOMAIN"
echo "🔑 Username: admin"
echo "🔑 Password (auto gen): $(grep N8N_BASIC_AUTH_PASSWORD /home/n8n/.n8n/.env | cut -d= -f2)"
