extends Node
## test.sh'in başlattığı headless istemciler. Gerçek FightView ile sunucuya bağlanır.
## Roller: ilk (A) maçı kazanmalı, ikinci (B) ortada bağlantıyı keser,
## yabanci (başka oda) eşleşmemeli, eski (yanlış sürüm) reddedilmeli.

const TIMEOUT_MSEC := 25000

var role := ""
var port := Net.DEFAULT_PORT
var address := "127.0.0.1"
var view: FightView
var _start := 0
var _foe_hurt := false
var _hit_events := 0
var _reported := false
var _last_trace := -1
var _any_events := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rol="):
			role = a.trim_prefix("--rol=")
		elif a.begins_with("--port="):
			port = a.trim_prefix("--port=").to_int()
		elif a.begins_with("--adres="):
			address = a.trim_prefix("--adres=")
	_start = Time.get_ticks_msec()
	Net.connect_failed.connect(func(m: String) -> void: _done(false, "bağlanamadı: " + m))
	if role == "menu":
		_start_via_menu()
		return
	Net.match_found.connect(_on_match)
	Net.queued.connect(func() -> void: print("[%s] kuyrukta" % role))
	Net.rejected.connect(_on_rejected)
	var code := "ODA1"
	if role == "yabanci":
		code = "BASKA"
	elif role == "eski":
		Net.client_version = Net.VERSION + 1
	Net.connect_to(address, port, "Bot-" + role + "\u0007", code)


## Oyuncunun izlediği yol: gerçek menüden maça girip menüye geri döner.
func _start_via_menu() -> void:
	var main: Node = get_parent()
	main.show_menu()
	var menu: Menu = main._current
	menu.persist = false
	menu._name_edit.text = "Menü Botu"
	menu._addr_edit.text = "127.0.0.1:%d" % port
	menu._code_edit.text = "menu"
	menu._start_search()


func _step_menu_role() -> void:
	var main: Node = get_parent()
	if not main._current is FightView:
		return
	var fight: FightView = main._current
	if fight.latest.is_empty() or int(fight.latest["tick"]) <= 60:
		return
	fight._leave()
	_done(main._current is Menu and not Net.is_online(), "menüden eşleşti, durum aldı, menüye döndü")


func _done(ok: bool, message: String) -> void:
	if _reported:
		return
	_reported = true
	print("%s [%s] %s" % ["OK  " if ok else "HATA", role, message])
	get_tree().quit(0 if ok else 1)


func _on_rejected(message: String) -> void:
	_done(role == "eski", "reddedildi: " + message)


func _on_match(side: int, name0: String, name1: String) -> void:
	if role != "ilk" and role != "ikinci":
		_done(false, "eşleşmemesi gerekirken eşleşti")
		return
	print("[%s] eşleşti: taraf %d, %s - %s" % [role, side, name0, name1])
	if name0.contains("\u0007") or name1.contains("\u0007"):
		_done(false, "sunucu isimdeki denetim karakterini temizlemedi")
		return
	view = FightView.new()
	view.start_online(side, name0, name1)
	view.input_override = _bot_input
	view.manual = "--sakin" in OS.get_cmdline_user_args()
	add_child(view)
	Net.event_received.connect(_on_event)


func _bot_input() -> int:
	if view.latest.is_empty() or int(view.latest["phase"]) != FightSim.Phase.FIGHT:
		return 0
	var me: Dictionary = view.latest["f"][view.my_side]
	var foe: Dictionary = view.latest["f"][1 - view.my_side]
	var dist := absf(float(me["x"]) - float(foe["x"]))
	if dist > 150.0:
		return FightSim.IN_RIGHT if float(foe["x"]) > float(me["x"]) else FightSim.IN_LEFT
	return FightSim.IN_JAB if Engine.get_physics_frames() % 20 < FightView.MIN_LATCH_TICKS else 0


func _on_event(ev: Dictionary) -> void:
	_any_events += 1
	if int(ev.get("e", -1)) == FightSim.Ev.HIT:
		_hit_events += 1
	if int(ev.get("e", -1)) == FightSim.Ev.OVER and role == "ilk":
		var won := int(ev["w"]) == view.my_side and int(ev["r"]) == FightSim.Res.FORFEIT
		_done(won and _foe_hurt and _hit_events > 0, "maç bitti: kazanan doğru=%s, can düştü=%s, isabet=%d" % [won, _foe_hurt, _hit_events])


func _process(_delta: float) -> void:
	var elapsed := Time.get_ticks_msec() - _start
	if view != null and "--izle" in OS.get_cmdline_user_args() and elapsed / 1000 != _last_trace:
		_last_trace = elapsed / 1000
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			var pp := enet.get_peer(1)
			print("[ağ %s] kayıp=%%%.1f rtt=%d kısma=%d" % [role,
				pp.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) * 100.0 / ENetPacketPeer.PACKET_LOSS_SCALE,
				pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
				pp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)])
		if view.latest.is_empty():
			print("[iz %s] %d sn: durum yok, ping=%d" % [role, _last_trace, Net.ping_ms])
		else:
			var f0: Dictionary = view.latest["f"][0]
			var f1: Dictionary = view.latest["f"][1]
			print("[iz %s] %d sn: tick=%d faz=%d x=%d/%d can=%d/%d isabet=%d olay=%d ping=%d" % [role, _last_trace,
				int(view.latest["tick"]), int(view.latest["phase"]), int(f0["x"]), int(f1["x"]),
				int(f0["hp"]), int(f1["hp"]), _hit_events, _any_events, Net.ping_ms])
	if role == "menu" and not _reported:
		_step_menu_role()
	if view != null and not view.latest.is_empty():
		var fighters: Array = view.latest["f"]
		if float(fighters[0]["hp"]) < 100.0 or float(fighters[1]["hp"]) < 100.0:
			_foe_hurt = true
	if role == "ikinci" and _hit_events >= 4:
		print("[ikinci] bağlantıyı kesiyor, ping=%d ms" % Net.ping_ms)
		Net.leave()
		_done(true, "maçta isabetler alındı, ayrıldı")
		return
	if elapsed > TIMEOUT_MSEC:
		_done(role == "yabanci", "süre doldu" + (" (eşleşmedi, beklenen)" if role == "yabanci" else ""))
