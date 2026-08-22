# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteModuleEmbed
extends RefCounted

# Canonical runtime-only Notes module embed syntax.
#
#   ![[module:notlight.stereometry]]
#   ![[module:notlight.stereometry|Стереометрия]]
#
# The canonical Markdown stores only the stable module_id plus an optional
# presentation caption. Module executable payloads are never embedded into Notes,
# and instance state is intentionally ephemeral in this first implementation.
const PREFIX: String = "![[module:"
const SUFFIX: String = "]]"
const MAX_EMBEDS_PER_NOTE: int = 256
const MAX_CAPTION_LENGTH: int = 240


static func syntax_for_module(module_id: String, caption: String = "") -> String:
	var clean_id: String = module_id.strip_edges().to_lower()
	if not ModuleManifest.is_valid_module_id(clean_id):
		return ""
	var clean_caption: String = caption.replace("\r", " ").replace("\n", " ").replace("|", " ").replace("[", "(").replace("]", ")").strip_edges().left(MAX_CAPTION_LENGTH)
	if clean_caption.is_empty():
		return "%s%s%s" % [PREFIX, clean_id, SUFFIX]
	return "%s%s|%s%s" % [PREFIX, clean_id, clean_caption, SUFFIX]


static func parse_exact(text: String) -> Dictionary:
	var clean: String = text.strip_edges()
	if not clean.begins_with(PREFIX) or not clean.ends_with(SUFFIX):
		return {}
	var body: String = clean.substr(PREFIX.length(), clean.length() - PREFIX.length() - SUFFIX.length())
	var separator: int = body.find("|")
	var module_id: String = body if separator < 0 else body.substr(0, separator)
	var caption: String = "" if separator < 0 else body.substr(separator + 1)
	module_id = module_id.strip_edges().to_lower()
	caption = caption.strip_edges().left(MAX_CAPTION_LENGTH)
	if not ModuleManifest.is_valid_module_id(module_id):
		return {}
	return {
		"module_id": module_id,
		"caption": caption,
	}


static func extract_module_ids(markdown: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var index: int = 0
	var in_fence: bool = false
	var fence_marker: String = ""
	var inline_ticks: int = 0
	while index < markdown.length() and result.size() < MAX_EMBEDS_PER_NOTE:
		if _at_line_start(markdown, index):
			var fence: String = _fence_at(markdown, index)
			if not fence.is_empty():
				if not in_fence:
					in_fence = true
					fence_marker = fence
				elif fence == fence_marker:
					in_fence = false
					fence_marker = ""
				index = _line_end(markdown, index)
				continue
		if in_fence:
			index += 1
			continue
		var character: String = markdown.substr(index, 1)
		if character == "`":
			var ticks: int = _count_run(markdown, index, "`")
			if inline_ticks == 0:
				inline_ticks = ticks
			elif ticks == inline_ticks:
				inline_ticks = 0
			index += ticks
			continue
		if inline_ticks > 0:
			index += 1
			continue
		if markdown.substr(index, PREFIX.length()) == PREFIX and not _is_escaped(markdown, index):
			var close_index: int = markdown.find(SUFFIX, index + PREFIX.length())
			if close_index < 0:
				break
			var raw: String = markdown.substr(index, close_index + SUFFIX.length() - index)
			var parsed: Dictionary = parse_exact(raw)
			var module_id: String = str(parsed.get("module_id", ""))
			if not module_id.is_empty() and not seen.has(module_id):
				seen[module_id] = true
				result.append(module_id)
			index = close_index + SUFFIX.length()
			continue
		index += 1
	return result


static func _at_line_start(text: String, index: int) -> bool:
	return index == 0 or text.substr(index - 1, 1) == "\n"


static func _fence_at(text: String, index: int) -> String:
	var cursor: int = index
	while cursor < text.length() and (text.substr(cursor, 1) == " " or text.substr(cursor, 1) == "\t"):
		cursor += 1
	var backticks: int = _count_run(text, cursor, "`")
	if backticks >= 3:
		return "`".repeat(backticks)
	var tildes: int = _count_run(text, cursor, "~")
	if tildes >= 3:
		return "~".repeat(tildes)
	return ""


static func _count_run(text: String, index: int, marker: String) -> int:
	var count: int = 0
	while index + count < text.length() and text.substr(index + count, 1) == marker:
		count += 1
	return count


static func _line_end(text: String, index: int) -> int:
	var newline: int = text.find("\n", index)
	return text.length() if newline < 0 else newline + 1


static func _is_escaped(text: String, index: int) -> bool:
	var slash_count: int = 0
	var cursor: int = index - 1
	while cursor >= 0 and text.substr(cursor, 1) == "\\":
		slash_count += 1
		cursor -= 1
	return slash_count % 2 == 1
