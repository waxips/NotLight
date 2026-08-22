# SPDX-License-Identifier: GPL-3.0-or-later
class_name HubAmbientPhraseLayer
extends Control

# A deliberately lightweight, non-interactive "human" layer for the Hub.
# Phrases are ordinary localized UI copy: only technical localization keys live
# in this script, while all human-readable text comes from NotLightL10n.
# The layer never consumes mouse/keyboard input.

const PHRASE_KEYS: Array[String] = [
	"ambient.phrase.001",
	"ambient.phrase.002",
	"ambient.phrase.003",
	"ambient.phrase.004",
	"ambient.phrase.005",
	"ambient.phrase.006",
	"ambient.phrase.007",
	"ambient.phrase.008",
	"ambient.phrase.009",
	"ambient.phrase.010",
	"ambient.phrase.011",
	"ambient.phrase.012",
	"ambient.phrase.013",
	"ambient.phrase.014",
	"ambient.phrase.015",
	"ambient.phrase.016",
	"ambient.phrase.017",
	"ambient.phrase.018",
	"ambient.phrase.019",
	"ambient.phrase.020",
	"ambient.phrase.021",
	"ambient.phrase.022",
	"ambient.phrase.023",
	"ambient.phrase.024",
	"ambient.phrase.025",
	"ambient.phrase.026",
	"ambient.phrase.027",
	"ambient.phrase.028",
	"ambient.phrase.029",
	"ambient.phrase.030",
	"ambient.phrase.031",
	"ambient.phrase.032",
	"ambient.phrase.033",
	"ambient.phrase.034",
	"ambient.phrase.035",
	"ambient.phrase.036",
	"ambient.phrase.037",
	"ambient.phrase.038",
	"ambient.phrase.039",
	"ambient.phrase.040"
]
const PHRASE_COLORS: Array[Color] = [
	Color("#237f52"),
	Color("#5d6b61"),
	Color("#a26c32"),
	Color("#596d9c"),
]

const MIN_VISIBLE_PHRASES: int = 10
const MAX_VISIBLE_PHRASES: int = 16
const MIN_FONT_SIZE: int = 17
const MAX_FONT_SIZE: int = 38
const EDGE_PADDING: float = 20.0
const SPREAD_CANDIDATE_MULTIPLIER: float = 1.65
const MAX_ROTATION_RADIANS: float = 0.12
const MIN_ALPHA: float = 0.060
const MAX_ALPHA: float = 0.105
const MIN_DRIFT_AMPLITUDE: float = 7.0
const MAX_DRIFT_AMPLITUDE: float = 18.0
const MIN_DRIFT_PERIOD_SECONDS: float = 18.0
const MAX_DRIFT_PERIOD_SECONDS: float = 38.0
const PRIMARY_LOCALE_SHARE: float = 0.84

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _phrases_by_locale: Dictionary = {}
var _phrase_colors: PackedColorArray = PackedColorArray()
var _items: Array[Dictionary] = []
var _rebuild_queued: bool = false
var _motion_time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rng.randomize()
	_load_phrases()
	resized.connect(_queue_rebuild)
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	_queue_rebuild()


func _exit_tree() -> void:
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func _process(delta: float) -> void:
	if delta <= 0.0 or size.x <= 1.0 or size.y <= 1.0:
		return
	_motion_time += delta
	for item: Dictionary in _items:
		var label_value: Variant = item.get("label")
		if label_value is not Label:
			continue
		var label: Label = label_value as Label
		if not is_instance_valid(label):
			continue
		var origin_value: Variant = item.get("origin", label.position)
		var amplitude_value: Variant = item.get("amplitude", Vector2.ZERO)
		var origin: Vector2 = origin_value as Vector2 if origin_value is Vector2 else label.position
		var amplitude: Vector2 = amplitude_value as Vector2 if amplitude_value is Vector2 else Vector2.ZERO
		var phase: float = float(item.get("phase", 0.0))
		var period: float = maxf(1.0, float(item.get("period", 24.0)))
		var t: float = (_motion_time / period) * TAU + phase
		# Orbit around the assigned spread cell instead of free-floating across the
		# whole Hub. Phrases keep their breathing motion without slowly clustering.
		label.position = origin + Vector2(sin(t) * amplitude.x, cos(t * 0.73) * amplitude.y)


