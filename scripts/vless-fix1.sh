#!/bin/bash
# Fix attempt 1 for the Reality handshake failure on Ju's Hengchuang box:
# print clock (Reality is time-sensitive), try to sync it, check dest
# reachability, switch Reality dest/SNI microsoft -> apple, restart, retest.
CFG=/usr/local/etc/xray/config.json
echo "== time before: $(date -u '+%F %T UTC')"
(systemctl start chronyd >/dev/null 2>&1; chronyc -a makestep >/dev/null 2>&1)
command -v ntpdate >/dev/null 2>&1 && ntpdate -u pool.ntp.org >/dev/null 2>&1
echo "== time after : $(date -u '+%F %T UTC')"
echo "== dest reachability from this server:"
echo -n "microsoft: "; curl -s --max-time 10 -o /dev/null -w "%{http_code}\n" https://www.microsoft.com
echo -n "apple    : "; curl -s --max-time 10 -o /dev/null -w "%{http_code}\n" https://www.apple.com
cp $CFG ${CFG}.bak-fix1
sed -i 's/www\.microsoft\.com/www.apple.com/g' $CFG
/usr/local/bin/xray run -test -config $CFG
systemctl restart xray
sleep 2
echo -n "xray service: "; systemctl is-active xray
UUID=$(sed -n 's/.*"id": "\([0-9a-f-]*\)".*/\1/p' $CFG | head -1)
PRIV=$(sed -n 's/.*"privateKey": "\([^"]*\)".*/\1/p' $CFG | head -1)
SID=$(sed -n 's/.*"shortIds": \["\([0-9a-f]*\)"\].*/\1/p' $CFG | head -1)
PUB=$(/usr/local/bin/xray x25519 -i "$PRIV" | grep -i public | awk -F': ' '{print $NF}')
IP=$(curl -s --max-time 10 https://api.ipify.org)
mkdir -p /tmp/vfix
cat > /tmp/vfix/c443.json <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"127.0.0.1","port":10812,"protocol":"socks","settings":{"udp":true}}],
 "outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"127.0.0.1","port":443,"users":[{"id":"$UUID","flow":"xtls-rprx-vision","encryption":"none"}]}]},
 "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.apple.com","fingerprint":"chrome","publicKey":"$PUB","shortId":"$SID"}}}]}
EOF
/usr/local/bin/xray run -c /tmp/vfix/c443.json >/dev/null 2>&1 &
P1=$!
sleep 3
R1=$(curl -s --max-time 12 --socks5-hostname 127.0.0.1:10812 https://www.google.com/generate_204 -o /dev/null -w "%{http_code}")
kill $P1 2>/dev/null
echo "===== FIX1 RESULT ====="
echo "443 Reality(apple): HTTP $R1 (204 = OK)"
echo "QX line:"
echo "vless=$IP:443, method=none, password=$UUID, obfs=over-tls, obfs-host=www.apple.com, tls-verification=false, reality-base64-pubkey=$PUB, reality-hex-shortid=$SID, vless-flow=xtls-rprx-vision, fast-open=false, udp-relay=false, tag=🇭🇰香港•自建"
