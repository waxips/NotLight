# SPDX-License-Identifier: GPL-3.0-or-later
class_name AudioPlayerPool
extends Control

signal message_requested(message: String)

const DEFAULT_MAX_ACTIVE_PLAYERS: int = 12

var board_view: NativeBoardView
var media: AudioMediaService
var library: AssetLibraryService
var _players: Dictionary = {}
var _layout_state: Dictionary = {}
var max_active_players: int = DEFAULT_MAX_ACTIVE_PLAYERS
var _transform_sync_count: int = 0
var _layout_reflow_count: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = true
	z_index = 105


func _exit_tree() -> void:
	_disconnect_sources()
	if library != null and library.library_changed.is_connected(refresh_player_names):
		library.library_changed.disconnect(refresh_player_names)




func configure(
	view: NativeBoardView,
	audio_media: AudioMediaService,
	asset_library: AssetLibraryService,
	active_player_budget: int = DEFAULT_MAX_ACTIVE_PLAYERS
) -> void:
	_disconnect_sources()
	board_view = view
	media = audio_media
	max_active_players = clampi(active_player_budget, 1, 32)
	_transform_sync_count = 0
	_layout_reflow_count = 0
	if library != null and library.library_changed.is_connected(refresh_player_names):
		library.library_changed.disconnect(refresh_player_names)
	library = asset_library
	if library != null and not library.library_changed.is_connected(refresh_player_names):
		library.library_changed.connect(refresh_player_names)
	refresh_player_names()
	if board_view != null and is_instance_valid(board_view):
		if not board_view.view_transform_changed.is_connected(_on_board_view_transform_changed):
			board_view.view_transform_changed.connect(_on_board_view_transform_changed)
		if not board_view.item_rect_changed.is_connected(_on_board_view_rect_changed):
			board_view.item_rect_changed.connect(_on_board_view_rect_changed)
		if board_view._runtime != null and not board_view._runtime.runtime_changed.is_connected(_on_runtime_changed):
			board_view._runtime.runtime_changed.connect(_on_runtime_changed)


func activate(entity_id: int, asset_id: String) -> bool:
	if entity_id <= 0 or asset_id.is_empty() or board_view == null or media == null:
		return false
	if _players.has(entity_id):
		(_players[entity_id] as AudioBoardPlayer).toggle_play()
		return true
	if _players.size() >= max_active_players:
		message_requested.emit(NotLightL10n.text("audio.player.limit", {"count": max_active_players}))
		return false
	var display_name: String = _display_name(entity_id, asset_id)
	var flags: int = 0
	if board_view._runtime != null and board_view._runtime.model.audios.contains(entity_id):
		flags = board_view._runtime.model.audios.get_flags(entity_id)
	var player: AudioBoardPlayer = AudioBoardPlayer.new()
	player.name = "AudioPlayer_%d" % entity_id
	player.close_requested.connect(deactivate)
	player.flags_changed.connect(_on_player_flags_changed)
	player.message_requested.connect(func(message: String) -> void: message_requested.emit(message))
	add_child(player)
	player.configure(entity_id, asset_id, display_name, media, flags)
	_players[entity_id] = player
	_layout_state[entity_id] = {
		"layout_zoom": -1.0,
		"bounds_size": Vector2.ZERO,
	}
	_update_player_layout(entity_id, player)
	return true


func deactivate(entity_id: int) -> void:
	if not _players.has(entity_id):
		return
	var player: AudioBoardPlayer = _players[entity_id] as AudioBoardPlayer
	_players.erase(entity_id)
	_layout_state.erase(entity_id)
	if player != null and is_instance_valid(player):
		player.shutdown()


func deactivate_all() -> void:
	var ids: Array = _players.keys()
	for raw_id: Variant in ids:
		deactivate(int(raw_id))


func active_count() -> int:
	return _players.size()



func get_developer_diagnostics_snapshot() -> Dictionary:
	return {
		"audio_surface_transform_syncs": _transform_sync_count,
		"audio_surface_layout_reflows": _layout_reflow_count,
	}



func refresh_player_names() -> void:
	for raw_id: Variant in _players.keys():
		var entity_id: int = int(raw_id)
		var player: AudioBoardPlayer = _players[entity_id] as AudioBoardPlayer
		if player != null and is_instance_valid(player):
			player.set_display_name(_display_name(entity_id, player.asset_id))



