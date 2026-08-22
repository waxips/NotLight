# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardExportOptionsDialog
extends Control

signal submitted(options: Dictionary)

var _mode: OptionButton
var _derived: CheckBox
var _include_notes: CheckBox
var _include_note_embeds: CheckBox
var _embed_warning_label: Label
var _missing_note_embed_count: int = 0
var _asset_panel: VBoxContainer
var _asset_section: VBoxContainer
var _asset_list_panel: PanelContainer
var _asset_search: LineEdit
var _asset_checks: Dictionary = {}
var _asset_records: Array[Dictionary] = []
var _estimate_label: Label
var _policy_label: Label
var _export_button: Button


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_as_relative = false
	z_index = 1450
	_build_ui()


func open_dialog(_board_name: String, plan: Dictionary) -> void:
	_refresh_localized_options()
	_asset_records = []
	_missing_note_embed_count = _packed_string_count(plan.get("missing_note_embed_hashes", PackedStringArray()))
	for raw_asset: Variant in (plan.get("assets", []) as Array):
		if raw_asset is Dictionary:
			_asset_records.append((raw_asset as Dictionary).duplicate(true))
	_rebuild_asset_checks()
	if _asset_search != null:
		_asset_search.clear()
	_mode.select(0)
	_derived.set_pressed_no_signal(false)
	_include_notes.set_pressed_no_signal(true)
	if _include_note_embeds != null:
		_include_note_embeds.set_pressed_no_signal(true)
		_include_note_embeds.disabled = false
	NotLightL10n.bind_text(_policy_label, "exchange.board.export_policy_all")
	_refresh_mode()
	visible = true
	move_to_front()
	grab_focus()
	_export_button.grab_focus()


func close_dialog() -> void:
	visible = false


func _refresh_localized_options() -> void:
	if _mode == null or _mode.item_count < 3:
		return
	_mode.set_item_text(0, NotLightL10n.text("exchange.board.export_mode_all"))
	_mode.set_item_text(1, NotLightL10n.text("exchange.board.export_mode_none"))
	_mode.set_item_text(2, NotLightL10n.text("exchange.board.export_mode_custom"))


