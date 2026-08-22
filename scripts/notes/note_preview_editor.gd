# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotePreviewEditor
extends ScrollContainer

signal content_replace_requested(start_offset: int, end_offset: int, replacement: String, keep_live_editor: bool)
signal note_link_requested(target: String)
signal source_edit_requested
signal source_edit_at_requested(source_offset: int)
signal asset_preview_requested(asset_id: String)

const CODE_SAVE_DELAY_SECONDS: float = 0.42
const MAX_INLINE_EDITOR_HEIGHT: float = 560.0
const MIN_INLINE_EDITOR_HEIGHT: float = 86.0
const MAX_NOTE_MODULE_LIVE_SURFACES: int = 8

var _markdown: String = ""
var _blocks: Array[Dictionary] = []
var _stack: VBoxContainer
var _active_inline_start: int = -1
var _rebuilding: bool = false
var _live_code_sessions: Array[Dictionary] = []
var _formula_service: FormulaRenderService
var _asset_library: AssetLibraryService
var _image_cache: ImageAssetCache
var _video_media: VideoMediaService
var _audio_media: AudioMediaService
var _pdf_media: PdfMediaService
var _module_registry: ModuleRegistry
var _app_settings: AppSettingsStore
var _embed_live_budget: int = AppSettingsStore.DEFAULT_NOTE_EMBED_LIVE_MEDIA
var _embed_rich_preview: bool = true
var _embed_live_order: Array[NoteResourceEmbedBlock] = []
var _module_live_budget: int = 1
var _module_live_order: Array[NoteModuleEmbedBlock] = []
var _callout_fold_state: Dictionary = {}


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var vertical_bar: VScrollBar = get_v_scroll_bar()
	vertical_bar.theme_type_variation = "NoteScrollBar"
	vertical_bar.custom_minimum_size = Vector2(11.0, 0.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack = VBoxContainer.new()
	_stack.name = "NotePreviewStack"
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_theme_constant_override("separation", 7)
	add_child(_stack)


func _exit_tree() -> void:
	if _app_settings != null and _app_settings.settings_changed.is_connected(_on_settings_changed):
		_app_settings.settings_changed.disconnect(_on_settings_changed)
	for block: NoteResourceEmbedBlock in _embed_live_order:
		if block != null and is_instance_valid(block):
			block.deactivate_live()
	_embed_live_order.clear()
	deactivate_module_embeds()


func deactivate_module_embeds() -> void:
	for module_block: NoteModuleEmbedBlock in _module_live_order:
		if module_block != null and is_instance_valid(module_block):
			module_block.deactivate_live()
	_module_live_order.clear()


func configure(
	formula_service: FormulaRenderService = null,
	asset_library: AssetLibraryService = null,
	image_cache: ImageAssetCache = null,
	video_media: VideoMediaService = null,
	audio_media: AudioMediaService = null,
	pdf_media: PdfMediaService = null,
	app_settings: AppSettingsStore = null,
	module_registry: ModuleRegistry = null
) -> void:
	if _app_settings != null and _app_settings.settings_changed.is_connected(_on_settings_changed):
		_app_settings.settings_changed.disconnect(_on_settings_changed)
	_formula_service = formula_service
	_asset_library = asset_library
	_image_cache = image_cache
	_video_media = video_media
	_audio_media = audio_media
	_pdf_media = pdf_media
	_module_registry = module_registry
	_app_settings = app_settings
	if _app_settings != null:
		if not _app_settings.settings_changed.is_connected(_on_settings_changed):
			_app_settings.settings_changed.connect(_on_settings_changed)
		_apply_embed_budget(_app_settings.get_snapshot())
	else:
		_embed_live_budget = AppSettingsStore.DEFAULT_NOTE_EMBED_LIVE_MEDIA
		_module_live_budget = 1
		_embed_rich_preview = true


func set_markdown(markdown: String, preserve_scroll: bool = true) -> void:
	if _rebuilding:
		return
	var old_scroll: int = scroll_vertical
	_markdown = markdown
	_blocks = NoteMarkdownBlocks.parse(markdown)
	_active_inline_start = -1
	_rebuild()
	if preserve_scroll:
		call_deferred("_restore_scroll", old_scroll)


func get_markdown() -> String:
	return _markdown


func flush_pending_edits() -> void:
	var sessions: Array[Dictionary] = _live_code_sessions.duplicate()
	for session: Dictionary in sessions:
		if not bool(session.get("dirty", false)):
			continue
		var commit_value: Variant = session.get("commit", Callable())
		if commit_value is Callable:
			var commit: Callable = commit_value as Callable
			if commit.is_valid():
				commit.call()


func _restore_scroll(value: int) -> void:
	scroll_vertical = value


func _rebuild() -> void:
	_rebuilding = true
	_live_code_sessions.clear()
	_embed_live_order.clear()
	_module_live_order.clear()
	for child: Node in _stack.get_children():
		child.queue_free()
	if _blocks.is_empty():
		var empty: Label = Label.new()
		NotLightL10n.bind_text(empty, "notes.preview.empty")
		empty.theme_type_variation = "BodyMutedLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(0.0, 80.0)
		empty.mouse_filter = Control.MOUSE_FILTER_STOP
		empty.gui_input.connect(_on_empty_input)
		_stack.add_child(empty)
		_rebuilding = false
		return
	for index: int in range(_blocks.size()):
		var block: Dictionary = _blocks[index]
		var control: Control = _block_control(block, index)
		if control != null:
			_stack.add_child(control)
	_rebuilding = false


func _block_control(block: Dictionary, block_index: int) -> Control:
	var type_name: StringName = StringName(str(block.get("type", NoteMarkdownBlocks.TYPE_PARAGRAPH)))
	if type_name == NoteMarkdownBlocks.TYPE_CODE:
		return _code_block(block, block_index)
	if type_name == NoteMarkdownBlocks.TYPE_MATH:
		return _editable_shell(_math_block(block), block)
	if type_name == NoteMarkdownBlocks.TYPE_EMBED:
		return _editable_shell(_resource_embed_block(block), block)
	if type_name == NoteMarkdownBlocks.TYPE_MODULE_EMBED:
		return _editable_shell(_module_embed_block(block), block)
	if type_name == NoteMarkdownBlocks.TYPE_FRONTMATTER:
		return _editable_shell(_frontmatter_block(block), block)
	if type_name == NoteMarkdownBlocks.TYPE_TASKS:
		return _tasks_block(block)
	if type_name == NoteMarkdownBlocks.TYPE_TABLE:
		return _editable_shell(_table_block(block), block)
	if type_name == NoteMarkdownBlocks.TYPE_RULE:
		var separator: HSeparator = HSeparator.new()
		separator.custom_minimum_size = Vector2(0.0, 18.0)
		return separator
	var content: Control
	if type_name == NoteMarkdownBlocks.TYPE_HEADING:
		content = _heading_block(block)
	elif type_name == NoteMarkdownBlocks.TYPE_QUOTE:
		content = _quote_block(block)
	elif type_name == NoteMarkdownBlocks.TYPE_LIST:
		content = _list_block(block)
	else:
		content = _paragraph_block(block)
	return _editable_shell(content, block)


func _editable_shell(content: Control, block: Dictionary) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "NotePreviewBlockPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	NotLightL10n.bind_tooltip(panel, "notes.preview.edit_block")
	panel.add_child(content)
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse: InputEventMouseButton = event as InputEventMouseButton
			if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and mouse.double_click:
				source_edit_at_requested.emit(int(block.get("start", 0)))
	)
	return panel


