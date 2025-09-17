#!/bin/bash

# ================================================================
# N8N All-in-One Management Script v3.3 (Anti-Flicker Edition)
# Dùng cho Ubuntu/Debian. Yêu cầu quyền root.
# Phiên bản: 3.3
# Phát hành ngày: 17-09-2025
# Phát triển bởi: Biệt Đội Tinh Nhuệ
#  Liên hệ: https://bietdoitinhnhue.com
# ================================================================

# ----------- Cấu hình màu sắc & biến toàn cục -----------
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

N8N_USER="n8n"
N8N_HOME="/home/$N8N_USER"
N8N_DIR="$N8N_HOME/.n8n"
ENV_FILE="$N8N_DIR/.env"
SERVICE_FILE="/etc/systemd/system/n8n.service"
LOG_FILE="/var/log/n8n-management.log"
BACKUP_DIR="/root/n8n-backups"

# Biến bổ sung cho chế độ triển khai
DEFAULT_PORT="${DEFAULT_PORT:-5678}"
DEPLOY_MODE=""       # "domain" | "ipport"
N8N_DOMAIN=""        # dùng khi DEPLOY_MODE=domain
N8N_PORT=""          # số port khi DEPLOY_MODE=ipport

# ----------- Kiểm tra quyền root -----------
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ Script này phải chạy với quyền root hoặc sudo.${NC}"
    echo "Vui lòng thử lại: sudo $0"
    exit 1
fi

# ----------- Tối ưu hóa & Thiết lập ban đầu -----------
mkdir -p "$BACKUP_DIR"

# Lấy IP một lần duy nhất để tránh gọi curl liên tục
SERVER_IP=$(curl -s ifconfig.me)
# Fallback IP nếu curl fail
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

