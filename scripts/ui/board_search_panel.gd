# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardSearchPanel
extends Control

signal entity_requested(entity_id: int)
signal open_changed(is_open: bool)

const MAX_VISIBLE_RESULTS: int = 28
const PANEL_TOP: float = 78.0
const PANEL_BOTTOM: float = 306.0
const PANEL_LEFT: float = 92.0
const PANEL_RIGHT: float = 18.0
const CARD_WIDTH: float = 238.0
const CARD_HEIGHT: float = 104.0

var _panel: PanelContainer
var _toggle_button: Button
var _search_edit: LineEdit
var _title_label: Label
var _close_button: Button
var _status_label: Label
var _results_row: HFlowContainer
var _snapshot: Dictionary = {}
var _is_open: bool = false
var _animation: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 560
	_build_ui()
	resized.connect(_update_geometry)
	_update_geometry()
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func is_open() -> bool:
	return _is_open


func set_snapshot(snapshot: Dictionary) -> void:
	# BoardSearchSnapshot is freshly built and treated as immutable. A shallow
	# dictionary copy keeps ownership clear without duplicating every packed array
	# just before filtering/materializing the result cards.
	_snapshot = snapshot.duplicate(false)
	if _is_open:
		_refresh_results()


func open_panel() -> void:
	set_open(true)


func close_panel() -> void:
	set_open(false)


func toggle_panel() -> void:
	set_open(not _is_open)


func set_open(open: bool) -> void:
	if _panel == null:
		return
	if _is_open == open and _panel.visible == open:
		if open and _search_edit != null:
			_search_edit.call_deferred("grab_focus")
		return
	_is_open = open
	if _animation != null:
		_animation.kill()
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_CUBIC)
	_animation.set_ease(Tween.EASE_OUT)
	if open:
		_panel.visible = true
		_panel.modulate.a = 0.0
		_panel.offset_top = PANEL_TOP - 22.0
		_panel.offset_bottom = PANEL_BOTTOM - 22.0
		_animation.set_parallel(true)
		_animation.tween_property(_panel, "offset_top", PANEL_TOP, 0.18)
		_animation.tween_property(_panel, "offset_bottom", PANEL_BOTTOM, 0.18)
		_animation.tween_property(_panel, "modulate:a", 1.0, 0.14)
		_refresh_results()
		if _search_edit != null:
			_search_edit.call_deferred("grab_focus")
	else:
		if _search_edit != null:
			_search_edit.release_focus()
		_animation.set_parallel(true)
		_animation.tween_property(_panel, "offset_top", PANEL_TOP - 16.0, 0.14)
		_animation.tween_property(_panel, "offset_bottom", PANEL_BOTTOM - 16.0, 0.14)
		_animation.tween_property(_panel, "modulate:a", 0.0, 0.12)
		_animation.finished.connect(_finish_close_animation)
	_refresh_toggle_button()
	open_changed.emit(_is_open)


func focus_search() -> void:
	if _search_edit != null:
		_search_edit.grab_focus()


func _build_ui() -> void:
	_toggle_button = Button.new()
	_toggle_button.name = "BoardSearchTab"
	_toggle_button.theme_type_variation = "AccentButton"
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.custom_minimum_size = Vector2(132.0, 34.0)
	_toggle_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toggle_button.offset_left = -66.0
	_toggle_button.offset_top = 6.0
	_toggle_button.offset_right = 66.0
	_toggle_button.offset_bottom = 40.0
	_toggle_button.pressed.connect(toggle_panel)
	add_child(_toggle_button)

	_panel = PanelContainer.new()
	_panel.name = "BoardSearchDrawer"
	_panel.theme_type_variation = "FloatingPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	_panel.visible = false
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	margin.add_child(root)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	root.add_child(top_row)

	_title_label = Label.new()
	_title_label.name = "SearchTitle"
	NotLightL10n.bind_text(_title_label, "board.search.title")
	_title_label.theme_type_variation = "SectionLabel"
	_title_label.custom_minimum_size = Vector2(154.0, 38.0)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(_title_label)

	_search_edit = LineEdit.new()
	_search_edit.name = "SearchEdit"
	NotLightL10n.bind_placeholder_text(_search_edit, "board.search.placeholder")
	_search_edit.clear_button_enabled = true
	_search_edit.right_icon = load("res://assets/icons/search.svg") as Texture2D
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.custom_minimum_size = Vector2(180.0, 38.0)
	_search_edit.text_changed.connect(_on_search_text_changed)
	_search_edit.text_submitted.connect(_on_search_submitted)
	top_row.add_child(_search_edit)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(_close_button, "board.search.close")
	_close_button.theme_type_variation = "IconButton"
	_close_button.custom_minimum_size = Vector2(38.0, 38.0)
	_close_button.expand_icon = true
	_close_button.add_theme_constant_override("icon_max_width", 15)
	_close_button.pressed.connect(close_panel)
	top_row.add_child(_close_button)

	_status_label = Label.new()
	_status_label.name = "SearchStatus"
	_status_label.theme_type_variation = "CaptionLabel"
	NotLightL10n.bind_text(_status_label, "board.search.hint")
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_status_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "SearchResultsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	_results_row = HFlowContainer.new()
	_results_row.name = "SearchResults"
	_results_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_row.add_theme_constant_override("h_separation", 9)
	_results_row.add_theme_constant_override("v_separation", 9)
	scroll.add_child(_results_row)

	_refresh_toggle_button()


