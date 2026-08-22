# SPDX-License-Identifier: GPL-3.0-or-later
class_name TextBlockRenderWorker
extends RefCounted

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _has_job: bool = false
var _working: bool = false
var _job: Dictionary = {}
var _has_result: bool = false
var _result: Dictionary = {}
var _last_signature: String = ""


func start() -> void:
	if _running:
		return
	_running = true
	_thread.start(_thread_loop)


func stop() -> void:
	_mutex.lock()
	_running = false
	_has_job = false
	_working = false
	_has_result = false
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()


func submit(snapshot: Dictionary, signature: String) -> bool:
	if signature == _last_signature:
		return false
	_last_signature = signature
	_mutex.lock()
	_job = snapshot.duplicate(false)
	_job["signature"] = signature
	_has_job = true
	_mutex.unlock()
	_semaphore.post()
	return true


func poll_result() -> Dictionary:
	_mutex.lock()
	if not _has_result:
		_mutex.unlock()
		return {}
	var result: Dictionary = _result
	_has_result = false
	_mutex.unlock()
	return result


func has_pending_work() -> bool:
	_mutex.lock()
	var pending: bool = _has_job or _working or _has_result
	_mutex.unlock()
	return pending


func _thread_loop() -> void:
	while true:
		_semaphore.wait()
		_mutex.lock()
		if not _running:
			_mutex.unlock()
			break
		if not _has_job:
			_mutex.unlock()
			continue
		var job: Dictionary = _job
		_has_job = false
		_working = true
		_mutex.unlock()
		var plan: Dictionary = _build_plan(job)
		_mutex.lock()
		_working = false
		_result = plan
		_has_result = true
		_mutex.unlock()


