class_name FightView
extends Node2D
## Maç ekranı. Yapay zekâ maçında sim burada döner; online'da sunucudan gelen
## durumları ara değerleyerek çizer, kendi boksörünü gecikmesiz hissettirir.

signal finished

const INTERP_TICKS := 7.0
const MIN_LATCH_TICKS := 6
const KEYS := {
	FightSim.IN_LEFT: [KEY_A, KEY_LEFT],
	FightSim.IN_RIGHT: [KEY_D, KEY_RIGHT],
	FightSim.IN_GUARD: [KEY_S, KEY_DOWN],
	FightSim.IN_JAB: [KEY_J, KEY_Z],
	FightSim.IN_HOOK: [KEY_K, KEY_X],
	FightSim.IN_UPPER: [KEY_L, KEY_C],
	FightSim.IN_DODGE: [KEY_SHIFT, KEY_SPACE],
}
const LATCHED := [FightSim.IN_JAB, FightSim.IN_HOOK, FightSim.IN_UPPER, FightSim.IN_DODGE]
const RESULT_TEXT := {
	FightSim.Res.KO: "NAKAVT",
	FightSim.Res.TKO: "TEKNİK NAKAVT",
	FightSim.Res.DECISION: "Hakem kararı",
	FightSim.Res.DRAW: "Puanlar eşit",
	FightSim.Res.FORFEIT: "Rakip maçı bıraktı",
}

var online := false
var my_side := 0
var names: Array[String] = ["", ""]
var sim: FightSim
var ai: BoxAI
var input_override := Callable()
var manual := false
var latest: Dictionary = {}
var over_event: Dictionary = {}

var _snaps: Array[Dictionary] = []
var _render_tick := 0.0
var _drawn: Array[Dictionary] = [{}, {}]
var _latch: Dictionary = {}
var _prev_keys := 0
var _pred_x := -1.0
var _pred_punch := 0
var _pred_time := 0.0
var _walk: Array[float] = [0.0, 0.0]
var _last_x: Array[float] = [0.0, 0.0]
var _ghost: Array[float] = [100.0, 100.0]
var _flash: Array[float] = [0.0, 0.0]
var _time := 0.0
var _shake := 0.0
var _shake_offset := Vector2.ZERO
var _excite := 0.0
var _parts: Array[Dictionary] = []
var _texts: Array[Dictionary] = []
var _banner := ""
var _banner_t := 0.0
var _lost := false
var _esc_armed := 0.0
var _sfx: Sfx
var _rng := RandomNumberGenerator.new()


func start_offline(player_name: String, level: int) -> void:
	online = false
	my_side = 0
	names = [player_name, ["Çaylak", "Usta", "Şampiyon"][level]]
	sim = FightSim.new()
	ai = BoxAI.new(1, level)
	push_snapshot(sim.snapshot())


func start_online(side: int, name0: String, name1: String) -> void:
	online = true
	my_side = side
	names = [name0, name1]
	Net.snap_received.connect(push_snapshot)
	Net.event_received.connect(handle_event)
	Net.disconnected.connect(_on_lost)


func _ready() -> void:
	_rng.randomize()
	_sfx = Sfx.new()
	add_child(_sfx)


func _read_input() -> int:
	if input_override.is_valid():
		return input_override.call()
	var held := 0
	for bit: int in KEYS:
		for key: int in KEYS[bit]:
			if Input.is_physical_key_pressed(key):
				held |= bit
				break
	var rising := held & ~_prev_keys
	_prev_keys = held
	# Kısa basışlar paket kaybında kaybolmasın diye birkaç kare açık tutulur.
	var mask := held
	for bit: int in LATCHED:
		if (rising & bit) != 0:
			_latch[bit] = MIN_LATCH_TICKS
		var left: int = _latch.get(bit, 0)
		if left > 0:
			mask |= bit
			_latch[bit] = left - 1
	_predict_punch(rising)
	return mask


