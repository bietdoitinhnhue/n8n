#!/bin/bash

# N8N Server Manager - Enhanced Version
# Author: bietdoitinhnhue.com
# Version: 2.0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Global variables
SCRIPT_NAME="/usr/local/bin/n8n-manager"
ALIAS_NAME="n8n"
N8N_DIR="/root/.n8n"
N8N_ENV="/etc/n8n.env"
N8N_SERVICE="/etc/systemd/system/n8n.service"
BACKUP_DIR="/root/n8n-backups"

# Safety checks
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Vui lòng chạy với quyền root: sudo $0${NC}"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

show_header() {
    clear
    echo -e "${CYAN}+================================================================+${NC}"
    echo -e "${CYAN}|                    N8N Server Manager v2.0                    |${NC}"
    echo -e "${CYAN}|                Powered by bietdoitinhnhue.com                  |${NC}"
    echo -e "${CYAN}+================================================================+${NC}"
    echo -e "${YELLOW}⚡ Truy cập nhanh: gõ 'n8n' ở bất kỳ đâu | Ctrl + C để thoát${NC}"
    echo ""
}

show_menu() {
    show_header
    echo -e "${WHITE}1)${NC}  🚀 Cài đặt N8N                        ${WHITE}6)${NC}  📤 ${YELLOW}Export workflow & credentials${NC}"
    echo -e "${WHITE}2)${NC}  🌐 Thay đổi tên miền                  ${WHITE}7)${NC}  📥 Import workflow & credentials"
    echo -e "${WHITE}3)${NC}  ⬆️  Nâng cấp phiên bản N8N             ${WHITE}8)${NC}  🔴 ${GREEN}Lấy thông tin Redis${NC}"
    echo -e "${WHITE}4)${NC}  🔒 Bật xác thực 2 bước (2FA/MFA)      ${WHITE}9)${NC}  🗑️  ${RED}Xóa N8N và cài đặt lại${NC}"
    echo -e "${WHITE}5)${NC}  👤 Đặt lại thông tin đăng nhập        ${WHITE}10)${NC} 📊 ${BLUE}Thông tin hệ thống${NC}"
    echo -e "${WHITE}11)${NC} 🔧 Quản lý SSL Certificate            ${WHITE}12)${NC} 📋 Xem logs N8N"
    echo "=================================================================================="
    echo -n -e "${WHITE}Nhập lựa chọn của bạn (1-12) [ 0 = Thoát ]:${NC} "
}

