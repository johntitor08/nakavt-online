class_name FightSim
extends RefCounted
## Dövüşün saf mantığı: çizim ve ağ bilmez. Online maçta yalnızca sunucuda,
## yapay zekâ maçında istemcide çalışır. Saniyede 60 adım ilerler.

const TPS := 60

const IN_LEFT := 1
const IN_RIGHT := 2
const IN_GUARD := 4
const IN_JAB := 8
const IN_HOOK := 16
const IN_UPPER := 32
const IN_DODGE := 64
const IN_ALL := 127
const PUNCH_BITS := IN_JAB | IN_HOOK | IN_UPPER

enum Phase { INTRO, FIGHT, COUNT, RESUME, REST, OVER }
enum St { IDLE, GUARD, BLOCKED, WINDUP, ACTIVE, RECOVER, DODGE, STUN, DOWN }
enum Punch { NONE, JAB, HOOK, UPPER }
enum Ev { BELL, HIT, BLOCK, GUARD_BROKEN, DODGED, KNOCKDOWN, COUNT, GETUP, ROUND_END, OVER }
enum Res { NONE, KO, TKO, DECISION, DRAW, FORFEIT }

const PUNCHES := {
	Punch.JAB: {"wind": 6, "active": 4, "rec": 9, "dmg": 5.0, "stam": 5.0, "reach": 170.0, "stun": 12, "push": 12.0},
	Punch.HOOK: {"wind": 13, "active": 5, "rec": 18, "dmg": 13.0, "stam": 12.0, "reach": 150.0, "stun": 22, "push": 24.0},
	Punch.UPPER: {"wind": 20, "active": 5, "rec": 24, "dmg": 20.0, "stam": 18.0, "reach": 122.0, "stun": 30, "push": 34.0},
}

const ROUNDS := 3
const ROUND_TICKS := 60 * TPS
const INTRO_TICKS := 150
const RESUME_TICKS := 90
const REST_TICKS := 300
const COUNT_TICKS := 50
const MIN_COUNT := 3
const MAX_HP := 100.0
const MAX_STAM := 100.0
const RING_MIN := 170.0
const RING_MAX := 1110.0
const START_GAP := 170.0
const MIN_GAP := 96.0
const WALK := 3.6
const WALK_BACK := 3.0
const WALK_GUARD := 1.8
const BUFFER_TICKS := 10
const DODGE_TICKS := 18
const DODGE_IFRAME_END := 12
const DODGE_SPEED := 9.0
const DODGE_COST := 12.0
const DODGE_COOLDOWN := 30
const COUNTER_WINDOW := 40
const REGEN_IDLE := 14.0 / TPS
const REGEN_GUARD := 5.0 / TPS
const METER_DECAY := 1.5 / TPS
const NO_SIDE := 255
const SNAP_SIZE := 44

class Fighter:
	var x := 0.0
	var st: int = 0
	var t := 0
	var dur := 0
	var punch: int = 0
	var landed := false
	var hp := 100.0
	var stam := 100.0
	var kd := 0
	var kd_round := 0
	var score := 0.0
	var meter := 0.0
	var prev_in := 0
	var buf := 0
	var buf_t := 0
	var mash := false
	var counter_t := 0
	var dodge_cd := 0

var fighters: Array[Fighter] = [Fighter.new(), Fighter.new()]
var tick := 0
var phase: int = Phase.INTRO
var timer := INTRO_TICKS
var clock := ROUND_TICKS
var round_no := 1
var count := 0
var count_t := 0
var downed := NO_SIDE
var winner := NO_SIDE
var result: int = Res.NONE
var _events: Array[Dictionary] = []


func _init() -> void:
	fighters[0].x = _start_x(0)
	fighters[1].x = _start_x(1)


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func step(in0: int, in1: int) -> void:
	tick += 1
	_read_presses(fighters[0], in0)
	_read_presses(fighters[1], in1)
	match phase:
		Phase.INTRO, Phase.RESUME:
			_settle_to(_start_x(0), _start_x(1), 8.0)
			timer -= 1
			if timer <= 0:
				if phase == Phase.INTRO:
					_emit({"e": Ev.BELL})
				phase = Phase.FIGHT
		Phase.FIGHT:
			_step_fight(in0, in1)
		Phase.COUNT:
			_step_count()
		Phase.REST:
			_step_rest()
		Phase.OVER:
			pass


func forfeit(side: int) -> void:
	if phase != Phase.OVER:
		_finish(1 - side, Res.FORFEIT)


static func meter_need(kd: int) -> int:
	return 12 + 8 * maxi(kd - 1, 0)