func _build_plan(job: Dictionary) -> Dictionary:
	var entity_ids: PackedInt64Array = job.get("entity_ids", PackedInt64Array()) as PackedInt64Array
	var texts: PackedStringArray = job.get("texts", PackedStringArray()) as PackedStringArray
	var rect_values: PackedFloat32Array = job.get("rect_values", PackedFloat32Array()) as PackedFloat32Array
	var font_sizes: PackedFloat32Array = job.get("font_sizes", PackedFloat32Array()) as PackedFloat32Array
	var font_families: PackedStringArray = job.get("font_families", PackedStringArray()) as PackedStringArray
	var alignments: PackedInt32Array = job.get("alignments", PackedInt32Array()) as PackedInt32Array
	var background_colors: PackedColorArray = job.get("background_colors", PackedColorArray()) as PackedColorArray
	var text_colors: PackedColorArray = job.get("text_colors", PackedColorArray()) as PackedColorArray
	var base_style_flags: PackedInt32Array = job.get("base_style_flags", PackedInt32Array()) as PackedInt32Array
	var run_offsets: PackedInt32Array = job.get("run_offsets", PackedInt32Array()) as PackedInt32Array
	var run_counts: PackedInt32Array = job.get("run_counts", PackedInt32Array()) as PackedInt32Array
	var run_starts: PackedInt32Array = job.get("run_starts", PackedInt32Array()) as PackedInt32Array
	var run_lengths: PackedInt32Array = job.get("run_lengths", PackedInt32Array()) as PackedInt32Array
	var run_flags: PackedInt32Array = job.get("run_flags", PackedInt32Array()) as PackedInt32Array
	var run_colors: PackedColorArray = job.get("run_colors", PackedColorArray()) as PackedColorArray
	var paragraph_offsets: PackedInt32Array = job.get("paragraph_offsets", PackedInt32Array()) as PackedInt32Array
	var paragraph_counts: PackedInt32Array = job.get("paragraph_counts", PackedInt32Array()) as PackedInt32Array
	var paragraph_types: PackedInt32Array = job.get("paragraph_types", PackedInt32Array()) as PackedInt32Array
	var paragraph_indents: PackedInt32Array = job.get("paragraph_indents", PackedInt32Array()) as PackedInt32Array
	var revisions: PackedInt64Array = job.get("revisions", PackedInt64Array()) as PackedInt64Array
	var lod: int = int(job.get("lod", int(BoardRenderPolicy.LodLevel.FULL)))
	var count: int = mini(int(job.get("count", entity_ids.size())), entity_ids.size())
	var preview_budget: int = maxi(0, int(job.get("max_text_previews", count)))
	var maximum_lines: int = maxi(1, int(job.get("max_text_lines", 12)))

	var output_ids: PackedInt64Array = entity_ids.slice(0, count)
	var output_rects: PackedFloat32Array = rect_values.slice(0, count * 4)
	var output_backgrounds: PackedColorArray = background_colors.slice(0, count)
	var text_entity_ids: PackedInt64Array = PackedInt64Array()
	var text_rects: PackedFloat32Array = PackedFloat32Array()
	var text_font_sizes: PackedFloat32Array = PackedFloat32Array()
	var text_font_families: PackedStringArray = PackedStringArray()
	var text_alignments: PackedInt32Array = PackedInt32Array()
	var output_text_colors: PackedColorArray = PackedColorArray()
	var output_base_style_flags: PackedInt32Array = PackedInt32Array()
	var text_run_offsets: PackedInt32Array = PackedInt32Array()
	var text_run_counts: PackedInt32Array = PackedInt32Array()
	var output_run_starts: PackedInt32Array = PackedInt32Array()
	var output_run_lengths: PackedInt32Array = PackedInt32Array()
	var output_run_flags: PackedInt32Array = PackedInt32Array()
	var output_run_colors: PackedColorArray = PackedColorArray()
	var line_offsets: PackedInt32Array = PackedInt32Array()
	var line_counts: PackedInt32Array = PackedInt32Array()
	var output_lines: PackedStringArray = PackedStringArray()
	var output_line_starts: PackedInt32Array = PackedInt32Array()
	var output_line_lengths: PackedInt32Array = PackedInt32Array()
	var output_line_prefixes: PackedStringArray = PackedStringArray()
	var output_line_indents: PackedFloat32Array = PackedFloat32Array()
	var text_count: int = 0

	if lod != int(BoardRenderPolicy.LodLevel.PLACEHOLDER):
		for index: int in range(count):
			if text_count >= preview_budget:
				break
			var source_text: String = texts[index] if index < texts.size() else ""
			if source_text.is_empty():
				continue
			var rect_index: int = index * 4
			if rect_index + 3 >= rect_values.size():
				continue
			var width: float = rect_values[rect_index + 2]
			var height: float = rect_values[rect_index + 3]
			var source_font_size: float = font_sizes[index] if index < font_sizes.size() else TextBlockStore.DEFAULT_FONT_SIZE
			var visible_font_size: float = _font_size_for_lod(source_font_size, lod)
			var background: Color = background_colors[index] if index < background_colors.size() else Color.TRANSPARENT
			var paragraphs: Array = _paragraph_slice(index, paragraph_offsets, paragraph_counts, paragraph_types, paragraph_indents)
			var style_runs: Array = _run_slice(index, run_offsets, run_counts, run_starts, run_lengths, run_flags, run_colors)
			var line_limit: int = _line_limit_for_rect(height, visible_font_size, background, lod, maximum_lines)
			if line_limit <= 0:
				continue
			var padding: Vector2 = TextLayoutUtils.padding_for_background(background)
			var wrapped: Dictionary = TextLayoutUtils.wrap_text_rich(
				source_text,
				maxf(8.0, width - padding.x * 2.0),
				visible_font_size,
				paragraphs,
				line_limit,
				style_runs,
				int(base_style_flags[index]) if index < base_style_flags.size() else 0
			)
			var wrapped_lines: PackedStringArray = wrapped.get("lines", PackedStringArray()) as PackedStringArray
			if wrapped_lines.is_empty():
				continue

			text_entity_ids.append(int(entity_ids[index]))
			text_rects.append(rect_values[rect_index])
			text_rects.append(rect_values[rect_index + 1])
			text_rects.append(width)
			text_rects.append(height)
			text_font_sizes.append(visible_font_size)
			text_font_families.append(font_families[index] if index < font_families.size() else TextBlockStore.DEFAULT_FONT_FAMILY)
			text_alignments.append(alignments[index] if index < alignments.size() else HORIZONTAL_ALIGNMENT_LEFT)
			output_text_colors.append(text_colors[index] if index < text_colors.size() else TextBlockStore.COLOR_TEXT)
			output_base_style_flags.append(base_style_flags[index] if index < base_style_flags.size() else 0)

			text_run_offsets.append(output_run_starts.size())
			var source_run_offset: int = int(run_offsets[index]) if index < run_offsets.size() else 0
			var source_run_count: int = int(run_counts[index]) if index < run_counts.size() else 0
			text_run_counts.append(source_run_count)
			for local_run: int in range(source_run_count):
				var source_run_index: int = source_run_offset + local_run
				if source_run_index < 0 or source_run_index >= run_starts.size():
					continue
				output_run_starts.append(run_starts[source_run_index])
				output_run_lengths.append(run_lengths[source_run_index] if source_run_index < run_lengths.size() else 0)
				output_run_flags.append(run_flags[source_run_index] if source_run_index < run_flags.size() else 0)
				output_run_colors.append(run_colors[source_run_index] if source_run_index < run_colors.size() else TextBlockStore.COLOR_TEXT)

			line_offsets.append(output_lines.size())
			line_counts.append(wrapped_lines.size())
			output_lines.append_array(wrapped_lines)
			output_line_starts.append_array(wrapped.get("starts", PackedInt32Array()) as PackedInt32Array)
			output_line_lengths.append_array(wrapped.get("lengths", PackedInt32Array()) as PackedInt32Array)
			output_line_prefixes.append_array(wrapped.get("prefixes", PackedStringArray()) as PackedStringArray)
			output_line_indents.append_array(wrapped.get("indents", PackedFloat32Array()) as PackedFloat32Array)
			text_count += 1

	return {
		"entity_ids": output_ids,
		"rect_values": output_rects,
		"background_colors": output_backgrounds,
		"text_entity_ids": text_entity_ids,
		"text_rects": text_rects,
		"text_font_sizes": text_font_sizes,
		"text_font_families": text_font_families,
		"text_alignments": text_alignments,
		"text_colors": output_text_colors,
		"text_base_style_flags": output_base_style_flags,
		"text_run_offsets": text_run_offsets,
		"text_run_counts": text_run_counts,
		"run_starts": output_run_starts,
		"run_lengths": output_run_lengths,
		"run_flags": output_run_flags,
		"run_colors": output_run_colors,
		"line_offsets": line_offsets,
		"line_counts": line_counts,
		"lines": output_lines,
		"line_starts": output_line_starts,
		"line_lengths": output_line_lengths,
		"line_prefixes": output_line_prefixes,
		"line_indents": output_line_indents,
		"rect_count": count,
		"text_count": text_count,
		"text_skipped": maxi(0, count - text_count),
		"lod": lod,
		"source_revisions": revisions,
		"signature": str(job.get("signature", "")),
	}


