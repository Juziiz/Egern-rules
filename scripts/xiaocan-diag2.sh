#!/usr/bin/env bash
# xiaocan-diag2.sh — 诊断第二个小蚕账号 (Silk 846415615) 资料同步失败的原因
# 对照组: 大号 527711911 (一直正常)。分别用 app / mini 两种模式直连官方查资料,
# 并实测 09:30 大牌券卡池接口是否可用。全程只读, 不改任何数据。
# 用法: curl -fsSL https://raw.githubusercontent.com/Juziiz/Egern-rules/main/scripts/xiaocan-diag2.sh | bash
set -u
LOG=/root/xiaocan-diag2.log
exec > >(tee -a "$LOG") 2>&1
echo "=== xiaocan-diag2 $(date '+%F %T') ==="

docker exec -i xiaocan-assistant python - <<'PYEOF'
import asyncio, sqlite3, sys
sys.path.insert(0, '/app/backend')
from app.protocol.client import XiaoCanClient

conn = sqlite3.connect('/app/backend/data/xiaocan.db')
conn.row_factory = sqlite3.Row
rows = {r['silk_id']: dict(r) for r in conn.execute("SELECT * FROM accounts WHERE platform != 'meituan'").fetchall()}
print('库内账号 Silk 列表:', list(rows.keys()))

async def probe(c, acc, plat):
    silk = acc['silk_id']
    try:
        res = await c.invoke_rpc(
            'Silkworm', 'SilkwormService.GetClientUserInfo',
            body={'silk_id': int(silk), 'if_need_subscribe': True, 'if_need_notify_status': True, 'inviter_silk_id': 0},
            city_code=acc.get('city_code') or 330110,
            token=acc['token'], user_id=acc['user_id'], silk_id=silk, platform=plat)
        u = res.get('user_info') or {}
        v = u.get('vip_level_info') or {}
        print(f"  [{plat}] 成功 昵称={u.get('nickname')} 等级={v.get('new_level')} silk={u.get('silk')} 官方silk_id={u.get('silk_id') or u.get('id')}")
        return True
    except Exception as e:
        print(f"  [{plat}] 失败 {type(e).__name__}: {str(e)[:260]}")
        return False

async def main():
    c = XiaoCanClient()
    for silk, label in (('527711911', '大号(对照)'), ('846415615', '新号')):
        acc = rows.get(silk)
        if not acc:
            print(f"{label} Silk {silk}: 库里没有这个账号")
            continue
        print(f"{label} Silk {silk} 库内等级={acc.get('vip_level')} 昵称={acc.get('nickname')} client_mode={acc.get('client_mode')}")
        for plat in ('app', 'mini'):
            await probe(c, acc, plat)
    acc2 = rows.get('846415615')
    if acc2:
        try:
            pool = await c.get_extra_brand_card_pool(token=acc2['token'], silk_id='846415615', user_id=acc2['user_id'], city_code=acc2.get('city_code') or 330110)
            items = pool.get('card_list') or pool.get('cards') or pool.get('list') or []
            print(f"新号大牌券卡池(app模式): 成功, 返回键={list(pool.keys())[:8]}, 卡数={len(items) if isinstance(items, list) else 'n/a'}")
        except Exception as e:
            print(f"新号大牌券卡池(app模式): 失败 {type(e).__name__}: {str(e)[:260]}")
    await c.close()

asyncio.run(main())
print('DIAG DONE')
PYEOF
echo "=== 完成, 日志: $LOG ==="