func _open_inline_editor(shell: PanelContainer, block: Dictionary) -> void:
	if _active_inline_start >= 0:
		return
	var start: int = int(block.get("start", 0))
	var end: int = int(block.get("end", start))
	_active_inline_start = start
	for child: Node in shell.get_children():
		shell.remove_child(child)
		child.queue_free()
	var editor: TextEdit = TextEdit.new()
	editor.theme_type_variation = "NoteInlineMarkdownEdit"
	editor.text = str(block.get("raw", ""))
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.scroll_fit_content_height = true
	editor.scroll_smooth = true
	NotLightL10n.bind_placeholder_text(editor, "notes.preview.block_placeholder")
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line_count: int = maxi(1, editor.text.count("\n") + 1)
	editor.custom_minimum_size = Vector2(0.0, clampf(float(line_count * 25 + 36), MIN_INLINE_EDITOR_HEIGHT, MAX_INLINE_EDITOR_HEIGHT))
	var committed: Array[bool] = [false]
	var commit: Callable = func() -> void:
		if committed[0]:
			return
		committed[0] = true
		_active_inline_start = -1
		content_replace_requested.emit(start, end, editor.text, false)
	editor.focus_exited.connect(commit)
	editor.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey:
			var key: InputEventKey = event as InputEventKey
			if key.pressed and not key.echo and key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
				commit.call()
				editor.release_focus()
	)
	shell.add_child(editor)
	editor.call_deferred("grab_focus")


