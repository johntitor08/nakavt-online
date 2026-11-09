extends RefCounted
## Dövüş kurallarının çevrimdışı testleri.

const S := preload("res://scripts/sim.gd")
var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("OK   ", label)
	else:
		_fails += 1
		print("HATA ", label)


func _fight_ready(gap: float = 140.0) -> FightSim:
	var s := FightSim.new()
	for i in S.INTRO_TICKS + 1:
		s.step(0, 0)
	s.fighters[0].x = 640.0 - gap * 0.5
	s.fighters[1].x = 640.0 + gap * 0.5
	s.drain_events()
	return s


func _press(s: FightSim, in0: int, in1: int, hold0: int = 0, hold1: int = 0) -> void:
	s.step(in0 | hold0, in1 | hold1)


func _run_ticks(s: FightSim, n: int, hold0: int = 0, hold1: int = 0) -> void:
	for i in n:
		s.step(hold0, hold1)


func run() -> int:
	_test_intro()
	_test_jab()
	_test_out_of_range()
	_test_guard()
	_test_upper_breaks_guard()
	_test_dodge_counter()
	_test_trade()
	_test_stamina()
	_test_knockdown_count()
	_test_getup()
	_test_tko()
	_test_round_flow()
	_test_forfeit()
	_test_snapshot()
	_test_keyboard()
	_test_ai_matches()
	print("SONUÇ: %s" % ("hepsi geçti" if _fails == 0 else "%d hata" % _fails))
	return 0 if _fails == 0 else 1


func _test_intro() -> void:
	var s := FightSim.new()
	_check(s.phase == S.Phase.INTRO, "maç tanıtımla başlar")
	s.step(S.IN_JAB, 0)
	_run_ticks(s, 20)
	_check(s.fighters[0].st == S.St.IDLE, "tanıtımda yumruk atılmaz")
	_run_ticks(s, S.INTRO_TICKS)
	_check(s.phase == S.Phase.FIGHT, "tanıtımdan sonra dövüş başlar")


func _test_jab() -> void:
	var s := _fight_ready()
	_press(s, S.IN_JAB, 0)
	_check(s.fighters[0].st == S.St.WINDUP, "düz yumruk hazırlığa girer")
	_run_ticks(s, 12)
	_check(s.fighters[1].hp == 95.0, "düz 5 hasar vurur (hp=%s)" % s.fighters[1].hp)
	_check(s.fighters[0].score == 5.0, "isabet puan yazar")
	var hits := s.drain_events().filter(func(e): return e["e"] == S.Ev.HIT)
	_check(hits.size() == 1, "bir yumruk bir kez isabet eder")


func _test_out_of_range() -> void:
	var s := _fight_ready(400.0)
	_press(s, S.IN_HOOK, 0)
	_run_ticks(s, 60)
	_check(s.fighters[1].hp == 100.0, "menzil dışı yumruk boşa gider")


func _test_guard() -> void:
	var s := _fight_ready()
	_run_ticks(s, 2, 0, S.IN_GUARD)
	_press(s, S.IN_HOOK, 0, 0, S.IN_GUARD)
	_run_ticks(s, 20, 0, S.IN_GUARD)
	var f := s.fighters[1]
	_check(is_equal_approx(f.hp, 100.0 - 13.0 * 0.15), "gard hasarı %%85 keser (hp=%s)" % f.hp)
	_check(f.stam < 100.0, "gard dayanıklılık yer")
	_check(s.fighters[0].score == 0.0, "gardlı yumruk puan yazmaz")


func _test_upper_breaks_guard() -> void:
	var s := _fight_ready(110.0)
	_run_ticks(s, 2, 0, S.IN_GUARD)
	_press(s, S.IN_UPPER, 0, 0, S.IN_GUARD)
	var broken := false
	for i in 30:
		s.step(0, S.IN_GUARD)
		for e in s.drain_events():
			if e["e"] == S.Ev.GUARD_BROKEN:
				broken = true
	_check(broken, "aparkat gardı kırar")


