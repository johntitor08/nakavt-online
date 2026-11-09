class_name Art
extends RefCounted
## Ring ve boksörlerin tamamı koddan çizilir; dışarıdan görsel dosyası yoktur.

const FLOOR_Y := 560.0
const OUTLINE := Color(0.07, 0.07, 0.11)
const GUARD_LEAD := Vector2(50, -176)
const GUARD_REAR := Vector2(34, -158)
const UPPER_ARM := 66.0
const FORE_ARM := 66.0
const THIGH := 50.0
const SHIN := 50.0

const RED_CORNER := {
	"skin": Color(0.87, 0.62, 0.45), "skin_dark": Color(0.72, 0.47, 0.33),
	"glove": Color(0.84, 0.13, 0.2), "glove_hi": Color(1.0, 0.42, 0.42),
	"trunks": Color(0.72, 0.1, 0.16), "trim": Color(0.98, 0.84, 0.35),
	"hair": Color(0.13, 0.1, 0.1), "boot": Color(0.93, 0.92, 0.88),
}
const BLUE_CORNER := {
	"skin": Color(0.55, 0.36, 0.25), "skin_dark": Color(0.42, 0.26, 0.18),
	"glove": Color(0.14, 0.38, 0.86), "glove_hi": Color(0.45, 0.68, 1.0),
	"trunks": Color(0.1, 0.25, 0.68), "trim": Color(0.92, 0.93, 0.97),
	"hair": Color(0.82, 0.71, 0.42), "boot": Color(0.15, 0.16, 0.22),
}

static var _crowd: Array[Dictionary] = []


static func _rect_gradient(c: CanvasItem, top: float, bottom: float, a: Color, b: Color) -> void:
	c.draw_polygon(
		PackedVector2Array([Vector2(-20, top), Vector2(1300, top), Vector2(1300, bottom), Vector2(-20, bottom)]),
		PackedColorArray([a, a, b, b]))


static func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var rows := [[150.0, 18.0, 0.34], [205.0, 22.0, 0.48], [268.0, 26.0, 0.62], [335.0, 30.0, 0.8]]
	for row: Array in rows:
		var x := -10.0 + rng.randf() * 20.0
		var size: float = row[1]
		while x < 1300.0:
			var shade: float = float(row[2]) * rng.randf_range(0.7, 1.05)
			var hue := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.55), shade * 0.55)
			_crowd.append({
				"p": Vector2(x, float(row[0]) + rng.randf_range(-5.0, 5.0)),
				"r": size * rng.randf_range(0.42, 0.52),
				"body": hue,
				"head": Color(0.62, 0.48, 0.4) * shade,
				"ph": rng.randf() * TAU,
				"sp": rng.randf_range(1.5, 3.6),
				"w": size,
			})
			x += size * rng.randf_range(1.5, 2.1)


static func draw_arena(c: CanvasItem, time: float, shake: Vector2, excitement: float) -> void:
	if _crowd.is_empty():
		_build_crowd()
	c.draw_set_transform(shake)
	_rect_gradient(c, -20, 440, Color(0.03, 0.04, 0.08), Color(0.09, 0.08, 0.15))
	_rect_gradient(c, 440, 740, Color(0.07, 0.07, 0.12), Color(0.02, 0.02, 0.04))
	for g in _crowd:
		var p: Vector2 = g["p"]
		var r: float = g["r"]
		var jump := absf(sin(time * float(g["sp"]) + float(g["ph"]))) * (1.5 + 10.0 * excitement)
		var at := p - Vector2(0, jump)
		c.draw_circle(at + Vector2(0, r * 2.5), r * 1.75, g["body"])
		c.draw_circle(at, r, g["head"])
	var bucket := int(time * 5.0)
	var fr := RandomNumberGenerator.new()
	fr.seed = bucket * 13 + 5
	for i in 2 + int(excitement * 6.0):
		var fp := Vector2(fr.randf() * 1280.0, fr.randf_range(130.0, 350.0))
		c.draw_circle(fp, 13.0, Color(1, 1, 1, 0.1))
		c.draw_circle(fp, 3.5, Color(1, 1, 1, 0.85))
	for lx: float in [260.0, 520.0, 760.0, 1020.0]:
		var spread := 150.0
		c.draw_polygon(
			PackedVector2Array([Vector2(lx * 0.3 + 448.0 - 20.0, -10), Vector2(lx * 0.3 + 448.0 + 20.0, -10),
				Vector2(lx + spread, 560), Vector2(lx - spread, 560)]),
			PackedColorArray([Color(1, 0.96, 0.82, 0.13), Color(1, 0.96, 0.82, 0.13),
				Color(1, 0.96, 0.82, 0.0), Color(1, 0.96, 0.82, 0.0)]))
	_draw_back_ring(c)
	_draw_mat(c)


