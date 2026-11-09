#!/bin/bash
# Tarayıcı sürümü tünelini kullanıcı servisi olarak kurar ve başlatır.
# Kaldırmak için: systemctl --user disable --now nakavt-web-tunel
set -euo pipefail
cd "$(dirname "$0")"
install -Dm755 web-tunel.sh "$HOME/.local/bin/nakavt-web-tunel.sh"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/nakavt-web-tunel.service" <<UNIT
[Unit]
Description=Nakavt Online tarayici tuneli
After=network-online.target

[Service]
ExecStart=%h/.local/bin/nakavt-web-tunel.sh
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable nakavt-web-tunel.service
systemctl --user restart nakavt-web-tunel.service
echo "== Tünel adresi bekleniyor"
sleep 20
systemctl --user is-active nakavt-web-tunel
grep -E "adres yayınlandı|UYARI" "$HOME/.local/state/nakavt-web-tunel.log" | tail -2