func _run_slice(
	index: int,
	offsets: PackedInt32Array,
	counts: PackedInt32Array,
	starts: PackedInt32Array,
	lengths: PackedInt32Array,
	flags: PackedInt32Array,
	colors: PackedColorArray
) -> Array:
	var result: Array = []
	var offset: int = int(offsets[index]) if index < offsets.size() else 0
	var count: int = int(counts[index]) if index < counts.size() else 0
	for local_index: int in range(count):
		var source_index: int = offset + local_index
		if source_index < 0 or source_index >= starts.size():
			continue
		result.append({
			"start": int(starts[source_index]),
			"length": int(lengths[source_index]) if source_index < lengths.size() else 0,
			"flags": int(flags[source_index]) if source_index < flags.size() else 0,
			"color": (colors[source_index] if source_index < colors.size() else TextBlockStore.COLOR_TEXT).to_html(true),
		})
	return result


func _paragraph_slice(
	index: int,
	offsets: PackedInt32Array,
	counts: PackedInt32Array,
	types: PackedInt32Array,
	indents: PackedInt32Array
) -> Array:
	var result: Array = []
	var offset: int = int(offsets[index]) if index < offsets.size() else 0
	var count: int = int(counts[index]) if index < counts.size() else 0
	for local_index: int in range(count):
		var source_index: int = offset + local_index
		if source_index < 0 or source_index >= types.size():
			continue
		result.append({
			"list_type": int(types[source_index]),
			"indent": int(indents[source_index]) if source_index < indents.size() else 0,
		})
	return result


func _font_size_for_lod(source_font_size: float, lod: int) -> float:
	match lod:
		int(BoardRenderPolicy.LodLevel.MEDIUM):
			return maxf(14.0, source_font_size)
		int(BoardRenderPolicy.LodLevel.LOW):
			return maxf(16.0, source_font_size * 0.88)
		_:
			return source_font_size


func _line_limit_for_rect(
	height: float,
	font_size: float,
	background: Color,
	lod: int,
	maximum_lines: int
) -> int:
	var padding: Vector2 = TextLayoutUtils.padding_for_background(background)
	var available_height: float = maxf(0.0, height - padding.y * 2.0)
	var fit: int = int(floor(available_height / TextLayoutUtils.line_height(font_size)))
	match lod:
		int(BoardRenderPolicy.LodLevel.MEDIUM):
			fit = mini(fit, 5)
		int(BoardRenderPolicy.LodLevel.LOW):
			fit = mini(fit, 2)
	return clampi(fit, 0, maximum_lines)
