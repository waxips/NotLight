# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotesGraphCanvas
extends Control

signal note_open_requested(note_id: String)
signal selection_changed(note_id: String)
signal relation_create_requested(source_note_id: String, target_note_id: String)
signal relation_remove_requested(source_note_id: String, target_note_id: String)

const SCOPE_GLOBAL: int = 0
const SCOPE_LOCAL: int = 1
const MIN_ZOOM: float = 0.055
const MAX_ZOOM: float = 3.4
const ZOOM_STEP: float = 1.10
const TRACKPAD_WHEEL_PAN_PIXELS: float = 46.0
const GESTURE_PAN_MULTIPLIER: float = 1.0
const CAMERA_RESPONSE: float = 10.5
const CAMERA_POSITION_EPSILON_SQUARED: float = 0.0004
const CAMERA_ZOOM_EPSILON: float = 0.0002
const CONNECTION_PICK_DISTANCE: float = 9.0
const MAX_VISIBLE_NODES: int = 6500
const MAX_VISIBLE_EDGES: int = 14000
const MAX_PICK_EDGES: int = 3200
const DOT_GRID_STEP: float = 84.0
const NODE_DRAG_THRESHOLD_PIXELS: float = 5.0
const RESET_LAYOUT_DURATION_SECONDS: float = 0.62
const MAX_RESET_ANIMATED_NODES: int = 1800
const RESET_ERUPTION_RADIUS: float = 24.0

var repository: NoteRepository
var app_settings: AppSettingsStore
var model: NotesGraphModel = NotesGraphModel.new()
var camera_position: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var _target_camera_position: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0
var selected_index: int = -1
var hovered_index: int = -1
var _panning: bool = false
var _pan_start_screen: Vector2 = Vector2.ZERO
var _pan_start_camera: Vector2 = Vector2.ZERO
var _connecting_from: int = -1
var _drag_candidate_index: int = -1
var _dragging_index: int = -1
var _drag_press_screen: Vector2 = Vector2.ZERO
var _drag_offset_world: Vector2 = Vector2.ZERO
var _layout_animation_active: bool = false
var _layout_animation_elapsed: float = 0.0
var _layout_animation_starts: PackedVector2Array = PackedVector2Array()
var _layout_animation_targets: PackedVector2Array = PackedVector2Array()
var _connection_pointer: Vector2 = Vector2.ZERO
var _positions: Dictionary = {}
var _font: Font
var _scope: int = SCOPE_GLOBAL
var _local_center_id: String = ""
var _local_hops: int = 2
var _snapshot_truncated: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_font = ThemeDB.fallback_font
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	set_process(false)


func configure(note_repository: NoteRepository, settings: AppSettingsStore = null) -> void:
	if repository != null:
		if repository.relation_index_changed.is_connected(_on_repository_changed):
			repository.relation_index_changed.disconnect(_on_repository_changed)
		if repository.notes_changed.is_connected(_on_repository_changed):
			repository.notes_changed.disconnect(_on_repository_changed)
	repository = note_repository
	app_settings = settings
	if repository != null:
		if not repository.relation_index_changed.is_connected(_on_repository_changed):
			repository.relation_index_changed.connect(_on_repository_changed)
		if not repository.notes_changed.is_connected(_on_repository_changed):
			repository.notes_changed.connect(_on_repository_changed)
	_target_camera_position = camera_position
	_target_zoom = zoom
	_rebuild(false)


func set_global_scope() -> void:
	if _scope == SCOPE_GLOBAL:
		return
	_scope = SCOPE_GLOBAL
	_local_center_id = ""
	_snapshot_truncated = false
	_rebuild(false)
	call_deferred("fit_all")


func set_local_scope(note_id: String, hops: int = 2) -> void:
	var clean_id: String = note_id.strip_edges()
	if repository == null or clean_id.is_empty() or not repository.contains(clean_id):
		return
	var safe_hops: int = clampi(hops, 1, 3)
	var changed: bool = _scope != SCOPE_LOCAL or _local_center_id != clean_id or _local_hops != safe_hops
	_scope = SCOPE_LOCAL
	_local_center_id = clean_id
	_local_hops = safe_hops
	if changed:
		_rebuild(false)
		selected_index = model.get_index(clean_id)
		call_deferred("fit_all")
	else:
		focus_note(clean_id, false)


