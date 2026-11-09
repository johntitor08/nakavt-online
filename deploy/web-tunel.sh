#!/bin/bash
# Nakavt Online tarayıcı sürümü için Cloudflare quick tunnel (hesapsız, ücretsiz).
# Sunucunun WebSocket portunu (7801/TCP) bir wss adresine açar. Adres her başlatmada değişir;
# yeni adres gizli gist'e yazılır, tarayıcı sürümü bağlanırken oradan okur.
export LC_ALL=C
GIST="$(cat "$HOME/.config/oyun-web-gist-id")"
DOSYA="nakavt.json"
LOG="$HOME/.local/state/nakavt-web-tunel.log"
mkdir -p "$(dirname "$LOG")"

yayinla() {
	local wss="${1/https:/wss:}"
	local deneme
	# Açılışta ağ ya da anahtarlık henüz hazır olmayabilir: 30 sn arayla 40 kez dene.
	for deneme in $(seq 1 40); do
		if printf '{"files":{"%s":{"content":"{\\"wss\\": \\"%s\\"}"}}}' "$DOSYA" "$wss" |
				timeout 30 gh api -X PATCH "gists/$GIST" --input - >/dev/null 2>>"$LOG"; then
			echo "$(date -Is) adres yayınlandı: $wss" >> "$LOG"
			return
		fi
		echo "$(date -Is) UYARI: adres yayınlanamadı ($deneme. deneme), 30 sn sonra yeniden" >> "$LOG"
		sleep 30
	done
}

echo "$(date -Is) tünel başlıyor" >> "$LOG"
last=""
"$HOME/.local/bin/cloudflared" tunnel --no-autoupdate --protocol http2 --url http://127.0.0.1:7801 2>&1 |
while IFS= read -r line; do
	echo "$line" >> "$LOG"
	# Cloudflare geçici tüneli silerse çık; systemd yeni tünelle yeniden başlatsın.
	if [[ $line == *"Tunnel not found"* ]]; then
		echo "$(date -Is) tünel silinmiş, yeniden başlatılıyor" >> "$LOG"
		exit 1
	fi
	if [[ $line =~ (https://[a-z0-9-]+\.trycloudflare\.com) ]] && [[ "${BASH_REMATCH[1]}" != "$last" ]]; then
		last="${BASH_REMATCH[1]}"
		yayinla "$last" &
	fi
done
