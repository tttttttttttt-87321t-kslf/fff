#!/usr/bin/env bash
set -e

# 1️⃣ بروزرسانی و نصب پیش‌نیازها
echo "🔹 Updating system and installing dependencies..."
sudo apt update
sudo apt install -y bluez bluez-tools pulseaudio pulseaudio-module-bluetooth \
                    pipewire pipewire-audio-client-libraries libspa-0.2-bluetooth \
                    git wget

# 2️⃣ فعال‌سازی و شروع سرویس Bluetooth
echo "🔹 Enabling Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# 3️⃣ شروع PipeWire برای مدیریت صوتی
echo "🔹 Starting PipeWire..."
systemctl --user enable pipewire
systemctl --user start pipewire

# 4️⃣ دستورالعمل اتصال گوشی (SSH-friendly)
echo "🔹 Pair, trust and connect your Android phone via bluetoothctl"
echo "Please run the following commands inside bluetoothctl:"
echo "
power on
agent on
default-agent
scan on
# find your phone MAC and replace <MAC_PHONE>
pair <MAC_PHONE>
trust <MAC_PHONE>
connect <MAC_PHONE>
scan off
"

# 5️⃣ آماده سازی PulseAudio/ PipeWire برای صدا
echo "🔹 List available sources and sinks:"
pactl list short sources
pactl list short sinks

echo "✅ Setup complete. After pairing, you can set default sink/source:"
echo "pactl set-default-source <SOURCE_NAME>"
echo "pactl set-default-sink <SINK_NAME>"
