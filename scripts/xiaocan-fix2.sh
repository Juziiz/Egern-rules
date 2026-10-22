#!/bin/bash
# 小蚕助手修复2: nginx 的 pwrite() 在 /run 与 /tmp 都被拒 (EPERM), 疑为本机容器 seccomp 拦截
# 方案A: 给 web 容器关 seccomp 再试 nginx; 不行自动走方案B: 换 Caddy 做密码反代
set -u
export PATH=$PATH:/usr/local/bin
APP_DIR=/opt/xiaocan-assistant
LOG_PREFIX="[xiaocan-fix2]"
say() { echo "$LOG_PREFIX $*"; }
cd "$APP_DIR" || { say "ERROR: $APP_DIR 不存在"; exit 1; }

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  say "ERROR: 找不到 compose 命令"; exit 1
fi

PASS=$(grep '^pass:' /root/xiaocan-access.txt | awk '{print $2}')
[ -n "$PASS" ] || { say "ERROR: 读不到访问密码"; exit 1; }

verify() {
  sleep 5
  CODE1=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8691/ || echo 000)
  CODE2=$(curl -s -o /dev/null -w '%{http_code}' -u "ju:$PASS" http://127.0.0.1:8691/ || echo 000)
  say "验证: 未登录=$CODE1 (预期401) 带密码=$CODE2 (预期200)"
  [ "$CODE1" = "401" ] && [ "$CODE2" = "200" ]
}

say "=== 方案A: nginx + seccomp=unconfined ==="
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
$COMPOSE up -d --force-recreate web >/dev/null 2>&1
if verify; then
  say "FIX OK (方案A: nginx 关 seccomp 后正常)"
  say "DONE"
  exit 0
fi
say "方案A未通过, web 容器最近日志:"
docker logs --tail=8 xiaocan-web 2>&1 | tail -8 || true

say "=== 方案B: 换 Caddy 做密码反代 ==="
HASH=$(docker run --rm caddy:2-alpine caddy hash-password --plaintext "$PASS" 2>/dev/null | tr -d '\r\n ')
[ -n "$HASH" ] || { say "ERROR: Caddy 密码哈希生成失败"; exit 1; }
printf ':80 {\n\tbasic_auth {\n\t\tju %s\n\t}\n\treverse_proxy xiaocan-assistant:8690\n}\n' "$HASH" > "$APP_DIR/Caddyfile"
cat > "$APP_DIR/docker-compose.override.yml" <<'OVERRIDE'
services:
  web:
    image: caddy:2-alpine
    container_name: xiaocan-web
    restart: unless-stopped
    ports:
      - "8691:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    tmpfs:
      - /data
      - /config
    depends_on:
      - xiaocan-assistant
OVERRIDE
$COMPOSE up -d --force-recreate web >/dev/null 2>&1
if verify; then
  say "FIX OK (方案B: 已换 Caddy)"
else
  say "ERROR: 方案B也未通过, web 容器最近日志:"
  docker logs --tail=20 xiaocan-web || true
fi
say "DONE"
