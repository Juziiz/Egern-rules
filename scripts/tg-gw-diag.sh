#!/usr/bin/env bash
# tg-gw-diag.sh — 在小蚕助手容器内实测 tg.juzii.top 网关可达性 (与助手同路径: httpx)
# 只读: DNS 解析 / TCP 连接计时 / HTTPS getMe 假 token (期望 TG 的 401)
# 用法: curl -fsSL https://raw.githubusercontent.com/Juziiz/Egern-rules/main/scripts/tg-gw-diag.sh | bash
set -u
LOG=/root/tg-gw-diag.log
exec > >(tee -a "$LOG") 2>&1
echo "=== tg-gw-diag $(date '+%F %T') ==="
docker exec -i xiaocan-assistant python - <<'PYEOF'
import socket, time
import httpx

for host in ('tg.juzii.top', 'fd.juzii.top'):
    try:
        infos = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
        ips = sorted({i[4][0] for i in infos})
        print(f"{host} 解析: {ips}")
    except Exception as e:
        print(f"{host} 解析失败: {e!r}")
        ips = []
    for ip in ips[:4]:
        s = socket.socket(socket.AF_INET if ':' not in ip else socket.AF_INET6)
        s.settimeout(6)
        t = time.time()
        try:
            s.connect((ip, 443)); print(f"  TCP {ip}:443 OK {(time.time()-t)*1000:.0f}ms")
        except Exception as e:
            print(f"  TCP {ip}:443 FAIL {(time.time()-t)*1000:.0f}ms {e!r}")
        finally:
            s.close()

url = 'https://tg.juzii.top/0640033a90861ee5/bot000000:FAKE/getMe'
for n in (1, 2):
    t = time.time()
    try:
        r = httpx.get(url, timeout=12.0)
        print(f"httpx GET 网关 第{n}次: HTTP {r.status_code} {(time.time()-t)*1000:.0f}ms body={r.text[:80]}")
    except Exception as e:
        print(f"httpx GET 网关 第{n}次: FAIL {(time.time()-t)*1000:.0f}ms {type(e).__name__}: {e}")
print('DIAG DONE')
PYEOF
echo "=== 完成, 日志: $LOG ==="