func _start_x(side: int) -> float:
	return 640.0 - START_GAP if side == 0 else 640.0 + START_GAP


func _emit(ev: Dictionary) -> void:
	_events.append(ev)


func _read_presses(f: Fighter, inp: int) -> void:
	var pressed := inp & ~f.prev_in
	f.prev_in = inp
	var act := pressed & (PUNCH_BITS | IN_DODGE)
	if act != 0:
		f.buf = act
		f.buf_t = BUFFER_TICKS
	elif f.buf_t > 0:
		f.buf_t -= 1
		if f.buf_t == 0:
			f.buf = 0
	f.mash = (pressed & PUNCH_BITS) != 0


func _settle_to(x0: float, x1: float, speed: float) -> void:
	for i in 2:
		var f := fighters[i]
		if f.st != St.DOWN:
			f.st = St.IDLE
			f.punch = Punch.NONE
		f.t += 1
		f.buf = 0
		f.buf_t = 0
	fighters[0].x = move_toward(fighters[0].x, x0, speed)
	fighters[1].x = move_toward(fighters[1].x, x1, speed)


func _step_fight(in0: int, in1: int) -> void:
	clock -= 1
	_update_fighter(fighters[0], fighters[1], in0)
	_update_fighter(fighters[1], fighters[0], in1)
	_separate()
	# Aynı anda gelen yumruklarda kimse sırada avantaj kazanmasın.
	var first := tick % 2
	var second := 1 - first
	var ready_first := _hit_ready(first)
	var ready_second := _hit_ready(second)
	var kind_first: int = fighters[first].punch
	var kind_second: int = fighters[second].punch
	if ready_first:
		_apply_hit(first, kind_first)
	if ready_second:
		_apply_hit(second, kind_second)
	if phase == Phase.FIGHT and clock <= 0:
		_end_round()


func _update_fighter(me: Fighter, other: Fighter, inp: int) -> void:
	me.t += 1
	me.counter_t = maxi(me.counter_t - 1, 0)
	me.dodge_cd = maxi(me.dodge_cd - 1, 0)
	var dir := 1.0 if other.x >= me.x else -1.0
	match me.st:
		St.IDLE, St.GUARD:
			if not _try_action(me):
				var wanted: int = St.GUARD if (inp & IN_GUARD) != 0 else St.IDLE
				if wanted != me.st:
					me.st = wanted
					me.t = 0
				_walk(me, inp, dir)
		St.BLOCKED, St.STUN:
			if me.t >= me.dur:
				_to_idle(me)
		St.WINDUP:
			var p: Dictionary = PUNCHES[me.punch]
			me.x += dir * 0.8
			if me.t >= int(p["wind"]):
				me.st = St.ACTIVE
				me.t = 0
				me.dur = int(p["active"])
		St.ACTIVE:
			if me.t >= me.dur:
				var rec := int(PUNCHES[me.punch]["rec"])
				me.st = St.RECOVER
				me.t = 0
				me.dur = int(rec * 0.6) if me.landed else rec
		St.RECOVER:
			if me.t >= me.dur:
				_to_idle(me)
		St.DODGE:
			me.x -= dir * DODGE_SPEED * (1.0 - float(me.t) / DODGE_TICKS)
			if me.t >= DODGE_TICKS:
				_to_idle(me)
	if me.st == St.IDLE:
		me.stam = minf(me.stam + REGEN_IDLE, MAX_STAM)
	elif me.st == St.GUARD:
		me.stam = minf(me.stam + REGEN_GUARD, MAX_STAM)
	me.x = clampf(me.x, RING_MIN, RING_MAX)


func _to_idle(f: Fighter) -> void:
	f.st = St.IDLE
	f.t = 0
	f.punch = Punch.NONE


func _try_action(f: Fighter) -> bool:
	if f.buf == 0:
		return false
	var act := f.buf
	if (act & IN_DODGE) != 0:
		if f.dodge_cd > 0 or f.stam < DODGE_COST:
			return false
		f.buf = 0
		f.buf_t = 0
		f.stam -= DODGE_COST
		f.dodge_cd = DODGE_COOLDOWN
		f.st = St.DODGE
		f.t = 0
		f.dur = DODGE_TICKS
		return true
	var kind: int = Punch.JAB
	if (act & IN_UPPER) != 0:
		kind = Punch.UPPER
	elif (act & IN_HOOK) != 0:
		kind = Punch.HOOK
	var p: Dictionary = PUNCHES[kind]
	if f.stam < float(p["stam"]):
		return false
	f.buf = 0
	f.buf_t = 0
	f.stam -= float(p["stam"])
	f.st = St.WINDUP
	f.t = 0
	f.dur = int(p["wind"])
	f.punch = kind
	f.landed = false
	return true