func _build_ui() -> void:
	var scrim: ColorRect = ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.035, 0.045, 0.040, 0.68)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.custom_minimum_size = Vector2(880.0, 600.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "exchange.board.export_options_title")
	title.theme_type_variation = "TitleLabel"
	root.add_child(title)

	var description: Label = Label.new()
	NotLightL10n.bind_text(description, "exchange.board.export_options_help")
	description.theme_type_variation = "BodyMutedLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)

	# Keep the resource list large even when export policy grows additional
	# switches. Configuration lives in a compact left column; the custom resource
	# picker owns the expandable right side instead of fighting every control above
	# it for the last few vertical pixels.
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	root.add_child(content)

	var options_column: VBoxContainer = VBoxContainer.new()
	options_column.custom_minimum_size = Vector2(310.0, 0.0)
	options_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_column.add_theme_constant_override("separation", 8)
	content.add_child(options_column)

	_mode = OptionButton.new()
	_mode.theme_type_variation = "SettingsOptionButton"
	_mode.custom_minimum_size = Vector2(0.0, 44.0)
	_mode.add_item(NotLightL10n.text("exchange.board.export_mode_all"))
	_mode.set_item_metadata(0, "all")
	_mode.add_item(NotLightL10n.text("exchange.board.export_mode_none"))
	_mode.set_item_metadata(1, "none")
	_mode.add_item(NotLightL10n.text("exchange.board.export_mode_custom"))
	_mode.set_item_metadata(2, "custom")
	_mode.item_selected.connect(func(_index: int) -> void: _refresh_mode())
	options_column.add_child(_mode)

	_policy_label = Label.new()
	_policy_label.theme_type_variation = "CaptionLabel"
	_policy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_column.add_child(_policy_label)

	_include_notes = CheckBox.new()
	NotLightL10n.bind_text(_include_notes, "exchange.board.include_notes")
	NotLightL10n.bind_tooltip(_include_notes, "exchange.board.include_notes_help")
	_include_notes.button_pressed = true
	_include_notes.toggled.connect(func(pressed: bool) -> void:
		if _include_note_embeds != null:
			_include_note_embeds.disabled = not pressed
		_refresh_asset_note_states()
		_refresh_embed_warning()
		_refresh_estimate()
	)
	options_column.add_child(_include_notes)

	_include_note_embeds = CheckBox.new()
	NotLightL10n.bind_text(_include_note_embeds, "exchange.board.include_note_embeds")
	NotLightL10n.bind_tooltip(_include_note_embeds, "exchange.board.include_note_embeds_help")
	_include_note_embeds.button_pressed = true
	_include_note_embeds.toggled.connect(func(_pressed: bool) -> void:
		_refresh_asset_note_states()
		_refresh_embed_warning()
		_refresh_estimate()
	)
	options_column.add_child(_include_note_embeds)

	_embed_warning_label = Label.new()
	_embed_warning_label.theme_type_variation = "CaptionLabel"
	_embed_warning_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("warning"))
	_embed_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_embed_warning_label.visible = false
	options_column.add_child(_embed_warning_label)

	_derived = CheckBox.new()
	NotLightL10n.bind_text(_derived, "exchange.board.include_derived")
	NotLightL10n.bind_tooltip(_derived, "exchange.board.include_derived_help")
	_derived.toggled.connect(func(_pressed: bool) -> void: _refresh_estimate())
	options_column.add_child(_derived)

	_asset_section = VBoxContainer.new()
	_asset_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_section.add_theme_constant_override("separation", 7)
	content.add_child(_asset_section)

	var resource_title: Label = Label.new()
	NotLightL10n.bind_text(resource_title, "exchange.board.custom_resources_title")
	resource_title.theme_type_variation = "CaptionStrongLabel"
	_asset_section.add_child(resource_title)

	_asset_search = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_asset_search, "exchange.board.resource_search_placeholder")
	_asset_search.clear_button_enabled = true
	_asset_search.text_changed.connect(func(_query: String) -> void: _refresh_asset_filter())
	_asset_section.add_child(_asset_search)

	var bulk_actions: HBoxContainer = HBoxContainer.new()
	bulk_actions.add_theme_constant_override("separation", 6)
	_asset_section.add_child(bulk_actions)
	var select_all: Button = Button.new()
	NotLightL10n.bind_text(select_all, "exchange.board.select_all")
	select_all.theme_type_variation = "GhostButton"
	select_all.pressed.connect(func() -> void: _set_visible_custom_assets_selected(true))
	bulk_actions.add_child(select_all)
	var clear_selection: Button = Button.new()
	NotLightL10n.bind_text(clear_selection, "exchange.board.clear_selection")
	clear_selection.theme_type_variation = "GhostButton"
	clear_selection.pressed.connect(func() -> void: _set_visible_custom_assets_selected(false))
	bulk_actions.add_child(clear_selection)

	_asset_list_panel = PanelContainer.new()
	_asset_list_panel.theme_type_variation = "SoftPanel"
	_asset_list_panel.custom_minimum_size = Vector2(0.0, 300.0)
	_asset_list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_section.add_child(_asset_list_panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list_panel.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)
	_asset_panel = VBoxContainer.new()
	_asset_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_panel.add_theme_constant_override("separation", 5)
	margin.add_child(_asset_panel)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)

	_estimate_label = Label.new()
	_estimate_label.theme_type_variation = "CaptionStrongLabel"
	_estimate_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_estimate_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	footer.add_child(actions)
	var cancel: Button = Button.new()
	NotLightL10n.bind_text(cancel, "common.cancel")
	cancel.theme_type_variation = "GhostButton"
	cancel.pressed.connect(close_dialog)
	actions.add_child(cancel)
	_export_button = Button.new()
	NotLightL10n.bind_text(_export_button, "exchange.board.choose_destination")
	_export_button.theme_type_variation = "PrimaryButton"
	_export_button.pressed.connect(_submit)
	actions.add_child(_export_button)