static func _post(c: CanvasItem, x: float, bottom: float, height: float, width: float, col: Color) -> void:
	c.draw_rect(Rect2(x - width * 0.5 - 2.0, bottom - height - 2.0, width + 4.0, height + 2.0), OUTLINE)
	c.draw_rect(Rect2(x - width * 0.5, bottom - height, width, height), col)
	c.draw_rect(Rect2(x - width * 0.5 + 2.0, bottom - height, width * 0.28, height), Color(1, 1, 1, 0.22))


static func _draw_back_ring(c: CanvasItem) -> void:
	var colors := [Color(0.85, 0.15, 0.2), Color(0.93, 0.93, 0.95), Color(0.15, 0.38, 0.86)]
	_post(c, 175, 442, 128, 16, Color(0.75, 0.13, 0.18))
	_post(c, 1105, 442, 128, 16, Color(0.14, 0.33, 0.78))
	for i in 3:
		var y := 332.0 + i * 34.0
		c.draw_line(Vector2(175, y), Vector2(1105, y), OUTLINE, 7.0)
		c.draw_line(Vector2(175, y), Vector2(1105, y), colors[i], 4.0)


static func _draw_mat(c: CanvasItem) -> void:
	var back := Color(0.27, 0.41, 0.6)
	var front := Color(0.36, 0.54, 0.76)
	c.draw_polygon(
		PackedVector2Array([Vector2(170, 440), Vector2(1110, 440), Vector2(1225, 612), Vector2(55, 612)]),
		PackedColorArray([back, back, front, front]))
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(Vector2(640 + cos(a) * 250.0, 525 + sin(a) * 58.0))
	c.draw_polyline(pts, Color(1, 1, 1, 0.3), 5.0, true)
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(390, 548), "NAKAVT", HORIZONTAL_ALIGNMENT_CENTER, 500, 62, Color(1, 1, 1, 0.14))
	c.draw_polygon(
		PackedVector2Array([Vector2(55, 612), Vector2(1225, 612), Vector2(1225, 700), Vector2(55, 700)]),
		PackedColorArray([Color(0.5, 0.08, 0.13), Color(0.5, 0.08, 0.13), Color(0.2, 0.03, 0.07), Color(0.2, 0.03, 0.07)]))
	c.draw_line(Vector2(55, 612), Vector2(1225, 612), Color(0.98, 0.84, 0.35), 5.0)
	c.draw_string_outline(font, Vector2(340, 676), "NAKAVT ONLINE", HORIZONTAL_ALIGNMENT_CENTER, 600, 50, 8, Color(0, 0, 0, 0.5))
	c.draw_string(font, Vector2(340, 676), "NAKAVT ONLINE", HORIZONTAL_ALIGNMENT_CENTER, 600, 50, Color(0.98, 0.9, 0.7))


static func draw_ring_front(c: CanvasItem, shake: Vector2) -> void:
	c.draw_set_transform(shake)
	_post(c, 70, 640, 230, 24, Color(0.78, 0.13, 0.18))
	_post(c, 1210, 640, 230, 24, Color(0.14, 0.34, 0.8))
	var colors := [Color(0.85, 0.15, 0.2, 0.75), Color(0.93, 0.93, 0.95, 0.75), Color(0.15, 0.38, 0.86, 0.75)]
	for i in 3:
		var y := 430.0 + i * 56.0
		c.draw_line(Vector2(70, y), Vector2(1210, y), Color(0.05, 0.05, 0.1, 0.55), 8.0)
		c.draw_line(Vector2(70, y), Vector2(1210, y), colors[i], 5.0)
	c.draw_set_transform(Vector2.ZERO)