func _frontmatter_block(block: Dictionary) -> Control:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "notes.preview.properties")
	title.theme_type_variation = "CaptionStrongLabel"
	root.add_child(title)
	var raw: String = str(block.get("raw", "")).replace("\r\n", "\n")
	var lines: PackedStringArray = raw.split("\n", true)
	var body: PackedStringArray = PackedStringArray()
	for index: int in range(1, lines.size()):
		var clean: String = lines[index].strip_edges()
		if clean == "---" or clean == "...":
			break
		body.append(lines[index])
	var text: String = "\n".join(body).strip_edges()
	var label: RichTextLabel = _rich_label("[code]%s[/code]" % NoteInlineMarkup.escape_bbcode(text))
	label.add_theme_color_override("default_color", NotLightTheme.semantic_color("text_muted"))
	root.add_child(label)
	return root


func _heading_block(block: Dictionary) -> Control:
	var raw: String = str(block.get("raw", "")).strip_edges()
	var level: int = clampi(int(block.get("level", 1)), 1, 6)
	var prefix_length: int = level + 1
	var text: String = raw.substr(prefix_length) if raw.length() >= prefix_length else raw
	var label: RichTextLabel = _rich_label(NoteInlineMarkup.to_bbcode(text))
	label.add_theme_font_size_override("normal_font_size", [32, 27, 23, 20, 18, 16][level - 1])
	label.add_theme_font_size_override("bold_font_size", [32, 27, 23, 20, 18, 16][level - 1])
	label.text = "[b]%s[/b]" % NoteInlineMarkup.to_bbcode(text)
	_attach_precise_source_navigation(label, block, text, maxi(0, raw.find(text)))
	return label


func _math_block(block: Dictionary) -> Control:
	var raw: String = str(block.get("raw", "")).strip_edges()
	var source: String = raw
	if source.begins_with("$$"):
		source = source.substr(2)
	if source.ends_with("$$"):
		source = source.substr(0, maxi(0, source.length() - 2))
	source = source.strip_edges()
	# NoteFormulaBlock owns centering internally. Keep the block itself full-width
	# so its responsive layout can measure the actual Notes column instead of a
	# shrink-to-content CenterContainer minimum.
	var formula: NoteFormulaBlock = NoteFormulaBlock.new()
	formula.configure(_formula_service, source)
	return formula


