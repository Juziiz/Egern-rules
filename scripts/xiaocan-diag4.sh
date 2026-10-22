#!/usr/bin/env bash
# xiaocan-diag4.sh — 确认新号 (Silk 846415615) 库里存的 token 到底换没换 + 单发复测
# 只读: 打印 token 指纹 (sha256 前 12 位) 与 JWT 的 exp, 不打印 token 本体。
# 用法: curl -fsSL https://raw.githubusercontent.com/Juziiz/Egern-rules/main/scripts/xiaocan-diag4.sh | bash
set -u
LOG=/root/xiaocan-diag4.log
exec > >(tee -a "$LOG") 2>&1
echo "=== xiaocan-diag4 $(date '+%F %T') ==="

docker exec -i xiaocan-assistant python - <<'PYEOF'
import asyncio, base64, hashlib, json, sqlite3, sys, time
sys.path.insert(0, '/app/backend')
from app.protocol.client import XiaoCanClient

conn = sqlite3.connect('/app/backend/data/xiaocan.db')
conn.row_factory = sqlite3.Row
acc = dict(conn.execute("SELECT * FROM accounts WHERE silk_id='846415615'").fetchone())
tok = acc['token']
print('token 指纹 sha256[:12]:', hashlib.sha256(tok.encode()).hexdigest()[:12], '长度:', len(tok))
try:
    p = tok.split('.')[1]
    p += '=' * (-len(p) % 4)
    payload = json.loads(base64.urlsafe_b64decode(p))
    exp = payload.get('exp')
    print('JWT UserId:', payload.get('UserId'), 'exp:', exp, '=', time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(exp)) if exp else None)
    print('(小程序那串旧 token 的 exp 是 1795597955; 若这里一样, 说明 token 根本没换上)')
except Exception as e:
    print('JWT 解码失败:', e)

async def main():
    c = XiaoCanClient()
    print('等 20 秒清冷却后单发 app 模式查资料...', flush=True)
    await asyncio.sleep(20)
    try:
        res = await c.invoke_rpc(
            'Silkworm', 'SilkwormService.GetClientUserInfo',
            body={'silk_id': 846415615, 'if_need_subscribe': True, 'if_need_notify_status': True, 'inviter_silk_id': 0},
            city_code=acc.get('city_code') or 330110,
            token=tok, user_id=acc['user_id'], silk_id='846415615', platform='app')
        u = res.get('user_info') or {}
        v = u.get('vip_level_info') or {}
        print(f"单发结果: 成功 昵称={u.get('nickname')} 等级={v.get('new_level')} silk={u.get('silk')}", flush=True)
    except Exception as e:
        print(f"单发结果: 失败 {str(e)[:200]} RAW={str(getattr(e, 'raw', ''))[:200]}", flush=True)
    await c.close()

asyncio.run(main())
print('DIAG4 DONE')
PYEOF
echo "=== 完成, 日志: $LOG ==="