# Validation functions
validate_input() {
    local input="$1"
    local min_length="$2"
    local field_name="$3"
    
    if [ ${#input} -lt $min_length ]; then
        echo -e "${RED}❌ $field_name phải có ít nhất $min_length ký tự!${NC}"
        return 1
    fi
    return 0
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}❌ Domain không hợp lệ! Vd: n8n.example.com${NC}"
        return 1
    fi
    return 0
}

# Check if N8N is installed
check_n8n_installed() {
    if systemctl is-active --quiet n8n 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Install N8N with enhanced security
install_n8n() {
    echo -e "${GREEN}=== 🚀 Cài đặt N8N Workflow Automation (Bảo mật nâng cao) ===${NC}"

    # Check if already installed
    if check_n8n_installed; then
        echo -e "${YELLOW}⚠️ N8N đã được cài đặt và đang chạy.${NC}"
        local version=$(npm list -g n8n 2>/dev/null | grep n8n | awk '{print $2}' || echo "Unknown")
        echo -e "${BLUE}📦 Phiên bản hiện tại: $version${NC}"
        
        read -p "Bạn có muốn cài đặt lại? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
        
        # Backup before reinstall
        echo -e "${BLUE}📦 Đang backup dữ liệu hiện tại...${NC}"
        export_data "auto-backup-before-reinstall"
    fi

    # Get credentials with validation
    while true; do
        read -p "👤 Nhập tên đăng nhập admin (tối thiểu 4 ký tự): " N8N_USER
        if validate_input "$N8N_USER" 4 "Username"; then
            break
        fi
    done

    while true; do
        read -s -p "🔑 Nhập mật khẩu admin (tối thiểu 8 ký tự): " N8N_PASS
        echo
        if validate_input "$N8N_PASS" 8 "Password"; then
            break
        fi
    done

    # Get encryption key
    while true; do
        read -s -p "🔐 Nhập encryption key (tối thiểu 16 ký tự): " ENCRYPTION_KEY
        echo
        if validate_input "$ENCRYPTION_KEY" 16 "Encryption key"; then
            break
        fi
    done

    echo -e "${BLUE}🔄 Đang cập nhật hệ thống...${NC}"
    apt update && apt upgrade -y

    # Install Node.js (latest LTS)
    echo -e "${BLUE}📦 Đang cài đặt Node.js LTS...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs build-essential

    # Install additional dependencies
    echo -e "${BLUE}📦 Đang cài đặt dependencies...${NC}"
    apt-get install -y python3 python3-pip redis-server nginx certbot python3-certbot-nginx

    # Enable and start Redis
    systemctl enable redis-server
    systemctl start redis-server

    # Install N8N globally
    echo -e "${BLUE}🚀 Đang cài đặt N8N phiên bản mới nhất...${NC}"
    npm install n8n@latest -g

    # Create secure environment file
    echo -e "${BLUE}🔒 Đang tạo file cấu hình bảo mật...${NC}"
    cat > "$N8N_ENV" <<EOF
# N8N Configuration - Secure Setup
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$N8N_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_EDITOR_BASE_URL=http://localhost:5678
DB_TYPE=sqlite
DB_SQLITE_DATABASE=/root/.n8n/database.sqlite
N8N_USER_FOLDER=/root/.n8n
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_LOG_FILE_LOCATION=/var/log/n8n/
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168
GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
WEBHOOK_URL=http://localhost:5678
EOF

    # Secure the environment file
    chmod 600 "$N8N_ENV"
    chown root:root "$N8N_ENV"

    # Create log directory
    mkdir -p /var/log/n8n
    chown root:root /var/log/n8n

    # Create systemd service with enhanced security
    echo -e "${BLUE}⚙️ Đang tạo systemd service...${NC}"
    cat > "$N8N_SERVICE" <<EOF
[Unit]
Description=n8n workflow automation
Documentation=https://docs.n8n.io
After=network.target redis-server.service
Wants=network.target
Requires=redis-server.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/root
EnvironmentFile=$N8N_ENV
ExecStart=/usr/bin/n8n start
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=n8n

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/root/.n8n /var/log/n8n /tmp

# Resource limits
LimitNOFILE=65536
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start N8N
    systemctl daemon-reload
    systemctl enable n8n
    systemctl start n8n

    # Configure firewall
    configure_firewall

    # Wait for N8N to start
    echo -e "${BLUE}⏳ Đang khởi động N8N...${NC}"
    sleep 10

    # Check if N8N started successfully
    if systemctl is-active --quiet n8n; then
        echo -e "${GREEN}✅ N8N đã được cài đặt và khởi động thành công!${NC}"
        local public_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "localhost")
        echo -e "${CYAN}🌐 URL truy cập:${NC} http://$public_ip:5678"
        echo -e "${CYAN}👤 Username:${NC} $N8N_USER"
        echo -e "${CYAN}🔑 Password:${NC} ********** (đã được bảo mật)"
        echo -e "${YELLOW}💡 Lưu ý: Thông tin đăng nhập được lưu bảo mật trong $N8N_ENV${NC}"
        echo -e "${YELLOW}🚀 Để truy cập nhanh, gõ: n8n${NC}"
    else
        echo -e "${RED}❌ Lỗi khởi động N8N! Kiểm tra logs: journalctl -u n8n -f${NC}"
    fi
}

# Configure firewall
configure_firewall() {
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}🔥 Đang cấu hình firewall...${NC}"
        ufw allow 5678/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        echo -e "${GREEN}✅ Firewall đã được cấu hình${NC}"
    fi
}

