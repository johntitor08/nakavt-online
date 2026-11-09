extends Node
## Görsel kontrol: menüyü ve maçın önemli anlarını user:// altına PNG yazar.

const S := preload("res://scripts/sim.gd")


func _ready() -> void:
	var menu := Menu.new()
	add_child(menu)
	await _settle()
	await _shot("menu")
	menu.queue_free()
	await get_tree().process_frame

	var view := FightView.new()
	view.manual = true
	view.start_offline("Eren", BoxAI.Level.MEDIUM)
	add_child(view)
	var s := view.sim
	await _settle()
	await _shot("intro")

	_advance(view, S.INTRO_TICKS + 1, 0, 0)
	s.fighters[0].x = 560.0
	s.fighters[1].x = 695.0
	s.fighters[1].hp = 62.0
	s.fighters[0].stam = 68.0
	_advance(view, 1, S.IN_HOOK, 0)
	_advance(view, 13 + 2, 0, 0)
	await _settle()
	await _shot("krose")

	_advance(view, 40, 0, S.IN_GUARD)
	s.fighters[1].x = s.fighters[0].x + 115.0
	_advance(view, 1, 0, S.IN_UPPER)
	_advance(view, 20 + 1, S.IN_GUARD, 0)
	await _settle()
	await _shot("aparkat")

	_advance(view, 60, 0, 0)
	s.fighters[1].x = s.fighters[0].x + 130.0
	s.fighters[1].hp = 1.0
	_advance(view, 1, S.IN_UPPER, 0)
	_advance(view, 30, 0, 0)
	_advance(view, S.COUNT_TICKS * 4, 0, 0)
	await _settle()
	await _shot("sayim")

	_advance(view, S.COUNT_TICKS * 7, 0, 0)
	await _settle(40)
	await _shot("son")
	get_tree().quit(0)


func _advance(view: FightView, n: int, in0: int, in1: int) -> void:
	for i in n:
		view.sim.step(in0, in1)
		view.push_snapshot(view.sim.snapshot())
		for ev in view.sim.drain_events():
			view.handle_event(ev)


func _settle(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://foto_%s.png" % label
	get_viewport().get_texture().get_image().save_png(path)
	print("foto: ", ProjectSettings.globalize_path(path))