func _predict_punch(rising: int) -> void:
	if not online or latest.is_empty() or int(latest["phase"]) != FightSim.Phase.FIGHT:
		return
	var own: Dictionary = latest["f"][my_side]
	var free := int(own["st"]) == FightSim.St.IDLE or int(own["st"]) == FightSim.St.GUARD
	if not free or _pred_punch != 0:
		return
	if (rising & FightSim.IN_UPPER) != 0:
		_pred_punch = FightSim.Punch.UPPER
	elif (rising & FightSim.IN_HOOK) != 0:
		_pred_punch = FightSim.Punch.HOOK
	elif (rising & FightSim.IN_JAB) != 0:
		_pred_punch = FightSim.Punch.JAB
	else:
		return
	_pred_time = 0.0


func _physics_process(_delta: float) -> void:
	if manual:
		return
	var mask := _read_input()
	if online:
		if not over_event.is_empty() or _lost:
			return
		Net.send_input(mask)
		return
	var ai_mask := ai.think(sim)
	sim.step(mask, ai_mask)
	push_snapshot(sim.snapshot())
	for ev in sim.drain_events():
		handle_event(ev)


func push_snapshot(bytes: PackedByteArray) -> void:
	var s := FightSim.decode(bytes)
	if s.is_empty():
		return
	if not latest.is_empty() and int(s["tick"]) <= int(latest["tick"]):
		return
	if latest.is_empty():
		_render_tick = float(s["tick"])
		for i in 2:
			_last_x[i] = float(s["f"][i]["x"])
			_ghost[i] = float(s["f"][i]["hp"])
	latest = s
	_snaps.append(s)
	if _snaps.size() > 24:
		_snaps.pop_front()


func _process(delta: float) -> void:
	_time += delta
	if latest.is_empty():
		queue_redraw()
		return
	_update_render(delta)
	_update_effects(delta)
	queue_redraw()


func _update_render(delta: float) -> void:
	var target := float(latest["tick"]) - (INTERP_TICKS if online else 0.0)
	_render_tick += delta * FightSim.TPS
	if absf(_render_tick - target) > 20.0 or not online:
		_render_tick = target
	else:
		_render_tick = lerpf(_render_tick, target, 0.05)
	var older: Dictionary = _snaps[0]
	var newer: Dictionary = latest
	for i in range(_snaps.size() - 1, -1, -1):
		if float(_snaps[i]["tick"]) <= _render_tick:
			older = _snaps[i]
			newer = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var span := maxf(float(newer["tick"]) - float(older["tick"]), 1.0)
	var k := clampf((_render_tick - float(older["tick"])) / span, 0.0, 1.0)
	for i in 2:
		var src: Dictionary = (latest if online and i == my_side else older)["f"][i]
		var f := src.duplicate()
		if not (online and i == my_side):
			f["x"] = lerpf(float(older["f"][i]["x"]), float(newer["f"][i]["x"]), k)
			if int(older["f"][i]["st"]) == int(newer["f"][i]["st"]):
				f["t"] = lerpf(float(older["f"][i]["t"]), float(newer["f"][i]["t"]), k)
		_drawn[i] = f
	if online:
		_apply_local_prediction(delta)
	for i in 2:
		var x: float = _drawn[i]["x"]
		_walk[i] += (x - _last_x[i]) * 0.085
		_last_x[i] = x


func _apply_local_prediction(delta: float) -> void:
	var own := _drawn[my_side]
	var server_x: float = own["x"]
	if _pred_x < 0.0:
		_pred_x = server_x
	var st: int = own["st"]
	var movable := (st == FightSim.St.IDLE or st == FightSim.St.GUARD) and int(latest["phase"]) == FightSim.Phase.FIGHT
	if movable and input_override.is_null():
		var move := 0.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			move += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			move -= 1.0
		var speed := FightSim.WALK_GUARD if st == FightSim.St.GUARD else FightSim.WALK
		_pred_x += move * speed * FightSim.TPS * delta
	_pred_x = lerpf(_pred_x, server_x, 1.0 - exp(-8.0 * delta))
	if absf(_pred_x - server_x) > 60.0:
		_pred_x = server_x
	_pred_x = clampf(_pred_x, FightSim.RING_MIN, FightSim.RING_MAX)
	own["x"] = _pred_x
	if _pred_punch != 0:
		_pred_time += delta
		if _pred_time > 0.2 or st != FightSim.St.IDLE and st != FightSim.St.GUARD:
			_pred_punch = 0
		else:
			own["st"] = FightSim.St.WINDUP
			own["punch"] = _pred_punch
			own["t"] = _pred_time * FightSim.TPS
			own["dur"] = FightSim.PUNCHES[_pred_punch]["wind"]