static func _ease_out(v: float) -> float:
	var k := clampf(v, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


## Durumdan iskelet duruşu üretir. Tüm konumlar ayaktan yukarı doğru, boksörün yüzü +x yönünde.
static func pose_for(f: Dictionary, time: float, walk: float, mood: String) -> Dictionary:
	var st: int = f["st"]
	var t: float = f["t"]
	var dur: float = maxf(float(f["dur"]), 1.0)
	var bob := sin(time * 5.0) * 3.0
	var stride := sin(walk)
	var pose := {
		"hip": Vector2(0, bob), "lean": 0.1, "head": Vector2.ZERO,
		"lead": GUARD_LEAD + Vector2(0, bob), "rear": GUARD_REAR + Vector2(0, bob * 1.3),
		"foot_f": Vector2(38 + stride * 18.0, -maxf(cos(walk), 0.0) * 8.0),
		"foot_b": Vector2(-36 - stride * 18.0, -maxf(-cos(walk), 0.0) * 8.0),
		"rot": 0.0, "lift": 0.0,
	}
	match st:
		FightSim.St.GUARD, FightSim.St.BLOCKED:
			var jolt := 0.0
			if st == FightSim.St.BLOCKED:
				jolt = (1.0 - t / dur) * 12.0
			pose["hip"] = Vector2(-jolt, 10.0 + bob * 0.5)
			pose["lean"] = 0.22
			pose["lead"] = Vector2(62 - jolt, -200)
			pose["rear"] = Vector2(50 - jolt, -180)
		FightSim.St.WINDUP, FightSim.St.ACTIVE, FightSim.St.RECOVER:
			_punch_pose(pose, f, t, dur)
		FightSim.St.DODGE:
			var k := sin(clampf(t / dur, 0.0, 1.0) * PI)
			pose["hip"] = Vector2(-20.0 * k, 12.0 * k)
			pose["lean"] = lerpf(0.1, -0.42, k)
		FightSim.St.STUN:
			var k := 1.0 - clampf(t / dur, 0.0, 1.0)
			pose["hip"] = Vector2(-16.0 * k, 4.0)
			pose["lean"] = lerpf(0.1, -0.36, k)
			pose["head"] = Vector2(-10.0 * k, 3.0)
			pose["lead"] = GUARD_LEAD.lerp(Vector2(30, -105), k)
			pose["rear"] = GUARD_REAR.lerp(Vector2(-20, -100), k)
		FightSim.St.DOWN:
			var k := _ease_out(t / 22.0)
			var rise := 0.0
			if int(f["need"]) > 0:
				rise = clampf(float(f["meter"]) / float(f["need"]), 0.0, 1.0)
			pose["rot"] = -1.5 * k * (1.0 - rise * 0.35)
			pose["lift"] = 16.0 * k
			pose["lean"] = 0.0
			pose["lead"] = Vector2(26, -92)
			pose["rear"] = Vector2(-16, -100)
			pose["foot_f"] = Vector2(16, 0)
			pose["foot_b"] = Vector2(-12, 0)
	if mood == "win":
		var wave := sin(time * 7.0) * 8.0
		pose["lean"] = -0.05
		pose["lead"] = Vector2(44, -290 + wave)
		pose["rear"] = Vector2(-34, -290 - wave)
	elif mood == "lose" and st != FightSim.St.DOWN:
		pose["lean"] = 0.42
		pose["hip"] = Vector2(0, 12)
		pose["lead"] = Vector2(44, -92)
		pose["rear"] = Vector2(14, -86)
		pose["head"] = Vector2(8, 12)
	return pose


static func _punch_pose(pose: Dictionary, f: Dictionary, t: float, dur: float) -> void:
	var st: int = f["st"]
	var kind: int = f["punch"]
	var ext := 0.0  # 0: gard, 1: tam uzanmış
	var wind := 0.0  # 0..1 hazırlık
	match st:
		FightSim.St.WINDUP:
			wind = clampf(t / dur, 0.0, 1.0)
		FightSim.St.ACTIVE:
			ext = _ease_out((t + 1.0) / 2.0)
		FightSim.St.RECOVER:
			ext = 1.0 - _ease_out(t / dur)
	match kind:
		FightSim.Punch.JAB:
			var target := Vector2(158, -205)
			var from := GUARD_LEAD + Vector2(-10.0 * wind, 2.0 * wind)
			pose["lead"] = from.lerp(target, ext)
			pose["lean"] = 0.1 + 0.2 * ext
			pose["hip"] = Vector2(12.0 * ext, 3.0)
			pose["foot_f"] = Vector2(38.0 + 22.0 * ext, 0.0)
		FightSim.Punch.HOOK:
			var back := Vector2(-40, -176)
			var target := Vector2(138, -204)
			var from := GUARD_REAR.lerp(back, wind)
			if st == FightSim.St.WINDUP:
				pose["rear"] = from
			else:
				# Dirsek yay çizsin diye hedefe yukarıdan yaklaşır.
				var mid := Vector2(60, -226)
				pose["rear"] = GUARD_REAR.lerp(mid, minf(ext * 2.0, 1.0)).lerp(target, maxf(ext * 2.0 - 1.0, 0.0))
			pose["lean"] = 0.1 - 0.2 * wind + 0.36 * ext
			pose["hip"] = Vector2(-8.0 * wind + 16.0 * ext, 6.0 * wind)
		FightSim.Punch.UPPER:
			var low := Vector2(16, -92)
			var target := Vector2(112, -252)
			var from := GUARD_REAR.lerp(low, wind)
			pose["rear"] = from if st == FightSim.St.WINDUP else low.lerp(target, ext)
			pose["lean"] = 0.1 + 0.24 * wind - 0.22 * ext
			pose["hip"] = Vector2(10.0 * ext, 24.0 * wind - 10.0 * ext)


static func _ik(a: Vector2, target: Vector2, l1: float, l2: float, bend: float) -> Array:
	var delta := target - a
	var dist := clampf(delta.length(), absf(l1 - l2) + 0.5, l1 + l2 - 0.5)
	var dir := delta.normalized() if delta.length() > 0.01 else Vector2.RIGHT
	var along := (dist * dist + l1 * l1 - l2 * l2) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var end := a + dir * dist
	var mid := a + dir * along + dir.orthogonal() * h * bend
	return [mid, end]


static func _limb(c: CanvasItem, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	c.draw_line(a, b, OUTLINE, width + 6.0)
	c.draw_circle(a, width * 0.5 + 3.0, OUTLINE)
	c.draw_circle(b, width * 0.5 + 3.0, OUTLINE)
	c.draw_line(a, b, col, width)
	c.draw_circle(a, width * 0.5, col)
	c.draw_circle(b, width * 0.5, col)


static func _arm(c: CanvasItem, shoulder: Vector2, hand: Vector2, pal: Dictionary, skin: Color) -> void:
	var ik := _ik(shoulder, hand, UPPER_ARM, FORE_ARM, -1.0)
	var elbow: Vector2 = ik[0]
	var wrist: Vector2 = ik[1]
	_limb(c, shoulder, elbow, 21.0, skin)
	_limb(c, elbow, wrist, 18.0, skin)
	var forward := (wrist - elbow).normalized()
	var glove := wrist + forward * 12.0
	c.draw_line(wrist - forward * 7.0, wrist + forward * 2.0, OUTLINE, 27.0)
	c.draw_line(wrist - forward * 5.0, wrist, pal["trim"], 21.0)
	c.draw_circle(glove, 26.0, OUTLINE)
	c.draw_circle(glove, 23.0, pal["glove"])
	c.draw_circle(glove + forward.orthogonal() * -9.0 + forward * 5.0, 8.0, pal["glove_hi"])
	c.draw_circle(glove + forward.orthogonal() * 13.0 - forward * 3.0, 9.0, pal["glove"].darkened(0.2))


static func _leg(c: CanvasItem, hip: Vector2, foot: Vector2, pal: Dictionary, skin: Color) -> void:
	var ik := _ik(hip, foot + Vector2(0, -12), THIGH, SHIN, 1.0)
	var knee: Vector2 = ik[0]
	var ankle: Vector2 = ik[1]
	_limb(c, hip, knee, 27.0, skin)
	_limb(c, knee, ankle, 21.0, skin)
	_limb(c, ankle + Vector2(-5, 3), ankle + Vector2(19, 8), 19.0, pal["boot"])
	c.draw_line(ankle + Vector2(-13, -14), ankle + Vector2(13, -14), OUTLINE, 5.0)


static func draw_boxer(c: CanvasItem, pos: Vector2, facing: float, pose: Dictionary, pal: Dictionary, flash: float, hp: float) -> void:
	var rot: float = pose["rot"]
	var at := pos - Vector2(0, float(pose["lift"]))
	c.draw_set_transform_matrix(Transform2D(rot * facing, Vector2(facing, 1.0), 0.0, at))
	var skin: Color = pal["skin"]
	var skin_dark: Color = pal["skin_dark"]
	if flash > 0.0:
		skin = skin.lerp(Color(1, 0.35, 0.3), flash * 0.75)
		skin_dark = skin_dark.lerp(Color(1, 0.3, 0.25), flash * 0.75)
	var lean: float = pose["lean"]
	var hip: Vector2 = Vector2(0, -98) + pose["hip"]
	var spine := Vector2(sin(lean), -cos(lean))
	var chest := hip + spine * 74.0
	var neck := chest + spine * 8.0
	var head_at: Vector2 = neck + spine * 30.0 + pose["head"] + Vector2(4, 0)
	var side := spine.orthogonal()

	_leg(c, hip + Vector2(-8, 0), pose["foot_b"], pal, skin_dark)
	_arm(c, chest + Vector2(14, 6), pose["lead"], pal, skin_dark)
	_leg(c, hip + Vector2(8, 0), pose["foot_f"], pal, skin)

	var torso := PackedVector2Array([
		chest + side * 32.0 + spine * 10.0, chest - side * 32.0 + spine * 10.0,
		hip - side * 25.0, hip + side * 25.0,
	])
	var torso_out := PackedVector2Array()
	var center := (chest + hip) * 0.5
	for p in torso:
		torso_out.append(center + (p - center) * 1.09)
	c.draw_colored_polygon(torso_out, OUTLINE)
	c.draw_colored_polygon(torso, skin)
	c.draw_circle(chest - side * 12.0, 15.0, skin.lightened(0.09))
	c.draw_line(chest - spine * 28.0 + side * 2.0, hip + spine * 26.0 + side * 2.0, skin_dark, 2.5)

	var low := hip - spine * 30.0
	var trunks := PackedVector2Array([
		hip + spine * 13.0 + side * 28.0, hip + spine * 13.0 - side * 28.0,
		low - side * 34.0, low + side * 34.0,
	])
	var trunks_out := PackedVector2Array()
	var tc := hip - spine * 8.0
	for p in trunks:
		trunks_out.append(tc + (p - tc) * 1.1)
	c.draw_colored_polygon(trunks_out, OUTLINE)
	c.draw_colored_polygon(trunks, pal["trunks"])
	c.draw_line(hip + spine * 11.0 + side * 28.0, hip + spine * 11.0 - side * 28.0, pal["trim"], 9.0)

	c.draw_line(neck - spine * 4.0, head_at, OUTLINE, 28.0)
	c.draw_line(neck - spine * 4.0, head_at, skin_dark, 22.0)
	c.draw_circle(head_at, 32.0, OUTLINE)
	c.draw_circle(head_at, 29.0, skin)
	c.draw_circle(head_at + Vector2(29, 3), 7.0, OUTLINE)
	c.draw_circle(head_at + Vector2(28, 3), 5.0, skin)
	c.draw_circle(head_at + Vector2(-8, 2), 7.0, OUTLINE)
	c.draw_circle(head_at + Vector2(-8, 2), 5.0, skin_dark)
	var hair := PackedVector2Array()
	for i in 15:
		var a := lerpf(PI * 0.98, PI * 1.92, i / 14.0)
		hair.append(head_at + Vector2(cos(a), sin(a)) * 31.0)
	hair.append(head_at + Vector2(12, -14))
	hair.append(head_at + Vector2(-14, -8))
	hair.append(head_at + Vector2(-26, 8))
	c.draw_colored_polygon(hair, pal["hair"])
	var eye := head_at + Vector2(15, -4)
	if hp < 30.0:
		c.draw_circle(eye, 8.5, Color(0.42, 0.18, 0.42, 0.85))
		c.draw_line(eye + Vector2(-5, 0), eye + Vector2(5, 1), OUTLINE, 2.5)
	else:
		c.draw_circle(eye, 5.0, Color(0.97, 0.97, 0.97))
		c.draw_circle(eye + Vector2(1.5, 0), 2.6, OUTLINE)
	c.draw_line(eye + Vector2(-8, -9), eye + Vector2(8, -6), OUTLINE, 4.0)
	c.draw_line(head_at + Vector2(9, 16), head_at + Vector2(23, 15), OUTLINE, 3.5)
	if hp < 60.0:
		c.draw_circle(head_at + Vector2(10, 9), 6.0, Color(0.72, 0.18, 0.22, 0.55))

	_arm(c, chest + Vector2(-8, 6), pose["rear"], pal, skin)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
