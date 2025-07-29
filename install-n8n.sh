#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

show_header() {
    clear
    echo -e "${CYAN}+==============================================================+${NC}"
    echo -e "${CYAN}|                   Server Manager                             |${NC}"
    echo -e "${CYAN}|             Powered by bietdoitinhnhue.com                    |${NC}"
    echo -e "${CYAN}+==============================================================+${NC}"
    echo -e "${YELLOW}Phím tắt: Ctrl + C hoặc nhập 0 để thoát${NC}"
}

show_menu() {
    show_header
    echo -e "${WHITE}1)${NC}  Cài đặt N8N                         ${WHITE}6)${NC}  ${YELLOW}Export workflow & credentials${NC}"
    echo -e "${WHITE}2)${NC}  Thay đổi tên miền                   ${WHITE}7)${NC}  Import workflow & credentials"
    echo -e "${WHITE}3)${NC}  Nâng cấp phiên bản N8N              ${WHITE}8)${NC}  ${GREEN}Lấy thông tin Redis${NC}"
    echo -e "${WHITE}4)${NC}  Bật xác thực 2 bước (2FA/MFA)       ${WHITE}9)${NC}  ${RED}Xóa N8N và cài đặt lại${NC}"
    echo -e "${WHITE}5)${NC}  Đặt lại thông tin đăng nhập         ${WHITE}10)${NC} ${BLUE}Thông tin hệ thống${NC}"
    echo "--------------------------------------------------------------------------------"
    echo -n -e "${WHITE}Nhập lựa chọn của bạn (1-10) [ 0 = Thoát ]:${NC} "
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Vui lòng chạy với quyền root: sudo $0${NC}"
        exit 1
    fi

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
            0)
                echo -e "${GREEN}Cảm ơn bạn đã sử dụng Server Manager!${NC}"
                echo -e "${CYAN}Visit: https://bietdoitinhnhue.com${NC}"
                exit 0
                ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ. Vui lòng thử lại.${NC}" ;;
        esac
        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