func _resource_embed_block(block: Dictionary) -> Control:
	var parsed: Dictionary = NoteResourceEmbed.parse_exact(str(block.get("raw", "")))
	var embed: NoteResourceEmbedBlock = NoteResourceEmbedBlock.new()
	embed.configure(
		_asset_library,
		_image_cache,
		_video_media,
		_audio_media,
		_pdf_media,
		str(parsed.get("hash_sha256", "")),
		str(parsed.get("caption", "")),
		_embed_rich_preview
	)
	embed.preview_requested.connect(func(asset_id: String) -> void: asset_preview_requested.emit(asset_id))
	embed.live_activation_requested.connect(_on_embed_live_activation_requested)
	return embed


func _on_embed_live_activation_requested(block: NoteResourceEmbedBlock) -> void:
	if block == null or not is_instance_valid(block):
		return
	var existing_index: int = _embed_live_order.find(block)
	if existing_index >= 0:
		_embed_live_order.remove_at(existing_index)
	while _embed_live_order.size() >= _embed_live_budget and not _embed_live_order.is_empty():
		var oldest: NoteResourceEmbedBlock = _embed_live_order[0]
		_embed_live_order.remove_at(0)
		if oldest != null and is_instance_valid(oldest):
			oldest.deactivate_live()
	if block.activate_live():
		_embed_live_order.append(block)


func _module_embed_block(block: Dictionary) -> Control:
	var parsed: Dictionary = NoteModuleEmbed.parse_exact(str(block.get("raw", "")))
	var embed: NoteModuleEmbedBlock = NoteModuleEmbedBlock.new()
	var instance_id: String = "note-embed:%s:%d" % [str(parsed.get("module_id", "")), int(block.get("start", 0))]
	embed.configure(
		_module_registry,
		str(parsed.get("module_id", "")),
		str(parsed.get("caption", "")),
		instance_id
	)
	embed.live_activation_requested.connect(_on_module_embed_live_activation_requested)
	return embed


func _on_module_embed_live_activation_requested(block: NoteModuleEmbedBlock) -> void:
	if block == null or not is_instance_valid(block):
		return
	var existing_index: int = _module_live_order.find(block)
	if existing_index >= 0:
		_module_live_order.remove_at(existing_index)
	while _module_live_order.size() >= _module_live_budget and not _module_live_order.is_empty():
		var oldest: NoteModuleEmbedBlock = _module_live_order[0]
		_module_live_order.remove_at(0)
		if oldest != null and is_instance_valid(oldest):
			oldest.deactivate_live()
	if block.activate_live():
		_module_live_order.append(block)


func _on_settings_changed(snapshot: Dictionary) -> void:
	var previous_rich_preview: bool = _embed_rich_preview
	_apply_embed_budget(snapshot)
	if previous_rich_preview != _embed_rich_preview and _stack != null and not _rebuilding:
		flush_pending_edits()
		var old_scroll: int = scroll_vertical
		_rebuild()
		call_deferred("_restore_scroll", old_scroll)


func _apply_embed_budget(snapshot: Dictionary) -> void:
	_embed_live_budget = clampi(
		int(snapshot.get("effective_note_embed_live_media", AppSettingsStore.DEFAULT_NOTE_EMBED_LIVE_MEDIA)),
		AppSettingsStore.MIN_NOTE_EMBED_LIVE_MEDIA,
		AppSettingsStore.MAX_NOTE_EMBED_LIVE_MEDIA
	)
	_embed_rich_preview = bool(snapshot.get("effective_note_embed_rich_preview", true))
	var performance_budget: Dictionary = _app_settings.get_performance_budget() if _app_settings != null else {}
	_module_live_budget = clampi(
		int(performance_budget.get("active_module_surfaces", 1)),
		1,
		MAX_NOTE_MODULE_LIVE_SURFACES
	)
	while _embed_live_order.size() > _embed_live_budget:
		var oldest: NoteResourceEmbedBlock = _embed_live_order[0]
		_embed_live_order.remove_at(0)
		if oldest != null and is_instance_valid(oldest):
			oldest.deactivate_live()
	while _module_live_order.size() > _module_live_budget:
		var oldest_module: NoteModuleEmbedBlock = _module_live_order[0]
		_module_live_order.remove_at(0)
		if oldest_module != null and is_instance_valid(oldest_module):
			oldest_module.deactivate_live()


