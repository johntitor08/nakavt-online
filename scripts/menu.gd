class_name Menu
extends Control
## Ana menü: isim, sunucu, oda kodu ve eşleşme durumu.

signal play_offline(player_name: String, level: int)
signal play_online(side: int, name0: String, name1: String)

const SETTINGS_PATH := "user://ayarlar.cfg"
const DEFAULT_ADDRESS := "chords-migrate.tun.ply.gg:19264"

var _name_edit: LineEdit
var _addr_edit: LineEdit
var _code_edit: LineEdit
var _level: OptionButton
var _online_btn: Button
var _cpu_btn: Button
var _cancel_btn: Button
var _status: Label
var _time := 0.0
var _searching := false
var persist := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_settings()
	Net.connected_ok.connect(_on_connected)
	Net.connect_failed.connect(_on_error)
	Net.rejected.connect(_on_rejected)
	Net.queued.connect(_on_queued)
	Net.match_found.connect(_on_match)
	Net.disconnected.connect(_on_disconnected)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	Art.draw_arena(self, _time, Vector2.ZERO, 0.25)
	var bob := {"st": FightSim.St.IDLE, "t": 0, "dur": 1, "punch": 0, "need": 0, "meter": 0}
	Art.draw_boxer(self, Vector2(205, Art.FLOOR_Y), 1.0, Art.pose_for(bob, _time, 0.0, ""), Art.RED_CORNER, 0.0, 100.0)
	Art.draw_boxer(self, Vector2(1075, Art.FLOOR_Y), -1.0, Art.pose_for(bob, _time + 0.8, 0.0, ""), Art.BLUE_CORNER, 0.0, 100.0)
	Art.draw_ring_front(self, Vector2.ZERO)


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.05, 0.06, 0.1, 0.93)
	box_style.border_color = Color(0.98, 0.84, 0.35)
	box_style.set_border_width_all(3)
	box_style.set_corner_radius_all(10)
	box_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", box_style)
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "NAKAVT ONLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 8)
	col.add_child(title)

	_name_edit = _field(col, "İsim", "Boksör adın")
	_name_edit.max_length = Net.MAX_NAME
	_addr_edit = _field(col, "Sunucu", DEFAULT_ADDRESS)
	_code_edit = _field(col, "Oda kodu", "Boş bırakırsan rastgele rakip")
	_code_edit.max_length = Net.MAX_CODE

	_online_btn = _button(col, "ONLINE MAÇ BUL", Color(0.8, 0.14, 0.2))
	_online_btn.pressed.connect(_start_search)
	_cancel_btn = _button(col, "Aramayı iptal et", Color(0.32, 0.33, 0.42))
	_cancel_btn.pressed.connect(_cancel_search)
	_cancel_btn.visible = false

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_cpu_btn = _button(row, "Yapay zekâya karşı", Color(0.16, 0.36, 0.72))
	_cpu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cpu_btn.pressed.connect(_start_offline)
	_level = OptionButton.new()
	_level.add_item("Kolay")
	_level.add_item("Orta")
	_level.add_item("Zor")
	_level.selected = 1
	_level.custom_minimum_size = Vector2(110, 0)
	row.add_child(_level)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.98, 0.84, 0.35))
	col.add_child(_status)

	var help := Label.new()
	help.text = "A/D hareket  •  S gard  •  J düz  •  K kroşe  •  L aparkat  •  Shift sıyrıl\nAparkat gardı kırar, sıyrılınca gelen ilk yumruk 1,5 kat vurur."
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	col.add_child(help)


func _field(parent: Control, caption: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _button(parent: Control, text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)
	for state: Array in [["normal", 0.0], ["hover", 0.15], ["pressed", -0.15], ["focus", 0.0]]:
		var style := StyleBoxFlat.new()
		style.bg_color = col.lightened(state[1]) if float(state[1]) >= 0.0 else col.darkened(-float(state[1]))
		style.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state[0], style)
	parent.add_child(b)
	return b


func _player_name() -> String:
	var text := _name_edit.text.strip_edges()
	return text if not text.is_empty() else "Boksör"


func _start_offline() -> void:
	_save_settings()
	play_offline.emit(_player_name(), _level.selected)


func _start_search() -> void:
	_save_settings()
	var address := _addr_edit.text.strip_edges()
	if address.is_empty():
		address = DEFAULT_ADDRESS
	var host := address
	var port := Net.DEFAULT_PORT
	var colon := address.rfind(":")
	if colon > 0:
		host = address.left(colon)
		port = address.substr(colon + 1).to_int()
	if port <= 0 or port > 65535:
		_status.text = "Sunucu adresindeki port geçersiz."
		return
	var err := Net.connect_to(host, port, _player_name(), _code_edit.text.strip_edges())
	if err != OK:
		_status.text = "Bağlantı başlatılamadı (hata %d)." % err
		return
	_status.text = "Sunucuya bağlanılıyor…"
	_set_searching(true)


func _cancel_search() -> void:
	Net.leave()
	_status.text = ""
	_set_searching(false)


func _set_searching(on: bool) -> void:
	_searching = on
	_online_btn.visible = not on
	_cancel_btn.visible = on
	_cpu_btn.disabled = on


func _on_connected() -> void:
	_status.text = "Bağlandı, eşleşme isteniyor…"


func _on_queued() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	_status.text = "Rakip aranıyor…" if code.is_empty() else "%s odasında arkadaşın bekleniyor…" % code


func _on_error(message: String) -> void:
	_status.text = message
	_set_searching(false)


func _on_rejected(message: String) -> void:
	Net.leave()
	_on_error(message)


func _on_disconnected() -> void:
	_on_error("Sunucu bağlantısı koptu.")


func _on_match(side: int, name0: String, name1: String) -> void:
	_save_settings()
	play_online.emit(side, name0, name1)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	_name_edit.text = cfg.get_value("oyuncu", "isim", "")
	_addr_edit.text = cfg.get_value("oyuncu", "sunucu", "")
	_code_edit.text = cfg.get_value("oyuncu", "oda", "")
	_level.selected = cfg.get_value("oyuncu", "zorluk", 1)


func _save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("oyuncu", "isim", _name_edit.text)
	cfg.set_value("oyuncu", "sunucu", _addr_edit.text)
	cfg.set_value("oyuncu", "oda", _code_edit.text)
	cfg.set_value("oyuncu", "zorluk", _level.selected)
	cfg.save(SETTINGS_PATH)
