#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Usage: sudo ./setup-wireguard.sh <A|B> <PEER_PUBLIC_IP> <PEER_SSH_USER@PEER_HOST> [PEER_SSH_PORT]
# Example:
#   sudo ./setup-wireguard.sh A 198.51.100.5 user@198.51.100.5
# Assumes docker & docker compose installed. Assumes SSH access to peer (key-based recommended).

if [[ $EUID -ne 0 ]]; then
  echo "Run as root or with sudo"
  exit 1
fi

ROLE="${1:-}"
PEER_IP="${2:-}"
PEER_SSH="${3:-}"
SSH_PORT="${4:-22}"

if [[ -z "$ROLE" || -z "$PEER_IP" || -z "$PEER_SSH" ]]; then
  echo "Usage: $0 <A|B> <PEER_PUBLIC_IP> <PEER_SSH_USER@PEER_HOST> [PEER_SSH_PORT]"
  exit 1
fi

if [[ "$ROLE" != "A" && "$ROLE" != "B" ]]; then
  echo "Role must be A or B"
  exit 1
fi

# Config
WG_PORT=51820
WG_DIR="/opt/wireguard"
WG_CONF_DIR="$WG_DIR/config/wg_confs"
SELF_TAG="server${ROLE}"
PEER_ROLE=$([ "$ROLE" == "A" ] && echo "B" || echo "A")
PEER_TAG="server${PEER_ROLE}"
SELF_PUB_TMP="/tmp/wg_${SELF_TAG}.pub"
SELF_PSK_TMP="/tmp/wg_${SELF_TAG}.psk"
REMOTE_PUB_TMP="/tmp/wg_${PEER_TAG}.pub"
REMOTE_PSK_TMP="/tmp/wg_${PEER_TAG}.psk"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT"

# internal IP mapping
declare -A IPMAP
IPMAP[A]="10.8.0.1/24"
IPMAP[B]="10.8.0.2/24"
declare -A IPSIMPLE
IPSIMPLE[A]="10.8.0.1"
IPSIMPLE[B]="10.8.0.2"

SELF_IP="${IPMAP[$ROLE]}"
PEER_IP_INTERNAL_SIMPLE="${IPSIMPLE[$PEER_ROLE]}"

echo "[*] Role: $ROLE"
echo "[*] Self internal IP: $SELF_IP"
echo "[*] Peer internal IP (will be used in AllowedIPs): $PEER_IP_INTERNAL_SIMPLE"
echo "[*] Peer public IP: $PEER_IP"
echo "[*] Peer SSH target: $PEER_SSH (port $SSH_PORT)"

# ensure dirs
mkdir -p "$WG_CONF_DIR/$SELF_TAG"
chown -R 1000:1000 "$WG_DIR" 2>/dev/null || true

# bring down any existing compose instance (best-effort)
if docker compose -f "$WG_DIR/docker-compose.yml" ps >/dev/null 2>&1; then
  (cd "$WG_DIR" && docker compose down) || true
fi