func set_local_hops(hops: int) -> void:
	var safe_hops: int = clampi(hops, 1, 3)
	if _local_hops == safe_hops:
		return
	_local_hops = safe_hops
	if _scope == SCOPE_LOCAL and not _local_center_id.is_empty():
		_rebuild(false)
		selected_index = model.get_index(_local_center_id)
		call_deferred("fit_all")


func is_local_scope() -> bool:
	return _scope == SCOPE_LOCAL


func get_local_hops() -> int:
	return _local_hops


func get_local_center_id() -> String:
	return _local_center_id


func get_graph_summary() -> Dictionary:
	var relation_counts: Dictionary = model.relation_counts()
	return {
		"nodes": model.size(),
		"edges": model.edge_count(),
		"textual_edges": int(relation_counts.get("textual", 0)),
		"explicit_edges": int(relation_counts.get("explicit", 0)),
		"mixed_edges": int(relation_counts.get("mixed", 0)),
		"local": _scope == SCOPE_LOCAL,
		"hops": _local_hops,
		"truncated": _snapshot_truncated,
	}


func focus_note(note_id: String, emit_selection: bool = true) -> void:
	var index: int = model.get_index(note_id)
	if index < 0:
		if _scope == SCOPE_LOCAL and repository != null and repository.contains(note_id):
			set_local_scope(note_id, _local_hops)
			index = model.get_index(note_id)
		if index < 0:
			return
	selected_index = index
	_target_camera_position = model.positions[index]
	set_process(true)
	if emit_selection:
		selection_changed.emit(note_id)
	queue_redraw()


func fit_all() -> void:
	if model.size() <= 0 or size.x <= 1.0 or size.y <= 1.0:
		camera_position = Vector2.ZERO
		_target_camera_position = Vector2.ZERO
		zoom = 1.0
		_target_zoom = 1.0
		queue_redraw()
		return
	var bounds: Rect2 = model.get_node_rect(0)
	for index: int in range(1, model.size()):
		bounds = bounds.merge(model.get_node_rect(index))
	_target_camera_position = bounds.get_center()
	var available: Vector2 = Vector2(maxf(1.0, size.x - 96.0), maxf(1.0, size.y - 96.0))
	var fit_x: float = available.x / maxf(bounds.size.x, 1.0)
	var fit_y: float = available.y / maxf(bounds.size.y, 1.0)
	_target_zoom = clampf(minf(fit_x, fit_y), MIN_ZOOM, 1.45 if _scope == SCOPE_LOCAL else 1.20)
	set_process(true)



func reset_layout(animate: bool = true) -> void:
	if model.size() <= 0:
		return
	_cancel_node_drag(false)
	var target_by_id: Dictionary = model.build_reset_layout()
	if target_by_id.is_empty():
		return
	if not animate or model.size() > MAX_RESET_ANIMATED_NODES:
		model.apply_positions(target_by_id)
		_positions = model.export_positions()
		_layout_animation_active = false
		queue_redraw()
		call_deferred("fit_all")
		return
	_layout_animation_starts = PackedVector2Array()
	_layout_animation_targets = PackedVector2Array()
	for index: int in range(model.size()):
		var note_id: String = model.get_note_id(index)
		var target_value: Variant = target_by_id.get(note_id, model.positions[index])
		var target: Vector2 = model.positions[index]
		if target_value is Vector2:
			target = target_value as Vector2
		var direction: Vector2 = target.normalized() if not target.is_zero_approx() else Vector2.RIGHT.rotated(float(index) * 2.399963229728653)
		var start: Vector2 = direction * minf(RESET_ERUPTION_RADIUS, target.length() * 0.12)
		_layout_animation_starts.append(start)
		_layout_animation_targets.append(target)
		model.positions[index] = start
	model.rebuild_spatial_index()
	_layout_animation_elapsed = 0.0
	_layout_animation_active = true
	camera_position = Vector2.ZERO
	_target_camera_position = Vector2.ZERO
	set_process(true)
	queue_redraw()


