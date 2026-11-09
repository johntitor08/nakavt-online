class_name Sfx
extends Node
## Sesler açılışta sentezlenir, ses dosyası gerekmez.

const RATE := 22050
const VOICES := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 91
	_streams["jab"] = _thump(0.09, 190.0, 0.65)
	_streams["hook"] = _thump(0.16, 120.0, 0.85)
	_streams["upper"] = _thump(0.24, 80.0, 1.0)
	_streams["block"] = _thump(0.07, 420.0, 0.35)
	_streams["whoosh"] = _whoosh(0.16)
	_streams["bell"] = _bell(1.3)
	_streams["tick"] = _thump(0.05, 700.0, 0.2)
	_streams["down"] = _thump(0.5, 52.0, 1.0)
	_streams["crowd"] = _crowd(1.5)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(id: String, volume_db: float = 0.0) -> void:
	if not _streams.has(id):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[id]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _thump(length: float, freq: float, noise: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * freq * (1.0 - 0.55 * k) / RATE
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.35)
		var body := sin(ph) * pow(1.0 - k, 2.0)
		var slap := low * noise * pow(1.0 - k, 5.0)
		out[i] = (body * 0.8 + slap * 1.3) * 0.8
	return _make(out)


func _whoosh(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	for i in n:
		var k := float(i) / n
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.1 + 0.25 * k)
		out[i] = low * sin(k * PI) * 0.9
	return _make(out)


func _bell(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[880.0, 1.0], [1760.0, 0.55], [2640.0, 0.3], [1187.0, 0.4]]
	var second := int(0.34 * RATE)
	for i in n:
		var v := 0.0
		for strike: int in [0, second]:
			if i < strike:
				continue
			var t := float(i - strike) / RATE
			for p: Array in partials:
				v += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t * 3.6)
		out[i] = v * 0.17
	return _make(out)


func _crowd(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var k := float(i) / n
		low = lerpf(low, _rng.randf_range(-1.0, 1.0), 0.16)
		band = lerpf(band, low, 0.08)
		out[i] = (low - band) * sin(k * PI) * 1.25
	return _make(out)
