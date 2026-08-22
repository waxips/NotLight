# SPDX-License-Identifier: GPL-3.0-or-later
class_name VideoPlayerPool
extends Control

signal message_requested(message: String)

const DEFAULT_MAX_ACTIVE_PLAYERS: int = 10
const EXPANDED_SAFE_LEFT: float = 96.0
const EXPANDED_SAFE_TOP: float = 86.0
const EXPANDED_SAFE_RIGHT: float = 92.0
const EXPANDED_SAFE_BOTTOM: float = 96.0

var board_view: NativeBoardView
var media: VideoMediaService
var library: AssetLibraryService
var _players: Dictionary = {} # entity_id -> VideoBoardPlayer
var _layout_state: Dictionary = {}
var _activation_order: Array[int] = []
var _expanded_entity_id: int = 0
var max_active_players: int = DEFAULT_MAX_ACTIVE_PLAYERS
var _transform_sync_count: int = 0
var _layout_reflow_count: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# World media sits above DOD renderers but below every BoardScreen UI island.
	z_as_relative = true
	z_index = 100


func _exit_tree() -> void:
	_disconnect_sources()
	if library != null and library.library_changed.is_connected(refresh_player_names):
		library.library_changed.disconnect(refresh_player_names)




func configure(
	view: NativeBoardView,
	video_media: VideoMediaService,
	asset_library: AssetLibraryService,
	active_player_budget: int = DEFAULT_MAX_ACTIVE_PLAYERS
) -> void:
	_disconnect_sources()
	board_view = view
	media = video_media
	set_active_player_budget(active_player_budget)
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
		var existing: VideoBoardPlayer = _players[entity_id] as VideoBoardPlayer
		_touch_order(entity_id)
		existing.toggle_play()
		return true
	if _players.size() >= max_active_players:
		message_requested.emit(
			NotLightL10n.text("runtime.ui.video_player_pool.89f3165138")
			% max_active_players
		)
		return false
	var record: Dictionary = library.get_asset(asset_id) if library != null else {}
	var display_name: String = str(record.get("display_name", NotLightL10n.text("board.asset.video")))
	if board_view._runtime != null and board_view._runtime.model.videos.contains(entity_id):
		var instance_title: String = board_view._runtime.model.videos.get_instance_title(entity_id)
		if not instance_title.is_empty():
			display_name = instance_title
	var player: VideoBoardPlayer = VideoBoardPlayer.new()
	player.name = "VideoPlayer_%d" % entity_id
	player.close_requested.connect(deactivate)
	player.expand_requested.connect(toggle_expanded)
	player.message_requested.connect(func(message: String) -> void: message_requested.emit(message))
	add_child(player)
	player.configure(entity_id, asset_id, display_name, media)
	_players[entity_id] = player
	_layout_state[entity_id] = {
		"layout_zoom": -1.0,
		"bounds_size": Vector2.ZERO,
	}
	_touch_order(entity_id)
	_update_player_layout(entity_id, player)
	return true


func deactivate(entity_id: int) -> void:
	if not _players.has(entity_id):
		return
	var player: VideoBoardPlayer = _players[entity_id] as VideoBoardPlayer
	_players.erase(entity_id)
	_layout_state.erase(entity_id)
	_activation_order.erase(entity_id)
	if _expanded_entity_id == entity_id:
		_expanded_entity_id = 0
	if is_instance_valid(player):
		player.shutdown()


func deactivate_all() -> void:
	var ids: Array = _players.keys()
	for raw_id: Variant in ids:
		deactivate(int(raw_id))


func toggle_expanded(entity_id: int) -> void:
	if not _players.has(entity_id):
		return
	if _expanded_entity_id == entity_id:
		_expanded_entity_id = 0
	else:
		var previous: int = _expanded_entity_id
		_expanded_entity_id = entity_id
		if previous > 0 and _players.has(previous):
			(_players[previous] as VideoBoardPlayer).set_expanded(false)
	(_players[entity_id] as VideoBoardPlayer).set_expanded(_expanded_entity_id == entity_id)
	_update_all_layouts()


func set_active_player_budget(value: int) -> void:
	max_active_players = clampi(value, AppSettingsStore.MIN_VIDEO_PLAYERS, AppSettingsStore.MAX_VIDEO_PLAYERS)
	while _players.size() > max_active_players and not _activation_order.is_empty():
		deactivate(_activation_order[0])