func _cancel_node_drag(resolve_overlap: bool = true) -> void:
	if _dragging_index >= 0 and resolve_overlap and _dragging_index < model.size():
		var resolved: Vector2 = model.resolve_non_overlapping_position(_dragging_index, model.positions[_dragging_index])
		model.set_position(_dragging_index, resolved)
	_drag_candidate_index = -1
	_dragging_index = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		var magnify: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		var factor: float = pow(maxf(magnify.factor, 0.01), _zoom_sensitivity())
		_zoom_target_at(magnify.position, _target_zoom * factor)
		accept_event()
		return
	if event is InputEventPanGesture:
		var pan: InputEventPanGesture = event as InputEventPanGesture
		_pan_target_by_screen_delta(pan.delta * GESTURE_PAN_MULTIPLIER * _camera_sensitivity())
		accept_event()
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed and _handle_wheel(event):
		accept_event()
		return
	if (
		event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and (event.ctrl_pressed or event.meta_pressed)
	):
		var edge_index: int = _hit_edge(event.position)
		if edge_index >= 0 and edge_index < model.edge_count():
			var flags: int = int(model.edge_flags[edge_index]) if edge_index < model.edge_flags.size() else 0
			if (flags & NotesGraphModel.EDGE_EXPLICIT) != 0:
				var source: int = int(model.source_indices[edge_index])
				var target: int = int(model.target_indices[edge_index])
				relation_remove_requested.emit(model.get_note_id(source), model.get_note_id(target))
				accept_event()
				return
	var space_pan: bool = event.button_index == MOUSE_BUTTON_LEFT and Input.is_action_pressed("board_pan")
	var pointer_pan: bool = event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT or space_pan
	if pointer_pan:
		if event.pressed:
			_panning = true
			_pan_start_screen = event.position
			_pan_start_camera = _target_camera_position
		else:
			_panning = false
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			var world: Vector2 = screen_to_graph(event.position)
			var hit: int = model.hit_test(world)
			if event.shift_pressed and hit >= 0:
				_cancel_node_drag(false)
				_connecting_from = hit
				_connection_pointer = world
				queue_redraw()
				accept_event()
				return
			if hit >= 0:
				selected_index = hit
				selection_changed.emit(model.get_note_id(hit))
				_drag_candidate_index = hit
				_dragging_index = -1
				_drag_press_screen = event.position
				_drag_offset_world = model.positions[hit] - world
				if event.double_click:
					_cancel_node_drag(false)
					note_open_requested.emit(model.get_note_id(hit))
			else:
				_cancel_node_drag(false)
				selected_index = -1
				selection_changed.emit("")
			queue_redraw()
		else:
			if _connecting_from >= 0:
				var target: int = model.hit_test(screen_to_graph(event.position))
				if target >= 0 and target != _connecting_from:
					relation_create_requested.emit(model.get_note_id(_connecting_from), model.get_note_id(target))
				_connecting_from = -1
			elif _dragging_index >= 0:
				var resolved: Vector2 = model.resolve_non_overlapping_position(_dragging_index, model.positions[_dragging_index])
				model.set_position(_dragging_index, resolved)
				_positions = model.export_positions()
			_cancel_node_drag(false)
			queue_redraw()
		accept_event()
		return
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var world: Vector2 = screen_to_graph(event.position)
	if _panning:
		var pointer_delta: Vector2 = (event.position - _pan_start_screen) * _camera_sensitivity()
		_target_camera_position = _pan_start_camera - pointer_delta / maxf(_target_zoom, 0.001)
		set_process(true)
		accept_event()
		return
	if _connecting_from >= 0:
		_connection_pointer = world
		queue_redraw()
		accept_event()
		return
	if _drag_candidate_index >= 0:
		if _dragging_index < 0 and event.position.distance_to(_drag_press_screen) >= NODE_DRAG_THRESHOLD_PIXELS:
			_dragging_index = _drag_candidate_index
			mouse_default_cursor_shape = Control.CURSOR_MOVE
		if _dragging_index >= 0:
			model.set_position(_dragging_index, world + _drag_offset_world)
			hovered_index = _dragging_index
			queue_redraw()
			accept_event()
			return
	var next_hover: int = model.hit_test(world)
	if next_hover != hovered_index:
		hovered_index = next_hover
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered_index >= 0 else Control.CURSOR_ARROW
		queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_F:
		fit_all()
		accept_event()
	elif event.keycode == KEY_ENTER and selected_index >= 0:
		note_open_requested.emit(model.get_note_id(selected_index))
		accept_event()
	elif event.keycode == KEY_ESCAPE:
		_connecting_from = -1
		_cancel_node_drag(true)
		queue_redraw()
		accept_event()