func _update_player_layout(entity_id: int, player: AudioBoardPlayer) -> void:
	if player == null or not is_instance_valid(player) or board_view == null or board_view._runtime == null:
		return
	_transform_sync_count += 1
	var bounds: Rect2 = board_view._runtime.model.get_entity_bounds(entity_id)
	if not bounds.has_area():
		player.visible = false
		return
	var screen_rect: Rect2 = BoardLiveSurfaceProjection.projected_rect(board_view, bounds)
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, size).grow(80.0)
	player.visible = screen_rect.intersects(viewport_rect)
	if not player.visible:
		return

	# As with video/modules/Notes workspaces, keep the nested audio UI at a coarse
	# logical resolution and animate only its CanvasItem transform between buckets.
	var view_zoom: float = maxf(board_view.zoom, 0.01)
	var layout_zoom: float = BoardLiveSurfaceProjection.layout_zoom_for(view_zoom)
	var transform_scale: float = BoardLiveSurfaceProjection.transform_scale_for(view_zoom, layout_zoom)
	var state: Dictionary = _layout_state.get(entity_id, {}) as Dictionary
	var previous_layout_zoom: float = float(state.get("layout_zoom", -1.0))
	var previous_bounds_size: Vector2 = state.get("bounds_size", Vector2.ZERO) as Vector2
	if not is_equal_approx(previous_layout_zoom, layout_zoom) or not previous_bounds_size.is_equal_approx(bounds.size):
		_layout_reflow_count += 1
		state["layout_zoom"] = layout_zoom
		state["bounds_size"] = bounds.size
		_layout_state[entity_id] = state
		player.size = Vector2(
			maxf(1.0, bounds.size.x * layout_zoom),
			maxf(1.0, bounds.size.y * layout_zoom)
		)
		player.pivot_offset = Vector2.ZERO
	player.scale = Vector2.ONE * transform_scale
	player.position = screen_rect.position
	player.set_inline_screen_size(screen_rect.size)



func _update_all_layouts() -> void:
	for raw_id: Variant in _players.keys():
		var entity_id: int = int(raw_id)
		_update_player_layout(entity_id, _players[entity_id] as AudioBoardPlayer)


func _on_board_view_transform_changed() -> void:
	_update_all_layouts()


func _on_board_view_rect_changed() -> void:
	_update_all_layouts()


func _on_runtime_changed() -> void:
	if board_view == null or board_view._runtime == null:
		return
	var stale: PackedInt64Array = PackedInt64Array()
	for raw_id: Variant in _players.keys():
		var entity_id: int = int(raw_id)
		if not board_view._runtime.model.audios.contains(entity_id):
			stale.append(entity_id)
			continue
		_update_player_layout(entity_id, _players[entity_id] as AudioBoardPlayer)
	for entity_id: int in stale:
		deactivate(entity_id)


func _disconnect_sources() -> void:
	if board_view == null or not is_instance_valid(board_view):
		return
	if board_view.view_transform_changed.is_connected(_on_board_view_transform_changed):
		board_view.view_transform_changed.disconnect(_on_board_view_transform_changed)
	if board_view.item_rect_changed.is_connected(_on_board_view_rect_changed):
		board_view.item_rect_changed.disconnect(_on_board_view_rect_changed)
	if board_view._runtime != null and board_view._runtime.runtime_changed.is_connected(_on_runtime_changed):
		board_view._runtime.runtime_changed.disconnect(_on_runtime_changed)



func _display_name(entity_id: int, asset_id: String) -> String:
	if board_view != null and board_view._runtime != null and board_view._runtime.model.audios.contains(entity_id):
		var local_name: String = board_view._runtime.model.audios.get_instance_title(entity_id)
		if not local_name.is_empty():
			return local_name
	var asset: Dictionary = library.get_asset(asset_id) if library != null else {}
	return str(asset.get("display_name", NotLightL10n.text("board.asset.audio")))


func _on_player_flags_changed(entity_id: int, flags: int) -> void:
	if board_view == null or board_view._runtime == null or not board_view._runtime.model.audios.contains(entity_id):
		return
	board_view._runtime.model.audios.set_flags(entity_id, flags)