func _test_dodge_counter() -> void:
	var s := _fight_ready(120.0)
	_press(s, S.IN_HOOK, 0)
	_run_ticks(s, 9)
	_press(s, 0, S.IN_DODGE)
	_run_ticks(s, 10)
	_check(s.fighters[1].hp == 100.0, "sıyrılma yumruğu boşa çıkarır (hp=%s)" % s.fighters[1].hp)
	_check(s.fighters[1].counter_t > 0, "sıyrılma kontra penceresi açar")
	_run_ticks(s, 30)
	s.fighters[1].x = s.fighters[0].x + 130.0
	s.fighters[1].counter_t = S.COUNTER_WINDOW
	s.drain_events()
	_press(s, 0, S.IN_JAB)
	_run_ticks(s, 10)
	var f := s.fighters[0]
	_check(is_equal_approx(f.hp, 100.0 - 7.5), "kontra 1,5 kat vurur (hp=%s)" % f.hp)


func _test_trade() -> void:
	var s := _fight_ready(130.0)
	_press(s, S.IN_JAB, S.IN_JAB)
	_run_ticks(s, 12)
	_check(s.fighters[0].hp < 100.0 and s.fighters[1].hp < 100.0, "aynı anda gelen yumruklar ikisine de işler")
	var s2 := _fight_ready(130.0)
	s2.tick += 1
	_press(s2, S.IN_JAB, S.IN_JAB)
	_run_ticks(s2, 12)
	_check(s2.fighters[0].hp == s.fighters[0].hp, "karşılıklı vuruş sıradan etkilenmez")


func _test_stamina() -> void:
	var s := _fight_ready(400.0)
	s.fighters[0].stam = 3.0
	_press(s, S.IN_JAB, 0)
	_check(s.fighters[0].st == S.St.IDLE, "dayanıklılık yetmezse yumruk çıkmaz")


func _down(s: FightSim, side: int) -> void:
	s.fighters[side].hp = 1.0
	s.fighters[1 - side].x = s.fighters[side].x + (-130.0 if side == 1 else 130.0)
	var a0 := S.IN_JAB if side == 1 else 0
	var a1 := S.IN_JAB if side == 0 else 0
	s.step(a0, a1)
	_run_ticks(s, 12)


func _test_knockdown_count() -> void:
	var s := _fight_ready()
	_down(s, 1)
	_check(s.phase == S.Phase.COUNT and s.fighters[1].st == S.St.DOWN, "can bitince sayım başlar")
	_run_ticks(s, S.COUNT_TICKS * 11)
	_check(s.phase == S.Phase.OVER and s.result == S.Res.KO and s.winner == 0, "10'a kadar kalkamayan nakavt olur")


func _mash(s: FightSim, side: int, times: int) -> void:
	for i in times:
		s.step(S.IN_JAB if side == 0 else 0, S.IN_JAB if side == 1 else 0)
		s.step(0, 0)


func _test_getup() -> void:
	var s := _fight_ready()
	_down(s, 1)
	_mash(s, 1, 5)
	_check(s.phase == S.Phase.COUNT, "az basınca kalkamaz")
	_mash(s, 1, 80)
	_check(s.phase == S.Phase.RESUME or s.phase == S.Phase.FIGHT, "yeterli basışla kalkar (faz=%d)" % s.phase)
	_check(s.fighters[1].hp == 50.0, "ilk kalkışta 50 can (hp=%s)" % s.fighters[1].hp)


func _test_tko() -> void:
	var s := _fight_ready()
	for i in 3:
		if s.phase == S.Phase.RESUME:
			_run_ticks(s, S.RESUME_TICKS + 1)
		_down(s, 1)
		if i < 2:
			_mash(s, 1, 90)
	_check(s.phase == S.Phase.OVER and s.result == S.Res.TKO and s.winner == 0, "bir rauntta 3 düşüş teknik nakavttır (sonuç=%d)" % s.result)


