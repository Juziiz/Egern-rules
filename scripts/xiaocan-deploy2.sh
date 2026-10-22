#!/bin/bash
# 小蚕小帮手 一键部署 v2 (含 nginx seccomp 兼容处理, 适用于华为云等新部署)
# 应用只监听本机内部, 对外经 nginx + 密码验证 (端口 8691)
# 用法: nohup bash xiaocan-deploy2.sh > /root/xiaocan-deploy.log 2>&1 &
set -u
export PATH=$PATH:/usr/local/bin

APP_DIR=/opt/xiaocan-assistant
WEB_PORT=8691
LOG_PREFIX="[xiaocan-deploy]"
say() { echo "$LOG_PREFIX $*"; }

say "=== 1/6 检查 Docker ==="
if ! command -v docker >/dev/null 2>&1; then
  say "未检测到 docker, 开始安装..."
  curl -fsSL https://get.docker.com | bash || { say "ERROR: docker 安装失败"; exit 1; }
  systemctl enable --now docker || service docker start || true
fi
docker --version || { say "ERROR: docker 不可用"; exit 1; }
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  say "安装 docker-compose..."
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { say "ERROR: docker-compose 下载失败"; exit 1; }
  chmod +x /usr/local/bin/docker-compose
  COMPOSE="docker-compose"
fi
say "compose 命令: $COMPOSE"

say "=== 2/6 拉取源码 ==="
mkdir -p "$APP_DIR"
if [ ! -f "$APP_DIR/Dockerfile" ]; then
  cd /tmp
  curl -fsSL -o xiaocan.zip https://codeload.github.com/AkiSeele/xiaocan-assistant/zip/refs/heads/main || { say "ERROR: 源码下载失败"; exit 1; }
  if command -v unzip >/dev/null 2>&1; then unzip -o -q xiaocan.zip; else python3 -c "import zipfile; zipfile.ZipFile('xiaocan.zip').extractall('.')"; fi
  cp -rf xiaocan-assistant-main/* "$APP_DIR"/
fi
cd "$APP_DIR" || exit 1
ls Dockerfile docker-compose.yml >/dev/null || { say "ERROR: 源码不完整"; exit 1; }
sed -i 's/"8690:8690"/"127.0.0.1:8690:8690"/' docker-compose.yml

say "=== 3/6 生成访问密码与反代配置 ==="
ACCESS_FILE=/root/xiaocan-access.txt
if [ ! -f "$ACCESS_FILE" ]; then
  PASS=$(head -c 48 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 14)
  echo "user: ju" > "$ACCESS_FILE"
  echo "pass: $PASS" >> "$ACCESS_FILE"
  chmod 600 "$ACCESS_FILE"
else
  PASS=$(grep '^pass:' "$ACCESS_FILE" | awk '{print $2}')
fi
HASH=$(openssl passwd -apr1 "$PASS")
echo "ju:$HASH" > "$APP_DIR/.htpasswd"

cat > "$APP_DIR/nginx.conf" <<'NGINX'
server {
    listen 80;
    auth_basic "xiaocan";
    auth_basic_user_file /etc/nginx/.htpasswd;
    location / {
        proxy_pass http://xiaocan-assistant:8690;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }
}
NGINX

cat > "$APP_DIR/nginx-main.conf" <<'MAIN'
user nginx;
worker_processes auto;
pid /tmp/nginx.pid;
error_log /dev/stderr notice;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /dev/stdout;
    client_body_temp_path /tmp/client_body;
    proxy_temp_path /tmp/proxy;
    fastcgi_temp_path /tmp/fastcgi;
    uwsgi_temp_path /tmp/uwsgi;
    scgi_temp_path /tmp/scgi;
    sendfile on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
}
MAIN

cat > "$APP_DIR/docker-compose.override.yml" <<'OVERRIDE'
services:
  web:
    image: nginx:alpine
    container_name: xiaocan-web
    restart: unless-stopped
    security_opt:
      - seccomp=unconfined
    ports:
      - "8691:80"
    volumes:
      - ./nginx-main.conf:/etc/nginx/nginx.conf:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./.htpasswd:/etc/nginx/.htpasswd:ro
    tmpfs:
      - /tmp
      - /run
    depends_on:
      - xiaocan-assistant
OVERRIDE

say "=== 4/6 构建并启动 (较慢, 约 3-10 分钟) ==="
$COMPOSE up -d --build || { say "ERROR: compose 启动失败"; $COMPOSE logs --tail=50; exit 1; }

say "=== 5/6 等待健康检查 ==="
OK=0
for i in $(seq 1 40); do
  if curl -fsS http://127.0.0.1:8690/health >/dev/null 2>&1 || docker exec xiaocan-assistant python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8690/health')" >/dev/null 2>&1; then
    OK=1; break
  fi
  sleep 5
done
$COMPOSE ps
if [ "$OK" = "1" ]; then
  say "应用健康检查通过"
else
  say "WARN: 健康检查暂未通过, 最近日志:"
  $COMPOSE logs --tail=40 xiaocan-assistant || true
fi
CODE1=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8691/ || echo 000)
say "门禁验证: 未登录访问 8691 返回 $CODE1 (预期 401)"

say "=== 6/6 完成 ==="
say "访问地址: http://服务器公网IP:$WEB_PORT (需在云厂商安全组放行 $WEB_PORT)"
say "登录账号密码保存在 $ACCESS_FILE :"
cat "$ACCESS_FILE"
say "DONE"