func _update_effects(delta: float) -> void:
	for i in 2:
		_flash[i] = maxf(_flash[i] - delta * 4.0, 0.0)
		var hp: float = latest["f"][i]["hp"]
		if _ghost[i] < hp:
			_ghost[i] = hp
		else:
			_ghost[i] = move_toward(_ghost[i], hp, delta * 28.0)
	_shake = maxf(_shake - delta * 42.0, 0.0)
	_shake_offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake))
	_excite = maxf(_excite - delta * 0.35, 0.0)
	_banner_t = maxf(_banner_t - delta, 0.0)
	_esc_armed = maxf(_esc_armed - delta, 0.0)
	for i in range(_parts.size() - 1, -1, -1):
		var p := _parts[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			_parts.remove_at(i)
			continue
		var v: Vector2 = p["v"]
		v.y += 900.0 * delta
		p["v"] = v
		p["p"] = (p["p"] as Vector2) + v * delta
	for i in range(_texts.size() - 1, -1, -1):
		var t := _texts[i]
		t["life"] = float(t["life"]) - delta
		t["p"] = (t["p"] as Vector2) + Vector2(0, -70.0 * delta)
		if float(t["life"]) <= 0.0:
			_texts.remove_at(i)


func handle_event(ev: Dictionary) -> void:
	var type: int = ev.get("e", -1)
	var head := Vector2(float(ev.get("x", 640.0)), Art.FLOOR_Y - 205.0)
	match type:
		FightSim.Ev.BELL:
			_sfx.play("bell", -3.0)
		FightSim.Ev.HIT:
			_on_hit(ev, head)
		FightSim.Ev.BLOCK:
			_sfx.play("block", -4.0)
			_sparks(head, 6, Color(0.75, 0.87, 1.0), 240.0)
			_shake = maxf(_shake, 2.0)
		FightSim.Ev.GUARD_BROKEN:
			_sfx.play("hook", -2.0)
			_sparks(head, 16, Color(1.0, 0.85, 0.3), 420.0)
			_float_text(head, "GARD KIRILDI", Color(1.0, 0.82, 0.3), 30)
			_shake = maxf(_shake, 9.0)
		FightSim.Ev.DODGED:
			_sfx.play("whoosh", -4.0)
			_float_text(head, "SIYRILDI", Color(0.6, 1.0, 0.8), 28)
		FightSim.Ev.KNOCKDOWN:
			_sfx.play("down")
			_sfx.play("crowd", -5.0)
			_sparks(head, 34, Color(1.0, 0.7, 0.25), 620.0)
			_shake = 18.0
			_excite = 1.0
			_show_banner("YERDE!", 1.3)
		FightSim.Ev.COUNT:
			_sfx.play("tick", 2.0)
		FightSim.Ev.GETUP:
			_sfx.play("crowd", -8.0)
			_excite = 0.6
		FightSim.Ev.ROUND_END:
			_show_banner("RAUNT %d BİTTİ" % int(ev.get("r", 1)), 2.2)
		FightSim.Ev.OVER:
			over_event = ev
			_sfx.play("crowd", -3.0)
			_excite = 1.0


func _on_hit(ev: Dictionary, head: Vector2) -> void:
	var kind: int = ev.get("p", FightSim.Punch.JAB)
	var dmg: float = ev.get("d", 0.0)
	var counter: bool = ev.get("c", false)
	var victim := 1 - int(ev.get("s", 0))
	_flash[victim] = 1.0
	match kind:
		FightSim.Punch.JAB:
			_sfx.play("jab")
			_sparks(head, 7, Color(1.0, 0.95, 0.7), 300.0)
			_shake = maxf(_shake, 3.0)
		FightSim.Punch.HOOK:
			_sfx.play("hook")
			_sparks(head, 15, Color(1.0, 0.82, 0.4), 440.0)
			_shake = maxf(_shake, 8.0)
			_excite = minf(_excite + 0.2, 1.0)
		FightSim.Punch.UPPER:
			_sfx.play("upper")
			_sparks(head, 24, Color(1.0, 0.65, 0.3), 560.0)
			_shake = maxf(_shake, 13.0)
			_excite = minf(_excite + 0.35, 1.0)
	var col := Color(1.0, 0.45, 0.3) if counter else Color(1, 1, 1)
	_float_text(head + Vector2(0, -30), ("KONTRA %d" if counter else "%d") % int(round(dmg)), col, 26 if counter else 24)


func _sparks(at: Vector2, n: int, col: Color, speed: float) -> void:
	for i in n:
		var a := _rng.randf() * TAU
		_parts.append({
			"p": at, "v": Vector2(cos(a), sin(a)) * _rng.randf_range(speed * 0.3, speed),
			"life": _rng.randf_range(0.15, 0.42), "col": col, "r": _rng.randf_range(1.6, 4.2),
		})


func _float_text(at: Vector2, text: String, col: Color, size: int) -> void:
	_texts.append({"p": at + Vector2(_rng.randf_range(-20, 20), 0), "text": text, "col": col, "size": size, "life": 0.8})


func _show_banner(text: String, duration: float) -> void:
	_banner = text
	_banner_t = duration


func _on_lost() -> void:
	if over_event.is_empty():
		_lost = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if not over_event.is_empty() or _lost:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_ESCAPE:
			_leave()
		return
	if key == KEY_ESCAPE:
		if _esc_armed > 0.0:
			_leave()
		else:
			_esc_armed = 2.5


func _leave() -> void:
	if online:
		Net.leave()
	finished.emit()


# --- Çizim ---

func _draw() -> void:
	Art.draw_arena(self, _time, _shake_offset, _excite)
	if latest.is_empty() or _drawn[0].is_empty():
		_draw_centered("Maç hazırlanıyor…", Vector2(640, 360), 44, Color.WHITE)
		return
	var order := [0, 1]
	if int(_drawn[0]["st"]) == FightSim.St.ACTIVE:
		order = [1, 0]
	for i: int in order:
		_draw_fighter(i)
	Art.draw_ring_front(self, _shake_offset)
	_draw_effects()
	_draw_hud()
	_draw_messages()


func _mood(i: int) -> String:
	if over_event.is_empty():
		return ""
	var w: int = over_event["w"]
	if w == FightSim.NO_SIDE:
		return ""
	return "win" if w == i else "lose"


func _draw_fighter(i: int) -> void:
	var f := _drawn[i]
	var other := _drawn[1 - i]
	var facing := 1.0 if float(other["x"]) >= float(f["x"]) else -1.0
	var pos := Vector2(float(f["x"]), Art.FLOOR_Y) + _shake_offset
	var pal: Dictionary = Art.RED_CORNER if i == 0 else Art.BLUE_CORNER
	draw_set_transform(_shake_offset)
	var shadow := PackedVector2Array()
	for a in 24:
		var ang := TAU * a / 24.0
		shadow.append(Vector2(float(f["x"]) + cos(ang) * 74.0, Art.FLOOR_Y + 6.0 + sin(ang) * 15.0))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	var phase_t := _time + i * 0.7
	Art.draw_boxer(self, pos, facing, Art.pose_for(f, phase_t, _walk[i], _mood(i)), pal, _flash[i], float(f["hp"]))
	if i == my_side and over_event.is_empty():
		var tip := Vector2(float(f["x"]), Art.FLOOR_Y - 278.0 + sin(_time * 5.0) * 4.0) + _shake_offset
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-11, -15), tip + Vector2(11, -15)]), Color(1.0, 0.9, 0.35))