func _walk(f: Fighter, inp: int, dir: float) -> void:
	var move := 0.0
	if (inp & IN_RIGHT) != 0:
		move += 1.0
	if (inp & IN_LEFT) != 0:
		move -= 1.0
	if move == 0.0:
		return
	var speed := WALK if signf(move) == dir else WALK_BACK
	if f.st == St.GUARD:
		speed = WALK_GUARD
	f.x += move * speed


func _separate() -> void:
	var a := fighters[0]
	var b := fighters[1]
	var gap := absf(a.x - b.x)
	if gap >= MIN_GAP:
		return
	var dir := 1.0 if b.x >= a.x else -1.0
	var push := (MIN_GAP - gap) * 0.5
	a.x = clampf(a.x - dir * push, RING_MIN, RING_MAX)
	b.x = clampf(b.x + dir * push, RING_MIN, RING_MAX)
	# Biri halata dayandıysa kalan payı diğeri alır.
	gap = absf(a.x - b.x)
	if gap < MIN_GAP:
		if a.x <= RING_MIN or a.x >= RING_MAX:
			b.x = clampf(a.x + dir * MIN_GAP, RING_MIN, RING_MAX)
		else:
			a.x = clampf(b.x - dir * MIN_GAP, RING_MIN, RING_MAX)


func _hit_ready(side: int) -> bool:
	var a := fighters[side]
	var d := fighters[1 - side]
	if a.st != St.ACTIVE or a.landed:
		return false
	return absf(a.x - d.x) <= float(PUNCHES[a.punch]["reach"])


func _apply_hit(side: int, kind: int) -> void:
	var a := fighters[side]
	var d := fighters[1 - side]
	var p: Dictionary = PUNCHES[kind]
	a.landed = true
	var dir := 1.0 if d.x >= a.x else -1.0
	if d.st == St.DODGE and d.t <= DODGE_IFRAME_END:
		d.counter_t = COUNTER_WINDOW
		_emit({"e": Ev.DODGED, "s": 1 - side, "x": d.x})
		return
	var dmg := float(p["dmg"])
	var push := float(p["push"])
	if d.st == St.GUARD or d.st == St.BLOCKED:
		var broke: bool = kind == Punch.UPPER
		var stam_loss := dmg * (1.0 if not broke else 1.4)
		d.stam = maxf(d.stam - stam_loss, 0.0)
		if d.stam <= 0.0:
			broke = true
		# Gard üzerinden gelen hasar tek başına nakavt ettirmez.
		d.hp = maxf(d.hp - dmg * (0.3 if broke else 0.15), 1.0)
		d.x = clampf(d.x + dir * push * 0.6, RING_MIN, RING_MAX)
		d.t = 0
		d.st = St.STUN if broke else St.BLOCKED
		d.dur = 26 if broke else 10
		_emit({"e": Ev.GUARD_BROKEN if broke else Ev.BLOCK, "s": side, "p": kind, "x": d.x})
		return
	var counter := d.st == St.WINDUP or d.st == St.RECOVER or a.counter_t > 0
	if a.counter_t > 0:
		dmg *= 1.5
		a.counter_t = 0
	elif counter:
		dmg *= 1.3
	if a.stam < 15.0:
		dmg *= 0.7
	d.stam = maxf(d.stam - dmg * 0.4, 0.0)
	d.x = clampf(d.x + dir * push, RING_MIN, RING_MAX)
	d.st = St.STUN
	d.t = 0
	d.dur = int(p["stun"])
	d.punch = Punch.NONE
	d.buf = 0
	d.buf_t = 0
	a.score += dmg
	_emit({"e": Ev.HIT, "s": side, "p": kind, "d": dmg, "x": d.x, "c": counter})
	_damage(d, dmg, side)


func _damage(d: Fighter, dmg: float, attacker: int) -> void:
	# Aynı karede iki nakavt olmasın: sayım başladıysa ikinci darbe düşürmez.
	if phase != Phase.FIGHT:
		d.hp = maxf(d.hp - dmg, 1.0)
		return
	d.hp = maxf(d.hp - dmg, 0.0)
	if d.hp <= 0.0:
		_knockdown(attacker)


func _knockdown(attacker: int) -> void:
	var a := fighters[attacker]
	var d := fighters[1 - attacker]
	a.score += 20.0
	d.kd += 1
	d.kd_round += 1
	d.st = St.DOWN
	d.t = 0
	d.punch = Punch.NONE
	d.meter = 0.0
	_emit({"e": Ev.KNOCKDOWN, "s": 1 - attacker, "x": d.x})
	if d.kd_round >= 3:
		_finish(attacker, Res.TKO)
		return
	phase = Phase.COUNT
	downed = 1 - attacker
	count = 0
	count_t = 0