func _rebuild_asset_checks() -> void:
	if _asset_panel == null:
		return
	for child: Node in _asset_panel.get_children():
		_asset_panel.remove_child(child)
		child.queue_free()
	_asset_checks.clear()
	if _asset_records.is_empty():
		var empty: Label = Label.new()
		NotLightL10n.bind_text(empty, "exchange.board.no_resources")
		empty.theme_type_variation = "BodyMutedLabel"
		_asset_panel.add_child(empty)
		return
	for asset: Dictionary in _asset_records:
		var asset_id: String = str(asset.get("id", ""))
		if asset_id.is_empty():
			continue
		var check: CheckBox = CheckBox.new()
		check.button_pressed = true
		check.text = NotLightL10n.text("ui.format.two_parts_spaced") % [
			str(asset.get("display_name", asset_id)),
			_format_bytes(int(asset.get("primary_bytes", 0))),
		]
		check.tooltip_text = str(asset.get("display_name", asset_id))
		check.toggled.connect(func(_pressed: bool) -> void: _refresh_estimate())
		_asset_panel.add_child(check)
		_asset_checks[asset_id] = check
	_refresh_asset_note_states()
	_refresh_asset_filter()


func _refresh_asset_filter() -> void:
	var query: String = _asset_search.text.strip_edges().to_lower() if _asset_search != null else ""
	for asset: Dictionary in _asset_records:
		var asset_id: String = str(asset.get("id", ""))
		var check: CheckBox = _asset_checks.get(asset_id, null) as CheckBox
		if check == null:
			continue
		var display_name: String = str(asset.get("display_name", asset_id)).to_lower()
		check.visible = query.is_empty() or display_name.contains(query) or asset_id.to_lower().contains(query)


func _set_visible_custom_assets_selected(selected: bool) -> void:
	for raw_check: Variant in _asset_checks.values():
		var check: CheckBox = raw_check as CheckBox
		if check == null or check.disabled or not check.visible:
			continue
		check.set_pressed_no_signal(selected)
	_refresh_estimate()


func _refresh_asset_note_states() -> void:
	if _include_notes == null:
		return
	var include_notes: bool = _include_notes.button_pressed
	var include_note_embeds: bool = include_notes and _include_note_embeds != null and _include_note_embeds.button_pressed
	for asset: Dictionary in _asset_records:
		var asset_id: String = str(asset.get("id", ""))
		var check: CheckBox = _asset_checks.get(asset_id, null) as CheckBox
		if check == null:
			continue
		var is_note: bool = int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
		var is_embed_dependency: bool = bool(asset.get("note_embed_dependency", false))
		if is_note:
			check.set_pressed_no_signal(include_notes)
			check.disabled = true
			check.tooltip_text = (
				NotLightL10n.text("exchange.board.note_missing")
				if bool(asset.get("missing", false)) and include_notes
				else NotLightL10n.text("exchange.board.note_policy_help")
			)
		elif is_embed_dependency:
			check.set_pressed_no_signal(include_note_embeds)
			check.disabled = true
			NotLightL10n.bind_tooltip(check, "exchange.board.note_embed_dependency_help")


func _refresh_mode() -> void:
	var mode: String = _selected_mode()
	var custom: bool = mode == "custom"
	if _derived != null:
		_derived.disabled = mode == "none"
	if _asset_section != null:
		_asset_section.visible = custom or _asset_records.is_empty()
	match mode:
		"none":
			NotLightL10n.bind_text(_policy_label, "exchange.board.export_policy_none")
		"custom":
			NotLightL10n.bind_text(_policy_label, "exchange.board.export_policy_custom")
		_:
			NotLightL10n.bind_text(_policy_label, "exchange.board.export_policy_all")
	_refresh_estimate()