func _paragraph_block(block: Dictionary) -> Control:
	var source_raw: String = str(block.get("raw", ""))
	var raw: String = source_raw.strip_edges()
	var label: RichTextLabel = _rich_label(NoteInlineMarkup.to_bbcode(raw))
	_attach_precise_source_navigation(label, block, raw, maxi(0, source_raw.find(raw)))
	return label


func _quote_block(block: Dictionary) -> Control:
	var lines: PackedStringArray = str(block.get("raw", "")).split("\n", false)
	var clean_lines: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var clean: String = line.strip_edges()
		if clean.begins_with(">"):
			clean = clean.substr(1).strip_edges()
		clean_lines.append(clean)
	var callout_type: String = ""
	var callout_title: String = ""
	var foldable: bool = false
	var collapsed_default: bool = false
	if not clean_lines.is_empty():
		var first: String = clean_lines[0]
		if first.begins_with("[!") and first.contains("]"):
			var close: int = first.find("]")
			callout_type = first.substr(2, maxi(0, close - 2)).strip_edges().to_upper()
			var remainder: String = first.substr(close + 1).strip_edges()
			if remainder.begins_with("+") or remainder.begins_with("-"):
				foldable = true
				collapsed_default = remainder.begins_with("-")
				remainder = remainder.substr(1).strip_edges()
			callout_title = remainder
			clean_lines.remove_at(0)
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "NoteCalloutPanel" if not callout_type.is_empty() else "NoteQuotePanel"
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	panel.add_child(root)
	var body: String = "\n".join(clean_lines).strip_edges()
	var body_control: Control = _rich_label(NoteInlineMarkup.to_bbcode(body)) if not body.is_empty() else Control.new()
	if not callout_type.is_empty():
		var header: HBoxContainer = HBoxContainer.new()
		header.add_theme_constant_override("separation", 6)
		root.add_child(header)
		var fold_button: Button
		if foldable:
			fold_button = Button.new()
			fold_button.theme_type_variation = "CompactIconButton"
			fold_button.focus_mode = Control.FOCUS_NONE
			fold_button.custom_minimum_size = Vector2(26.0, 26.0)
			header.add_child(fold_button)
		var heading: Label = Label.new()
		heading.text = callout_title if not callout_title.is_empty() else callout_type
		heading.theme_type_variation = "CaptionStrongLabel"
		heading.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(heading)
		if foldable:
			var state_key: int = int(block.get("start", 0))
			var collapsed: bool = bool(_callout_fold_state.get(state_key, collapsed_default))
			body_control.visible = not collapsed
			fold_button.text = "›" if collapsed else "⌄"
			fold_button.tooltip_text = NotLightL10n.text("notes.callout.expand" if collapsed else "notes.callout.collapse")
			fold_button.pressed.connect(func() -> void:
				var next_collapsed: bool = body_control.visible
				body_control.visible = not next_collapsed
				_callout_fold_state[state_key] = next_collapsed
				fold_button.text = "›" if next_collapsed else "⌄"
				fold_button.tooltip_text = NotLightL10n.text("notes.callout.expand" if next_collapsed else "notes.callout.collapse")
			)
	if not body.is_empty():
		root.add_child(body_control)
	return panel


