#!/usr/bin/env bash
set -euo pipefail

# ========== CHỈNH MẶC ĐỊNH TẠI ĐÂY ==========
DEFAULT_DOMAIN="your-domain"
# ============================================

DOMAIN="${1:-${DOMAIN:-$DEFAULT_DOMAIN}}"
echo "▶ Using DOMAIN = $DOMAIN"

# 1) Cài Docker/Compose (gọn, không hỏi)
if ! command -v docker >/dev/null 2>&1; then
  echo "▶ Installing Docker..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# 2) Thư mục làm việc
WORKDIR="/opt/n8n"
sudo mkdir -p "$WORKDIR/vol_n8n"
sudo chown -R 1000:1000 "$WORKDIR/vol_n8n"
sudo chmod -R 755 "$WORKDIR/vol_n8n"
cd "$WORKDIR"

# 3) Ghi .env (đầy đủ biến môi trường n8n, dùng HTTPS + domain)
cat > .env <<EOF
# ===== Common =====
DOMAIN=$DOMAIN
GENERIC_TIMEZONE=Asia/Ho_Chi_Minh

# ===== n8n Core =====
# Lưu binary vào filesystem để ổn định khi chạy lâu
N8N_DEFAULT_BINARY_DATA_MODE=filesystem

# Cookie an toàn vì đi qua HTTPS (Caddy cấp TLS)
N8N_SECURE_COOKIE=true

# Host/URL công khai qua reverse proxy (Caddy)
N8N_HOST=${DOMAIN}
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://${DOMAIN}
WEBHOOK_URL=https://${DOMAIN}/

# ===== MCP (bật nếu bạn dùng multi-client/platform) =====
N8N_MCP_ENABLED=true
N8N_MCP_MODE=server
EOF

# 4) Ghi compose_noai.yaml (n8n + Caddy)
cat > compose_noai.yaml <<'EOF'
version: "3.8"

services:
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - N8N_DEFAULT_BINARY_DATA_MODE=${N8N_DEFAULT_BINARY_DATA_MODE}
      - N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
      - N8N_HOST=${N8N_HOST}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_MCP_ENABLED=${N8N_MCP_ENABLED}
      - N8N_MCP_MODE=${N8N_MCP_MODE}
    volumes:
      - ./vol_n8n:/home/node/.n8n
    networks:
      - n8n_net
    # Không publish port; Caddy reverse proxy vào đây

  caddy:
    image: caddy:2
    restart: unless-stopped
    depends_on:
      - n8n
    ports:
      - "80:80"
      - "443:443"
    environment:
      - DOMAIN=${DOMAIN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - n8n_net

networks:
  n8n_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF

# 5) Ghi Caddyfile
cat > Caddyfile <<'EOF'
{$DOMAIN} {
    reverse_proxy n8n:5678
    encode gzip
    log
}
EOF

# 6) Khởi chạy
echo "▶ docker compose up -d"
docker compose -f compose_noai.yaml up -d

echo
echo "✅ Done. Truy cập: https://${DOMAIN}"
echo "   Nhớ: A record của domain phải trỏ về IP máy chủ + mở cổng 80/443 để Caddy tự xin TLS."