func _draw_effects() -> void:
	draw_set_transform(_shake_offset)
	for p in _parts:
		var col: Color = p["col"]
		col.a = clampf(float(p["life"]) * 4.0, 0.0, 1.0)
		draw_circle(p["p"], float(p["r"]), col)
	for t in _texts:
		var col: Color = t["col"]
		col.a = clampf(float(t["life"]) * 2.5, 0.0, 1.0)
		_draw_centered(t["text"], t["p"], t["size"], col)
	draw_set_transform(Vector2.ZERO)


func _draw_centered(text: String, at: Vector2, size: int, col: Color, outline: int = 7) -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(at.x - 700.0, at.y)
	if outline > 0:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 1400, size, outline, Color(0.03, 0.03, 0.07, col.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 1400, size, col)


func _bar(rect: Rect2, ratio: float, ghost: float, col: Color, from_right: bool) -> void:
	draw_rect(rect.grow(3), Color(0.04, 0.04, 0.08))
	draw_rect(rect, Color(0.16, 0.16, 0.22))
	var make := func(k: float) -> Rect2:
		var w := rect.size.x * clampf(k, 0.0, 1.0)
		var x := rect.end.x - w if from_right else rect.position.x
		return Rect2(x, rect.position.y, w, rect.size.y)
	if ghost > ratio:
		draw_rect(make.call(ghost), Color(1.0, 0.85, 0.5))
	draw_rect(make.call(ratio), col)
	var top: Rect2 = make.call(ratio)
	top.size.y *= 0.38
	draw_rect(top, Color(1, 1, 1, 0.22))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var f0: Dictionary = latest["f"][0]
	var f1: Dictionary = latest["f"][1]
	var hp_cols := [_hp_color(float(f0["hp"])), _hp_color(float(f1["hp"]))]
	_bar(Rect2(44, 40, 490, 30), float(f0["hp"]) / FightSim.MAX_HP, _ghost[0] / FightSim.MAX_HP, hp_cols[0], false)
	_bar(Rect2(746, 40, 490, 30), float(f1["hp"]) / FightSim.MAX_HP, _ghost[1] / FightSim.MAX_HP, hp_cols[1], true)
	var stam := Color(0.35, 0.82, 1.0)
	_bar(Rect2(44, 78, 300, 12), float(f0["stam"]) / FightSim.MAX_STAM, 0.0, stam, false)
	_bar(Rect2(936, 78, 300, 12), float(f1["stam"]) / FightSim.MAX_STAM, 0.0, stam, true)

	var left_name := names[0] + (" (Sen)" if my_side == 0 else "")
	var right_name := names[1] + (" (Sen)" if my_side == 1 else "")
	draw_string_outline(font, Vector2(44, 30), left_name, HORIZONTAL_ALIGNMENT_LEFT, 440, 24, 6, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(44, 30), left_name, HORIZONTAL_ALIGNMENT_LEFT, 440, 24, Color(1.0, 0.72, 0.7))
	draw_string_outline(font, Vector2(796, 30), right_name, HORIZONTAL_ALIGNMENT_RIGHT, 440, 24, 6, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(796, 30), right_name, HORIZONTAL_ALIGNMENT_RIGHT, 440, 24, Color(0.7, 0.82, 1.0))
	for i in int(f0["kd"]):
		draw_circle(Vector2(362.0 + i * 24.0, 84.0), 8.0, Color(1.0, 0.3, 0.25))
	for i in int(f1["kd"]):
		draw_circle(Vector2(918.0 - i * 24.0, 84.0), 8.0, Color(1.0, 0.3, 0.25))

	draw_rect(Rect2(548, 18, 184, 82), Color(0.04, 0.04, 0.08, 0.9))
	draw_rect(Rect2(548, 18, 184, 82), Color(0.98, 0.84, 0.35), false, 3.0)
	var secs := ceili(float(latest["clock"]) / FightSim.TPS)
	_draw_centered("%d:%02d" % [secs / 60, secs % 60], Vector2(640, 66), 44, Color.WHITE, 0)
	_draw_centered("RAUNT %d / %d" % [int(latest["round"]), FightSim.ROUNDS], Vector2(640, 91), 18, Color(0.98, 0.84, 0.35), 0)

	if online and Net.ping_ms >= 0:
		draw_string(font, Vector2(1160, 712), "%d ms" % Net.ping_ms, HORIZONTAL_ALIGNMENT_RIGHT, 100, 16, Color(1, 1, 1, 0.65))
	draw_string(font, Vector2(20, 712), "A/D hareket   S gard   J düz   K kroşe   L aparkat   Shift sıyrıl   Esc çık",
		HORIZONTAL_ALIGNMENT_LEFT, 1000, 16, Color(1, 1, 1, 0.65))


