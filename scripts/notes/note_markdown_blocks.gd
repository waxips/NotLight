# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteMarkdownBlocks
extends RefCounted

const TYPE_PARAGRAPH: StringName = &"paragraph"
const TYPE_FRONTMATTER: StringName = &"frontmatter"
const TYPE_HEADING: StringName = &"heading"
const TYPE_CODE: StringName = &"code"
const TYPE_MATH: StringName = &"math"
const TYPE_EMBED: StringName = &"embed"
const TYPE_MODULE_EMBED: StringName = &"module_embed"
const TYPE_TASKS: StringName = &"tasks"
const TYPE_LIST: StringName = &"list"
const TYPE_QUOTE: StringName = &"quote"
const TYPE_TABLE: StringName = &"table"
const TYPE_RULE: StringName = &"rule"
const MAX_BLOCKS: int = 4096


static func parse(markdown: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lines: Array[Dictionary] = _lines_with_offsets(markdown)
	var index: int = 0
	while index < lines.size() and result.size() < MAX_BLOCKS:
		var line: Dictionary = lines[index]
		var text: String = str(line.get("text", ""))
		if index == 0 and text.strip_edges() == "---":
			var frontmatter_end: int = _frontmatter_end(lines)
			if frontmatter_end > 1:
				result.append(_block(markdown, lines, 0, frontmatter_end, TYPE_FRONTMATTER))
				index = frontmatter_end
				continue
		if text.strip_edges().is_empty():
			index += 1
			continue
		if not NoteResourceEmbed.parse_exact(text).is_empty():
			result.append(_block(markdown, lines, index, index + 1, TYPE_EMBED))
			index += 1
			continue
		if not NoteModuleEmbed.parse_exact(text).is_empty():
			result.append(_block(markdown, lines, index, index + 1, TYPE_MODULE_EMBED))
			index += 1
			continue
		if _is_math_start(text):
			var math_end: int = _math_block_end(lines, index)
			result.append(_block(markdown, lines, index, math_end, TYPE_MATH))
			index = math_end
			continue
		var fence: String = _fence_marker(text)
		if not fence.is_empty():
			var end_index: int = index + 1
			while end_index < lines.size():
				if _fence_marker(str(lines[end_index].get("text", ""))) == fence:
					end_index += 1
					break
				end_index += 1
			result.append(_block(markdown, lines, index, mini(end_index, lines.size()), TYPE_CODE))
			index = mini(end_index, lines.size())
			continue
		if _heading_level(text) > 0:
			var heading: Dictionary = _block(markdown, lines, index, index + 1, TYPE_HEADING)
			heading["level"] = _heading_level(text)
			result.append(heading)
			index += 1
			continue
		if _is_rule(text):
			result.append(_block(markdown, lines, index, index + 1, TYPE_RULE))
			index += 1
			continue
		if _is_table_start(lines, index):
			var table_end: int = index + 2
			while table_end < lines.size() and str(lines[table_end].get("text", "")).contains("|") and not str(lines[table_end].get("text", "")).strip_edges().is_empty():
				table_end += 1
			result.append(_block(markdown, lines, index, table_end, TYPE_TABLE))
			index = table_end
			continue
		if _is_task_line(text):
			var task_end: int = index + 1
			while task_end < lines.size() and _is_task_line(str(lines[task_end].get("text", ""))):
				task_end += 1
			result.append(_block(markdown, lines, index, task_end, TYPE_TASKS))
			index = task_end
			continue
		if _is_list_line(text):
			var list_end: int = index + 1
			while list_end < lines.size() and _is_list_line(str(lines[list_end].get("text", ""))):
				list_end += 1
			result.append(_block(markdown, lines, index, list_end, TYPE_LIST))
			index = list_end
			continue
		if text.strip_edges().begins_with(">"):
			var quote_end: int = index + 1
			while quote_end < lines.size() and str(lines[quote_end].get("text", "")).strip_edges().begins_with(">"):
				quote_end += 1
			result.append(_block(markdown, lines, index, quote_end, TYPE_QUOTE))
			index = quote_end
			continue
		var paragraph_end: int = index + 1
		while paragraph_end < lines.size():
			var next_text: String = str(lines[paragraph_end].get("text", ""))
			if next_text.strip_edges().is_empty() or _starts_block(lines, paragraph_end):
				break
			paragraph_end += 1
		result.append(_block(markdown, lines, index, paragraph_end, TYPE_PARAGRAPH))
		index = paragraph_end
	return result


static func _lines_with_offsets(markdown: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start: int = 0
	while start < markdown.length():
		var newline: int = markdown.find("\n", start)
		var finish: int = markdown.length() if newline < 0 else newline + 1
		var visible_end: int = finish
		if visible_end > start and markdown.substr(visible_end - 1, 1) == "\n":
			visible_end -= 1
		if visible_end > start and markdown.substr(visible_end - 1, 1) == "\r":
			visible_end -= 1
		result.append({"start": start, "end": finish, "text": markdown.substr(start, visible_end - start)})
		start = finish
	if markdown.is_empty():
		return result
	if markdown.ends_with("\n"):
		result.append({"start": markdown.length(), "end": markdown.length(), "text": ""})
	return result


static func _block(markdown: String, lines: Array[Dictionary], start_line: int, end_line_exclusive: int, type_name: StringName) -> Dictionary:
	var start: int = int(lines[start_line].get("start", 0))
	var end: int = markdown.length()
	if end_line_exclusive > 0 and end_line_exclusive <= lines.size():
		end = int(lines[end_line_exclusive - 1].get("end", markdown.length()))
	return {
		"type": type_name,
		"start": start,
		"end": end,
		"raw": markdown.substr(start, maxi(0, end - start)),
		"line_start": start_line,
		"line_count": maxi(1, end_line_exclusive - start_line),
	}


static func _starts_block(lines: Array[Dictionary], index: int) -> bool:
	var text: String = str(lines[index].get("text", ""))
	return (
		not NoteResourceEmbed.parse_exact(text).is_empty()
		or not NoteModuleEmbed.parse_exact(text).is_empty()
		or _is_math_start(text)
		or not _fence_marker(text).is_empty()
		or _heading_level(text) > 0
		or _is_rule(text)
		or _is_table_start(lines, index)
		or _is_task_line(text)
		or _is_list_line(text)
		or text.strip_edges().begins_with(">")
	)


static func _is_math_start(text: String) -> bool:
	var clean: String = text.strip_edges()
	return clean.begins_with("$$")


static func _math_block_end(lines: Array[Dictionary], start_index: int) -> int:
	var first: String = str(lines[start_index].get("text", "")).strip_edges()
	if first.length() > 4 and first.ends_with("$$"):
		return start_index + 1
	for index: int in range(start_index + 1, lines.size()):
		if str(lines[index].get("text", "")).strip_edges().ends_with("$$"):
			return index + 1
	return lines.size()


static func _fence_marker(text: String) -> String:
	var clean: String = text.strip_edges()
	if clean.begins_with("```"):
		return "```"
	if clean.begins_with("~~~"):
		return "~~~"
	return ""


static func _heading_level(text: String) -> int:
	var clean: String = text.strip_edges()
	var count: int = 0
	while count < clean.length() and count < 6 and clean.substr(count, 1) == "#":
		count += 1
	if count <= 0 or count >= clean.length() or clean.substr(count, 1) != " ":
		return 0
	return count


static func _is_rule(text: String) -> bool:
	var clean: String = text.strip_edges().replace(" ", "")
	return clean == "---" or clean == "***" or clean == "___"


static func _is_task_line(text: String) -> bool:
	var clean: String = text.strip_edges()
	if clean.length() < 6:
		return false
	return (clean.begins_with("- [") or clean.begins_with("* [") or clean.begins_with("+ [")) and clean.substr(4, 1) == "]"


static func _is_list_line(text: String) -> bool:
	var clean: String = text.strip_edges()
	if clean.begins_with("- ") or clean.begins_with("* ") or clean.begins_with("+ "):
		return true
	var dot: int = clean.find(". ")
	if dot <= 0 or dot > 8:
		return false
	return clean.substr(0, dot).is_valid_int()


static func _is_table_start(lines: Array[Dictionary], index: int) -> bool:
	if index + 1 >= lines.size():
		return false
	var header: String = str(lines[index].get("text", ""))
	var separator: String = str(lines[index + 1].get("text", "")).strip_edges()
	if not header.contains("|") or not separator.contains("-") or not separator.contains("|"):
		return false
	var cells: PackedStringArray = separator.trim_prefix("|").trim_suffix("|").split("|", false)
	if cells.is_empty():
		return false
	for cell: String in cells:
		var clean: String = cell.strip_edges().trim_prefix(":").trim_suffix(":")
		if clean.length() < 3:
			return false
		for character: String in clean:
			if character != "-":
				return false
	return true

static func _frontmatter_end(lines: Array[Dictionary]) -> int:
	if lines.size() < 2 or str(lines[0].get("text", "")).strip_edges() != "---":
		return -1
	for index: int in range(1, lines.size()):
		var clean: String = str(lines[index].get("text", "")).strip_edges()
		if clean == "---" or clean == "...":
			return index + 1
	return -1

