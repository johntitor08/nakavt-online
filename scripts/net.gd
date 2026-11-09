extends Node
## ENet katmanı. Sunucu yetkilidir: istemciler yalnızca tuş maskesi gönderir,
## dövüşü sunucudaki FightSim yürütür ve durumu istemcilere yayar.

signal connected_ok
signal connect_failed(message: String)
signal rejected(message: String)
signal queued
signal match_found(side: int, name0: String, name1: String)
signal snap_received(bytes: PackedByteArray)
signal event_received(ev: Dictionary)
signal disconnected

const VERSION := 2
const DualPeer := preload("res://scripts/dual_peer.gd")
const WS_PORT_OFFSET := 1
const DEFAULT_PORT := 7800
const MAX_PEERS := 256
const CHANNELS := 5
const CH_INPUT := 1
const CH_SNAP := 2
const CH_EVENT := 3
const CH_PING := 4
const HELLO_TIMEOUT_MSEC := 10000
const THROTTLE_INTERVAL_MSEC := 5000
const INPUT_HEARTBEAT_TICKS := 3
const SNAPSHOT_EVERY_TICKS := 3
const MAX_NAME := 16
const MAX_CODE := 12

class Room:
	var sim := FightSim.new()
	var peers: Array[int] = []
	var inputs: Array[int] = [0, 0]
	var over_ticks := 0

var is_server := false
var ping_ms := -1
var client_version := VERSION

var _queue: Array[Dictionary] = []
var _rooms: Array[Room] = []
var _peer_room: Dictionary = {}
var _pending: Dictionary = {}

var _hello_name := ""
var _hello_code := ""
var _ping_accum := 0.0
var _last_input := 0
var _input_age := 0


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_server(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS, CHANNELS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	# Tarayıcılar UDP kullanamaz: aynı odalara WebSocket ile (port + 1, TCP) bağlanırlar.
	var ws := WebSocketMultiplayerPeer.new()
	var ws_err := ws.create_server(port + WS_PORT_OFFSET)
	if ws_err == OK:
		var dual := DualPeer.new()
		dual.setup(peer, ws)
		multiplayer.multiplayer_peer = dual
		print("[sunucu] tarayıcılar için WebSocket: %d" % (port + WS_PORT_OFFSET))
	else:
		push_warning("WebSocket portu açılamadı (hata %d), yalnızca UDP" % ws_err)
		multiplayer.multiplayer_peer = peer
	is_server = true
	print("[sunucu] port %d dinleniyor, sürüm %d" % [port, VERSION])
	return OK


func connect_to(address: String, port: int, player_name: String, code: String) -> Error:
	leave()
	_hello_name = player_name
	_hello_code = code
	if OS.has_feature("web") or address.begins_with("ws://") or address.begins_with("wss://"):
		var ws := WebSocketMultiplayerPeer.new()
		var ws_err := ws.create_client(address)
		if ws_err != OK:
			return ws_err
		multiplayer.multiplayer_peer = ws
		return OK
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, CHANNELS)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


## Bağlantıyı kapatır; sunucu kuyruktan çıkarır, maç sürüyorsa hükmen yenik sayar.
func leave() -> void:
	ping_ms = -1
	var peer := multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Tuşlar değişince hemen, değişmese de 3 karede bir gönderilir.
## Saniyede 60 paket playit tünelinde kuyruk biriktirip gecikmeyi saniyeye çıkarıyordu.
func send_input(mask: int) -> void:
	if not is_online():
		return
	_input_age += 1
	if mask != _last_input or _input_age >= INPUT_HEARTBEAT_TICKS:
		_last_input = mask
		_input_age = 0
		_c_input.rpc_id(1, mask)


func _process(delta: float) -> void:
	if is_server or not is_online():
		return
	_ping_accum += delta
	if _ping_accum >= 1.0:
		_ping_accum = 0.0
		_c_ping.rpc_id(1, Time.get_ticks_msec())


func _physics_process(_delta: float) -> void:
	if is_server:
		_server_tick()


# --- İstemci olayları ---

func _on_connected() -> void:
	# ENet gecikme dalgalanmasında güvenilmez paketleri kısar; açılışta sıfıra düşünce
	# tuş ve durum paketlerinin neredeyse hepsi atılıyordu. Ayar iki uca da uygulanır.
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		enet.get_peer(1).throttle_configure(THROTTLE_INTERVAL_MSEC, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)
	connected_ok.emit()
	_c_hello.rpc_id(1, client_version, _hello_name, _hello_code)