func _test_round_flow() -> void:
	var s := _fight_ready()
	s.fighters[0].score = 30.0
	s.fighters[1].hp = 40.0
	s.clock = 2
	_run_ticks(s, 3)
	_check(s.phase == S.Phase.REST, "süre bitince mola gelir")
	_run_ticks(s, S.REST_TICKS)
	_check(s.round_no == 2 and s.phase == S.Phase.INTRO, "moladan sonra yeni raunt")
	_check(is_equal_approx(s.fighters[1].hp, 65.0), "molada can toparlanır (hp=%s)" % s.fighters[1].hp)
	_run_ticks(s, S.INTRO_TICKS + 1)
	s.clock = 1
	_run_ticks(s, 2)
	_run_ticks(s, S.REST_TICKS + S.INTRO_TICKS + 1)
	s.clock = 1
	_run_ticks(s, 2)
	_check(s.phase == S.Phase.OVER and s.result == S.Res.DECISION and s.winner == 0, "son raunttan sonra puan kararı")


func _test_forfeit() -> void:
	var s := _fight_ready()
	s.forfeit(0)
	_check(s.phase == S.Phase.OVER and s.winner == 1 and s.result == S.Res.FORFEIT, "bırakan hükmen yenilir")


func _test_snapshot() -> void:
	var s := _fight_ready()
	s.fighters[0].x = 333.25
	s.fighters[1].hp = 72.5
	s.fighters[1].stam = 11.5
	var bytes := s.snapshot()
	_check(bytes.size() == S.SNAP_SIZE, "paket boyutu %d bayt" % bytes.size())
	var d := FightSim.decode(bytes)
	_check(float(d["f"][0]["x"]) == 333.25 and float(d["f"][1]["hp"]) == 72.5, "paket doğru çözülür")
	_check(FightSim.decode(PackedByteArray([1, 2, 3])).is_empty(), "bozuk paket reddedilir")


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _test_keyboard() -> void:
	var v := FightView.new()
	_key(KEY_J, true)
	_key(KEY_D, true)
	var mask := v._read_input()
	_check((mask & S.IN_JAB) != 0 and (mask & S.IN_RIGHT) != 0, "J ve D tuşları girişe yansır")
	_key(KEY_J, false)
	_key(KEY_D, false)
	var latched := v._read_input()
	_check((latched & S.IN_JAB) != 0 and (latched & S.IN_RIGHT) == 0, "kısa basış birkaç kare korunur")
	for i in FightView.MIN_LATCH_TICKS:
		latched = v._read_input()
	_check(latched == 0, "tuş bırakılınca giriş sıfırlanır")
	v.free()


func _test_ai_matches() -> void:
	var results := {}
	var longest := 0
	var total_hits := 0
	for level in 3:
		for match_no in 10:
			var s := FightSim.new()
			var a := BoxAI.new(0, level, 100 + match_no)
			var b := BoxAI.new(1, level, 900 + match_no)
			var guard := 0
			while s.phase != S.Phase.OVER and guard < 60 * 60 * 10:
				s.step(a.think(s), b.think(s))
				guard += 1
				for e in s.drain_events():
					if e["e"] == S.Ev.HIT:
						total_hits += 1
			longest = maxi(longest, guard)
			results[s.result] = int(results.get(s.result, 0)) + 1
			if s.phase != S.Phase.OVER:
				_check(false, "yapay zekâ maçı bitmedi")
	print("[yz] 30 maç sonuçları (KO=1, TKO=2, karar=3, berabere=4): ", results, "  isabet: ", total_hits, "  en uzun: ", longest / 60, " sn")
	_check(total_hits > 300, "yapay zekâlar birbirine vurabiliyor")
	# Zor seviye kolayı yenmeli; yoksa zorluk ayarı anlamsızdır.
	var hard_wins := 0
	for match_no in 20:
		var s := FightSim.new()
		var a := BoxAI.new(0, BoxAI.Level.HARD, 300 + match_no)
		var b := BoxAI.new(1, BoxAI.Level.EASY, 700 + match_no)
		while s.phase != S.Phase.OVER:
			s.step(a.think(s), b.think(s))
		if s.winner == 0:
			hard_wins += 1
	_check(hard_wins >= 16, "zor yapay zekâ kolayı yener (%d/20)" % hard_wins)
