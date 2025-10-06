#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating system packages ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing required packages ==="
sudo apt install -y bluez pulseaudio pulseaudio-module-bluetooth ofono pulseaudio-utils

echo "=== Enabling and starting oFono ==="
sudo systemctl enable --now ofono

echo "=== Starting PulseAudio ==="
pulseaudio --start || true

echo "=== Loading Bluetooth modules in PulseAudio ==="
pactl load-module module-bluetooth-discover || echo "Module bluetooth-discover already loaded or failed"
pactl load-module module-bluetooth-policy   || echo "Module bluetooth-policy already loaded or failed"

echo "=== Installing WirePlumber if missing ==="
if ! dpkg -l | grep -q wireplumber; then
    sudo apt install -y wireplumber
fi

echo "=== Enabling WirePlumber ==="
systemctl --user enable --now wireplumber || true

echo "=== Restarting audio services ==="
systemctl --user daemon-reload
systemctl --user restart pipewire pipewire-pulse wireplumber || true

echo "=== Bluetoothctl helper ==="
echo "Use bluetoothctl to pair and connect your phone:"
echo "   bluetoothctl"
echo "   power on"
echo "   agent on"
echo "   default-agent"
echo "   scan on"
echo "   pair XX:XX:XX:XX:XX:XX"
echo "   trust XX:XX:XX:XX:XX:XX"
echo "   connect XX:XX:XX:XX:XX:XX"

echo "=== Done ==="