func _draw() -> void:
	_draw_background()
	if model.size() <= 0:
		_draw_empty_state()
		return
	var visible_graph: Rect2 = _visible_graph_rect().grow(NotesGraphModel.NODE_CULL_MARGIN)
	var all_visible_nodes: PackedInt32Array = model.query_rect(visible_graph)
	var visible_nodes: PackedInt32Array = _bounded_indices(all_visible_nodes, MAX_VISIBLE_NODES)
	var visible_set: Dictionary = {}
	for index: int in visible_nodes:
		visible_set[index] = true
	var visible_edges: PackedInt32Array = _bounded_indices(model.query_edges_for_nodes(visible_nodes), MAX_VISIBLE_EDGES)
	_draw_edges(visible_set, visible_edges)
	for index: int in visible_nodes:
		_draw_node(index)
	if _connecting_from >= 0 and _connecting_from < model.size():
		var start: Vector2 = graph_to_screen(model.positions[_connecting_from])
		var finish: Vector2 = graph_to_screen(_connection_pointer)
		draw_dashed_line(start, finish, NotLightTheme.semantic_color("accent"), 2.0, 7.0, true, true)
	_draw_interaction_hint(all_visible_nodes.size(), visible_nodes.size())


func _draw_background() -> void:
	var background: Color = NotLightTheme.semantic_color("board_background")
	draw_rect(Rect2(Vector2.ZERO, size), background, true)
	if zoom < 0.34:
		return
	var step: float = DOT_GRID_STEP * zoom
	if step < 18.0:
		return
	var center: Vector2 = size * 0.5 - camera_position * zoom
	var start_x: float = fmod(center.x, step)
	var start_y: float = fmod(center.y, step)
	var dot_color: Color = Color(NotLightTheme.semantic_color("border"), 0.42)
	var y: float = start_y
	while y < size.y:
		var x: float = start_x
		while x < size.x:
			draw_circle(Vector2(x, y), 1.15, dot_color, true)
			x += step
		y += step


func _draw_edges(visible_set: Dictionary, edge_indices: PackedInt32Array) -> void:
	var textual_lines: PackedVector2Array = PackedVector2Array()
	var explicit_lines: PackedVector2Array = PackedVector2Array()
	var combined_lines: PackedVector2Array = PackedVector2Array()
	for edge_index: int in edge_indices:
		var source: int = int(model.source_indices[edge_index])
		var target: int = int(model.target_indices[edge_index])
		if not visible_set.has(source) and not visible_set.has(target):
			continue
		var start: Vector2 = graph_to_screen(model.positions[source])
		var finish: Vector2 = graph_to_screen(model.positions[target])
		if finish.distance_squared_to(start) < 1.0:
			continue
		var flags: int = int(model.edge_flags[edge_index]) if edge_index < model.edge_flags.size() else 0
		if (flags & NotesGraphModel.EDGE_TEXTUAL) != 0 and (flags & NotesGraphModel.EDGE_EXPLICIT) != 0:
			combined_lines.append(start)
			combined_lines.append(finish)
		elif (flags & NotesGraphModel.EDGE_EXPLICIT) != 0:
			explicit_lines.append(start)
			explicit_lines.append(finish)
		else:
			textual_lines.append(start)
			textual_lines.append(finish)
	if not textual_lines.is_empty():
		draw_multiline(textual_lines, Color(NotLightTheme.semantic_color("text_muted"), 0.31), 1.15, true)
	if not explicit_lines.is_empty():
		draw_multiline(explicit_lines, Color(NotLightTheme.semantic_color("accent"), 0.48), 1.55, true)
	if not combined_lines.is_empty():
		draw_multiline(combined_lines, Color(NotLightTheme.semantic_color("accent"), 0.72), 2.0, true)


