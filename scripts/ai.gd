class_name BoxAI
extends RefCounted
## Antrenman rakibi. Sim'e yalnızca oyuncunun yapabileceği tuşlarla müdahale eder.

enum Level { EASY, MEDIUM, HARD }

const THINK_MIN := [20, 11, 6]
const THINK_MAX := [38, 22, 12]
const REACT := [0.15, 0.45, 0.75]
const PUNISH := [0.2, 0.55, 0.9]
const MASH_CHANCE := [0.08, 0.14, 0.22]

var side := 1
var level: int = Level.MEDIUM
var rng := RandomNumberGenerator.new()
var _cool := 0
var _held := 0
var _press := 0


func _init(p_side: int, p_level: int, p_seed: int = 0) -> void:
	side = p_side
	level = p_level
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()


func think(s: FightSim) -> int:
	if s.phase == FightSim.Phase.COUNT:
		if s.downed == side and rng.randf() < MASH_CHANCE[level] and s.fighters[side].prev_in == 0:
			return FightSim.IN_JAB
		return 0
	if s.phase != FightSim.Phase.FIGHT:
		_held = 0
		_press = 0
		return 0
	if _press != 0:
		var out := _held | _press
		_press = 0
		return out
	_cool -= 1
	if _cool <= 0:
		_decide(s)
	return _held


func _decide(s: FightSim) -> void:
	var me: FightSim.Fighter = s.fighters[side]
	var foe: FightSim.Fighter = s.fighters[1 - side]
	var dist := absf(me.x - foe.x)
	var forward := FightSim.IN_RIGHT if foe.x > me.x else FightSim.IN_LEFT
	var back := FightSim.IN_LEFT if foe.x > me.x else FightSim.IN_RIGHT
	var jab_reach := _reach(FightSim.Punch.JAB)
	var hook_reach := _reach(FightSim.Punch.HOOK)
	var upper_reach := _reach(FightSim.Punch.UPPER)
	_cool = rng.randi_range(THINK_MIN[level], THINK_MAX[level])
	_held = 0

	if foe.st == FightSim.St.WINDUP and dist < _reach(foe.punch) + 30.0 and rng.randf() < REACT[level]:
		if foe.punch == FightSim.Punch.UPPER and me.stam >= FightSim.DODGE_COST:
			_press = FightSim.IN_DODGE
		else:
			_held = FightSim.IN_GUARD
		_cool = maxi(_cool, 14)
		return

	var open := foe.st == FightSim.St.RECOVER or foe.st == FightSim.St.STUN
	if open and dist <= hook_reach and rng.randf() < PUNISH[level]:
		if dist <= upper_reach and rng.randf() < 0.3 and me.stam >= 18.0:
			_press = FightSim.IN_UPPER
		elif me.stam >= 12.0:
			_press = FightSim.IN_HOOK
		else:
			_press = FightSim.IN_JAB
		return

	if me.stam < 20.0:
		if dist < 210.0:
			_held = FightSim.IN_GUARD if rng.randf() < 0.4 else back
		return

	if dist > jab_reach - 8.0:
		_held = forward
		return

	var roll := rng.randf()
	if roll < 0.38:
		_press = FightSim.IN_JAB
	elif roll < 0.60:
		_press = FightSim.IN_HOOK if dist <= hook_reach else FightSim.IN_JAB
		if dist > hook_reach:
			_held = forward
	elif roll < 0.70 and dist <= upper_reach:
		_press = FightSim.IN_UPPER
	elif roll < 0.85:
		_held = FightSim.IN_GUARD
	else:
		_held = back if rng.randf() < 0.5 else forward


func _reach(kind: int) -> float:
	return float(FightSim.PUNCHES[kind]["reach"])
