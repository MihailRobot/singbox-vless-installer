#!/bin/bash
set -e

apt install -y curl iptables-persistent

# 2. Ask for port
read -p "Enter port for Sing-box Reality VLESS [default 443]: " PORT
PORT=${PORT:-443}

echo "[*] Using port: $PORT"

# 3. Open port with iptables
echo "[*] Opening TCP port $PORT in iptables..."
iptables -I INPUT -p tcp --dport $PORT -j ACCEPT
netfilter-persistent save
systemctl enable netfilter-persistent
systemctl start netfilter-persistent

# 4. Download Sing-box
echo "[*] Downloading Sing-box..."
curl -L https://github.com/SagerNet/sing-box/releases/download/v1.12.4/sing-box-1.12.4-linux-amd64.tar.gz -o sb.tar.gz

# Extract the tarball (creates a folder)
tar -xvzf sb.tar.gz

# Move the sing-box binary from the extracted folder to /usr/local/bin
mv */sing-box /usr/local/bin/

# Clean up
rm -rf sb.tar.gz */   # remove the tarball and the extracted folder


# 5. Generate UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "[*] Generated UUID: $UUID"

# 6. Generate Reality keypair
echo "[*] Generating Reality keypair..."
KEY_OUTPUT=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep "PrivateKey:" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep "PublicKey:" | awk '{print $2}')

# 6a. Generate a random Short ID (8 bytes hex)
SHORT_ID=$(sing-box generate rand --hex 8)

echo "[*] PrivateKey: $PRIVATE_KEY"
echo "[*] PublicKey: $PUBLIC_KEY"
echo "[*] ShortId: $SHORT_ID"

# 7. Create config.json
CONFIG_DIR="/etc/sing-box"
mkdir -p $CONFIG_DIR
cat > $CONFIG_DIR/config.json <<EOF
{
  "log": { "disabled": false },
  "inbounds": [
    {
      "type": "vless",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.bing.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.bing.com",
            "server_port": 443
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF

# 8. Create systemd service
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Reality VLESS
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_DIR/config.json
Restart=always
RestartSec=5
LimitNOFILE=4096
MemoryMax=80M

[Install]
WantedBy=multi-user.target
EOF

# 9. Reload systemd and start service
systemctl daemon-reload
systemctl enable sing-box
systemctl start sing-box

# 10. Output VLESS link
IP=$(curl -s api.ipify.org)
echo ""
echo "[*] Sing-box Reality VLESS server is running on port $PORT."
echo "[*] Use this VLESS link in your client:"
echo ""
echo "vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Reality"