func _update_geometry() -> void:
	if _panel == null:
		return
	# The left inset intentionally clears the 18..74 px tool rail. The panel also
	# starts below the 16..70 px board-title island, so opening search never hides
	# either of the permanent board controls.
	var left_inset: float = PANEL_LEFT
	var right_inset: float = PANEL_RIGHT
	if size.x < 760.0:
		left_inset = 82.0
		right_inset = 10.0
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = left_inset
	_panel.offset_right = -right_inset
	if _is_open:
		_panel.offset_top = PANEL_TOP
		_panel.offset_bottom = PANEL_BOTTOM


func _refresh_results() -> void:
	if _results_row == null:
		return
	for child: Node in _results_row.get_children():
		_results_row.remove_child(child)
		child.queue_free()

	var results: Array[Dictionary] = _filtered_results(_search_edit.text if _search_edit != null else "")
	var total: int = results.size()
	if total == 0:
		var empty: Label = Label.new()
		NotLightL10n.bind_text(empty, "board.search.empty")
		empty.theme_type_variation = "BodyMutedLabel"
		empty.custom_minimum_size = Vector2(320.0, CARD_HEIGHT)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_results_row.add_child(empty)
	else:
		var shown: int = mini(total, MAX_VISIBLE_RESULTS)
		for index: int in range(shown):
			_results_row.add_child(_make_result_card(results[index]))
	if _status_label != null:
		var query: String = _search_edit.text.strip_edges() if _search_edit != null else ""
		if query.is_empty():
			_status_label.text = NotLightL10n.text("board.search.hint_count", {"count": total})
		elif total > MAX_VISIBLE_RESULTS:
			_status_label.text = NotLightL10n.text("board.search.count_limited", {"shown": MAX_VISIBLE_RESULTS, "count": total})
		else:
			_status_label.text = NotLightL10n.text("board.search.count", {"count": total})


func _filtered_results(query: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var entity_ids: PackedInt64Array = _snapshot.get("entity_ids", PackedInt64Array())
	var type_ids: PackedStringArray = _snapshot.get("type_ids", PackedStringArray())
	var titles: PackedStringArray = _snapshot.get("titles", PackedStringArray())
	var bodies: PackedStringArray = _snapshot.get("bodies", PackedStringArray())
	var search_texts: PackedStringArray = _snapshot.get("search_texts", PackedStringArray())
	var count: int = mini(entity_ids.size(), mini(type_ids.size(), mini(titles.size(), mini(bodies.size(), search_texts.size()))))
	var clean_query: String = query.strip_edges().to_lower()
	var terms: PackedStringArray = clean_query.split(" ", false)
	for index: int in range(count):
		var type_id: String = type_ids[index]
		var title: String = titles[index].strip_edges()
		var type_label: String = _type_label(type_id)
		var haystack: String = "%s %s" % [search_texts[index], type_label.to_lower()]
		if not _matches_terms(haystack, terms):
			continue
		var score: int = _match_score(clean_query, title, haystack)
		results.append({
			"entity_id": entity_ids[index],
			"type_id": type_id,
			"type_label": type_label,
			"title": title if not title.is_empty() else NotLightL10n.text("board.search.untitled"),
			"body": bodies[index],
			"score": score,
		})
	results.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score: int = int(left.get("score", 0))
		var right_score: int = int(right.get("score", 0))
		if left_score != right_score:
			return left_score > right_score
		var title_compare: int = str(left.get("title", "")).naturalnocasecmp_to(str(right.get("title", "")))
		if title_compare != 0:
			return title_compare < 0
		return int(left.get("entity_id", 0)) < int(right.get("entity_id", 0))
	)
	return results