func _load_phrases() -> void:
	_phrases_by_locale.clear()
	_phrase_colors = PackedColorArray()
	var russian: Array[String] = []
	for key: String in PHRASE_KEYS:
		var phrase: String = NotLightL10n.text(key).strip_edges()
		if not phrase.is_empty() and phrase != key:
			russian.append(phrase)
	if not russian.is_empty():
		_phrases_by_locale["ru"] = russian
	for color: Color in PHRASE_COLORS:
		_phrase_colors.append(color)


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuild_queued = false
	for item: Dictionary in _items:
		var label_value: Variant = item.get("label")
		if label_value is Label:
			var label: Label = label_value as Label
			if is_instance_valid(label):
				label.queue_free()
	_items.clear()
	if _phrases_by_locale.is_empty() or size.x < 320.0 or size.y < 240.0:
		return
	var target_count: int = clampi(int(round((size.x * size.y) / 105000.0)), MIN_VISIBLE_PHRASES, MAX_VISIBLE_PHRASES)
	var choices: Array[Dictionary] = _build_phrase_choices(target_count)
	var slots: Array[Vector2] = _build_spread_slots(choices.size())
	for index: int in range(choices.size()):
		_create_phrase(str(choices[index].get("text", "")), slots[index] if index < slots.size() else size * 0.5)


