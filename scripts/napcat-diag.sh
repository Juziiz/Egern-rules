#!/usr/bin/env bash
# napcat-diag.sh — 诊断小蚕助手 -> NapCat (OneBot) 推送连不上
# 只读检查: 容器状态 / 两容器是否同网络 / 从助手容器内直连 napcat:8080 / NapCat 近期日志
# 用法: curl -fsSL https://raw.githubusercontent.com/Juziiz/Egern-rules/main/scripts/napcat-diag.sh | bash
set -u
LOG=/root/napcat-diag.log
exec > >(tee -a "$LOG") 2>&1
echo "=== napcat-diag $(date '+%F %T') ==="

echo "--- 1) 容器状态 ---"
docker ps -a --format '{{.Names}} | {{.Status}} | networks={{.Networks}}' | grep -Ei 'napcat|xiaocan' || echo "(没找到相关容器)"

NC="$(docker ps -a --format '{{.Names}}' | grep -i napcat | head -1)"
echo "NapCat 容器名: ${NC:-未找到}"

echo "--- 2) 从小蚕助手容器内直连 napcat:8080 (TCP) ---"
docker exec -i xiaocan-assistant python - <<'PYEOF'
import socket
s = socket.socket(); s.settimeout(5)
try:
    s.connect(('napcat', 8080))
    print('TCP 结果: OK — napcat:8080 能连上 (那问题在 OneBot 服务/Token 层)')
except Exception as e:
    print('TCP 结果: FAIL —', repr(e), '(连不上: 容器没起 / 不在同一网络 / OneBot HTTP 没监听 8080)')
PYEOF

if [ -n "${NC:-}" ]; then
  echo "--- 3) NapCat 最近 40 行日志 ---"
  docker logs --tail 40 "$NC" 2>&1 | tail -40
fi
echo "DIAG DONE — 日志: $LOG"
