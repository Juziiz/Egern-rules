#!/bin/bash
# Self-test for the Xray VLESS install on Ju's Hengchuang box:
# reads the live server config, derives the public key from the private key,
# tests both inbounds via loopback with a real Xray client, and prints
# QX server lines generated from the live config (no transcription).
CFG=/usr/local/etc/xray/config.json
UUID=$(sed -n 's/.*"id": "\([0-9a-f-]*\)".*/\1/p' $CFG | head -1)
PRIV=$(sed -n 's/.*"privateKey": "\([^"]*\)".*/\1/p' $CFG | head -1)
SID=$(sed -n 's/.*"shortIds": \["\([0-9a-f]*\)"\].*/\1/p' $CFG | head -1)
PUB=$(/usr/local/bin/xray x25519 -i "$PRIV" | grep -i public | awk -F': ' '{print $NF}')
IP=$(curl -s --max-time 10 https://api.ipify.org)
mkdir -p /tmp/vtest
cat > /tmp/vtest/c443.json <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"127.0.0.1","port":10810,"protocol":"socks","settings":{"udp":true}}],
 "outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"127.0.0.1","port":443,"users":[{"id":"$UUID","flow":"xtls-rprx-vision","encryption":"none"}]}]},
 "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"www.microsoft.com","fingerprint":"chrome","publicKey":"$PUB","shortId":"$SID"}}}]}
EOF
cat > /tmp/vtest/c8443.json <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"127.0.0.1","port":10811,"protocol":"socks","settings":{"udp":true}}],
 "outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"127.0.0.1","port":8443,"users":[{"id":"$UUID","encryption":"none"}]}]},
 "streamSettings":{"network":"tcp","security":"none"}}]}
EOF
/usr/local/bin/xray run -c /tmp/vtest/c443.json >/dev/null 2>&1 &
P1=$!
/usr/local/bin/xray run -c /tmp/vtest/c8443.json >/dev/null 2>&1 &
P2=$!
sleep 3
R1=$(curl -s --max-time 12 --socks5-hostname 127.0.0.1:10810 https://www.google.com/generate_204 -o /dev/null -w "%{http_code}")
R2=$(curl -s --max-time 12 --socks5-hostname 127.0.0.1:10811 https://www.google.com/generate_204 -o /dev/null -w "%{http_code}")
kill $P1 $P2 2>/dev/null
echo "===== SELFTEST ====="
echo "443 Reality: HTTP $R1 (204 = OK)"
echo "8443 Plain : HTTP $R2 (204 = OK)"
echo "===== QX LINES (from live config) ====="
echo "vless=$IP:443, method=none, password=$UUID, obfs=over-tls, obfs-host=www.microsoft.com, tls-verification=false, reality-base64-pubkey=$PUB, reality-hex-shortid=$SID, vless-flow=xtls-rprx-vision, fast-open=false, udp-relay=false, tag=🇭🇰香港•自建"
echo "vless=$IP:8443, method=none, password=$UUID, obfs=none, fast-open=false, udp-relay=true, tag=🇭🇰香港•自建直连"