# Change domain with SSL support
change_domain() {
    echo -e "${GREEN}=== 🌐 Cấu hình tên miền cho N8N ===${NC}"
    
    while true; do
        read -p "🌐 Nhập domain (vd: n8n.example.com): " domain
        if [ -n "$domain" ] && validate_domain "$domain"; then
            break
        fi
    done

    # Install and configure NGINX
    if ! command -v nginx &> /dev/null; then
        echo -e "${BLUE}📦 Đang cài đặt nginx...${NC}"
        apt update && apt install nginx -y
        systemctl enable nginx
        systemctl start nginx
    fi

    # Create directories
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

    # Remove default site
    rm -f /etc/nginx/sites-enabled/default

    # Create nginx config with security headers
    cat > "/etc/nginx/sites-available/n8n" <<EOF
server {
    listen 80;
    server_name $domain;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=n8n:10m rate=10r/m;
    limit_req zone=n8n burst=5 nodelay;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Block access to sensitive files
    location ~ /\\.ht {
        deny all;
    }
    
    location ~ /\\.env {
        deny all;
    }
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n

    # Test and reload nginx
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}✅ Đã cấu hình NGINX cho domain: $domain${NC}"
        
        # Update N8N environment
        if [ -f "$N8N_ENV" ]; then
            sed -i "s|N8N_EDITOR_BASE_URL=.*|N8N_EDITOR_BASE_URL=http://$domain|" "$N8N_ENV"
            sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=http://$domain|" "$N8N_ENV"
            systemctl restart n8n
        fi
        
        local public_ip=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
        echo -e "${YELLOW}📍 Hãy trỏ A record của domain về IP: $public_ip${NC}"
        echo -e "${CYAN}🔗 URL mới: http://$domain${NC}"
        
        # Ask for SSL
        read -p "🔒 Bạn có muốn cài đặt SSL certificate miễn phí? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_ssl "$domain"
        fi
    else
        echo -e "${RED}❌ Lỗi cấu hình NGINX!${NC}"
    fi
}

# Setup SSL certificate
setup_ssl() {
    local domain="$1"
    echo -e "${GREEN}=== 🔒 Cài đặt SSL Certificate ===${NC}"
    
    # Install certbot
    apt install -y certbot python3-certbot-nginx
    
    # Get certificate
    certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@"$domain"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ SSL Certificate đã được cài đặt thành công!${NC}"
        
        # Update N8N environment for HTTPS
        if [ -f "$N8N_ENV" ]; then
            sed -i "s|N8N_PROTOCOL=.*|N8N_PROTOCOL=https|" "$N8N_ENV"
            sed -i "s|N8N_EDITOR_BASE_URL=.*|N8N_EDITOR_BASE_URL=https://$domain|" "$N8N_ENV"
            sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=https://$domain|" "$N8N_ENV"
            systemctl restart n8n
        fi
        
        echo -e "${CYAN}🔗 URL HTTPS: https://$domain${NC}"
        
        # Setup auto-renewal
        crontab -l 2>/dev/null | grep -v certbot | crontab -
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        echo -e "${GREEN}✅ Đã thiết lập auto-renewal cho SSL${NC}"
    else
        echo -e "${RED}❌ Lỗi cài đặt SSL Certificate!${NC}"
    fi
}

# Update N8N to latest version
update_n8n() {
    echo -e "${GREEN}=== ⬆️ Nâng cấp phiên bản N8N ===${NC}"
    
    if ! check_n8n_installed; then
        echo -e "${RED}❌ N8N chưa được cài đặt!${NC}"
        return
    fi

    # Backup before update
    echo -e "${BLUE}📦 Đang backup dữ liệu...${NC}"
    export_data "auto-backup-before-update"

    # Get current version
    local current_version=$(npm list -g n8n 2>/dev/null | grep n8n | awk '{print $2}' || echo "Unknown")
    echo -e "${BLUE}📦 Phiên bản hiện tại: $current_version${NC}"

    # Stop N8N
    systemctl stop n8n

    # Update N8N
    echo -e "${BLUE}⬆️ Đang cập nhật N8N...${NC}"
    npm install n8n@latest -g

    # Start N8N
    systemctl start n8n

    # Wait and check
    sleep 10
    if systemctl is-active --quiet n8n; then
        local new_version=$(npm list -g n8n 2>/dev/null | grep n8n | awk '{print $2}' || echo "Unknown")
        echo -e "${GREEN}✅ N8N đã được nâng cấp thành công!${NC}"
        echo -e "${CYAN}📦 Phiên bản mới: $new_version${NC}"
    else
        echo -e "${RED}❌ Lỗi sau khi nâng cấp! Kiểm tra logs: journalctl -u n8n -f${NC}"
    fi
}