func _hp_color(hp: float) -> Color:
	if hp > 50.0:
		return Color(0.32, 0.82, 0.38)
	if hp > 25.0:
		return Color(0.95, 0.72, 0.2)
	return Color(0.92, 0.22, 0.2)


func _draw_messages() -> void:
	var phase: int = latest["phase"]
	if _esc_armed > 0.0 and over_event.is_empty():
		_draw_centered("Çıkmak için tekrar Esc" + (" (hükmen yenilirsin)" if online else ""), Vector2(640, 150), 26, Color(1, 0.8, 0.5))
	if _lost:
		_panel("BAĞLANTI KOPTU", "Sunucuyla bağlantı kesildi", Color(1.0, 0.6, 0.4))
		return
	if not over_event.is_empty():
		_draw_over()
		return
	match phase:
		FightSim.Phase.INTRO:
			var sec := ceili(float(latest["timer"]) / FightSim.TPS)
			_draw_centered("RAUNT %d" % int(latest["round"]), Vector2(640, 250), 84, Color.WHITE)
			_draw_centered(str(sec), Vector2(640, 340), 66, Color(0.98, 0.84, 0.35))
		FightSim.Phase.COUNT:
			_draw_count()
		FightSim.Phase.RESUME:
			_draw_centered("DEVAM!", Vector2(640, 280), 72, Color(0.98, 0.84, 0.35))
		FightSim.Phase.REST:
			var sec := ceili(float(latest["timer"]) / FightSim.TPS)
			_draw_centered("KÖŞE MOLASI", Vector2(640, 250), 62, Color.WHITE)
			_draw_centered("%d" % sec, Vector2(640, 330), 56, Color(0.98, 0.84, 0.35))
			var f0: Dictionary = latest["f"][0]
			var f1: Dictionary = latest["f"][1]
			_draw_centered("Puan  %d - %d" % [int(f0["score"]), int(f1["score"])], Vector2(640, 385), 30, Color(1, 1, 1, 0.9))
	if _banner_t > 0.0 and phase != FightSim.Phase.COUNT:
		_draw_centered(_banner, Vector2(640, 220), 64, Color(1.0, 0.45, 0.3))