func _touch_order(entity_id: int) -> void:
	_activation_order.erase(entity_id)
	_activation_order.append(entity_id)


func active_count() -> int:
	return _players.size()




func get_developer_diagnostics_snapshot() -> Dictionary:
	return {
		"video_surface_transform_syncs": _transform_sync_count,
		"video_surface_layout_reflows": _layout_reflow_count,
	}



func refresh_player_names() -> void:
	if library == null:
		return
	for raw_id: Variant in _players.keys():
		var player: VideoBoardPlayer = _players[int(raw_id)] as VideoBoardPlayer
		if player == null or not is_instance_valid(player):
			continue
		var asset: Dictionary = library.get_asset(player.asset_id)
		var display_name: String = str(asset.get("display_name", NotLightL10n.text("board.asset.video")))
		if board_view != null and board_view._runtime != null and board_view._runtime.model.videos.contains(int(raw_id)):
			var instance_title: String = board_view._runtime.model.videos.get_instance_title(int(raw_id))
			if not instance_title.is_empty():
				display_name = instance_title
		player.set_display_name(display_name)


func _update_all_layouts() -> void:
	for raw_id: Variant in _players.keys():
		var entity_id: int = int(raw_id)
		_update_player_layout(entity_id, _players[entity_id] as VideoBoardPlayer)


func _update_player_layout(entity_id: int, player: VideoBoardPlayer) -> void:
	if player == null or not is_instance_valid(player) or board_view == null or board_view._runtime == null:
		return
	if entity_id == _expanded_entity_id:
		_layout_expanded_player(player)
		return

	_transform_sync_count += 1
	var bounds: Rect2 = board_view._runtime.model.get_entity_bounds(entity_id)
	if not bounds.has_area():
		player.visible = false
		return
	var screen_rect: Rect2 = BoardLiveSurfaceProjection.projected_rect(board_view, bounds)
	var in_view: bool = screen_rect.intersects(Rect2(Vector2.ZERO, size).grow(80.0))
	player.visible = in_view
	if not player.visible:
		return

	# VideoStreamPlayer and its responsive chrome must not be recursively resized on
	# every camera interpolation frame. Keep a quantized logical layout and scale
	# the CanvasItem between buckets; update responsive breakpoints from the real
	# projected screen extent only when their visibility class changes.
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


func _layout_expanded_player(player: VideoBoardPlayer) -> void:
	player.scale = Vector2.ONE
	player.pivot_offset = Vector2.ZERO
	var safe_position: Vector2 = Vector2(EXPANDED_SAFE_LEFT, EXPANDED_SAFE_TOP)
	var safe_size: Vector2 = Vector2(
		maxf(360.0, size.x - EXPANDED_SAFE_LEFT - EXPANDED_SAFE_RIGHT),
		maxf(260.0, size.y - EXPANDED_SAFE_TOP - EXPANDED_SAFE_BOTTOM)
	)
	var aspect: float = player.video_aspect_ratio()
	var fitted: Vector2 = _fit_aspect_inside(safe_size, aspect)

	# Keep the chrome usable for very narrow portrait media while the actual
	# VideoStreamPlayer remains aspect-correct inside its AspectRatioContainer.
	if fitted.x < 520.0 and safe_size.x >= 520.0:
		fitted.x = 520.0
	if fitted.y < 320.0 and safe_size.y >= 320.0:
		fitted.y = 320.0
	fitted.x = minf(fitted.x, safe_size.x)
	fitted.y = minf(fitted.y, safe_size.y)

	player.position = safe_position + (safe_size - fitted) * 0.5
	player.size = fitted
	player.visible = true



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
		if not board_view._runtime.model.videos.contains(entity_id):
			stale.append(entity_id)
			continue
		_update_player_layout(entity_id, _players[entity_id] as VideoBoardPlayer)
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



func _fit_aspect_inside(bounds: Vector2, aspect: float) -> Vector2:
	var safe_aspect: float = clampf(aspect, 0.20, 5.0)
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		return Vector2.ZERO
	var result: Vector2 = bounds
	if bounds.x / bounds.y > safe_aspect:
		result.x = bounds.y * safe_aspect
	else:
		result.y = bounds.x / safe_aspect
	return result
