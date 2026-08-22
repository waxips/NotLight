# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteFormulaBlock
extends PanelContainer

const PREVIEW_EXTENT_SINGLE: float = 1024.0
const PREVIEW_EXTENT_MULTI: float = 1536.0
const PREVIEW_EXTENT_TALL: float = 2048.0
const MIN_FORMULA_WIDTH: float = 64.0
const MIN_FORMULA_HEIGHT: float = 56.0
const PREFERRED_SINGLE_LINE_WIDTH: float = 220.0
const PREFERRED_MULTI_LINE_WIDTH: float = 360.0
const MAX_FORMULA_WIDTH: float = 1120.0
const MAX_FORMULA_HEIGHT: float = 2200.0
const SINGLE_LINE_DISPLAY_HEIGHT: float = 84.0
const EXTRA_ROW_DISPLAY_HEIGHT: float = 82.0
const FORMULA_HORIZONTAL_PADDING: float = 28.0
const FORMULA_VERTICAL_PADDING: float = 26.0
const MAX_PRESENTATION_ROWS: int = 32

var _service: FormulaRenderService
var _source: String = ""
var _render_source: String = ""
var _layout_host: Control
var _texture: TextureRect
var _status: Label
var _cache_key: String = ""
var _texture_source_size: Vector2 = Vector2.ZERO
var _request_extent: float = PREVIEW_EXTENT_SINGLE


func _ready() -> void:
	theme_type_variation = "NoteFormulaPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var stack: VBoxContainer = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 4)
	add_child(stack)
	_status = Label.new()
	_status.theme_type_variation = "CaptionLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	stack.add_child(_status)
	_layout_host = Control.new()
	_layout_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_host.custom_minimum_size = Vector2(0.0, MIN_FORMULA_HEIGHT + FORMULA_VERTICAL_PADDING * 2.0)
	_layout_host.clip_contents = false
	_layout_host.resized.connect(_layout_texture)
	stack.add_child(_layout_host)
	_texture = TextureRect.new()
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture.custom_minimum_size = Vector2.ZERO
	_texture.modulate = NotLightTheme.semantic_color("text")
	_layout_host.add_child(_texture)
	_refresh()


func configure(service: FormulaRenderService, source_latex: String) -> void:
	_disconnect_service()
	_service = service
	_source = FormulaStore.normalize_source(source_latex)
	_render_source = _prepare_render_source(_source)
	_request_extent = _preview_extent_for_source()
	if _service != null:
		if not _service.texture_ready.is_connected(_on_texture_ready):
			_service.texture_ready.connect(_on_texture_ready)
		if not _service.render_failed.is_connected(_on_render_failed):
			_service.render_failed.connect(_on_render_failed)
		if not _service.backend_status_changed.is_connected(_on_backend_status_changed):
			_service.backend_status_changed.connect(_on_backend_status_changed)
	if is_inside_tree():
		_refresh()


func _exit_tree() -> void:
	_disconnect_service()


func _record() -> Dictionary:
	return {
		"source_latex": _render_source,
		"display_mode": FormulaStore.DISPLAY_BLOCK,
		"font_scale": FormulaStore.DEFAULT_FONT_SCALE,
		"foreground": NotLightTheme.semantic_color("text"),
	}


func _prepare_render_source(source: String) -> String:
	# Multi-line Notes math is presentation sugar only: canonical Markdown remains
	# untouched. Plain non-empty lines become an aligned derivation. Authors who
	# already provide an environment or explicit LaTeX line breaks retain full
	# control and bypass this transform.
	var normalized: String = FormulaStore.normalize_source(source).replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	if not normalized.contains("\n"):
		return normalized
	if normalized.contains("\\begin{") or normalized.contains("\\\\"):
		return normalized
	var lines: PackedStringArray = PackedStringArray()
	for raw_line: String in normalized.split("\n", false):
		var clean: String = raw_line.strip_edges()
		if not clean.is_empty():
			lines.append(_prepare_aligned_line(clean))
	if lines.size() <= 1:
		return normalized
	return "\\begin{aligned}%s\\end{aligned}" % " \\\\ ".join(lines)


func _prepare_aligned_line(line: String) -> String:
	# Align the first plain equality for derivation-style Notes math without
	# forcing authors to write `&` in every line. Explicit alignment markers
	# always win, and canonical source is never rewritten.
	if line.contains("&"):
		return line
	var equality: int = line.find("=")
	if equality < 0:
		return line
	return line.substr(0, equality) + "&" + line.substr(equality)


func _refresh() -> void:
	if _texture == null or _status == null:
		return
	_texture.texture = null
	_texture_source_size = Vector2.ZERO
	_texture.modulate = NotLightTheme.semantic_color("text")
	_texture.position = Vector2.ZERO
	_texture.size = Vector2.ZERO
	_cache_key = ""
	_request_extent = _preview_extent_for_source()
	if _layout_host != null:
		_layout_host.custom_minimum_size.y = MIN_FORMULA_HEIGHT + FORMULA_VERTICAL_PADDING * 2.0
	if _source.strip_edges().is_empty():
		_show_status(NotLightL10n.text("notes.math.empty"), true)
		return
	if _service == null:
		_show_status(NotLightL10n.text("notes.math.backend_unavailable"), true)
		return
	var record: Dictionary = _record()
	var texture: Texture2D = _service.request_texture(record, _request_extent)
	_cache_key = _service.cache_key_for_record(record, _request_extent)
	if texture != null:
		_apply_texture(texture)
		return
	_show_status(_service.backend_status_text() if not _service.backend_available() else NotLightL10n.text("notes.math.rendering"), true)