func _refresh_estimate() -> void:
	if _estimate_label == null:
		return
	var mode: String = _selected_mode()
	var bytes: int = 0
	var embedded_count: int = 0
	var included_asset_count: int = 0
	var omitted_notes: int = 0
	for asset: Dictionary in _asset_records:
		var asset_id: String = str(asset.get("id", ""))
		var is_note: bool = int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
		var is_embed_dependency: bool = bool(asset.get("note_embed_dependency", false))
		if is_note and not _include_notes.button_pressed:
			omitted_notes += 1
			continue
		if is_embed_dependency and (not _include_notes.button_pressed or _include_note_embeds == null or not _include_note_embeds.button_pressed):
			continue
		included_asset_count += 1
		var embedded: bool = is_note or is_embed_dependency or mode == "all"
		if mode == "custom" and not is_note and not is_embed_dependency:
			var check: CheckBox = _asset_checks.get(asset_id, null) as CheckBox
			embedded = check != null and check.button_pressed
		if not embedded:
			continue
		embedded_count += 1
		bytes += int(asset.get("durable_bytes" if _derived.button_pressed else "primary_bytes", 0))
	_estimate_label.text = NotLightL10n.text("exchange.board.export_estimate_notes", {
		"size": _format_bytes(bytes),
		"embedded": embedded_count,
		"external": maxi(0, included_asset_count - embedded_count),
		"omitted_notes": omitted_notes,
	})
	_refresh_embed_warning()


func _refresh_embed_warning() -> void:
	if _embed_warning_label == null:
		return
	var enabled: bool = (
		_missing_note_embed_count > 0
		and _include_notes != null
		and _include_notes.button_pressed
		and _include_note_embeds != null
		and _include_note_embeds.button_pressed
	)
	_embed_warning_label.visible = enabled
	if enabled:
		_embed_warning_label.text = NotLightL10n.text(
			"exchange.board.note_embed_missing_warning",
			{"count": _missing_note_embed_count}
		)


func _packed_string_count(value: Variant) -> int:
	if value is PackedStringArray:
		return (value as PackedStringArray).size()
	if value is Array:
		return (value as Array).size()
	return 0


func _selected_mode() -> String:
	if _mode == null or _mode.selected < 0:
		return "all"
	return str(_mode.get_item_metadata(_mode.selected))


func _submit() -> void:
	var mode: String = _selected_mode()
	var embedded_ids: PackedStringArray = PackedStringArray()
	if mode == "custom":
		for asset: Dictionary in _asset_records:
			if int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE or bool(asset.get("note_embed_dependency", false)):
				continue
			var asset_id: String = str(asset.get("id", ""))
			var check: CheckBox = _asset_checks.get(asset_id, null) as CheckBox
			if check != null and check.button_pressed:
				embedded_ids.append(asset_id)
	visible = false
	submitted.emit({
		"resource_mode": mode,
		"embedded_asset_ids": embedded_ids,
		"include_derived_variants": _derived.button_pressed,
		"include_notes": _include_notes.button_pressed,
		"include_note_embeds": _include_notes.button_pressed and _include_note_embeds != null and _include_note_embeds.button_pressed,
	})


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		close_dialog()
		get_viewport().set_input_as_handled()


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close_dialog()


func _format_bytes(value: int) -> String:
	var bytes: float = float(maxi(0, value))
	if bytes < 1024.0:
		return NotLightL10n.text("ui.format.bytes_b") % int(bytes)
	if bytes < 1024.0 * 1024.0:
		return NotLightL10n.text("ui.format.bytes_kb") % (bytes / 1024.0)
	if bytes < 1024.0 * 1024.0 * 1024.0:
		return NotLightL10n.text("ui.format.bytes_mb") % (bytes / (1024.0 * 1024.0))
	return NotLightL10n.text("ui.format.bytes_gb") % (bytes / (1024.0 * 1024.0 * 1024.0))