# Setup 2FA for SSH
setup_2fa() {
    echo -e "${GREEN}=== 🔒 Thiết lập Google Authenticator 2FA cho SSH ===${NC}"
    
    # Install required packages
    apt update
    apt install -y libpam-google-authenticator qrencode

    # Setup for root user
    echo -e "${BLUE}🔧 Đang cấu hình 2FA cho user root...${NC}"
    
    # Generate secret key
    google-authenticator -t -d -f -r 3 -R 30 -w 3 -e 10 -Q UTF8

    # Configure PAM
    if ! grep -q "pam_google_authenticator.so" /etc/pam.d/sshd; then
        echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
    fi

    # Configure SSH
    sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#AuthenticationMethods/AuthenticationMethods/' /etc/ssh/sshd_config
    
    # Add 2FA method
    if ! grep -q "AuthenticationMethods" /etc/ssh/sshd_config; then
        echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
    fi

    # Restart SSH
    systemctl restart sshd

    echo -e "${GREEN}✅ 2FA đã được kích hoạt!${NC}"
    echo -e "${YELLOW}⚠️ Lưu ý: Hãy quét mã QR bằng Google Authenticator trước khi đóng session này!${NC}"
    echo -e "${YELLOW}💡 Secret key đã được lưu trong: /root/.google_authenticator${NC}"
}

# Reset N8N credentials
reset_credentials() {
    echo -e "${RED}=== 👤 Đặt lại thông tin đăng nhập N8N ===${NC}"
    
    if [ ! -f "$N8N_ENV" ]; then
        echo -e "${RED}❌ File cấu hình N8N không tồn tại!${NC}"
        return
    fi

    while true; do
        read -p "👤 Tên đăng nhập mới (tối thiểu 4 ký tự): " NEW_USER
        if validate_input "$NEW_USER" 4 "Username"; then
            break
        fi
    done

    while true; do
        read -s -p "🔑 Mật khẩu mới (tối thiểu 8 ký tự): " NEW_PASS
        echo
        if validate_input "$NEW_PASS" 8 "Password"; then
            break
        fi
    done

    # Update credentials
    sed -i "s/^N8N_BASIC_AUTH_USER=.*/N8N_BASIC_AUTH_USER=$NEW_USER/" "$N8N_ENV"
    sed -i "s/^N8N_BASIC_AUTH_PASSWORD=.*/N8N_BASIC_AUTH_PASSWORD=$NEW_PASS/" "$N8N_ENV"

    # Restart N8N
    systemctl restart n8n

    if systemctl is-active --quiet n8n; then
        echo -e "${GREEN}✅ Đã cập nhật thông tin đăng nhập thành công!${NC}"
        echo -e "${CYAN}👤 Username: $NEW_USER${NC}"
        echo -e "${YELLOW}💡 Hãy đăng nhập lại với thông tin mới!${NC}"
    else
        echo -e "${RED}❌ Lỗi khởi động lại N8N!${NC}"
    fi
}

# Export N8N data with timestamp
export_data() {
    local backup_type="${1:-manual}"
    echo -e "${GREEN}=== 📤 Export toàn bộ dữ liệu N8N ===${NC}"
    
    if [ ! -d "$N8N_DIR" ]; then
        echo -e "${RED}❌ Thư mục N8N không tồn tại!${NC}"
        return
    fi

    create_backup_dir
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/n8n-backup-${backup_type}-${timestamp}.tar.gz"

    echo -e "${BLUE}📦 Đang tạo backup...${NC}"
    
    # Stop N8N temporarily for consistent backup
    systemctl stop n8n
    
    # Create comprehensive backup
    tar -czf "$backup_file" \
        -C / \
        root/.n8n \
        etc/n8n.env \
        etc/systemd/system/n8n.service \
        etc/nginx/sites-available/n8n 2>/dev/null || true

    # Restart N8N
    systemctl start n8n

    if [ -f "$backup_file" ]; then
        local file_size=$(du -h "$backup_file" | cut -f1)
        echo -e "${GREEN}✅ Đã export dữ liệu thành công!${NC}"
        echo -e "${CYAN}📁 File: $backup_file${NC}"
        echo -e "${CYAN}📊 Kích thước: $file_size${NC}"
        
        # List recent backups
        echo -e "${BLUE}📋 5 backup gần nhất:${NC}"
        ls -lt "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -5 | while read line; do
            echo "  $line"
        done
    else
        echo -e "${RED}❌ Lỗi tạo backup!${NC}"
    fi
}

