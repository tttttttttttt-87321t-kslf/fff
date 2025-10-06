#!/usr/bin/env bash
set -e

echo "🔹 Updating system and installing dependencies..."
sudo apt update
sudo apt install -y bluez bluez-tools pulseaudio pulseaudio-module-bluetooth \
                    pipewire pipewire-audio-client-libraries libspa-0.2-bluetooth \
                    git wget

echo "🔹 Enabling Bluetooth service..."
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

echo "🔹 Starting PipeWire..."
systemctl --user enable pipewire
systemctl --user start pipewire

echo "🔹 Please pair and connect your Android phone using bluetoothctl:"
echo "
# Run inside bluetoothctl:
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

echo "🔹 List available audio sources and sinks:"
pactl list short sources
pactl list short sinks

echo "✅ Setup complete. Use pactl to set default source/sink if needed:"
echo "pactl set-default-source <SOURCE_NAME>"
echo "pactl set-default-sink <SINK_NAME>"
