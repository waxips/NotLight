# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardCard
extends PanelContainer

signal open_requested(board_id: String)
signal rename_requested(board_id: String, current_name: String)
signal duplicate_requested(board_id: String, current_name: String)
signal export_requested(board_id: String, current_name: String)
signal delete_requested(board_id: String, current_name: String)

var metadata: Dictionary = {}
var _title_label: Label
var _date_label: Label
var _thumbnail: BoardThumbnail


func _ready() -> void:
	theme_type_variation = "CardPanel"
	custom_minimum_size = Vector2(320, 262)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modulate = Color(0.985, 0.985, 0.985, 1.0)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_build_ui()


func configure(board_metadata: Dictionary) -> void:
	metadata = board_metadata.duplicate(true)
	if not is_node_ready():
		await ready
	_refresh()


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 13)
	add_child(root)

	_thumbnail = BoardThumbnail.new()
	_thumbnail.name = "Thumbnail"
	root.add_child(_thumbnail)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	root.add_child(title_row)

	_title_label = Label.new()
	_title_label.theme_type_variation = "SectionLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(_title_label)

	var menu_button: MenuButton = MenuButton.new()
	menu_button.text = "•••"
	NotLightL10n.bind_tooltip(menu_button, "hub.board.actions")
	menu_button.theme_type_variation = "GhostButton"
	menu_button.custom_minimum_size = Vector2(42, 36)
	menu_button.get_popup().add_item(NotLightL10n.text("common.rename"), 1)
	menu_button.get_popup().add_item(NotLightL10n.text("common.duplicate"), 4)
	menu_button.get_popup().add_item(NotLightL10n.text("common.export"), 2)
	menu_button.get_popup().add_separator()
	menu_button.get_popup().add_item(NotLightL10n.text("common.delete"), 3)
	menu_button.get_popup().id_pressed.connect(_on_menu_action)
	title_row.add_child(menu_button)

	_date_label = Label.new()
	_date_label.theme_type_variation = "BodyMutedLabel"
	root.add_child(_date_label)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 2)
	root.add_child(spacer)

	var open_button: Button = Button.new()
	NotLightL10n.bind_text(open_button, "hub.board.open")
	open_button.theme_type_variation = "PrimaryButton"
	open_button.custom_minimum_size = Vector2(0, 44)
	open_button.pressed.connect(_on_open_pressed)
	root.add_child(open_button)


func _refresh() -> void:
	if _title_label == null:
		return
	var board_id: String = str(metadata.get("id", ""))
	_title_label.text = str(metadata.get("name", NotLightL10n.text("hub.board.untitled")))
	_date_label.text = _format_updated_at(int(metadata.get("updated_at_unix", 0)))
	if _thumbnail != null:
		_thumbnail.configure(board_id)


func _format_updated_at(unix_time: int) -> String:
	if unix_time <= 0:
		return NotLightL10n.text("hub.board.date_unknown")
	var timezone: Dictionary = Time.get_time_zone_from_system()
	var local_unix_time: int = unix_time + int(timezone.get("bias", 0)) * 60
	var data: Dictionary = Time.get_datetime_dict_from_unix_time(local_unix_time)
	var date_text: String = NotLightL10n.text("hub.board.date_format", {
		"day": "%02d" % int(data.get("day", 1)),
		"month": "%02d" % int(data.get("month", 1)),
		"year": "%04d" % int(data.get("year", 1970)),
		"hour": "%02d" % int(data.get("hour", 0)),
		"minute": "%02d" % int(data.get("minute", 0)),
	})
	return NotLightL10n.text("hub.board.modified_at", {"date": date_text})


func _on_open_pressed() -> void:
	open_requested.emit(str(metadata.get("id", "")))


func _on_menu_action(action_id: int) -> void:
	var board_id: String = str(metadata.get("id", ""))
	var current_name: String = str(metadata.get("name", NotLightL10n.text("hub.board.untitled")))
	match action_id:
		1:
			rename_requested.emit(board_id, current_name)
		2:
			export_requested.emit(board_id, current_name)
		4:
			duplicate_requested.emit(board_id, current_name)
		3:
			delete_requested.emit(board_id, current_name)


func _on_mouse_entered() -> void:
	modulate = Color(1.0, 1.0, 1.0, 1.0)


func _on_mouse_exited() -> void:
	modulate = Color(0.985, 0.985, 0.985, 1.0)
