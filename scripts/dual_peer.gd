extends MultiplayerPeerExtension
## Sunucu için iki taşıyıcıyı tek eşte birleştirir: masaüstü oyuncular ENet (UDP), tarayıcı oyuncuları
## WebSocket (TCP) ile bağlanır; oyunun geri kalanı tek bir MultiplayerPeer görür.
## Kimlikler çakışırsa WebSocket tarafındakine yeni bir kimlik verilir (iki yönde çevrilir).

var enet: ENetMultiplayerPeer
var ws: WebSocketMultiplayerPeer

var _queue: Array = []             # [{peer, channel, mode, data}]
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _ws_out := {}                  # dış kimlik -> ws kimliği
var _ws_in := {}                   # ws kimliği -> dış kimlik
var _enet_ids := {}                # enet kimlikleri


func setup(enet_peer: ENetMultiplayerPeer, ws_peer: WebSocketMultiplayerPeer) -> void:
	enet = enet_peer
	ws = ws_peer
	enet.peer_connected.connect(func(id): _enet_ids[id] = true; peer_connected.emit(id))
	enet.peer_disconnected.connect(func(id): _enet_ids.erase(id); peer_disconnected.emit(id))
	ws.peer_connected.connect(_on_ws_connected)
	ws.peer_disconnected.connect(_on_ws_disconnected)


func _on_ws_connected(wid: int) -> void:
	var out := wid
	while out == 1 or _enet_ids.has(out) or _ws_out.has(out):
		out = randi_range(2, 2147483647)
	_ws_out[out] = wid
	_ws_in[wid] = out
	peer_connected.emit(out)


func _on_ws_disconnected(wid: int) -> void:
	var out: int = _ws_in.get(wid, wid)
	_ws_in.erase(wid)
	_ws_out.erase(out)
	peer_disconnected.emit(out)


func is_web_peer(id: int) -> bool:
	return _ws_out.has(id)


# ------------------------------------------------------------------ MultiplayerPeerExtension

func _poll() -> void:
	enet.poll()
	ws.poll()
	while enet.get_available_packet_count() > 0:
		var pid := enet.get_packet_peer()
		var ch := enet.get_packet_channel()
		var md := enet.get_packet_mode()
		_queue.append({"peer": pid, "channel": ch, "mode": md, "data": enet.get_packet()})
	while ws.get_available_packet_count() > 0:
		var wid := ws.get_packet_peer()
		var ch2 := ws.get_packet_channel()
		var md2 := ws.get_packet_mode()
		_queue.append({"peer": _ws_in.get(wid, wid), "channel": ch2, "mode": md2, "data": ws.get_packet()})


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	return _queue.pop_front().data


func _get_packet_peer() -> int:
	return _queue[0].peer if not _queue.is_empty() else 0


func _get_packet_channel() -> int:
	return _queue[0].channel if not _queue.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _queue[0].mode if not _queue.is_empty() else TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return 1 << 20


func _put_packet_script(buf: PackedByteArray) -> Error:
	enet.transfer_mode = _mode
	enet.transfer_channel = _channel
	if _target == 0:
		enet.set_target_peer(0)
		enet.put_packet(buf)
		if not _ws_out.is_empty():
			ws.set_target_peer(0)
			ws.put_packet(buf)
		return OK
	if _target < 0:
		var ex := -_target
		if _ws_out.has(ex):
			enet.set_target_peer(0)
			enet.put_packet(buf)
			ws.set_target_peer(-int(_ws_out[ex]))
			ws.put_packet(buf)
		else:
			enet.set_target_peer(-ex)
			enet.put_packet(buf)
			if not _ws_out.is_empty():
				ws.set_target_peer(0)
				ws.put_packet(buf)
		return OK
	if _ws_out.has(_target):
		ws.set_target_peer(int(_ws_out[_target]))
		return ws.put_packet(buf)
	enet.set_target_peer(_target)
	return enet.put_packet(buf)


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_transfer_channel(ch: int) -> void:
	_channel = ch


func _get_transfer_channel() -> int:
	return _channel


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> ConnectionStatus:
	return CONNECTION_CONNECTED


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable
	enet.refuse_new_connections = enable
	ws.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(peer: int, force: bool) -> void:
	if _ws_out.has(peer):
		ws.disconnect_peer(int(_ws_out[peer]), force)
	else:
		enet.disconnect_peer(peer, force)


func _close() -> void:
	enet.close()
	ws.close()
	_queue.clear()
	_ws_out.clear()
	_ws_in.clear()
	_enet_ids.clear()