install_n8n() {
    echo -e "${GREEN}=== Cài đặt N8N Workflow Automation (Bảo mật) ===${NC}"

    # Check if already installed
    if command -v n8n &> /dev/null; then
        echo -e "${YELLOW}N8N đã được cài đặt. Phiên bản: $(n8n --version)${NC}"
        read -p "Bạn có muốn cài đặt lại? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    # Prompt for credentials
    while true; do
        read -p "Nhập tên đăng nhập admin: " N8N_USER
        [ -z "$N8N_USER" ] && echo -e "${RED}Username không được để trống!${NC}" || break
    done
    while true; do
        read -s -p "Nhập mật khẩu admin: " N8N_PASS
        echo
        [ -z "$N8N_PASS" ] && echo -e "${RED}Password không được để trống!${NC}" || break
    done

    change_domain() {
    echo -e "${GREEN}=== Cập nhật tên miền cho N8N ===${NC}"
    read -p "Nhập domain mới (vd: n8n.tenmiencuaban.com): " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain không được để trống!${NC}"
        return
    fi

    # Tạo nginx config đơn giản
    cat > /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
    systemctl reload nginx
    echo -e "${GREEN}✓ Đã cấu hình NGINX cho domain: $domain${NC}"
    echo -e "${YELLOW}Hãy trỏ A record của domain về IP: $(curl -s ifconfig.me)${NC}"
}

update_n8n() {
    echo -e "${GREEN}=== Nâng cấp phiên bản N8N ===${NC}"
    systemctl stop n8n
    npm install n8n -g
    systemctl restart n8n
    echo -e "${GREEN}✓ N8N đã được nâng cấp. Phiên bản mới: $(n8n --version)${NC}"
}

setup_2fa() {
    echo -e "${GREEN}=== Thiết lập Google Authenticator 2FA cho SSH ===${NC}"
    apt install -y libpam-google-authenticator qrencode
    google-authenticator -t -d -f -r 3 -R 30 -w 3
    echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
    sed -i 's/#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e "${YELLOW}Đã bật 2FA, hãy quét mã QR ở trên app Google Authenticator!${NC}"
}

reset_credentials() {
    echo -e "${RED}=== Đặt lại user/password N8N ===${NC}"
    read -p "Tên đăng nhập mới: " NEW_USER
    read -s -p "Mật khẩu mới: " NEW_PASS; echo
    if [ -z "$NEW_USER" ] || [ -z "$NEW_PASS" ]; then
        echo -e "${RED}Thông tin không hợp lệ!${NC}"; return
    fi
    sed -i "s/^N8N_BASIC_AUTH_USER=.*/N8N_BASIC_AUTH_USER=$NEW_USER/" /etc/n8n.env
    sed -i "s/^N8N_BASIC_AUTH_PASSWORD=.*/N8N_BASIC_AUTH_PASSWORD=$NEW_PASS/" /etc/n8n.env
    systemctl restart n8n
    echo -e "${GREEN}✓ Đã đổi user/password, hãy login lại!${NC}"
}

export_data() {
    echo -e "${GREEN}=== Export toàn bộ dữ liệu N8N ===${NC}"
    NOW=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="/root/n8n-backup-$NOW.tar.gz"
    tar -czf "$BACKUP_FILE" /root/.n8n
    echo -e "${GREEN}✓ Đã export dữ liệu ra: $BACKUP_FILE${NC}"
}

import_data() {
    echo -e "${GREEN}=== Import dữ liệu N8N ===${NC}"
    read -p "Nhập đường dẫn file backup (.tar.gz): " FILE
    if [ ! -f "$FILE" ]; then
        echo -e "${RED}File không tồn tại!${NC}"; return
    fi
    systemctl stop n8n
    tar -xzf "$FILE" -C /root/
    systemctl restart n8n
    echo -e "${GREEN}✓ Đã import dữ liệu xong!${NC}"
}

get_redis_info() {
    echo -e "${GREEN}=== Thông tin Redis ===${NC}"
    systemctl status redis-server || echo -e "${YELLOW}Redis chưa cài đặt!${NC}"
    redis-cli info | grep -E 'version|used_memory|connected_clients|total_commands_processed'
}

delete_n8n() {
    echo -e "${RED}=== Xóa N8N và toàn bộ dữ liệu! ===${NC}"
    read -p "Bạn chắc chắn? (gõ YES để xác nhận): " CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        echo -e "${YELLOW}Đã hủy thao tác.${NC}"; return
    fi
    systemctl stop n8n
    systemctl disable n8n
    rm -f /etc/systemd/system/n8n.service
    rm -rf /root/.n8n /etc/n8n.env
    systemctl daemon-reload
    npm uninstall n8n -g
    echo -e "${GREEN}✓ Đã xóa toàn bộ N8N và dữ liệu!${NC}"
}

show_system_info() {
    echo -e "${GREEN}=== Thông tin hệ thống ===${NC}"
    lsb_release -a
    uname -a
    echo "Public IP: $(curl -s ifconfig.me)"
    df -h /
    free -h
    systemctl status n8n --no-pager
}
    

    # Tạo file môi trường riêng, quyền chỉ root đọc
    cat > /etc/n8n.env <<EOF
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$N8N_USER
N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
EOF
    chmod 600 /etc/n8n.env

    echo -e "${BLUE}Đang cập nhật hệ thống...${NC}"
    apt update && apt upgrade -y

    echo -e "${BLUE}Đang cài đặt Node.js 18...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    echo -e "${BLUE}Đang cài đặt N8N...${NC}"
    npm install n8n -g

    echo -e "${BLUE}Đang tạo systemd service...${NC}"
    cat > /etc/systemd/system/n8n.service <<EOF
[Unit]
Description=n8n workflow automation
Documentation=https://docs.n8n.io
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
EnvironmentFile=/etc/n8n.env
ExecStart=/usr/bin/n8n start
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable n8n
    systemctl restart n8n

    # Configure firewall
    if command -v ufw &> /dev/null; then
        ufw allow 5678/tcp
        echo -e "${GREEN}✓ Firewall đã được cấu hình${NC}"
    fi

    echo -e "${GREEN}✓ N8N đã được cài đặt thành công!${NC}"
    echo -e "${CYAN}URL:${NC} http://$(curl -s ifconfig.me):5678"
    echo -e "${CYAN}Username:${NC} $N8N_USER"
    echo -e "${CYAN}Password:${NC} <Mật khẩu bạn vừa nhập>"
    echo -e "${YELLOW}Lưu ý: Password đã được bảo mật trong /etc/n8n.env (chỉ root truy cập)!${NC}"
}

# Các hàm khác giữ nguyên như cũ: change_domain, update_n8n, setup_2fa, reset_credentials, export_data, import_data, get_redis_info, delete_n8n, show_system_info, v.v.

main
