#!/bin/bash
# 小蚕助手修复3 (华为云): Docker Hub 直连超时, 配置国内镜像加速后从构建步骤续跑
set -u
export PATH=$PATH:/usr/local/bin
APP_DIR=/opt/xiaocan-assistant
LOG_PREFIX="[xiaocan-fix3]"
say() { echo "$LOG_PREFIX $*"; }

say "=== 1/4 配置 Docker 国内镜像加速 ==="
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://dockerproxy.net",
    "https://hub-mirror.c.163.com"
  ]
}
JSON
systemctl restart docker || service docker restart || { say "ERROR: docker 重启失败"; exit 1; }
sleep 3
docker info 2>/dev/null | grep -A6 "Registry Mirrors" || true

say "=== 2/4 测试拉取镜像 ==="
if docker pull nginx:alpine >/dev/null 2>&1; then
  say "nginx:alpine 拉取成功, 镜像加速已生效"
else
  say "ERROR: 换了镜像站仍拉不到 nginx:alpine, 把本屏发给助手看"
  docker pull nginx:alpine || true
  exit 1
fi

say "=== 3/4 继续构建并启动 (约 3-10 分钟) ==="
cd "$APP_DIR" || { say "ERROR: $APP_DIR 不存在"; exit 1; }
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  say "ERROR: 找不到 compose 命令"; exit 1
fi
$COMPOSE up -d --build || { say "ERROR: compose 启动失败"; $COMPOSE logs --tail=50; exit 1; }

say "=== 4/4 健康检查 ==="
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
say "登录账号密码保存在 /root/xiaocan-access.txt :"
cat /root/xiaocan-access.txt
say "DONE"