func _build_phrase_choices(target_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used: Dictionary = {}
	var current_locale: String = NotLightL10n.current_locale()
	var available_locales: Array[String] = []
	for raw_locale: Variant in _phrases_by_locale.keys():
		available_locales.append(str(raw_locale))
	if available_locales.is_empty():
		return result
	var has_primary: bool = _phrases_by_locale.has(current_locale)
	var primary_count: int = int(round(float(target_count) * PRIMARY_LOCALE_SHARE)) if has_primary else 0
	for index: int in range(target_count):
		var locale: String = current_locale if index < primary_count else _random_secondary_locale(current_locale, available_locales)
		if not _phrases_by_locale.has(locale):
			locale = available_locales[_rng.randi_range(0, available_locales.size() - 1)]
		var pool_value: Variant = _phrases_by_locale.get(locale, [])
		if pool_value is not Array:
			continue
		var pool: Array = pool_value as Array
		if pool.is_empty():
			continue
		var phrase: String = ""
		for attempt: int in range(12):
			var candidate: String = str(pool[_rng.randi_range(0, pool.size() - 1)])
			if not used.has(candidate):
				phrase = candidate
				break
		if phrase.is_empty():
			phrase = str(pool[_rng.randi_range(0, pool.size() - 1)])
		used[phrase] = true
		result.append({"text": phrase, "locale": locale})
	# Do not visually cluster the primary language first; the quota is about
	# probability/coverage, not position on screen.
	result.shuffle()
	return result


func _random_secondary_locale(primary: String, available_locales: Array[String]) -> String:
	var secondary: Array[String] = []
	for locale: String in available_locales:
		if locale != primary:
			secondary.append(locale)
	if secondary.is_empty():
		return primary
	return secondary[_rng.randi_range(0, secondary.size() - 1)]


func _build_spread_slots(count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var usable_width: float = maxf(1.0, size.x - EDGE_PADDING * 2.0)
	var usable_height: float = maxf(1.0, size.y - EDGE_PADDING * 2.0)
	var aspect: float = usable_width / usable_height

	# Build more candidate cells than visible phrases, then use a lightweight
	# farthest-point pass. The previous one-cell-per-phrase grid could still put
	# several long phrases in neighbouring cells; sparse candidates leave real
	# breathing room while the small score jitter keeps the result human rather
	# than looking like a perfectly regular wallpaper.
	var candidate_count: int = maxi(count, int(ceil(float(count) * SPREAD_CANDIDATE_MULTIPLIER)))
	var columns: int = maxi(1, int(ceil(sqrt(float(candidate_count) * aspect))))
	var rows: int = maxi(1, int(ceil(float(candidate_count) / float(columns))))
	var cell_width: float = usable_width / float(columns)
	var cell_height: float = usable_height / float(rows)
	var candidates: Array[Vector2] = []
	for cell_index: int in range(columns * rows):
		var column: int = cell_index % columns
		var row: int = floori(float(cell_index) / float(columns))
		var jitter_x: float = _rng.randf_range(0.16, 0.84)
		var jitter_y: float = _rng.randf_range(0.16, 0.84)
		candidates.append(Vector2(
			EDGE_PADDING + (float(column) + jitter_x) * cell_width,
			EDGE_PADDING + (float(row) + jitter_y) * cell_height
		))

	while result.size() < count and not candidates.is_empty():
		var chosen_index: int = 0
		if result.is_empty():
			chosen_index = _rng.randi_range(0, candidates.size() - 1)
		else:
			var best_score: float = -1.0
			for candidate_index: int in range(candidates.size()):
				var candidate: Vector2 = candidates[candidate_index]
				var min_distance_squared: float = 1.0e30
				for selected: Vector2 in result:
					min_distance_squared = minf(min_distance_squared, candidate.distance_squared_to(selected))
				var score: float = min_distance_squared * _rng.randf_range(0.92, 1.08)
				if score > best_score:
					best_score = score
					chosen_index = candidate_index
		result.append(candidates[chosen_index])
		candidates.remove_at(chosen_index)
	return result


func _create_phrase(text: String, slot_center: Vector2) -> void:
	if text.is_empty():
		return
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", _rng.randi_range(MIN_FONT_SIZE, MAX_FONT_SIZE))
	var base_color: Color = NotLightTheme.semantic_color("text_muted")
	if not _phrase_colors.is_empty():
		base_color = _phrase_colors[_rng.randi_range(0, _phrase_colors.size() - 1)]
	base_color.a = _rng.randf_range(MIN_ALPHA, MAX_ALPHA)
	label.add_theme_color_override("font_color", base_color)
	label.rotation = _rng.randf_range(-MAX_ROTATION_RADIANS, MAX_ROTATION_RADIANS)
	label.tooltip_text = ""
	add_child(label)
	label.reset_size()
	var bounds: Vector2 = label.get_combined_minimum_size()
	label.size = bounds
	var x_limit: float = maxf(EDGE_PADDING, size.x - bounds.x - EDGE_PADDING)
	var y_limit: float = maxf(EDGE_PADDING, size.y - bounds.y - EDGE_PADDING)
	label.position = Vector2(
		clampf(slot_center.x - bounds.x * 0.5, EDGE_PADDING, x_limit),
		clampf(slot_center.y - bounds.y * 0.5, EDGE_PADDING, y_limit)
	)
	var amplitude_x: float = _rng.randf_range(MIN_DRIFT_AMPLITUDE, MAX_DRIFT_AMPLITUDE)
	var amplitude_y: float = _rng.randf_range(MIN_DRIFT_AMPLITUDE * 0.55, MAX_DRIFT_AMPLITUDE * 0.80)
	_items.append({
		"label": label,
		"origin": label.position,
		"amplitude": Vector2(amplitude_x, amplitude_y),
		"phase": _rng.randf_range(0.0, TAU),
		"period": _rng.randf_range(MIN_DRIFT_PERIOD_SECONDS, MAX_DRIFT_PERIOD_SECONDS),
	})


func _on_locale_changed(_locale: String) -> void:
	_load_phrases()
	_queue_rebuild()
