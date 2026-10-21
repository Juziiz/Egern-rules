#!/bin/bash
# Xray VLESS installer (Reality :443 + plain :8443) for Ju's Hengchuang HK CentOS 7 box.
# Generates UUID / Reality keys on the server and prints them at the end.
yum install -y curl unzip openssl >/dev/null 2>&1
mkdir -p /usr/local/etc/xray /tmp/xraydl
curl -L -o /tmp/xraydl/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip -o /tmp/xraydl/xray.zip xray -d /tmp/xraydl >/dev/null
install -m 755 /tmp/xraydl/xray /usr/local/bin/xray
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$(/usr/local/bin/xray x25519)
PRIV=$(echo "$KEYS" | grep -i private | awk -F': ' '{print $NF}')
PUB=$(echo "$KEYS" | grep -i public | awk -F': ' '{print $NF}')
SID=$(openssl rand -hex 8)
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0", "port": 443, "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {"show": false, "dest": "www.microsoft.com:443", "xver": 0,
          "serverNames": ["www.microsoft.com"], "privateKey": "$PRIV", "shortIds": ["$SID"]}},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "listen": "0.0.0.0", "port": 8443, "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID"}], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "none"},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
firewall-cmd --permanent --add-port=443/tcp --add-port=8443/tcp >/dev/null 2>&1
firewall-cmd --reload >/dev/null 2>&1
sleep 2
echo "===== VLESS DONE ====="
echo "UUID=$UUID"
echo "PUB=$PUB"
echo "SID=$SID"
systemctl is-active xray
ss -tlnp | grep -E ':443|:8443'
