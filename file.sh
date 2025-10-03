#!/bin/bash

SERVER_ROLE=$1
if [[ -z "$SERVER_ROLE" ]]; then
  echo "Usage: $0 <A|B>"
  exit 1
fi

WG_PORT=51820

WG_DIR=/opt/wireguard
WG_CONF_DIR=$WG_DIR/config/wg_confs

if [[ "$SERVER_ROLE" == "A" ]]; then
    WG_IP="10.8.0.1/24"
    PEER_IP="10.8.0.2/24"
else
    WG_IP="10.8.0.2/24"
    PEER_IP="10.8.0.1/24"
fi

sudo docker compose down 2>/dev/null
sudo rm -rf $WG_DIR/config/*

sudo mkdir -p $WG_CONF_DIR/server$SERVER_ROLE

PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
PRESHARED_KEY=$(wg genpsk)

echo "[*] Private key: $PRIVATE_KEY"
echo "[*] Public key: $PUBLIC_KEY"
echo "[*] Preshared key: $PRESHARED_KEY"

echo "$PRIVATE_KEY" > $WG_CONF_DIR/server$SERVER_ROLE/privatekey
echo "$PUBLIC_KEY" > $WG_CONF_DIR/server$SERVER_ROLE/publickey
echo "$PRESHARED_KEY" > $WG_CONF_DIR/server$SERVER_ROLE/presharedkey

cat <<EOF | sudo tee $WG_CONF_DIR/server$SERVER_ROLE/wg0.conf
[Interface]
Address = $WG_IP
PrivateKey = $PRIVATE_KEY
ListenPort = $WG_PORT
DNS = 10.8.0.1

# Peer configuration will be added manually later
# [Peer]
# PublicKey = <Peer_PublicKey>
# PresharedKey = <PresharedKey>
# Endpoint = <Peer_PublicIP>:51820
# AllowedIPs = <Peer_InternalIP>/32
# PersistentKeepalive = 25
EOF

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

echo "[*]  WireGuard..."
cd $WG_DIR
sudo docker compose up -d

echo "[*] $WG_CONF_DIR/server$SERVER_ROLE/wg0.conf"
