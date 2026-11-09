extends Node
## Giriş noktası: menü ile maç ekranı arasında geçiş yapar, sunucu ve test
## kiplerini komut satırından başlatır.

var _current: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--sunucu" in args:
		_run_server(args)
	elif "--test-sim" in args:
		var test: Object = _load_tool("res://tests/test_sim.gd")
		if test != null:
			get_tree().quit(test.run())
	elif "--test-bot" in args:
		var bot: Object = _load_tool("res://tests/net_bot.gd")
		if bot != null:
			add_child(bot)
	elif "--foto" in args:
		var foto: Object = _load_tool("res://tests/foto.gd")
		if foto != null:
			add_child(foto)
	else:
		show_menu()


## Test betiği derlenemezse Godot açık kalıp testi sonsuza dek bekletmesin.
func _load_tool(path: String) -> Object:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		push_error("Betik yüklenemedi: " + path)
		get_tree().quit(1)
		return null
	return script.new()


func _run_server(args: PackedStringArray) -> void:
	var port := Net.DEFAULT_PORT
	for a in args:
		if a.begins_with("--port="):
			port = a.trim_prefix("--port=").to_int()
	var err := Net.start_server(port)
	if err != OK:
		push_error("Sunucu port %d üzerinde açılamadı (hata %d)" % [port, err])
		get_tree().quit(1)


func _swap(node: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = node
	add_child(node)


func show_menu() -> void:
	var menu := Menu.new()
	menu.play_offline.connect(_on_play_offline)
	menu.play_online.connect(_on_play_online)
	_swap(menu)


func _on_play_offline(player_name: String, level: int) -> void:
	var view := FightView.new()
	view.finished.connect(show_menu)
	view.start_offline(player_name, level)
	_swap(view)


func _on_play_online(side: int, name0: String, name1: String) -> void:
	var view := FightView.new()
	view.finished.connect(show_menu)
	view.start_online(side, name0, name1)
	_swap(view)
