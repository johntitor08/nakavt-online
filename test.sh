#!/bin/sh
# Otomatik testler: kurallar, sonra gerçek ağ üzerinden sunucu + istemciler.
D="$(dirname "$(readlink -f "$0")")"
G="flatpak run org.godotengine.Godot --headless --path $D"
PORT=7806
TMP="$(mktemp -d)"
trap 'pkill -f "^/app/bin/godot-bin.*(--test-|--port=$PORT)"; rm -rf "$TMP"' EXIT

echo "--- Kurallar ---"
timeout 180 $G -- --test-sim > "$TMP/sim.log" 2>&1
RC=$?
grep -E "^OK|^HATA|SONUÇ|\[yz\]|SCRIPT ERROR|Parse Error|   at: " "$TMP/sim.log"
if [ "$RC" -ne 0 ]; then
	echo "SONUÇ: kural testleri başarısız (çıkış $RC)"
	exit 1
fi

echo "--- Ağ ---"
$G -- --sunucu --port=$PORT > "$TMP/sunucu.log" 2>&1 &
sleep 3
timeout 45 $G -- --test-bot --rol=eski --port=$PORT > "$TMP/eski.log" 2>&1 &
P0=$!
timeout 45 $G -- --test-bot --rol=yabanci --port=$PORT > "$TMP/yabanci.log" 2>&1 &
P1=$!
sleep 1
timeout 45 $G -- --test-bot --rol=ilk --port=$PORT > "$TMP/ilk.log" 2>&1 &
P2=$!
timeout 45 $G -- --test-bot --rol=ikinci --port=$PORT --adres=ws://127.0.0.1:$((PORT+1)) > "$TMP/ikinci.log" 2>&1 &
P3=$!
timeout 45 $G -- --test-bot --rol=menu --port=$PORT > "$TMP/menu1.log" 2>&1 &
P4=$!
timeout 45 $G -- --test-bot --rol=menu --port=$PORT > "$TMP/menu2.log" 2>&1 &
P5=$!
FAIL=0
wait $P0 || FAIL=1
wait $P1 || FAIL=1
wait $P2 || FAIL=1
wait $P3 || FAIL=1
wait $P4 || FAIL=1
wait $P5 || FAIL=1
grep -hE "^OK|^HATA|SCRIPT ERROR|Parse Error|\[ikinci\] bağ" "$TMP/eski.log" "$TMP/yabanci.log" "$TMP/ilk.log" "$TMP/ikinci.log" "$TMP/menu1.log" "$TMP/menu2.log"
grep -h "maç başladı" "$TMP/sunucu.log"
if [ "$FAIL" -ne 0 ]; then
	echo "SONUÇ: ağ testi başarısız"
	exit 1
fi
echo "SONUÇ: ağ testi geçti"
