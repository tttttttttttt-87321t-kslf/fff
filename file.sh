#!/bin/bash

SERVER_ROLE=$1
PEER_ROLE=$([[ "$SERVER_ROLE" == "A" ]] && echo "B" || echo "A")

if [[ -z "$SERVER_ROLE" ]]; then
  echo "Usage: $0 <A|B>"
  exit 1
fi

WG_PORT=51820
WG_DIR=/opt/wireguard
WG_CONF_DIR=$WG_DIR/config/wg_confs

declare -A WG_IP
WG_IP[A]="10.8.0.1/24"
WG_IP[B]="10.8.0.2/24"

# Clean up previous config
sudo docker compose down 2>/dev/null
sudo rm -rf $WG_DIR/config/*

sudo mkdir -p $WG_CONF_DIR/server$SERVER_ROLE

# Generate keys
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
PRESHARED_KEY=$(wg genpsk)

echo "$PRIVATE_KEY" > $WG_CONF_DIR/server$SERVER_ROLE/privatekey
echo "$PUBLIC_KEY" > $WG_CONF_DIR/server$SERVER_ROLE/publickey
echo "$PRESHARED_KEY" > $WG_CONF_DIR/server$SERVER_ROLE/presharedkey

# Save peer info to tmp files for cross-server usage
echo "$PUBLIC_KEY" > $WG_DIR/$SERVER_ROLE.public
echo "$PRESHARED_KEY" > $WG_DIR/$SERVER_ROLE.psk

# Wait until peer files exist
echo "[*] Waiting for peer keys..."
while [ ! -f $WG_DIR/$PEER_ROLE.public ] || [ ! -f $WG_DIR/$PEER_ROLE.psk ]; do
    sleep 1
done

PEER_PUBLIC_KEY=$(cat $WG_DIR/$PEER_ROLE.public)
PEER_PSK=$(cat $WG_DIR/$PEER_ROLE.psk)

cat <<EOF | sudo tee $WG_CONF_DIR/server$SERVER_ROLE/wg0.conf
[Interface]
Address = ${WG_IP[$SERVER_ROLE]}
PrivateKey = $PRIVATE_KEY
ListenPort = $WG_PORT
DNS = 10.8.0.1

[Peer]
PublicKey = $PEER_PUBLIC_KEY
PresharedKey = $PEER_PSK
Endpoint = <PEER_PUBLIC_IP>:$WG_PORT
AllowedIPs = ${WG_IP[$PEER_ROLE]}/32
PersistentKeepalive = 25
EOF

# docker-compose.yml
cat <<EOF | sudo tee $WG_DIR/docker-compose.yml
version: '3.8'
services:
  wireguard:
    image: linuxserver/wireguard
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    volumes:
      - ./config:/config
    ports:
      - "$WG_PORT:$WG_PORT/udp"
    restart: unless-stopped
EOF

# Launch
cd $WG_DIR
sudo docker compose up -d

echo "[*] WireGuard Server $SERVER_ROLE is up!"
