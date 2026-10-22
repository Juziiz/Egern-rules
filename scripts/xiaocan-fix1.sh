#!/bin/bash
# 小蚕助手修复1: nginx 容器因 pid 文件写不进 /run/nginx.pid 反复重启
# 修法: 自定义 nginx 主配置把 pid 与所有临时目录改到 /tmp, 并给 /tmp 挂 tmpfs
set -u
export PATH=$PATH:/usr/local/bin
APP_DIR=/opt/xiaocan-assistant
LOG_PREFIX="[xiaocan-fix1]"
say() { echo "$LOG_PREFIX $*"; }

cd "$APP_DIR" || { say "ERROR: $APP_DIR 不存在"; exit 1; }

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  say "ERROR: 找不到 compose 命令"; exit 1
fi

say "=== 1/3 写入 nginx 主配置 (pid 与临时目录改到 /tmp) ==="
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

say "=== 2/3 更新 override 并重建 web 容器 ==="
cat > "$APP_DIR/docker-compose.override.yml" <<'OVERRIDE'
services:
  web:
    image: nginx:alpine
    container_name: xiaocan-web
    restart: unless-stopped
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

$COMPOSE up -d --force-recreate web || { say "ERROR: web 容器重建失败"; exit 1; }
sleep 5

say "=== 3/3 验证 ==="
docker ps --filter name=xiaocan-web --format '{{.Names}} {{.Status}}'
CODE1=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8691/ || echo 000)
say "未登录访问返回: $CODE1 (预期 401)"
PASS=$(grep '^pass:' /root/xiaocan-access.txt | awk '{print $2}')
CODE2=$(curl -s -o /dev/null -w '%{http_code}' -u "ju:$PASS" http://127.0.0.1:8691/ || echo 000)
say "带密码访问返回: $CODE2 (预期 200)"
if [ "$CODE1" = "401" ] && [ "$CODE2" = "200" ]; then
  say "FIX OK"
else
  say "WARN: 结果不符合预期, web 容器最近日志:"
  docker logs --tail=20 xiaocan-web || true
fi
say "DONE"
