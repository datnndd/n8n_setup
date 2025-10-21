#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Script này cần chạy với quyền root"
   exit 1
fi

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Nhận input domain từ người dùng
read -p "Nhập domain hoặc subdomain của bạn: " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN đã được trỏ đúng tới server này. Tiếp tục cài đặt"
else
    echo "Domain $DOMAIN chưa được trỏ tới server này."
    echo "Vui lòng cập nhật DNS để trỏ $DOMAIN tới IP $(curl -s https://api.ipify.org)"
    echo "Sau khi cập nhật DNS, chạy lại script này"
    exit 1
fi

# Sử dụng thư mục /home/n8n
N8N_DIR="/home/n8n"

# Cài đặt Docker và Docker Compose
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Tạo thư mục cho n8n
mkdir -p $N8N_DIR/files

# Tạo file .env
cat << 'EOF' > $N8N_DIR/.env
N8N_HOST=$DOMAIN
WEBHOOK_URL=https://$DOMAIN/
WEBHOOK_TUNNEL_URL=https://$DOMAIN/
N8N_DEFAULT_BINARY_DATA_MODE=filesystem
EOF

# Tạo file docker-compose.yml
cat << 'EOF' > $N8N_DIR/docker-compose.yml
services:
  n8n:
    image: n8nio/n8n
    restart: always
    env_file:
      - .env
    ports:
      - "5678:5678"
    volumes:
      - ./files:/home/node/.n8n
    networks:
      - n8n_network

  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n
    networks:
      - n8n_network

networks:
  n8n_network:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF

# Tạo file Caddyfile
cat << 'EOF' > $N8N_DIR/Caddyfile
$DOMAIN {
    reverse_proxy n8n:5678
    encode gzip
    log
}
EOF

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động các container và kiểm tra lỗi
cd $N8N_DIR
docker-compose up -d

# Kiểm tra trạng thái container
echo "Kiểm tra trạng thái container..."
sleep 10
if docker ps -a | grep -q "n8n_n8n_1"; then
    if docker ps | grep -q "n8n_n8n_1"; then
        echo "Container n8n đang chạy ổn định."
    else
        echo "Lỗi: Container n8n không chạy. Kiểm tra log với lệnh: docker logs n8n_n8n_1"
    fi
else
    echo "Lỗi: Container n8n không được tạo. Kiểm tra file docker-compose.yml và log."
fi

echo ""
echo "╔═════════════════════════════════════════════════════════════╗"
echo "║                                                             ║"
echo "║  ✅ N8n đã được cài đặt (hoặc đang xử lý).                  ║"
echo "║                                                             ║"
echo "║  🌐 Truy cập: https://$DOMAIN                              ║"
echo "║                                                             ║"
echo "╚═════════════════════════════════════════════════════════════╝"
echo ""
