#!/bin/bash
# NapCatQQ 部署脚本 (配合已运行的小蚕助手)
# - NapCat 加入小蚕助手现有的 Docker 网络, 小蚕可通过 http://napcat:8080 调用 OneBot
# - 只把 NapCat WebUI 的 6099 映射到宿主机; OneBot 8080 不映射到宿主机、不对公网开放
# - WebUI 与 OneBot 的 Token 随机生成并保存在 /root/napcat-access.txt (600 权限)
set -u
export PATH=$PATH:/usr/local/bin

NAPCAT_DIR=/opt/napcat
ACCESS_FILE=/root/napcat-access.txt
LOG_PREFIX="[napcat-deploy]"
say() { echo "$LOG_PREFIX $*"; }
fail() { say "ERROR: $*"; exit 1; }

say "=== 1/5 检查 Docker 和小蚕助手 ==="
command -v docker >/dev/null 2>&1 || fail "未检测到 docker"
docker info >/dev/null 2>&1 || fail "docker 服务不可用"
docker inspect xiaocan-assistant >/dev/null 2>&1 || fail "未找到 xiaocan-assistant 容器, 请先确认小蚕助手正在运行"

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  fail "未找到 docker compose 命令"
fi

NETWORK=$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' xiaocan-assistant | awk 'NF && $1 != "bridge" && $1 != "host" && $1 != "none" {print; exit}')
[ -n "${NETWORK:-}" ] || fail "无法识别小蚕助手的 Docker 网络"
say "小蚕 Docker 网络: $NETWORK"

say "=== 2/5 准备目录和访问 Token ==="
mkdir -p "$NAPCAT_DIR/config" "$NAPCAT_DIR/qq" "$NAPCAT_DIR/plugins"
if [ -f "$ACCESS_FILE" ]; then
  WEBUI_TOKEN=$(grep '^WEBUI_TOKEN=' "$ACCESS_FILE" | head -n1 | cut -d= -f2-)
  ONEBOT_TOKEN=$(grep '^ONEBOT_TOKEN=' "$ACCESS_FILE" | head -n1 | cut -d= -f2-)
fi
if [ -z "${WEBUI_TOKEN:-}" ]; then
  WEBUI_TOKEN=$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 24)
fi
if [ -z "${ONEBOT_TOKEN:-}" ]; then
  ONEBOT_TOKEN=$(head -c 96 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 32)
fi
cat > "$ACCESS_FILE" <<EOF
WEBUI_TOKEN=$WEBUI_TOKEN
ONEBOT_TOKEN=$ONEBOT_TOKEN
ONEBOT_URL=http://napcat:8080
EOF
chmod 600 "$ACCESS_FILE"

cat > "$NAPCAT_DIR/.env" <<EOF
WEBUI_TOKEN=$WEBUI_TOKEN
XIAOCAN_NETWORK=$NETWORK
EOF
chmod 600 "$NAPCAT_DIR/.env"

say "=== 3/5 预置 OneBot HTTP 配置 ==="
if [ ! -f "$NAPCAT_DIR/config/onebot11.json" ]; then
  cat > "$NAPCAT_DIR/config/onebot11.json" <<EOF
{
  "network": {
    "httpServers": [
      {
        "name": "xiaocan",
        "enable": true,
        "port": 8080,
        "host": "0.0.0.0",
        "enableCors": true,
        "enableWebsocket": false,
        "messagePostFormat": "array",
        "token": "$ONEBOT_TOKEN",
        "debug": false
      }
    ],
    "httpClients": [],
    "websocketServers": [],
    "websocketClients": []
  },
  "musicSignUrl": "",
  "enableLocalFile2Url": false,
  "parseMultMsg": false
}
EOF
  say "已写入默认 OneBot 配置: HTTP 8080"
else
  say "已有 onebot11.json, 保留原配置不覆盖"
fi

say "=== 4/5 写入 Compose 并启动 ==="
cat > "$NAPCAT_DIR/docker-compose.yml" <<'YAML'
services:
  napcat:
    image: mlikiowa/napcat-docker:latest
    container_name: napcat
    restart: unless-stopped
    environment:
      - TZ=Asia/Shanghai
      - NAPCAT_UID=0
      - NAPCAT_GID=0
      - WEBUI_TOKEN=${WEBUI_TOKEN}
    ports:
      - "6099:6099"
    volumes:
      - ./config:/app/napcat/config
      - ./qq:/app/.config/QQ
      - ./plugins:/app/napcat/plugins
    networks:
      xiaocan:
        aliases:
          - napcat

networks:
  xiaocan:
    external: true
    name: ${XIAOCAN_NETWORK}
YAML

cd "$NAPCAT_DIR" || fail "无法进入 $NAPCAT_DIR"
$COMPOSE pull || fail "NapCat 镜像拉取失败, 查看上方错误"
$COMPOSE up -d || fail "NapCat 启动失败"
$COMPOSE ps

say "=== 5/5 检查 WebUI 和容器状态 ==="
WEBUI_OK=0
for i in $(seq 1 30); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:6099/webui/ || echo 000)
  if [ "$CODE" != "000" ]; then
    WEBUI_OK=1
    say "NapCat WebUI 已响应: HTTP $CODE"
    break
  fi
  sleep 3
done
if [ "$WEBUI_OK" != "1" ]; then
  say "WARN: WebUI 暂未响应, 最近日志如下:"
  docker logs --tail=60 napcat || true
  exit 1
fi

if docker exec xiaocan-assistant python -c 'import socket; s=socket.create_connection(("napcat", 8080), 3); s.close(); print("open")' >/dev/null 2>&1; then
  say "小蚕容器已能连到 napcat:8080"
else
  say "提示: OneBot 8080 通常要等 QQ 扫码登录成功后才会开始监听, 现在连不上不代表部署失败"
fi

say "NapCat 容器状态:"
docker ps --filter name=napcat --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
say "WebUI 和 OneBot Token 保存在 $ACCESS_FILE, 请勿把该文件内容发到公开场合"
say "DONE"