func _draw_node(index: int) -> void:
	var center: Vector2 = graph_to_screen(model.positions[index])
	var radius: float = model.get_node_radius(index) * zoom
	if radius < 1.5:
		return
	var selected: bool = index == selected_index
	var hovered: bool = index == hovered_index
	var hop: int = model.get_hop(index)
	var accent: Color = NotLightTheme.semantic_color("accent")
	var fill: Color = NotLightTheme.semantic_color("surface")
	var border: Color = NotLightTheme.semantic_color("border_strong")
	if hop == 0:
		fill = accent
		border = accent
	elif hop == 1:
		fill = NotLightTheme.semantic_color("accent_soft")
		border = Color(accent, 0.74)
	elif hop == 2:
		fill = NotLightTheme.semantic_color("surface")
		border = Color(accent, 0.45)
	elif hop == 3:
		fill = NotLightTheme.semantic_color("surface_alt")
		border = NotLightTheme.semantic_color("border_strong")
	if hovered and hop != 0:
		fill = NotLightTheme.semantic_color("accent_soft")
	if selected:
		draw_circle(center, radius + 6.0, Color(accent, 0.16), true)
		draw_circle(center, radius + 2.0, accent, false, 2.2, true)
	draw_circle(center, radius, fill, true)
	draw_circle(center, radius, border, false, 1.4 if not selected else 2.0, true)
	var center_dot: Color = NotLightTheme.semantic_color("text_on_accent") if hop == 0 else accent
	draw_circle(center, maxf(2.0, radius * 0.14), Color(center_dot, 0.88), true)
	if not _should_draw_label(index):
		return
	var title: String = model.get_title(index)
	var font_size: int = clampi(int(round(13.0 * clampf(zoom, 0.85, 1.35))), 11, 16)
	var label_width: float = 210.0
	var baseline: Vector2 = center + Vector2(radius + 8.0, float(font_size) * 0.35)
	var outline: Color = Color(NotLightTheme.semantic_color("board_background"), 0.94)
	draw_string_outline(_font, baseline, title, HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, 4, outline)
	draw_string(_font, baseline, title, HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size, NotLightTheme.semantic_color("text"))


func _should_draw_label(index: int) -> bool:
	if index == selected_index or index == hovered_index or model.get_hop(index) == 0:
		return true
	if _scope == SCOPE_LOCAL:
		return zoom >= 0.48 or model.get_hop(index) <= 1
	return zoom >= 0.78


func _draw_interaction_hint(total_visible: int, drawn_visible: int) -> void:
	if size.x < 520.0 or size.y < 180.0:
		return
	var hint: String = NotLightL10n.text("notes.graph.hint")
	if total_visible > drawn_visible:
		hint = NotLightL10n.text("ui.format.two_parts_spaced") % [hint, NotLightL10n.text("notes.graph.lod", {"visible": drawn_visible, "total": total_visible})]
	draw_string(_font, Vector2(18.0, size.y - 18.0), hint, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, size.x - 36.0), 12, Color(NotLightTheme.semantic_color("text_muted"), 0.86))