# ----------- Hàm hiển thị header -----------
show_header() {
    # Dùng escape để xóa màn hình mượt
    printf '\033[H\033[2J'
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗"
    echo "║         N8N Management v3.3 - Biệt Đội Tinh Nhuệ             ║"
    echo "║         https://bietdoitinhnhue.com - Phát triển bởi BĐTNH   ║"
    echo "║         Phiên bản: 3.3 - Phát hành ngày: 17-09-2025          ║"
    echo "║         Nếu bạn muốn mời mình CAFE                           ║"
    echo "║         Vietcombank - 9968333342 - Nguyen Huy Lan            ║"
    echo "╚══════════════════════════════════════════════════════════════╝${NC}"
    echo " Server IP: $SERVER_IP | $(date '+%Y-%m-%d %H:%M:%S') | Uptime: $(uptime -p)"
    if systemctl is-active --quiet n8n; then
        local domain=$(grep 'N8N_HOST' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        local proto=$(grep 'N8N_PROTOCOL' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        local port=$(grep '^N8N_PORT=' "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        if [[ "$proto" = "https" ]]; then
            echo -e "${GREEN} n8n: RUNNING https://$domain${NC}"
        else
            echo -e "${GREEN} n8n: RUNNING http://$domain:$port${NC}"
        fi
    else
        echo -e "${YELLOW} n8n: NOT RUNNING${NC}"
    fi
    echo ""
}

# ----------- Hàm tiện ích -----------
log_action() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$USER] $1" >> "$LOG_FILE"; }
press_enter() { echo ""; read -p "Nhấn Enter để quay lại menu..."; }
confirm_action() { read -p "$1 [y/N]: " resp; [[ "$resp" =~ ^([yY][eE][sS]|[yY])$ ]]; }
cleanup_logs() { find /var/log -name "*.log" -size +50M -delete 2>/dev/null; find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null; }
backup_env() { [ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$ENV_FILE.bak-$(date +%Y%m%d_%H%M%S)"; }

get_domain() {
    N8N_DOMAIN="${N8N_DOMAIN:-$(grep "N8N_HOST" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')}"
    while [[ ! $N8N_DOMAIN =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; do
        read -p "Nhập domain của bạn (VD: bietdoitinhnhue.com): " N8N_DOMAIN
    done
}

validate_domain_ip() {
    # Đảm bảo có dnsutils (chứa lệnh dig)
    if ! command -v dig &> /dev/null; then
        echo -e "${YELLOW}Lệnh 'dig' không tồn tại. Đang cài đặt dnsutils...${NC}"
        apt-get update > /dev/null && apt-get install -y dnsutils
    fi

    local domain_ip=$(dig +short "$N8N_DOMAIN" A | tail -1)
    if [[ "$SERVER_IP" != "$domain_ip" ]]; then
        echo -e "${YELLOW}⚠️  Domain $N8N_DOMAIN chưa trỏ về IP $SERVER_IP (đang trỏ về: ${domain_ip:-N/A}).${NC}"
        confirm_action "Tiếp tục thao tác dù có thể lỗi SSL?" || return 1
    fi
    return 0
}

check_n8n() {
    [ -f "$SERVICE_FILE" ] || { echo -e "${YELLOW}n8n chưa được cài đặt.${NC}"; return 1; }
}

get_deployment_mode() {
    echo ""
    echo "Chọn chế độ triển khai n8n:"
    echo "  1) Dùng DOMAIN (HTTPS + Nginx + SSL)"
    echo "  2) Dùng IP:PORT (HTTP trực tiếp, không cần domain, không SSL)"
    read -p "Lựa chọn [1/2]: " mode_choice
    case "$mode_choice" in
        1) DEPLOY_MODE="domain" ;;
        2) DEPLOY_MODE="ipport" ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; return 1 ;;
    esac

    if [ "$DEPLOY_MODE" = "domain" ]; then
        get_domain
        validate_domain_ip || return 1
    else
        # Hỏi PORT, mặc định 5678, validate 1-65535
        while true; do
            read -p "Nhập PORT để chạy n8n (mặc định $DEFAULT_PORT): " N8N_PORT
            N8N_PORT="${N8N_PORT:-$DEFAULT_PORT}"
            if [[ "$N8N_PORT" =~ ^[0-9]+$ ]] && [ "$N8N_PORT" -ge 1 ] && [ "$N8N_PORT" -le 65535 ]; then
                break
            else
                echo -e "${YELLOW}PORT không hợp lệ.${NC}"
            fi
        done
        echo -e "${GREEN}Sẽ chạy n8n ở: http://$SERVER_IP:$N8N_PORT${NC}"
    fi
}

# ----------- Các hàm chức năng chính -----------

install_n8n() {
    show_header
    echo "--- Cài đặt n8n ---"
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}n8n đã cài rồi.${NC}"
        confirm_action "Cài lại (overwrite)?" || return
    fi

    # Chọn mode cài
    get_deployment_mode || return
    backup_env

    echo "--> Cài đặt packages..."
    apt update && apt upgrade -y
    apt install -y curl gnupg2 ca-certificates lsb-release ufw build-essential

    echo "--> Cấu hình Firewall..."
    ufw allow OpenSSH

    echo "--> Cài NodeJS LTS + n8n..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt install -y nodejs
    npm install -g n8n

    # Tạo user & thư mục
    echo "--> Tạo user, thư mục..."
    id "$N8N_USER" &>/dev/null || useradd -m -d "$N8N_HOME" -s /bin/bash "$N8N_USER"
    mkdir -p "$N8N_DIR"; chown -R "$N8N_USER:$N8N_USER" "$N8N_HOME"; chmod 700 "$N8N_DIR"

    N8N_PASSWORD=$(openssl rand -hex 12)

    if [ "$DEPLOY_MODE" = "domain" ]; then
        # Cần nginx + ssl
        apt install -y nginx
        ufw allow 'Nginx Full'; ufw --force enable

        cat <<EOF > "$ENV_FILE"
N8N_HOST="$N8N_DOMAIN"
N8N_PROTOCOL="https"
N8N_PORT=5678
NODE_ENV="production"
WEBHOOK_TUNNEL_URL="https://$N8N_DOMAIN/"
N8N_EDITOR_BASE_URL="https://$N8N_DOMAIN/"
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
EOF
        chown "$N8N_USER:$N8N_USER" "$ENV_FILE"; chmod 600 "$ENV_FILE"

        echo "--> Systemd service..."
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=n8n automation
After=network.target
[Service]
Type=simple
User=$N8N_USER
EnvironmentFile=$ENV_FILE
ExecStart=$(command -v n8n)
Restart=always
WorkingDirectory=$N8N_HOME
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable n8n; systemctl start n8n

        echo "--> Nginx reverse proxy..."
        tee "/etc/nginx/sites-available/$N8N_DOMAIN" > /dev/null <<EOF
server {
    listen 80;
    server_name $N8N_DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
        ln -sf "/etc/nginx/sites-available/$N8N_DOMAIN" "/etc/nginx/sites-enabled/$N8N_DOMAIN"
        nginx -t && systemctl reload nginx

        manage_ssl_internal

        log_action "Cài n8n (DOMAIN) cho $N8N_DOMAIN"
        echo -e "${GREEN}✅ CÀI ĐẶT HOÀN TẤT!${NC}"
        echo "URL: https://$N8N_DOMAIN | User: admin | Pass: $N8N_PASSWORD"

    else
        # IP:PORT - không dùng nginx/ssl, chạy trực tiếp
        ufw allow "$N8N_PORT"/tcp; ufw --force enable

        cat <<EOF > "$ENV_FILE"
N8N_HOST="$SERVER_IP"
N8N_PROTOCOL="http"
N8N_PORT=$N8N_PORT
NODE_ENV="production"
WEBHOOK_TUNNEL_URL="http://$SERVER_IP:$N8N_PORT/"
N8N_EDITOR_BASE_URL="http://$SERVER_IP:$N8N_PORT/"
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
EOF
        chown "$N8N_USER:$N8N_USER" "$ENV_FILE"; chmod 600 "$ENV_FILE"

        echo "--> Systemd service..."
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=n8n automation
After=network.target
[Service]
Type=simple
User=$N8N_USER
EnvironmentFile=$ENV_FILE
ExecStart=$(command -v n8n)
Restart=always
WorkingDirectory=$N8N_HOME
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable n8n; systemctl start n8n

        log_action "Cài n8n (IP:PORT) tại $SERVER_IP:$N8N_PORT"
        echo -e "${GREEN}✅ CÀI ĐẶT HOÀN TẤT!${NC}"
        echo "URL: http://$SERVER_IP:$N8N_PORT | User: admin | Pass: $N8N_PASSWORD"
    fi
}

update_n8n() {
    check_n8n || return
    show_header
    backup_env
    echo "--- Update n8n ---"
    npm install -g n8n
    systemctl restart n8n
    echo -n "Phiên bản: "; sudo -u $N8N_USER n8n --version
    log_action "Update n8n"
}

update_node_npm() {
    show_header
    echo "--- Cập nhật Node.js và npm ---"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt install -y nodejs
    npm install -g npm@latest
    echo "Node.js: $(node -v) | npm: $(npm -v)"
    log_action "Update Node/npm"
}

setup_n8n_2fa_info() {
    show_header
    echo -e "${CYAN}--- 2FA cho n8n (phiên bản community chưa hỗ trợ built-in 2FA) ---${NC}"
    echo "1. Sử dụng proxy xác thực (Authelia, Authentik, Keycloak)"
    echo "2. Cloudflare Access (miễn phí, đơn giản cho domain quản lý Cloudflare)"
    echo "3. n8n Enterprise (mua bản quyền)"
    echo ""
    echo -e "${YELLOW}Đọc thêm: https://docs.n8n.io/hosting/advanced/authentication/${NC}"
}

reset_credentials() {
    check_n8n || return
    show_header
    backup_env
    local current_user=$(grep "N8N_BASIC_AUTH_USER" "$ENV_FILE" | cut -d'=' -f2)
    NEW_PASSWORD=$(openssl rand -hex 12)
    sed -i "/N8N_BASIC_AUTH_PASSWORD/c\N8N_BASIC_AUTH_PASSWORD=$NEW_PASSWORD" "$ENV_FILE"
    systemctl restart n8n
    log_action "Reset password user $current_user"
    echo -e "${GREEN}✅ Đã đặt lại password!${NC} User: $current_user | Pass: $NEW_PASSWORD"
}

manage_ssl_internal() {
    echo "--> Cài đặt Certbot..."
    apt install -y certbot python3-certbot-nginx
    echo "--> Xử lý SSL cho $N8N_DOMAIN..."
    certbot --nginx --non-interactive --agree-tos --redirect -d "$N8N_DOMAIN" -m "admin@$N8N_DOMAIN"
    log_action "Setup SSL cho $N8N_DOMAIN"
    echo -e "${GREEN}✅ SSL OK!${NC}"
}

manage_ssl() {
    show_header
    if [ -z "$N8N_DOMAIN" ]; then
        get_domain
    fi
    if [[ -z "$N8N_DOMAIN" || "$N8N_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${YELLOW}Chức năng SSL chỉ áp dụng khi dùng DOMAIN.${NC}"
        return
    fi
    validate_domain_ip || return
    manage_ssl_internal
}

export_data() {
    check_n8n || return; show_header
    BACKUP_FILE="$BACKUP_DIR/n8n-data-$(date +%Y-%m-%d_%H%M).tar.gz"
    echo "Dừng n8n..."; systemctl stop n8n
    tar -czf "$BACKUP_FILE" -C "$N8N_HOME" .n8n
    systemctl start n8n
    log_action "Export backup n8n"
    echo -e "${GREEN}✅ Sao lưu thành công: $BACKUP_FILE${NC}"
}

import_data() {
    check_n8n || return; show_header
    echo -e "${RED}CẢNH BÁO: Ghi đè toàn bộ dữ liệu n8n hiện tại!${NC}"
    read -p "Nhập đường dẫn file backup (.tar.gz): " BACKUP_FILE
    [ ! -f "$BACKUP_FILE" ] && { echo -e "${RED}❌ File không tồn tại!${NC}"; return; }
    confirm_action "Bạn chắc chắn phục hồi?" || return
    tar -czf "$BACKUP_DIR/n8n-pre-restore-$(date +%Y-%m-%d_%H%M).tar.gz" -C "$N8N_HOME" .n8n
    echo "Dừng n8n..."; systemctl stop n8n
    rm -rf "$N8N_DIR"; tar -xzf "$BACKUP_FILE" -C "$N8N_HOME"
    chown -R "$N8N_USER:$N8N_USER" "$N8N_DIR"
    systemctl start n8n
    log_action "Import backup $BACKUP_FILE"
    echo -e "${GREEN}✅ Phục hồi thành công!${NC}"
}

uninstall_n8n() {
    check_n8n || return; show_header
    confirm_action "⚠️ GỠ CÀI ĐẶT n8n và file cấu hình. Tiếp tục?" || return
    N8N_DOMAIN_DETECTED=$(grep "N8N_HOST" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
    systemctl stop n8n; systemctl disable n8n
    # Gỡ nginx site nếu có
    if [ -n "$N8N_DOMAIN_DETECTED" ] && [ -f "/etc/nginx/sites-available/$N8N_DOMAIN_DETECTED" ]; then
        rm -f "/etc/nginx/sites-enabled/$N8N_DOMAIN_DETECTED" "/etc/nginx/sites-available/$N8N_DOMAIN_DETECTED"
        systemctl reload nginx || true
    fi
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    npm uninstall -g n8n
    if [[ "$N8N_USER" != "root" && -n "$N8N_USER" ]]; then
        confirm_action "Xóa luôn user $N8N_USER và dữ liệu?" && userdel -r "$N8N_USER"
    fi
    log_action "Uninstall n8n host $N8N_DOMAIN_DETECTED"
    echo -e "${GREEN}✅ Đã gỡ cài đặt n8n hoàn tất.${NC}"
}

show_system_info() {
    show_header
    echo "--- Dung lượng ổ cứng ---"; df -h
    echo "--- RAM & Swap ---"; free -h
    cleanup_logs
    echo "Đã tự động xóa log >50MB hoặc cũ hơn 30 ngày."
    log_action "Xem thông tin hệ thống"
}

install_file_manager() {
    show_header
    apt update
    apt install -y mc
    echo -e "${GREEN}Cài đặt 'mc' thành công! Gõ 'mc' để dùng.${NC}"
    log_action "Cài Midnight Commander"
}

manage_mysql() {
    show_header
    apt update
    apt install -y mysql-server
    mysql_secure_installation
    echo -e "${GREEN}MySQL Server đã sẵn sàng!${NC}"
    log_action "Cài MySQL"
}

manage_postgresql() {
    show_header
    apt update
    apt install -y postgresql postgresql-contrib
    echo -e "${GREEN}PostgreSQL Server đã sẵn sàng!${NC}"
    log_action "Cài PostgreSQL"
}

setup_gdrive_backup() {
    show_header
    if ! command -v rclone &> /dev/null; then
        curl -fsSL https://rclone.org/install.sh | bash
    fi
    rclone config
    echo -e "${GREEN}✅ Đã cấu hình rclone!${NC}"
    log_action "Cấu hình rclone"
}

backup_mysql_to_gdrive() {
    show_header
    read -p "Database cần backup: " DBNAME
    read -p "User MySQL: " DBUSER
    read -s -p "Password: " DBPASS; echo
    read -p "Tên remote rclone (VD: gdrive): " RCLONE_REMOTE
    FILE="mysql-${DBNAME}-$(date +%Y-%m-%d_%H%M).sql.gz"
    mysqldump -u"$DBUSER" -p"$DBPASS" "$DBNAME" | gzip > "/tmp/$FILE"
    rclone copy "/tmp/$FILE" "${RCLONE_REMOTE}:MySQL_Backups/"
    rm "/tmp/$FILE"
    echo -e "${GREEN}✅ Backup MySQL $DBNAME lên GDrive thành công!${NC}"
    log_action "Backup MySQL $DBNAME lên GDrive"
}

backup_psql_to_gdrive() {
    show_header
    read -p "Database cần backup: " DBNAME
    read -p "User PostgreSQL: " DBUSER
    read -s -p "Password: " PGPASSWORD; echo
    read -p "Tên remote rclone: " RCLONE_REMOTE
    export PGPASSWORD
    FILE="psql-${DBNAME}-$(date +%Y-%m-%d_%H%M).sql.gz"
    pg_dump -U "$DBUSER" -h localhost -d "$DBNAME" | gzip > "/tmp/$FILE"
    unset PGPASSWORD
    rclone copy "/tmp/$FILE" "${RCLONE_REMOTE}:PostgreSQL_Backups/"
    rm "/tmp/$FILE"
    echo -e "${GREEN}✅ Backup PostgreSQL $DBNAME lên GDrive thành công!${NC}"
    log_action "Backup PostgreSQL $DBNAME lên GDrive"
}

change_domain() {
    check_n8n || return
    show_header
    echo "--- Đổi domain cho n8n ---"

    get_domain
    validate_domain_ip || return
    backup_env

    # Đảm bảo nginx + certbot
    apt update
    apt install -y nginx certbot python3-certbot-nginx
    ufw allow 'Nginx Full'

    # Cập nhật ENV sang HTTPS + domain mới
    sed -i "s#^N8N_HOST=.*#N8N_HOST=\"$N8N_DOMAIN\"#g" "$ENV_FILE"
    sed -i "s#^N8N_PROTOCOL=.*#N8N_PROTOCOL=\"https\"#g" "$ENV_FILE"
    sed -i "s#^N8N_PORT=.*#N8N_PORT=5678#g" "$ENV_FILE"
    sed -i "s#^WEBHOOK_TUNNEL_URL=.*#WEBHOOK_TUNNEL_URL=\"https://$N8N_DOMAIN/\"#g" "$ENV_FILE"
    sed -i "s#^N8N_EDITOR_BASE_URL=.*#N8N_EDITOR_BASE_URL=\"https://$N8N_DOMAIN/\"#g" "$ENV_FILE"

    # Tạo server block mới (proxy tới 127.0.0.1:5678)
    tee "/etc/nginx/sites-available/$N8N_DOMAIN" > /dev/null <<EOF
server {
    listen 80;
    server_name $N8N_DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "/etc/nginx/sites-available/$N8N_DOMAIN" "/etc/nginx/sites-enabled/$N8N_DOMAIN"
    nginx -t && systemctl reload nginx

    # Lấy/ gia hạn SSL và bật redirect
    certbot --nginx --non-interactive --agree-tos --redirect -d "$N8N_DOMAIN" -m "admin@$N8N_DOMAIN"

    systemctl restart n8n
    log_action "Đổi domain sang $N8N_DOMAIN"
    echo -e "${GREEN}✅ Đã chuyển sang domain mới: https://$N8N_DOMAIN${NC}"
}

change_port() {
    check_n8n || return
    show_header
    echo "--- Đổi PORT cho n8n ---"
    backup_env

    local old_port=$(grep "^N8N_PORT=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"')
    while true; do
        read -p "Nhập PORT mới (1-65535): " NEW_PORT
        if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1 ] && [ "$NEW_PORT" -le 65535 ]; then
            break
        else
            echo -e "${YELLOW}PORT không hợp lệ.${NC}"
        fi
    done

    # Mở firewall port mới
    ufw allow "$NEW_PORT"/tcp

    # Update ENV
    sed -i "s#^N8N_PORT=.*#N8N_PORT=$NEW_PORT#g" "$ENV_FILE"
    # Nếu đang chạy IP mode (protocol=http và host là SERVER_IP) thì cập nhật URLs cho đúng
    if grep -q '^N8N_PROTOCOL="http"' "$ENV_FILE"; then
        sed -i "s#^WEBHOOK_TUNNEL_URL=.*#WEBHOOK_TUNNEL_URL=\"http://$SERVER_IP:$NEW_PORT/\"#g" "$ENV_FILE"
        sed -i "s#^N8N_EDITOR_BASE_URL=.*#N8N_EDITOR_BASE_URL=\"http://$SERVER_IP:$NEW_PORT/\"#g" "$ENV_FILE"
    fi

    # Nếu có nginx site dùng proxy_pass 127.0.0.1:<old_port> thì sửa
    if grep -R "proxy_pass http://127.0.0.1:$old_port" /etc/nginx/sites-available/ >/dev/null 2>&1; then
        sed -i "s#proxy_pass http://127.0.0.1:$old_port#proxy_pass http://127.0.0.1:$NEW_PORT#g" /etc/nginx/sites-available/*
        nginx -t && systemctl reload nginx
    fi

    systemctl restart n8n
    log_action "Đổi PORT n8n từ $old_port sang $NEW_PORT"
    echo -e "${GREEN}✅ Đã đổi PORT: $NEW_PORT${NC}"
}

# ========================= MENU CHÍNH =========================
main_menu() {
    # Chuyển sang màn hình ảo khi bắt đầu và đặt bẫy để thoát an toàn
    trap 'tput cnorm; tput rmcup; exit' EXIT INT TERM
    tput smcup # Lưu màn hình hiện tại và chuyển sang màn hình ảo
    tput civis # Ẩn con trỏ

    while true; do
        tput cnorm # Hiện lại con trỏ để người dùng nhập
        show_header
        echo -e "${GREEN}--- Quản lý N8N ---${NC}"
        echo " 1) Cài đặt n8n (DOMAIN HTTPS hoặc IP:PORT HTTP)"
        echo " 2) Cập nhật n8n"
        echo " 3) Cập nhật Node.js & npm"
        echo " 4) [INFO] 2FA cho n8n"
        echo " 5) Đặt lại mật khẩu truy cập"
        echo " 6) Cài đặt / Gia hạn SSL (DOMAIN)"
        echo " 7) Sao lưu (Export) dữ liệu n8n"
        echo " 8) Phục hồi (Import) dữ liệu n8n"
        echo " 9) Gỡ cài đặt n8n"
        echo ""
        echo -e "${GREEN}--- Quản lý Server & Database ---${NC}"
        echo "10) Thông tin hệ thống & cleanup log"
        echo "11) Cài đặt File Manager (mc)"
        echo "12) Cài MySQL | Cài PostgreSQL"
        echo "13) Cấu hình GDrive backup (rclone)"
        echo "14) Backup MySQL lên GDrive"
        echo "15) Backup PostgreSQL lên GDrive"
        echo ""
        echo -e "${GREEN}--- Chuyển đổi cấu hình ---${NC}"
        echo "16) Đổi domain (IP:PORT → DOMAIN hoặc đổi domain khác)"
        echo "17) Đổi PORT n8n"
        echo ""
        echo -e "${YELLOW}0) Thoát${NC}"
        echo ""
        read -p "Chọn chức năng: " choice
        tput civis # Ẩn con trỏ khi xử lý

        case "$choice" in
            1) install_n8n; press_enter ;;
            2) update_n8n; press_enter ;;
            3) update_node_npm; press_enter ;;
            4) setup_n8n_2fa_info; press_enter ;;
            5) reset_credentials; press_enter ;;
            6) manage_ssl; press_enter ;;
            7) export_data; press_enter ;;
            8) import_data; press_enter ;;
            9) uninstall_n8n; press_enter ;;
            10) show_system_info; press_enter ;;
            11) install_file_manager; press_enter ;;
            12)
                tput cnorm
                read -p "Cài MySQL (m) hay PostgreSQL (p)? [m/p]: " db_choice
                tput civis
                case "$db_choice" in
                    m|M) manage_mysql ;;
                    p|P) manage_postgresql ;;
                    *) echo -e "${RED}Lựa chọn không hợp lệ.${NC}" ;;
                esac
                press_enter
                ;;
            13) setup_gdrive_backup; press_enter ;;
            14) backup_mysql_to_gdrive; press_enter ;;
            15) backup_psql_to_gdrive; press_enter ;;
            16) change_domain; press_enter ;;
            17) change_port; press_enter ;;
            0) exit 0 ;;
            *) echo -e "${RED}❌ Lựa chọn không hợp lệ!${NC}"; press_enter ;;
        esac
    done
}

# ========================= START =========================
main_menu
