# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteBoardPreviewExtractor
extends RefCounted

const MAX_RUNS: int = 192
const MAX_TOTAL_CHARACTERS: int = 12000
const MAX_CODE_LINES: int = 18
const MAX_TABLE_ROWS: int = 12
const MAX_TABLE_COLUMNS: int = 8


static func extract(markdown: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var total_characters: int = 0
	var blocks: Array[Dictionary] = NoteMarkdownBlocks.parse(markdown)
	for block: Dictionary in blocks:
		if output.size() >= MAX_RUNS or total_characters >= MAX_TOTAL_CHARACTERS:
			break
		var kind: StringName = StringName(str(block.get("type", NoteMarkdownBlocks.TYPE_PARAGRAPH)))
		if kind == NoteMarkdownBlocks.TYPE_FRONTMATTER:
			continue
		if kind == NoteMarkdownBlocks.TYPE_RULE:
			output.append({"kind": "rule"})
			continue
		if kind == NoteMarkdownBlocks.TYPE_HEADING:
			var heading_text: String = _heading_text(block)
			total_characters += heading_text.length()
			output.append({"kind": "heading", "text": heading_text, "level": clampi(int(block.get("level", 1)), 1, 6)})
			continue
		if kind == NoteMarkdownBlocks.TYPE_CODE:
			var code: Dictionary = _code_run(block)
			total_characters += str(code.get("text", "")).length()
			output.append(code)
			continue
		if kind == NoteMarkdownBlocks.TYPE_MATH:
			var math_text: String = _math_source(str(block.get("raw", "")))
			total_characters += math_text.length()
			output.append({"kind": "math", "text": math_text.left(640)})
			continue
		if kind == NoteMarkdownBlocks.TYPE_EMBED:
			var embed: Dictionary = NoteResourceEmbed.parse_exact(str(block.get("raw", "")))
			if not embed.is_empty():
				var caption: String = str(embed.get("caption", "")).strip_edges()
				var hash_sha256: String = str(embed.get("hash_sha256", ""))
				var visible: String = caption if not caption.is_empty() else NotLightL10n.text("ui.format.hash_short") % hash_sha256.left(12)
				total_characters += visible.length()
				output.append({"kind": "embed", "text": visible, "hash_sha256": hash_sha256})
			continue
		if kind == NoteMarkdownBlocks.TYPE_MODULE_EMBED:
			var module_embed: Dictionary = NoteModuleEmbed.parse_exact(str(block.get("raw", "")))
			if not module_embed.is_empty():
				var module_caption: String = str(module_embed.get("caption", "")).strip_edges()
				var module_id: String = str(module_embed.get("module_id", ""))
				var module_visible: String = module_caption if not module_caption.is_empty() else module_id
				total_characters += module_visible.length()
				output.append({"kind": "embed", "text": module_visible, "module_id": module_id})
			continue
		if kind == NoteMarkdownBlocks.TYPE_TASKS:
			for run: Dictionary in _task_runs(block):
				if output.size() >= MAX_RUNS:
					break
				total_characters += str(run.get("text", "")).length()
				output.append(run)
			continue
		if kind == NoteMarkdownBlocks.TYPE_LIST:
			for run: Dictionary in _list_runs(block):
				if output.size() >= MAX_RUNS:
					break
				total_characters += str(run.get("text", "")).length()
				output.append(run)
			continue
		if kind == NoteMarkdownBlocks.TYPE_TABLE:
			var table: Dictionary = _table_run(block)
			total_characters += int(table.get("characters", 0))
			output.append(table)
			continue
		if kind == NoteMarkdownBlocks.TYPE_QUOTE:
			var quote_run: Dictionary = _quote_run(block)
			var quote_text: String = str(quote_run.get("text", ""))
			if not quote_text.is_empty():
				total_characters += quote_text.length()
				output.append(quote_run)
			continue
		var text: String = _plain_inline(str(block.get("raw", "")).strip_edges())
		if text.is_empty():
			continue
		total_characters += text.length()
		output.append({"kind": "paragraph", "text": text})
	return output


static func _quote_run(block: Dictionary) -> Dictionary:
	var lines: PackedStringArray = str(block.get("raw", "")).replace("\r\n", "\n").split("\n", false)
	var clean_lines: PackedStringArray = PackedStringArray()
	for raw_line: String in lines:
		var line: String = raw_line.strip_edges()
		if line.begins_with(">"):
			line = line.substr(1).strip_edges()
		clean_lines.append(line)
	var callout_type: String = ""
	var callout_title: String = ""
	if not clean_lines.is_empty():
		var first: String = clean_lines[0]
		if first.begins_with("[!") and first.contains("]"):
			var close: int = first.find("]")
			callout_type = first.substr(2, maxi(0, close - 2)).strip_edges().to_upper()
			callout_title = first.substr(close + 1).strip_edges()
			clean_lines.remove_at(0)
	var body: String = _plain_inline("\n".join(clean_lines).strip_edges())
	if not callout_type.is_empty():
		return {
			"kind": "callout",
			"callout_type": callout_type,
			"title": callout_title if not callout_title.is_empty() else callout_type,
			"text": body,
		}
	return {"kind": "quote", "text": body}


static func _heading_text(block: Dictionary) -> String:
	var raw: String = str(block.get("raw", "")).strip_edges()
	var level: int = clampi(int(block.get("level", 1)), 1, 6)
	var prefix_length: int = mini(raw.length(), level + 1)
	return _plain_inline(raw.substr(prefix_length).strip_edges())


static func _code_run(block: Dictionary) -> Dictionary:
	var raw: String = str(block.get("raw", "")).replace("\r\n", "\n")
	var lines: PackedStringArray = raw.split("\n", true)
	var opening: String = lines[0].strip_edges() if not lines.is_empty() else "```"
	var fence: String = "~~~" if opening.begins_with("~~~") else "```"
	var language: String = opening.trim_prefix(fence).strip_edges().left(40)
	var content: PackedStringArray = PackedStringArray()
	var end_index: int = lines.size()
	if end_index > 1 and lines[end_index - 1].strip_edges().begins_with(fence):
		end_index -= 1
	for index: int in range(1, mini(end_index, MAX_CODE_LINES + 1)):
		content.append(lines[index].left(220))
	return {"kind": "code", "language": language, "text": "\n".join(content)}


static func _math_source(raw: String) -> String:
	var clean: String = raw.strip_edges()
	if clean.begins_with("$$"):
		clean = clean.substr(2)
	if clean.ends_with("$$"):
		clean = clean.substr(0, maxi(0, clean.length() - 2))
	return clean.strip_edges()


static func _task_runs(block: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for raw_line: String in str(block.get("raw", "")).replace("\r\n", "\n").split("\n", false):
		var line: String = raw_line.strip_edges()
		if line.length() < 6:
			continue
		var bracket: int = line.find("[")
		var close: int = line.find("]", bracket + 1)
		if bracket < 0 or close < 0:
			continue
		var checked: bool = line.substr(bracket + 1, 1).to_lower() == "x"
		output.append({"kind": "task", "checked": checked, "text": _plain_inline(line.substr(close + 1).strip_edges())})
	return output


static func _list_runs(block: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for raw_line: String in str(block.get("raw", "")).replace("\r\n", "\n").split("\n", false):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		var separator: int = line.find(" ")
		if separator <= 0:
			continue
		var marker: String = line.substr(0, separator)
		var text: String = _plain_inline(line.substr(separator + 1).strip_edges())
		output.append({"kind": "list", "marker": marker if marker.ends_with(".") else "•", "text": text})
	return output


static func _table_run(block: Dictionary) -> Dictionary:
	var rows: Array = []
	var characters: int = 0
	var lines: PackedStringArray = str(block.get("raw", "")).replace("\r\n", "\n").split("\n", false)
	for line_index: int in range(lines.size()):
		if line_index == 1:
			continue
		if rows.size() >= MAX_TABLE_ROWS:
			break
		var cells: PackedStringArray = lines[line_index].strip_edges().trim_prefix("|").trim_suffix("|").split("|", true)
		var bounded: PackedStringArray = PackedStringArray()
		for column: int in range(mini(cells.size(), MAX_TABLE_COLUMNS)):
			var text: String = _plain_inline(cells[column].strip_edges()).left(90)
			characters += text.length()
			bounded.append(text)
		rows.append(bounded)
	return {"kind": "table", "rows": rows, "characters": characters}


static func _plain_inline(value: String) -> String:
	var text: String = value.replace("\r", "")
	var output: String = ""
	var index: int = 0
	while index < text.length():
		if text.substr(index, 2) == "[[":
			var end: int = text.find("]]", index + 2)
			if end >= 0:
				var raw: String = text.substr(index + 2, end - index - 2)
				var pipe: int = raw.find("|")
				output += (raw if pipe < 0 else raw.substr(pipe + 1)).strip_edges()
				index = end + 2
				continue
		if text.substr(index, 1) == "[":
			var label_end: int = text.find("](", index + 1)
			if label_end >= 0:
				var url_end: int = text.find(")", label_end + 2)
				if url_end >= 0:
					output += text.substr(index + 1, label_end - index - 1)
					index = url_end + 1
					continue
		var character: String = text.substr(index, 1)
		if character != "*" and character != "_" and character != "`" and character != "~" and character != "=":
			output += character
		index += 1
	return output.strip_edges()