func _draw_empty_state() -> void:
	var title: String = NotLightL10n.text("notes.graph.empty_title")
	var body: String = NotLightL10n.text("notes.graph.empty_body")
	var center: Vector2 = size * 0.5
	draw_circle(center + Vector2(0.0, -54.0), 18.0, NotLightTheme.semantic_color("accent_soft"), true)
	draw_circle(center + Vector2(0.0, -54.0), 18.0, NotLightTheme.semantic_color("accent"), false, 1.5, true)
	draw_string(_font, center + Vector2(-150.0, -8.0), title, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 18, NotLightTheme.semantic_color("text"))
	draw_string(_font, center + Vector2(-210.0, 22.0), body, HORIZONTAL_ALIGNMENT_CENTER, 420.0, 13, NotLightTheme.semantic_color("text_muted"))


func graph_to_screen(point: Vector2) -> Vector2:
	return (point - camera_position) * zoom + size * 0.5


func screen_to_graph(point: Vector2) -> Vector2:
	return camera_position + (point - size * 0.5) / maxf(zoom, 0.001)


func _visible_graph_rect() -> Rect2:
	return Rect2(screen_to_graph(Vector2.ZERO), size / maxf(zoom, 0.001))


func _process(delta: float) -> void:
	var layout_changed: bool = false
	if _layout_animation_active:
		_layout_animation_elapsed += maxf(0.0, delta)
		var t: float = clampf(_layout_animation_elapsed / RESET_LAYOUT_DURATION_SECONDS, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - t, 3.0)
		var count: int = mini(model.size(), mini(_layout_animation_starts.size(), _layout_animation_targets.size()))
		for index: int in range(count):
			model.positions[index] = _layout_animation_starts[index].lerp(_layout_animation_targets[index], eased)
		model.rebuild_spatial_index()
		layout_changed = true
		if t >= 1.0:
			_layout_animation_active = false
			_positions = model.export_positions()
			call_deferred("fit_all")
	var response: float = 1.0 - exp(-_camera_response() * delta)
	var previous_camera: Vector2 = camera_position
	var previous_zoom: float = zoom
	camera_position = camera_position.lerp(_target_camera_position, response)
	var safe_zoom: float = maxf(zoom, MIN_ZOOM)
	var safe_target_zoom: float = maxf(_target_zoom, MIN_ZOOM)
	zoom = exp(lerpf(log(safe_zoom), log(safe_target_zoom), response))
	var settled_camera: bool = camera_position.distance_squared_to(_target_camera_position) <= CAMERA_POSITION_EPSILON_SQUARED
	var settled_zoom: bool = absf(zoom - _target_zoom) <= CAMERA_ZOOM_EPSILON
	if settled_camera:
		camera_position = _target_camera_position
	if settled_zoom:
		zoom = _target_zoom
	if layout_changed or not camera_position.is_equal_approx(previous_camera) or not is_equal_approx(zoom, previous_zoom):
		queue_redraw()
	if settled_camera and settled_zoom and not _layout_animation_active:
		set_process(false)


func _handle_wheel(event: InputEventMouseButton) -> bool:
	var is_vertical: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	var is_horizontal: bool = event.button_index == MOUSE_BUTTON_WHEEL_LEFT or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT
	if not is_vertical and not is_horizontal:
		return false
	var factor: float = absf(event.factor)
	if factor <= 0.0001:
		factor = 1.0
	var mode: int = int(app_settings.input_mode) if app_settings != null else int(AppSettingsStore.InputMode.TRACKPAD)
	var modifier_zoom: bool = event.ctrl_pressed or event.meta_pressed
	if mode == int(AppSettingsStore.InputMode.MOUSE) or modifier_zoom:
		if not is_vertical:
			return false
		var direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		_zoom_target_at(event.position, _target_zoom * pow(ZOOM_STEP, direction * factor * _zoom_sensitivity()))
		return true
	var delta: Vector2 = Vector2.ZERO
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			delta.y = TRACKPAD_WHEEL_PAN_PIXELS * factor
		MOUSE_BUTTON_WHEEL_DOWN:
			delta.y = -TRACKPAD_WHEEL_PAN_PIXELS * factor
		MOUSE_BUTTON_WHEEL_LEFT:
			delta.x = TRACKPAD_WHEEL_PAN_PIXELS * factor
		MOUSE_BUTTON_WHEEL_RIGHT:
			delta.x = -TRACKPAD_WHEEL_PAN_PIXELS * factor
	_pan_target_by_screen_delta(delta * _camera_sensitivity())
	return true