func _list_block(block: Dictionary) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	for line: String in str(block.get("raw", "")).split("\n", false):
		var clean: String = line.strip_edges()
		if clean.is_empty():
			continue
		var marker_end: int = clean.find(" ")
		var marker: String = clean.substr(0, marker_end) if marker_end >= 0 else ""
		var text: String = clean.substr(marker_end + 1) if marker_end >= 0 else clean
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		var bullet: Label = Label.new()
		bullet.text = marker if marker.ends_with(".") and marker.trim_suffix(".").is_valid_int() else "•"
		bullet.theme_type_variation = "CaptionStrongLabel"
		row.add_child(bullet)
		var label: RichTextLabel = _rich_label(NoteInlineMarkup.to_bbcode(text))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		box.add_child(row)
	return box


func _tasks_block(block: Dictionary) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var raw: String = str(block.get("raw", ""))
	var normalized_raw: String = raw.replace("\r\n", "\n")
	var lines: PackedStringArray = normalized_raw.split("\n", true)
	for line_index: int in range(lines.size()):
		var line: String = lines[line_index]
		if line.strip_edges().is_empty():
			continue
		var bracket: int = line.find("[")
		if bracket < 0 or bracket + 2 >= line.length():
			continue
		var close: int = line.find("]", bracket + 1)
		if close < 0:
			continue
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var checkbox: CheckBox = CheckBox.new()
		var state: String = line.substr(bracket + 1, 1).to_lower()
		checkbox.button_pressed = state == "x"
		checkbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		checkbox.focus_mode = Control.FOCUS_NONE
		checkbox.toggled.connect(func(checked: bool) -> void:
			_toggle_task(block, line_index, checked)
		)
		row.add_child(checkbox)
		var task_text: String = line.substr(close + 1).strip_edges()
		var label: RichTextLabel = _rich_label(NoteInlineMarkup.to_bbcode(task_text))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		box.add_child(row)
	return box


func _toggle_task(block: Dictionary, line_index: int, checked: bool) -> void:
	var raw: String = str(block.get("raw", ""))
	var newline: String = "\r\n" if raw.contains("\r\n") else "\n"
	var normalized_raw: String = raw.replace("\r\n", "\n")
	var lines: PackedStringArray = normalized_raw.split("\n", true)
	if line_index < 0 or line_index >= lines.size():
		return
	var line: String = lines[line_index]
	var bracket: int = line.find("[")
	if bracket < 0 or bracket + 2 >= line.length():
		return
	lines[line_index] = line.substr(0, bracket + 1) + ("x" if checked else " ") + line.substr(bracket + 2)
	content_replace_requested.emit(int(block.get("start", 0)), int(block.get("end", 0)), newline.join(lines), false)


func _table_block(block: Dictionary) -> Control:
	var lines: PackedStringArray = str(block.get("raw", "")).split("\n", false)
	if lines.size() < 2:
		return _paragraph_block(block)
	var rows: Array[PackedStringArray] = []
	for index: int in range(lines.size()):
		if index == 1:
			continue
		var cells: PackedStringArray = lines[index].strip_edges().trim_prefix("|").trim_suffix("|").split("|", true)
		for cell_index: int in range(cells.size()):
			cells[cell_index] = cells[cell_index].strip_edges()
		rows.append(cells)
	var column_count: int = 1
	for row: PackedStringArray in rows:
		column_count = maxi(column_count, row.size())
	var grid: GridContainer = GridContainer.new()
	grid.columns = column_count
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for row_index: int in range(rows.size()):
		var row: PackedStringArray = rows[row_index]
		for column: int in range(column_count):
			var cell_panel: PanelContainer = PanelContainer.new()
			cell_panel.theme_type_variation = "NoteTableHeaderPanel" if row_index == 0 else "NoteTableCellPanel"
			cell_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label: RichTextLabel = _rich_label(NoteInlineMarkup.to_bbcode(row[column] if column < row.size() else ""))
			if row_index == 0:
				label.text = "[b]%s[/b]" % label.text
			cell_panel.add_child(label)
			grid.add_child(cell_panel)
	return grid


