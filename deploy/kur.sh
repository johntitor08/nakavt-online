#!/bin/bash
# Nakavt Online sunucusunu bu bilgisayara systemd kullanıcı servisi olarak kurar ya da günceller.
# Kullanım: ./deploy/kur.sh [port]   (varsayılan 7800/UDP)
set -euo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-7800}"
HEDEF="$HOME/.local/share/nakavt-sunucu"

echo "== Linux sürümü derleniyor"
mkdir -p "$D/build/linux"
flatpak run org.godotengine.Godot --headless --path "$D" --export-release "Linux" "$D/build/linux/NakavtOnline.x86_64" > /dev/null 2>&1

if systemctl --user is-active --quiet nakavt-sunucu; then
	echo "== Çalışan sunucu durduruluyor (süren maçlar biter)"
	systemctl --user stop nakavt-sunucu
fi

mkdir -p "$HEDEF" "$HOME/.config/systemd/user"
cp "$D/build/linux/NakavtOnline.x86_64" "$HEDEF/"
cat > "$HOME/.config/systemd/user/nakavt-sunucu.service" <<UNIT
[Unit]
Description=Nakavt Online oyun sunucusu
After=network-online.target

[Service]
WorkingDirectory=%h/.local/share/nakavt-sunucu
ExecStart=/usr/bin/stdbuf -oL -eL %h/.local/share/nakavt-sunucu/NakavtOnline.x86_64 --headless -- --sunucu --port=$PORT
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now nakavt-sunucu
sleep 3
systemctl --user --no-pager status nakavt-sunucu | head -5
ss -ulnp | grep ":$PORT " || echo "UYARI: $PORT/UDP dinlenmiyor, logu kontrol et: journalctl --user -u nakavt-sunucu"

echo "== Tarayıcı tüneli kuruluyor"
"$D/deploy/web-tunel-kur.sh"
