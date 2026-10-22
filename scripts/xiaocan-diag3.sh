#!/usr/bin/env bash
# xiaocan-diag3.sh — 拉开间隔单发验证新号 (Silk 846415615) 到底是"连发频控"还是"账号被盯"
# 每次调用间隔 45 秒, 避免 burst 触发 WAF 频次拦截; 失败时打印官方原始返回。
# 全程只读。用时约 3 分钟, 建议 nohup 后台跑:
#   nohup bash -c 'curl -fsSL https://raw.githubusercontent.com/Juziiz/Egern-rules/main/scripts/xiaocan-diag3.sh | bash' >/dev/null 2>&1 &
# 结果看: cat /root/xiaocan-diag3.log
set -u
LOG=/root/xiaocan-diag3.log
exec > >(tee -a "$LOG") 2>&1
echo "=== xiaocan-diag3 $(date '+%F %T') ==="

docker exec -i xiaocan-assistant python - <<'PYEOF'
import asyncio, sqlite3, sys, time
sys.path.insert(0, '/app/backend')
from app.protocol.client import XiaoCanClient

conn = sqlite3.connect('/app/backend/data/xiaocan.db')
conn.row_factory = sqlite3.Row
rows = {r['silk_id']: dict(r) for r in conn.execute("SELECT * FROM accounts WHERE platform != 'meituan'").fetchall()}

async def probe(c, acc, plat, tag):
    silk = acc['silk_id']
    try:
        res = await c.invoke_rpc(
            'Silkworm', 'SilkwormService.GetClientUserInfo',
            body={'silk_id': int(silk), 'if_need_subscribe': True, 'if_need_notify_status': True, 'inviter_silk_id': 0},
            city_code=acc.get('city_code') or 330110,
            token=acc['token'], user_id=acc['user_id'], silk_id=silk, platform=plat)
        u = res.get('user_info') or {}
        v = u.get('vip_level_info') or {}
        print(f"{tag} [{plat}] 成功 昵称={u.get('nickname')} 等级={v.get('new_level')} silk={u.get('silk')}", flush=True)
        return True
    except Exception as e:
        raw = getattr(e, 'raw', None)
        print(f"{tag} [{plat}] 失败 {str(e)[:200]} RAW={str(raw)[:300]}", flush=True)
        return False

async def main():
    c = XiaoCanClient()
    new = rows.get('846415615')
    main_acc = rows.get('527711911')
    print('第1发: 新号 app 模式 (先等 20 秒让冷却清零)', flush=True)
    await asyncio.sleep(20)
    await probe(c, new, 'app', '新号-1')
    print('等 45 秒...', flush=True)
    await asyncio.sleep(45)
    await probe(c, new, 'app', '新号-2')
    print('等 45 秒...', flush=True)
    await asyncio.sleep(45)
    await probe(c, new, 'mini', '新号-3')
    print('等 45 秒...', flush=True)
    await asyncio.sleep(45)
    await probe(c, main_acc, 'app', '大号-对照')
    await c.close()

asyncio.run(main())
print('DIAG3 DONE', flush=True)
PYEOF
echo "=== 完成, 日志: $LOG ==="