func _draw_count() -> void:
	var down: int = latest["downed"]
	var count: int = latest["count"]
	var col := Color(1.0, 0.35, 0.28)
	_draw_centered(str(count) if count > 0 else "YERDE!", Vector2(640, 300), 150 if count > 0 else 96, col, 12)
	if down != my_side:
		return
	var f: Dictionary = latest["f"][down]
	var ratio := clampf(float(f["meter"]) / maxf(float(f["need"]), 1.0), 0.0, 1.0)
	var pulse := 0.65 + 0.35 * sin(_time * 12.0)
	_draw_centered("KALK! J - K - L TUŞLARINA ART ARDA BAS", Vector2(640, 365), 32, Color(1, 1, 1, pulse))
	_bar(Rect2(420, 385, 440, 24), ratio, 0.0, Color(1.0, 0.82, 0.3), false)


func _draw_over() -> void:
	var w: int = over_event["w"]
	var res: int = over_event["r"]
	var title := "BERABERE"
	var col := Color(0.98, 0.84, 0.35)
	if w != FightSim.NO_SIDE:
		title = "KAZANDIN!" if w == my_side else "KAYBETTİN"
		col = Color(0.45, 1.0, 0.55) if w == my_side else Color(1.0, 0.4, 0.35)
	var line := "%s   •   Puan %d - %d" % [RESULT_TEXT.get(res, ""), int(over_event["s0"]), int(over_event["s1"])]
	_panel(title, line, col)


func _panel(title: String, line: String, col: Color) -> void:
	draw_rect(Rect2(290, 190, 700, 250), Color(0.03, 0.03, 0.07, 0.86))
	draw_rect(Rect2(290, 190, 700, 250), col, false, 4.0)
	_draw_centered(title, Vector2(640, 290), 86, col)
	_draw_centered(line, Vector2(640, 350), 30, Color.WHITE, 0)
	_draw_centered("Menüye dönmek için Enter", Vector2(640, 410), 22, Color(1, 1, 1, 0.75), 0)