func _apply_texture(texture: Texture2D) -> void:
	_texture.texture = texture
	_texture.modulate = NotLightTheme.semantic_color("text")
	_texture_source_size = texture.get_size()
	if _texture_source_size.x <= 0.0 or _texture_source_size.y <= 0.0:
		_texture_source_size = Vector2(MIN_FORMULA_WIDTH, MIN_FORMULA_HEIGHT)
	_layout_texture()
	call_deferred("_layout_texture")
	_show_status("", false)


func _layout_texture() -> void:
	if _texture == null or _layout_host == null or _texture_source_size.x <= 0.0 or _texture_source_size.y <= 0.0:
		return
	# The texture rect itself is positioned explicitly inside a full-width host.
	# The host reserves the exact required height, so tall aligned/environment
	# formulas never depend on CenterContainer shrink-to-content behaviour and do
	# not get clipped by an arbitrary fixed preview rectangle.
	var aspect: float = _texture_source_size.x / maxf(1.0, _texture_source_size.y)
	var row_count: int = _presentation_row_count()
	var semantic_height: float = SINGLE_LINE_DISPLAY_HEIGHT + float(maxi(0, row_count - 1)) * EXTRA_ROW_DISPLAY_HEIGHT
	var desired_height: float = maxf(MIN_FORMULA_HEIGHT, semantic_height)
	var desired_width: float = maxf(MIN_FORMULA_WIDTH, desired_height * maxf(0.08, aspect))
	var host_width: float = _layout_host.size.x
	var available_width: float = minf(MAX_FORMULA_WIDTH, host_width - FORMULA_HORIZONTAL_PADDING * 2.0) if host_width > FORMULA_HORIZONTAL_PADDING * 2.0 + MIN_FORMULA_WIDTH else minf(MAX_FORMULA_WIDTH, 760.0)
	available_width = maxf(MIN_FORMULA_WIDTH, available_width)
	# Tall/narrow environments need a useful readable width rather than a tiny
	# width derived only from row count. Expanding to this preferred width also
	# expands the host height from the exact raster aspect, so nothing is cropped.
	var preferred_width: float = PREFERRED_SINGLE_LINE_WIDTH if row_count <= 1 else PREFERRED_MULTI_LINE_WIDTH
	var readable_width: float = minf(available_width, preferred_width)
	if desired_width < readable_width:
		desired_width = readable_width
		desired_height = desired_width / maxf(0.08, aspect)
	if desired_width > available_width:
		var width_scale: float = available_width / desired_width
		desired_width *= width_scale
		desired_height *= width_scale
	if desired_height > MAX_FORMULA_HEIGHT:
		var height_scale: float = MAX_FORMULA_HEIGHT / desired_height
		desired_width *= height_scale
		desired_height *= height_scale
	var reserved_height: float = ceil(desired_height + FORMULA_VERTICAL_PADDING * 2.0)
	if not is_equal_approx(_layout_host.custom_minimum_size.y, reserved_height):
		_layout_host.custom_minimum_size.y = reserved_height
	var actual_host_width: float = maxf(desired_width, _layout_host.size.x)
	_texture.size = Vector2(desired_width, desired_height)
	_texture.position = Vector2(
		maxf(0.0, floor((actual_host_width - desired_width) * 0.5)),
		FORMULA_VERTICAL_PADDING
	)


func _presentation_row_count() -> int:
	var normalized: String = _source.replace("\r\n", "\n").replace("\r", "\n")
	var rows: int = 0
	for raw_line: String in normalized.split("\n", false):
		var clean: String = raw_line.strip_edges()
		if clean.is_empty() or clean.begins_with("\\begin{") or clean.begins_with("\\end{"):
			continue
		rows += 1
	if rows <= 1 and normalized.contains("\\\\"):
		rows = 1 + normalized.count("\\\\")
	return clampi(maxi(1, rows), 1, MAX_PRESENTATION_ROWS)


func _preview_extent_for_source() -> float:
	var rows: int = _presentation_row_count()
	if rows >= 5:
		return PREVIEW_EXTENT_TALL
	if rows >= 2:
		return PREVIEW_EXTENT_MULTI
	return PREVIEW_EXTENT_SINGLE


func _show_status(text: String, visible: bool) -> void:
	_status.text = text
	_status.visible = visible and not text.is_empty()


func _on_texture_ready(cache_key: String) -> void:
	if _service == null:
		return
	if _cache_key.is_empty():
		_cache_key = _service.cache_key_for_record(_record(), _request_extent)
	if cache_key != _cache_key:
		return
	var texture: Texture2D = _service.get_cached_texture(_record(), _request_extent)
	if texture == null:
		return
	_apply_texture(texture)


func _on_render_failed(cache_key: String, _message: String, _detail: String) -> void:
	if cache_key != _cache_key:
		return
	_texture.texture = null
	_texture_source_size = Vector2.ZERO
	_show_status(NotLightL10n.text("notes.math.failed"), true)


func _on_backend_status_changed() -> void:
	_refresh()


func _disconnect_service() -> void:
	if _service == null:
		return
	if _service.texture_ready.is_connected(_on_texture_ready):
		_service.texture_ready.disconnect(_on_texture_ready)
	if _service.render_failed.is_connected(_on_render_failed):
		_service.render_failed.disconnect(_on_render_failed)
	if _service.backend_status_changed.is_connected(_on_backend_status_changed):
		_service.backend_status_changed.disconnect(_on_backend_status_changed)