func _step_count() -> void:
	var d := fighters[downed]
	var a := fighters[1 - downed]
	a.st = St.IDLE
	a.punch = Punch.NONE
	a.t += 1
	a.x = move_toward(a.x, RING_MIN + 90.0 if downed == 1 else RING_MAX - 90.0, 5.0)
	d.t += 1
	d.meter = maxf(d.meter - METER_DECAY, 0.0)
	if d.mash:
		d.meter += 1.0
	count_t += 1
	if count_t % COUNT_TICKS == 0:
		count += 1
		_emit({"e": Ev.COUNT, "n": count})
	if count >= 10:
		_finish(1 - downed, Res.KO)
	elif d.meter >= meter_need(d.kd) and count >= MIN_COUNT:
		_get_up(d)


func _get_up(d: Fighter) -> void:
	var table: Array[float] = [50.0, 35.0, 20.0]
	d.hp = maxf(d.hp, table[mini(d.kd - 1, table.size() - 1)])
	d.stam = maxf(d.stam, 60.0)
	d.st = St.IDLE
	d.t = 0
	d.meter = 0.0
	_emit({"e": Ev.GETUP, "s": downed})
	downed = NO_SIDE
	count = 0
	phase = Phase.RESUME
	timer = RESUME_TICKS


func _end_round() -> void:
	_emit({"e": Ev.ROUND_END, "r": round_no})
	_emit({"e": Ev.BELL})
	if round_no >= ROUNDS:
		_decide()
		return
	phase = Phase.REST
	timer = REST_TICKS


func _step_rest() -> void:
	_settle_to(RING_MIN + 40.0, RING_MAX - 40.0, 5.0)
	for f in fighters:
		f.hp = minf(f.hp + 25.0 / REST_TICKS, MAX_HP)
		f.stam = minf(f.stam + 100.0 / REST_TICKS, MAX_STAM)
	timer -= 1
	if timer <= 0:
		round_no += 1
		clock = ROUND_TICKS
		for f in fighters:
			f.kd_round = 0
		phase = Phase.INTRO
		timer = INTRO_TICKS


func _decide() -> void:
	var diff := fighters[0].score - fighters[1].score
	if absf(diff) < 1.0:
		_finish(NO_SIDE, Res.DRAW)
	else:
		_finish(0 if diff > 0.0 else 1, Res.DECISION)


func _finish(side: int, res: int) -> void:
	phase = Phase.OVER
	winner = side
	result = res
	downed = NO_SIDE
	_emit({
		"e": Ev.OVER, "w": side, "r": res,
		"s0": int(fighters[0].score), "s1": int(fighters[1].score),
	})


## Ağdan geçen durum paketi. 44 bayt; WARP'ın küçük MTU'sunda bile sorun çıkarmaz.
func snapshot() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u8(phase)
	b.put_u16(maxi(timer, 0))
	b.put_u16(maxi(clock, 0))
	b.put_u8(round_no)
	b.put_u8(count)
	b.put_u8(downed)
	b.put_u8(winner)
	b.put_u8(result)
	for f in fighters:
		b.put_16(int(f.x * 4.0))
		b.put_u8(f.st)
		b.put_u8(mini(f.t, 255))
		b.put_u8(mini(f.dur, 255))
		b.put_u8(f.punch)
		b.put_u16(int(ceilf(f.hp * 10.0)))
		b.put_u16(int(f.stam * 10.0))
		b.put_u8(f.kd)
		b.put_u8(mini(int(f.meter), 255))
		b.put_u8(mini(meter_need(f.kd), 255))
		b.put_u16(int(f.score))
	return b.data_array


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != SNAP_SIZE:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var s := {
		"tick": b.get_u32(), "phase": b.get_u8(), "timer": b.get_u16(), "clock": b.get_u16(),
		"round": b.get_u8(), "count": b.get_u8(), "downed": b.get_u8(),
		"winner": b.get_u8(), "result": b.get_u8(),
	}
	var list: Array[Dictionary] = []
	for i in 2:
		list.append({
			"x": b.get_16() / 4.0, "st": b.get_u8(), "t": b.get_u8(), "dur": b.get_u8(),
			"punch": b.get_u8(), "hp": b.get_u16() / 10.0, "stam": b.get_u16() / 10.0,
			"kd": b.get_u8(), "meter": b.get_u8(), "need": b.get_u8(), "score": b.get_u16(),
		})
	s["f"] = list
	return s