func _on_connection_failed() -> void:
	leave()
	connect_failed.emit("Sunucuya bağlanılamadı.")


func _on_server_gone() -> void:
	leave()
	disconnected.emit()


# --- Sunucu olayları ---

func _on_peer_connected(id: int) -> void:
	if is_server:
		_pending[id] = Time.get_ticks_msec()


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_pending.erase(id)
	_remove_from_queue(id)
	var room: Room = _peer_room.get(id)
	if room != null:
		var side := room.peers.find(id)
		_peer_room.erase(id)
		room.peers[side] = 0
		room.sim.forfeit(side)


func _server_tick() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _pending.keys():
		if now - int(_pending[id]) > HELLO_TIMEOUT_MSEC:
			_pending.erase(id)
			multiplayer.multiplayer_peer.disconnect_peer(id)
	for room: Room in _rooms.duplicate():
		_tick_room(room)


func _tick_room(room: Room) -> void:
	room.sim.step(room.inputs[0], room.inputs[1])
	for ev in room.sim.drain_events():
		for p in room.peers:
			if p != 0:
				_s_event.rpc_id(p, ev)
	var over := room.sim.phase == FightSim.Phase.OVER
	if room.sim.tick % SNAPSHOT_EVERY_TICKS == 0 or over:
		var bytes := room.sim.snapshot()
		for p in room.peers:
			if p != 0:
				_s_snap.rpc_id(p, bytes)
	if over:
		room.over_ticks += 1
		if room.over_ticks >= 30:
			_close_room(room)


func _close_room(room: Room) -> void:
	for p in room.peers:
		_peer_room.erase(p)
	_rooms.erase(room)


func _remove_from_queue(id: int) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if int(_queue[i]["peer"]) == id:
			_queue.remove_at(i)


func _clean_text(text: String, limit: int) -> String:
	var out := ""
	for ch in text.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.left(limit)


func _match_or_queue(id: int, player_name: String, code: String) -> void:
	for i in _queue.size():
		var other: Dictionary = _queue[i]
		if str(other["code"]) == code:
			_queue.remove_at(i)
			_start_room(int(other["peer"]), str(other["name"]), id, player_name)
			return
	_queue.append({"peer": id, "name": player_name, "code": code})
	_s_queued.rpc_id(id)


func _start_room(p0: int, n0: String, p1: int, n1: String) -> void:
	var room := Room.new()
	room.peers = [p0, p1]
	_rooms.append(room)
	_peer_room[p0] = room
	_peer_room[p1] = room
	_s_match.rpc_id(p0, 0, n0, n1)
	_s_match.rpc_id(p1, 1, n0, n1)
	print("[sunucu] maç başladı: %s - %s (oda sayısı %d)" % [n0, n1, _rooms.size()])


# --- İstemciden sunucuya ---

@rpc("any_peer", "call_remote", "reliable", CH_EVENT)
func _c_hello(version: int, player_name: String, code: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id):
		return
	_pending.erase(id)
	if version != VERSION:
		_s_rejected.rpc_id(id, "Oyun sürümün sunucuyla uyuşmuyor. Lütfen güncelle.")
		return
	var clean := _clean_text(player_name, MAX_NAME)
	if clean.is_empty():
		clean = "Boksör"
	_match_or_queue(id, clean, _clean_text(code, MAX_CODE).to_upper())


@rpc("any_peer", "call_remote", "unreliable_ordered", CH_INPUT)
func _c_input(mask: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var room: Room = _peer_room.get(id)
	if room != null:
		room.inputs[room.peers.find(id)] = mask & FightSim.IN_ALL


@rpc("any_peer", "call_remote", "unreliable", CH_PING)
func _c_ping(stamp: int) -> void:
	if is_server:
		_s_pong.rpc_id(multiplayer.get_remote_sender_id(), stamp)


# --- Sunucudan istemciye ---

@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_rejected(message: String) -> void:
	rejected.emit(message)


@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_queued() -> void:
	queued.emit()


@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_match(side: int, name0: String, name1: String) -> void:
	match_found.emit(side, name0, name1)


@rpc("authority", "call_remote", "unreliable_ordered", CH_SNAP)
func _s_snap(bytes: PackedByteArray) -> void:
	snap_received.emit(bytes)


@rpc("authority", "call_remote", "reliable", CH_EVENT)
func _s_event(ev: Dictionary) -> void:
	event_received.emit(ev)


@rpc("authority", "call_remote", "unreliable", CH_PING)
func _s_pong(stamp: int) -> void:
	ping_ms = Time.get_ticks_msec() - stamp