# Import N8N data
import_data() {
    echo -e "${GREEN}=== 📥 Import dữ liệu N8N ===${NC}"
    
    # List available backups
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR/*.tar.gz 2>/dev/null)" ]; then
        echo -e "${BLUE}📋 Các file backup có sẵn:${NC}"
        ls -lt "$BACKUP_DIR"/*.tar.gz | nl
        echo
    fi

    read -p "📁 Nhập đường dẫn file backup (.tar.gz): " backup_file
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}❌ File không tồn tại: $backup_file${NC}"
        return
    fi

    # Confirm import
    echo -e "${YELLOW}⚠️ Import sẽ ghi đè toàn bộ dữ liệu hiện tại!${NC}"
    read -p "Bạn có chắc chắn? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}❌ Đã hủy import.${NC}"
        return
    fi

    # Backup current data before import
    echo -e "${BLUE}📦 Đang backup dữ liệu hiện tại...${NC}"
    export_data "before-import"

    # Stop N8N
    systemctl stop n8n

    # Extract backup
    echo -e "${BLUE}📥 Đang restore dữ liệu...${NC}"
    tar -xzf "$backup_file" -C /

    # Fix permissions
    chown -R root:root "$N8N_DIR" 2>/dev/null
    chmod 600 "$N8N_ENV" 2>/dev/null

    # Reload systemd and restart N8N
    systemctl daemon-reload
    systemctl start n8n

    # Check status
    sleep 5
    if systemctl is-active --quiet n8n; then
        echo -e "${GREEN}✅ Import dữ liệu thành công!${NC}"
    else
        echo -e "${RED}❌ Lỗi sau khi import! Kiểm tra logs: journalctl -u n8n -f${NC}"
    fi
}

# Get Redis information
get_redis_info() {
    echo -e "${GREEN}=== 🔴 Thông tin Redis ===${NC}"
    
    if ! command -v redis-cli &> /dev/null; then
        echo -e "${RED}❌ Redis chưa được cài đặt!${NC}"
        read -p "Bạn có muốn cài đặt Redis? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            apt update && apt install -y redis-server
            systemctl enable redis-server
            systemctl start redis-server
        else
            return
        fi
    fi

    echo -e "${BLUE}📊 Trạng thái Redis:${NC}"
    systemctl status redis-server --no-pager -l

    echo -e "\n${BLUE}📈 Thông tin chi tiết:${NC}"
    redis-cli info | grep -E 'redis_version|used_memory_human|connected_clients|total_commands_processed|uptime_in_days'

    echo -e "\n${BLUE}🔧 Cấu hình Redis:${NC}"
    redis-cli config get '*memory*' | head -10
}

# Delete N8N completely
delete_n8n() {
    echo -e "${RED}=== 🗑️ Xóa N8N và toàn bộ dữ liệu! ===${NC}"
    echo -e "${YELLOW}⚠️ Thao tác này sẽ xóa:${NC}"
    echo -e "  • Toàn bộ workflows và credentials"
    echo -e "  • File cấu hình"
    echo -e "  • Service và logs"
    echo -e "  • NGINX config"
    echo
    
    read -p "🚫 Gõ 'DELETE' để xác nhận xóa hoàn toàn: " confirm
    if [ "$confirm" != "DELETE" ]; then
        echo -e "${YELLOW}❌ Đã hủy thao tác.${NC}"
        return
    fi

    # Final backup before deletion
    echo -e "${BLUE}📦 Tạo backup cuối cùng...${NC}"
    export_data "final-backup-before-delete"

    # Stop and disable service
    systemctl stop n8n 2>/dev/null
    systemctl disable n8n 2>/dev/null

    # Remove files
    rm -rf "$N8N_DIR"
    rm -f "$N8N_ENV"
    rm -f "$N8N_SERVICE"
    rm -f /etc/nginx/sites-available/n8n
    rm -f /etc/nginx/sites-enabled/n8n
    rm -rf /var/log/n8n

    # Reload systemd
    systemctl daemon-reload

    # Uninstall N8N globally
    npm uninstall n8n -g 2>/dev/null

    # Restart nginx if available
    if command -v nginx &> /dev/null; then
        nginx -t && systemctl reload nginx
    fi

    echo -e "${GREEN}✅ Đã xóa toàn bộ N8N và dữ liệu!${NC}"
    echo -e "${BLUE}💾 Backup cuối được lưu tại: $BACKUP_DIR${NC}"
}

# Manage SSL certificates
manage_ssl() {
    echo -e "${GREEN}=== 🔧 Quản lý SSL Certificate ===${NC}"
    
    if ! command -v certbot &> /dev/null; then
        echo -e "${RED}❌ Certbot chưa được cài đặt!${NC}"
        return
    fi

    echo -e "${WHITE}1)${NC} 📋 Xem danh sách certificates"
    echo -e "${WHITE}2)${NC} 🔄 Renew certificates"
    echo -e "${WHITE}3)${NC} ➕ Thêm certificate mới"
    echo -e "${WHITE}4)${NC} 🗑️ Xóa certificate"
    echo
    read -p "Chọn hành động (1-4): " ssl_choice

    case $ssl_choice in
        1)
            echo -e "${BLUE}📋 Danh sách SSL certificates:${NC}"
            certbot certificates
            ;;
        2)
            echo -e "${BLUE}🔄 Đang renew certificates...${NC}"
            certbot renew --dry-run
            if [ $? -eq 0 ]; then
                certbot renew
                systemctl reload nginx
                echo -e "${GREEN}✅ Đã renew certificates thành công!${NC}"
            fi
            ;;
        3)
            read -p "🌐 Nhập domain cần thêm SSL: " new_domain
            if validate_domain "$new_domain"; then
                certbot --nginx -d "$new_domain"
            fi
            ;;
        4)
            read -p "🗑️ Nhập domain cần xóa SSL: " del_domain
            if [ -n "$del_domain" ]; then
                certbot delete --cert-name "$del_domain"
            fi
            ;;
        *)
            echo -e "${RED}❌ Lựa chọn không hợp lệ!${NC}"
            ;;
    esac
}

# View N8N logs
view_logs() {
    echo -e "${GREEN}=== 📋 Xem logs N8N ===${NC}"
    
    echo -e "${WHITE}1)${NC} 📄 Xem logs realtime"
    echo -e "${WHITE}2)${NC} 📚 Xem logs gần nhất (100 dòng)"
    echo -e "${WHITE}3)${NC} 🔍 Tìm kiếm lỗi"
    echo -e "${WHITE}4)${NC} 💾 Export logs"
    echo
    read -p "Chọn hành động (1-4): " log_choice

    case $log_choice in
        1)
            echo -e "${BLUE}📄 Logs realtime (Ctrl+C để thoát):${NC}"
            journalctl -u n8n -f
            ;;
        2)
            echo -e "${BLUE}📚 100 dòng logs gần nhất:${NC}"
            journalctl -u n8n -n 100 --no-pager
            ;;
        3)
            echo -e "${BLUE}🔍 Tìm kiếm lỗi:${NC}"
            journalctl -u n8n --no-pager | grep -i "error\|fail\|exception" | tail -20
            ;;
        4)
            local log_file="/tmp/n8n-logs-$(date +%Y%m%d-%H%M%S).txt"
            journalctl -u n8n --no-pager > "$log_file"
            echo -e "${GREEN}✅ Logs đã được export: $log_file${NC}"
            ;;
        *)
            echo -e "${RED}❌ Lựa chọn không hợp lệ!${NC}"
            ;;
    esac
}

# Show comprehensive system information
show_system_info() {
    echo -e "${GREEN}=== 📊 Thông tin hệ thống chi tiết ===${NC}"
    
    # OS Information
    echo -e "${BLUE}🖥️ Hệ điều hành:${NC}"
    if command -v lsb_release &> /dev/null; then
        lsb_release -a 2>/dev/null
    else
        cat /etc/os-release
    fi
    echo

    # System specs
    echo -e "${BLUE}⚙️ Thông số hệ thống:${NC}"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo

    # Network info
    echo -e "${BLUE}🌐 Thông tin mạng:${NC}"
    local public_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "N/A")
    echo "Public IP: $public_ip"
    echo "Local IP: $(ip route get 1 | awk '{print $7}' | head -1)"
    echo

    # Resources
    echo -e "${BLUE}💾 Tài nguyên hệ thống:${NC}"
    echo "$(free -h)"
    echo
    echo -e "${BLUE}💿 Dung lượng ổ đĩa:${NC}"
    df -h / /root 2>/dev/null
    echo

    # N8N specific info
    echo -e "${BLUE}🚀 Thông tin N8N:${NC}"
    if check_n8n_installed; then
        echo "Status: ✅ Đang chạy"
        local version=$(npm list -g n8n 2>/dev/null | grep n8n | awk '{print $2}' || echo "Unknown")
        echo "Version: $version"
        echo "Port: $(grep N8N_PORT $N8N_ENV 2>/dev/null | cut -d'=' -f2 || echo "5678")"
        echo "Data dir: $N8N_DIR"
        if [ -d "$N8N_DIR" ]; then
            echo "Data size: $(du -sh $N8N_DIR | cut -f1)"
        fi
    else
        echo "Status: ❌ Chưa cài đặt/không chạy"
    fi
    echo

    # Services status
    echo -e "${BLUE}🔧 Trạng thái services:${NC}"
    for service in n8n nginx redis-server; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            echo "$service: ✅ Active"
        else
            echo "$service: ❌ Inactive"
        fi
    done
    echo

    # Node.js info
    echo -e "${BLUE}📦 Môi trường phát triển:${NC}"
    if command -v node &> /dev/null; then
        echo "Node.js: $(node --version)"
        echo "NPM: $(npm --version)"
    else
        echo "Node.js: ❌ Chưa cài đặt"
    fi
    echo

    # Security info
    echo -e "${BLUE}🔒 Bảo mật:${NC}"
    if command -v ufw &> /dev/null; then
        echo "UFW: $(ufw status | head -1)"
    fi
    if [ -f /root/.google_authenticator ]; then
        echo "2FA SSH: ✅ Đã kích hoạt"
    else
        echo "2FA SSH: ❌ Chưa kích hoạt"
    fi
    
    # SSL info
    if [ -d /etc/letsencrypt/live ]; then
        local ssl_count=$(ls /etc/letsencrypt/live | wc -l)
        echo "SSL Certificates: $ssl_count domain(s)"
    else
        echo "SSL Certificates: ❌ Chưa có"
    fi
}

# Install script globally and create alias
install_script_globally() {
    local script_path="$0"
    
    # Copy script to global location
    cp "$script_path" "$SCRIPT_NAME"
    chmod +x "$SCRIPT_NAME"
    
    # Create alias in bashrc
    if ! grep -q "alias $ALIAS_NAME=" /root/.bashrc; then
        echo "alias $ALIAS_NAME='$SCRIPT_NAME'" >> /root/.bashrc
    fi
    
    # Create alias for current session
    alias $ALIAS_NAME="$SCRIPT_NAME"
    
    echo -e "${GREEN}✅ Script đã được cài đặt globally!${NC}"
    echo -e "${CYAN}🚀 Sử dụng lệnh '$ALIAS_NAME' để truy cập nhanh${NC}"
}

# Cleanup and optimization
cleanup_system() {
    echo -e "${BLUE}🧹 Đang dọn dẹp hệ thống...${NC}"
    
    # Clean package cache
    apt autoremove -y
    apt autoclean
    
    # Clean npm cache
    if command -v npm &> /dev/null; then
        npm cache clean --force
    fi
    
    # Clean old logs
    if [ -d /var/log/n8n ]; then
        find /var/log/n8n -name "*.log" -mtime +30 -delete
    fi
    
    # Clean old backups (keep last 10)
    if [ -d "$BACKUP_DIR" ]; then
        ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +11 | xargs rm -f
    fi
    
    echo -e "${GREEN}✅ Dọn dẹp hoàn tất!${NC}"
}

# Main menu loop
main() {
    # Check root permissions
    check_root
    
    # Install script globally on first run
    if [ ! -f "$SCRIPT_NAME" ]; then
        install_script_globally
    fi
    
    # Create backup directory
    create_backup_dir
    
    # Main loop
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) install_n8n ;;
            2) change_domain ;;
            3) update_n8n ;;
            4) setup_2fa ;;
            5) reset_credentials ;;
            6) export_data ;;
            7) import_data ;;
            8) get_redis_info ;;
            9) delete_n8n ;;
            10) show_system_info ;;
            11) manage_ssl ;;
            12) view_logs ;;
            0)
                cleanup_system
                echo -e "${GREEN}✨ Cảm ơn bạn đã sử dụng N8N Server Manager!${NC}"
                echo -e "${CYAN}🌐 Visit: https://bietdoitinhnhue.com${NC}"
                echo -e "${YELLOW}💡 Sử dụng lệnh 'n8n' để truy cập nhanh lần sau${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Lựa chọn không hợp lệ. Vui lòng chọn từ 0-12.${NC}"
                sleep 2
                ;;
        esac
        
        echo ""
        read -p "⏎ Nhấn Enter để tiếp tục..." -t 10
    done
}

# Signal handlers
trap 'echo -e "\n${YELLOW}👋 Tạm biệt!${NC}"; exit 0' INT TERM

# Run main function
main "$@"