# wipe previous config for fresh start
rm -rf "$WG_DIR/config"/*
mkdir -p "$WG_CONF_DIR/$SELF_TAG"

# generate keys using wg (must be installed inside host)
if ! command -v wg >/dev/null 2>&1; then
  echo "[!] 'wg' tool not found. Installing wireguard-tools..."
  apt-get update && apt-get install -y wireguard
fi

echo "[*] Generating keys..."
SELF_PRIVATE=$(wg genkey)
SELF_PUBLIC=$(printf "%s" "$SELF_PRIVATE" | wg pubkey)
SELF_PRESHARED=$(wg genpsk)

# save keys locally
printf "%s" "$SELF_private" >/dev/null 2>&1 || true
echo "$SELF_PRIVATE" > "$WG_CONF_DIR/$SELF_TAG/privatekey"
echo "$SELF_PUBLIC"  > "$WG_CONF_DIR/$SELF_TAG/publickey"
echo "$SELF_PRESHARED" > "$WG_CONF_DIR/$SELF_TAG/presharedkey"

# also write temporary files for exchange
echo "$SELF_PUBLIC"  > "$SELF_PUB_TMP"
echo "$SELF_PRESHARED" > "$SELF_PSK_TMP"
chmod 600 "$SELF_PUB_TMP" "$SELF_PSK_TMP"

# push our public+psk to peer
echo "[*] Copying our public key and psk to peer ($PEER_SSH)..."
scp $SSH_OPTS "$SELF_PUB_TMP" "$PEER_SSH:/tmp/" || {
  echo "[!] scp pub to peer failed. Make sure you have SSH access. Trying again..."
  sleep 2
  scp $SSH_OPTS "$SELF_PUB_TMP" "$PEER_SSH:/tmp/"
}
scp $SSH_OPTS "$SELF_PSK_TMP" "$PEER_SSH:/tmp/" || {
  echo "[!] scp psk to peer failed. Trying again..."
  sleep 2
  scp $SSH_OPTS "$SELF_PSK_TMP" "$PEER_SSH:/tmp/"
}

# wait to receive peer public+psk from remote /tmp (peer should push theirs)
echo "[*] Waiting for peer public key and psk to appear on remote and fetch them..."
# Try fetch loop (peer may not have run yet; we retry for 60s)
RETRIES=60
SLEEP=1
got_peer_files=0
for i in $(seq 1 $RETRIES); do
  # try to fetch remote files (peer should have uploaded theirs to /tmp via their run)
  scp $SSH_OPTS "$PEER_SSH:/tmp/wg_server${PEER_ROLE}.pub" "/tmp/" 2>/dev/null || true
  scp $SSH_OPTS "$PEER_SSH:/tmp/wg_server${PEER_ROLE}.psk" "/tmp/" 2>/dev/null || true

  if [[ -f "/tmp/wg_server${PEER_ROLE}.pub" && -f "/tmp/wg_server${PEER_ROLE}.psk" ]]; then
    got_peer_files=1
    break
  fi
  sleep $SLEEP
done

if [[ $got_peer_files -eq 0 ]]; then
  echo "[!] Could not fetch peer public/psk from remote within timeout. You can manually copy peer's /opt/wireguard/config/wg_confs/server${PEER_ROLE}/publickey and presharedkey to this host /tmp/wg_server${PEER_ROLE}.pub and /tmp/wg_server${PEER_ROLE}.psk and re-run script."
  exit 2
fi

PEER_PUBLIC=$(cat "/tmp/wg_server${PEER_ROLE}.pub")
PEER_PSK=$(cat "/tmp/wg_server${PEER_ROLE}.psk")

echo "[*] Peer public: $PEER_PUBLIC"
# write final wg0.conf
cat > "$WG_CONF_DIR/$SELF_TAG/wg0.conf" <<EOF
[Interface]
Address = $SELF_IP
PrivateKey = $SELF_PRIVATE
ListenPort = $WG_PORT
DNS = 10.8.0.1

[Peer]
PublicKey = $PEER_PUBLIC
PresharedKey = $PEER_PSK
Endpoint = $PEER_IP:$WG_PORT
AllowedIPs = $PEER_IP_INTERNAL_SIMPLE/32
PersistentKeepalive = 25
EOF

# docker-compose
cat > "$WG_DIR/docker-compose.yml" <<'EOF'
version: '3.8'
services:
  wireguard:
    image: linuxserver/wireguard
    container_name: wireguard
    cap_add:
      - NET_ADMIN
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - SERVERURL=auto
      - SERVERPORT=51820
      - PEERS=
      - PEERDNS=auto
      - INTERNAL_SUBNET=10.8.0.0/24
    volumes:
      - ./config:/config
      - /lib/modules:/lib/modules
    ports:
      - "51820:51820/udp"
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
EOF

# ensure ownership & permissions
chmod -R 700 "$WG_CONF_DIR/$SELF_TAG"
chown -R 1000:1000 "$WG_DIR" 2>/dev/null || true

# bring up compose
cd "$WG_DIR"
docker compose up -d

# cleanup remote temp files (best-effort)
ssh $SSH_OPTS "$PEER_SSH" "rm -f /tmp/wg_${PEER_TAG}.pub /tmp/wg_${PEER_TAG}.psk" || true
rm -f "/tmp/wg_${SELF_TAG}.pub" "/tmp/wg_${SELF_TAG}.psk" "/tmp/wg_server${PEER_ROLE}.pub" "/tmp/wg_server${PEER_ROLE}.psk"

echo "[*] Done. WireGuard container started. Run inside container:"
echo "    docker exec -it wireguard ip addr show wg0"
echo "    docker exec -it wireguard wg show"
echo "Then test ping to peer internal IP: ${PEER_IP_INTERNAL_SIMPLE}"