func _camera_response() -> float:
	if app_settings == null:
		return CAMERA_RESPONSE
	return clampf(float(app_settings.camera_speed), 3.0, 30.0)


func _camera_sensitivity() -> float:
	if app_settings == null:
		return 1.0
	return clampf(float(app_settings.camera_sensitivity), 0.25, 3.0)


func _zoom_sensitivity() -> float:
	if app_settings == null:
		return 1.0
	return clampf(float(app_settings.zoom_sensitivity), 0.25, 3.0)


func _pan_target_by_screen_delta(screen_delta: Vector2) -> void:
	if screen_delta.is_zero_approx():
		return
	_target_camera_position -= screen_delta / maxf(_target_zoom, 0.001)
	set_process(true)


func _zoom_target_at(screen_point: Vector2, requested_zoom: float) -> void:
	var safe_current: float = maxf(_target_zoom, MIN_ZOOM)
	var before: Vector2 = _target_camera_position + (screen_point - size * 0.5) / safe_current
	_target_zoom = clampf(requested_zoom, MIN_ZOOM, MAX_ZOOM)
	var after: Vector2 = _target_camera_position + (screen_point - size * 0.5) / maxf(_target_zoom, MIN_ZOOM)
	_target_camera_position += before - after
	set_process(true)


func _hit_edge(screen_point: Vector2) -> int:
	var visible_nodes: PackedInt32Array = model.query_rect(_visible_graph_rect().grow(NotesGraphModel.NODE_CULL_MARGIN))
	var candidates: PackedInt32Array = _bounded_indices(model.query_edges_for_nodes(visible_nodes), MAX_PICK_EDGES)
	for candidate_offset: int in range(candidates.size() - 1, -1, -1):
		var edge_index: int = int(candidates[candidate_offset])
		var source: int = int(model.source_indices[edge_index])
		var target: int = int(model.target_indices[edge_index])
		var start: Vector2 = graph_to_screen(model.positions[source])
		var finish: Vector2 = graph_to_screen(model.positions[target])
		if _distance_to_segment(screen_point, start, finish) <= CONNECTION_PICK_DISTANCE:
			return edge_index
	return -1


func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta: Vector2 = b - a
	var length_squared: float = delta.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(a + delta * t)


func _bounded_indices(source: PackedInt32Array, maximum_count: int) -> PackedInt32Array:
	if source.size() <= maximum_count:
		return source
	var result: PackedInt32Array = PackedInt32Array()
	var stride: float = float(source.size()) / float(maximum_count)
	for index: int in range(maximum_count):
		var source_index: int = mini(source.size() - 1, int(floor(float(index) * stride)))
		result.append(int(source[source_index]))
	return result


func _on_locale_changed(_locale: String) -> void:
	queue_redraw()


func _on_repository_changed() -> void:
	if _scope == SCOPE_LOCAL and (repository == null or not repository.contains(_local_center_id)):
		_scope = SCOPE_GLOBAL
		_local_center_id = ""
	_rebuild(true)


func _rebuild(preserve_positions: bool = true) -> void:
	_cancel_node_drag(false)
	_layout_animation_active = false
	_positions = model.export_positions() if preserve_positions else {}
	var selected_id: String = model.get_note_id(selected_index)
	var snapshot: Dictionary = {}
	if repository != null:
		if _scope == SCOPE_LOCAL and not _local_center_id.is_empty():
			snapshot = repository.local_relation_snapshot(_local_center_id, _local_hops)
		else:
			snapshot = repository.relation_snapshot()
	_snapshot_truncated = bool(snapshot.get("truncated", false))
	model.rebuild(snapshot, _positions)
	if _scope == SCOPE_LOCAL and not _local_center_id.is_empty():
		selected_index = model.get_index(_local_center_id)
	elif not selected_id.is_empty():
		selected_index = model.get_index(selected_id)
	else:
		selected_index = -1
	hovered_index = -1
	queue_redraw()