func _code_block(block: Dictionary, block_index: int) -> Control:
	var raw: String = str(block.get("raw", ""))
	var newline: String = "\r\n" if raw.contains("\r\n") else "\n"
	var normalized_raw: String = raw.replace("\r\n", "\n")
	var lines: PackedStringArray = normalized_raw.split("\n", true)
	var opening: String = lines[0] if not lines.is_empty() else "```"
	var fence: String = "~~~" if opening.strip_edges().begins_with("~~~") else "```"
	var language: String = opening.strip_edges().trim_prefix(fence).strip_edges()
	var terminal_newline: bool = normalized_raw.ends_with("\n")
	var last_content_index: int = lines.size() - 1
	if terminal_newline and last_content_index >= 0 and lines[last_content_index].is_empty():
		last_content_index -= 1
	var has_closing: bool = last_content_index >= 1 and lines[last_content_index].strip_edges().begins_with(fence)
	var body_start: int = 1
	var body_end: int = last_content_index if has_closing else lines.size()
	if not has_closing and terminal_newline and body_end > 0:
		body_end -= 1
	var code_lines: PackedStringArray = PackedStringArray()
	for index: int in range(body_start, body_end):
		code_lines.append(lines[index])
	var code_text: String = "\n".join(code_lines)
	var shell: PanelContainer = PanelContainer.new()
	shell.theme_type_variation = "NoteCodeBlockPanel"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	shell.add_child(root)
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)
	var language_label: Label = Label.new()
	language_label.text = language if not language.is_empty() else NotLightL10n.text("notes.code.language_text")
	language_label.theme_type_variation = "CaptionStrongLabel"
	language_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(language_label)
	var hint: Label = Label.new()
	NotLightL10n.bind_text(hint, "notes.preview.code_live")
	hint.theme_type_variation = "CaptionLabel"
	toolbar.add_child(hint)
	var copy_button: Button = Button.new()
	copy_button.icon = load("res://assets/icons/copy.svg") as Texture2D
	copy_button.theme_type_variation = "IconButton"
	copy_button.custom_minimum_size = Vector2(32.0, 32.0)
	copy_button.focus_mode = Control.FOCUS_NONE
	NotLightL10n.bind_tooltip(copy_button, "notes.preview.copy_code")
	toolbar.add_child(copy_button)
	var editor: CodeEdit = CodeEdit.new()
	editor.theme_type_variation = "NoteCodeEdit"
	editor.text = code_text
	editor.gutters_draw_line_numbers = true
	editor.gutters_zero_pad_line_numbers = false
	editor.line_folding = false
	editor.indent_use_spaces = false
	editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	editor.scroll_smooth = true
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var visible_lines: int = clampi(maxi(1, code_lines.size()), 2, 18)
	editor.custom_minimum_size = Vector2(0.0, float(visible_lines * 24 + 32))
	root.add_child(editor)
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = CODE_SAVE_DELAY_SECONDS
	shell.add_child(timer)
	var session: Dictionary = {"dirty": false}
	var commit: Callable = func() -> void:
		if not bool(session.get("dirty", false)) or not is_instance_valid(editor):
			return
		session["dirty"] = false
		timer.stop()
		_commit_live_code_block(block_index, editor.text, fence, opening, has_closing, newline)
	session["commit"] = commit
	_live_code_sessions.append(session)
	copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(editor.text)
		NotLightL10n.bind_tooltip(copy_button, "notes.preview.copied")
	)
	editor.text_changed.connect(func() -> void:
		session["dirty"] = true
		timer.start()
	)
	editor.focus_exited.connect(func() -> void: commit.call())
	timer.timeout.connect(func() -> void: commit.call())
	return shell