func _matches_terms(haystack: String, terms: PackedStringArray) -> bool:
	for term: String in terms:
		var clean_term: String = term.strip_edges().to_lower()
		if not clean_term.is_empty() and haystack.find(clean_term) < 0:
			return false
	return true


func _match_score(clean_query: String, title: String, haystack: String) -> int:
	if clean_query.is_empty():
		return 0
	var normalized_title: String = title.to_lower()
	if normalized_title == clean_query:
		return 400
	if normalized_title.begins_with(clean_query):
		return 300
	if normalized_title.find(clean_query) >= 0:
		return 220
	if haystack.find(clean_query) >= 0:
		return 120
	return 50


func _make_result_card(result: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SoftPanel"
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	margin.add_child(root)

	var type_label: Label = Label.new()
	type_label.text = str(result.get("type_label", ""))
	type_label.theme_type_variation = "CaptionStrongLabel"
	type_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	root.add_child(type_label)

	var title_label: Label = Label.new()
	title_label.text = str(result.get("title", ""))
	title_label.tooltip_text = title_label.text
	title_label.theme_type_variation = "SectionLabel"
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(title_label)

	var detail: Label = Label.new()
	detail.text = _result_detail(str(result.get("body", "")))
	detail.theme_type_variation = "CaptionLabel"
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(detail)

	var go_button: Button = Button.new()
	NotLightL10n.bind_text(go_button, "board.search.goto")
	go_button.theme_type_variation = "GhostButton"
	go_button.custom_minimum_size = Vector2(0.0, 28.0)
	go_button.pressed.connect(_request_entity.bind(int(result.get("entity_id", 0))))
	root.add_child(go_button)
	return panel


func _result_detail(body: String) -> String:
	var clean: String = body.replace("\n", " ").replace("\r", " ").strip_edges()
	while clean.find("  ") >= 0:
		clean = clean.replace("  ", " ")
	if clean.is_empty():
		return NotLightL10n.text("board.search.media_detail")
	return clean.left(110)


func _type_label(type_id: String) -> String:
	match StringName(type_id):
		BoardEntityTypes.TEXT:
			return NotLightL10n.text("board.search.type.text")
		BoardEntityTypes.IMAGE:
			return NotLightL10n.text("board.search.type.image")
		BoardEntityTypes.PDF:
			return NotLightL10n.text("board.search.type.pdf")
		BoardEntityTypes.FORMULA:
			return NotLightL10n.text("board.search.type.formula")
		BoardEntityTypes.VIDEO:
			return NotLightL10n.text("board.search.type.video")
		BoardEntityTypes.AUDIO:
			return NotLightL10n.text("board.search.type.audio")
		BoardEntityTypes.MODULE:
			return NotLightL10n.text("board.search.type.module")
		BoardEntityTypes.NOTE_PORTAL:
			return NotLightL10n.text("board.search.type.note")
		_:
			return NotLightL10n.text("board.search.type.object")


func _request_entity(entity_id: int) -> void:
	if entity_id <= 0:
		return
	entity_requested.emit(entity_id)


func _on_search_text_changed(_text: String) -> void:
	_refresh_results()


func _on_search_submitted(_text: String) -> void:
	var results: Array[Dictionary] = _filtered_results(_search_edit.text if _search_edit != null else "")
	if not results.is_empty():
		_request_entity(int(results[0].get("entity_id", 0)))


func _finish_close_animation() -> void:
	if _panel != null and not _is_open:
		_panel.visible = false
		_panel.modulate.a = 1.0
		_panel.offset_top = PANEL_TOP
		_panel.offset_bottom = PANEL_BOTTOM


func _refresh_toggle_button() -> void:
	if _toggle_button == null:
		return
	_toggle_button.text = "⌃" if _is_open else "⌄"
	_toggle_button.tooltip_text = NotLightL10n.text("board.search.toggle_close" if _is_open else "board.search.toggle_open")


func _on_locale_changed(_locale: String) -> void:
	if not is_inside_tree():
		return
	if _title_label != null:
		NotLightL10n.bind_text(_title_label, "board.search.title")
	if _search_edit != null:
		NotLightL10n.bind_placeholder_text(_search_edit, "board.search.placeholder")
	if _close_button != null:
		NotLightL10n.bind_tooltip(_close_button, "board.search.close")
	_refresh_toggle_button()
	_refresh_results()
