#!/bin/bash
# 小蚕助手诊断1: 导出后端日志中与拉取资料/WAF拦截相关的行
docker logs xiaocan-assistant > /tmp/xc-full.log 2>&1
echo "===== RPC/WAF 相关 (最近15条) ====="
grep -aE "GetClientUserInfo|WAF|403|gateway error|rejected|network failure|用户详情" /tmp/xc-full.log | tail -15
echo "===== 原始日志最后 8 行 ====="
tail -8 /tmp/xc-full.log
echo "===== DIAG DONE ====="