func _commit_live_code_block(
	block_index: int,
	code_text: String,
	fence: String,
	opening: String,
	had_closing: bool,
	newline: String
) -> void:
	if block_index < 0 or block_index >= _blocks.size():
		return
	var block: Dictionary = _blocks[block_index]
	var start: int = int(block.get("start", 0))
	var end: int = int(block.get("end", start))
	var safe_newline: String = "\r\n" if newline == "\r\n" else "\n"
	var normalized_code: String = code_text.replace("\r\n", "\n").replace("\r", "\n")
	var replacement: String = opening + safe_newline + normalized_code.replace("\n", safe_newline)
	if not replacement.ends_with(safe_newline):
		replacement += safe_newline
	if had_closing:
		replacement += fence
		if str(block.get("raw", "")).ends_with("\n"):
			replacement += safe_newline
	var delta: int = replacement.length() - (end - start)
	block["end"] = end + delta
	block["raw"] = replacement
	_blocks[block_index] = block
	for index: int in range(block_index + 1, _blocks.size()):
		var later: Dictionary = _blocks[index]
		later["start"] = int(later.get("start", 0)) + delta
		later["end"] = int(later.get("end", 0)) + delta
		_blocks[index] = later
	_markdown = _markdown.substr(0, start) + replacement + _markdown.substr(end)
	content_replace_requested.emit(start, end, replacement, true)


func _attach_precise_source_navigation(label: RichTextLabel, block: Dictionary, inline_source: String, raw_offset: int) -> void:
	label.gui_input.connect(func(event: InputEvent) -> void:
		if event is not InputEventMouseButton:
			return
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed or not mouse.double_click:
			return
		var visible_index: int = _visible_character_at(label, mouse.position)
		var inline_offset: int = NoteInlineMarkup.source_offset_for_visible_index(inline_source, visible_index)
		var source_offset: int = int(block.get("start", 0)) + raw_offset + inline_offset
		source_edit_at_requested.emit(clampi(source_offset, int(block.get("start", 0)), int(block.get("end", source_offset))))
		# Prevent the outer editable shell from receiving the same double-click and
		# replacing the precise caret target with the block start.
		label.accept_event()
	)


func _visible_character_at(label: RichTextLabel, local_position: Vector2) -> int:
	var line_count: int = maxi(1, label.get_line_count())
	var line: int = 0
	for candidate: int in range(line_count):
		if label.get_line_offset(candidate) <= local_position.y:
			line = candidate
		else:
			break
	var character_range: Vector2i = label.get_line_range(line)
	var parsed: String = label.get_parsed_text()
	var start: int = clampi(character_range.x, 0, parsed.length())
	var finish: int = clampi(character_range.y + 1, start, parsed.length())
	var line_text: String = parsed.substr(start, finish - start)
	if line_text.is_empty():
		return start
	var font: Font = label.get_theme_font("normal_font")
	if font == null:
		font = ThemeDB.fallback_font
	var font_size: int = label.get_theme_font_size("normal_font_size")
	if font_size <= 0:
		font_size = 16
	var best: int = 0
	var best_distance: float = 1.0e30
	for offset: int in range(line_text.length() + 1):
		var prefix: String = line_text.substr(0, offset)
		var width: float = font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var distance: float = absf(width - local_position.x)
		if distance < best_distance:
			best_distance = distance
			best = offset
	return clampi(start + best, start, finish)


func _rich_label(bbcode: String) -> RichTextLabel:
	var label: RichTextLabel = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = "NoteRichText"
	label.text = bbcode
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _on_meta_clicked(meta: Variant) -> void:
	var value: String = str(meta)
	if value.begins_with("note://"):
		note_link_requested.emit(value.trim_prefix("note://").uri_decode())
		return
	if value.begins_with("external://"):
		var target: String = value.trim_prefix("external://").uri_decode()
		if _is_safe_external_target(target):
			OS.shell_open(target)


func _is_safe_external_target(target: String) -> bool:
	var lower: String = target.strip_edges().to_lower()
	return lower.begins_with("https://") or lower.begins_with("http://") or lower.begins_with("mailto:")


func _on_empty_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed and mouse.double_click:
			source_edit_at_requested.emit(0)
