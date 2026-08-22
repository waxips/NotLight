# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteLinkParser
extends RefCounted

# Lightweight relation extractor, intentionally independent from the preview
# renderer. It ignores fenced/inline code and escaped opening brackets so graph
# semantics do not accidentally treat code samples as knowledge links.
const MAX_LINKS_PER_NOTE: int = 4096
const MAX_TARGET_LENGTH: int = 240


static func extract_wikilink_targets(markdown: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var index: int = 0
	var in_fence: bool = false
	var fence_marker: String = ""
	var inline_ticks: int = 0
	while index < markdown.length() and result.size() < MAX_LINKS_PER_NOTE:
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
		if markdown.substr(index, 2) == "[[" and not _is_escaped(markdown, index) and not (index > 0 and markdown.substr(index - 1, 1) == "!"):
			var close_index: int = markdown.find("]]", index + 2)
			if close_index < 0:
				break
			var raw_target: String = markdown.substr(index + 2, close_index - index - 2)
			var separator: int = raw_target.find("|")
			if separator >= 0:
				raw_target = raw_target.substr(0, separator)
			var anchor: int = raw_target.find("#")
			if anchor >= 0:
				raw_target = raw_target.substr(0, anchor)
			var target: String = raw_target.strip_edges().left(MAX_TARGET_LENGTH)
			var normalized: String = normalize_title(target)
			if not normalized.is_empty() and not seen.has(normalized):
				seen[normalized] = true
				result.append(target)
			index = close_index + 2
			continue
		index += 1
	return result


static func normalize_title(title: String) -> String:
	var clean: String = title.replace("\\", "/").strip_edges()
	while clean.contains("//"):
		clean = clean.replace("//", "/")
	if clean.to_lower().ends_with(".md"):
		clean = clean.left(clean.length() - 3)
	return clean.strip_edges().to_lower()


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
