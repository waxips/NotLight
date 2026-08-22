# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteInlineMarkup
extends RefCounted

const MAX_RECURSION_DEPTH: int = 8


static func to_bbcode(text: String, depth: int = 0) -> String:
	if depth >= MAX_RECURSION_DEPTH:
		return escape_bbcode(text)
	var output: String = ""
	var buffer: String = ""
	var index: int = 0
	while index < text.length():
		if text.substr(index, 1) == "\\" and index + 1 < text.length():
			buffer += text.substr(index + 1, 1)
			index += 2
			continue
		if text.substr(index, NoteResourceEmbed.PREFIX.length()) == NoteResourceEmbed.PREFIX:
			var embed_end: int = text.find(NoteResourceEmbed.SUFFIX, index + NoteResourceEmbed.PREFIX.length())
			if embed_end >= 0:
				var embed_raw: String = text.substr(index, embed_end + NoteResourceEmbed.SUFFIX.length() - index)
				var embed: Dictionary = NoteResourceEmbed.parse_exact(embed_raw)
				if not embed.is_empty():
					output += escape_bbcode(buffer)
					buffer = ""
					var caption: String = str(embed.get("caption", "")).strip_edges()
					if caption.is_empty():
						caption = NotLightL10n.text("notes.embed.inline_placeholder")
					output += "[color=%s]%s[/color]" % [NotLightTheme.semantic_color("text_muted").to_html(false), escape_bbcode(caption)]
					index = embed_end + NoteResourceEmbed.SUFFIX.length()
					continue
		if text.substr(index, NoteModuleEmbed.PREFIX.length()) == NoteModuleEmbed.PREFIX:
			var module_end: int = text.find(NoteModuleEmbed.SUFFIX, index + NoteModuleEmbed.PREFIX.length())
			if module_end >= 0:
				var module_raw: String = text.substr(index, module_end + NoteModuleEmbed.SUFFIX.length() - index)
				var module_embed: Dictionary = NoteModuleEmbed.parse_exact(module_raw)
				if not module_embed.is_empty():
					output += escape_bbcode(buffer)
					buffer = ""
					var module_caption: String = str(module_embed.get("caption", "")).strip_edges()
					if module_caption.is_empty():
						module_caption = NotLightL10n.text("notes.module_embed.inline_placeholder")
					output += "[color=%s]%s[/color]" % [NotLightTheme.semantic_color("text_muted").to_html(false), escape_bbcode(module_caption)]
					index = module_end + NoteModuleEmbed.SUFFIX.length()
					continue
		if text.substr(index, 1) == "[" and text.substr(index, 2) != "[[" and not (index > 0 and text.substr(index - 1, 1) == "!"):
			var label_end: int = _find_unescaped(text, "](", index + 1)
			if label_end > index + 1:
				var target_end: int = _find_unescaped(text, ")", label_end + 2)
				if target_end > label_end + 2:
					var link_label: String = text.substr(index + 1, label_end - index - 1)
					var link_target: String = text.substr(label_end + 2, target_end - label_end - 2).strip_edges()
					if _is_safe_external_target(link_target):
						output += escape_bbcode(buffer)
						buffer = ""
						output += "[url=external://%s][color=%s]%s[/color][/url]" % [
							link_target.uri_encode(),
							NotLightTheme.semantic_color("accent").to_html(false),
							to_bbcode(link_label, depth + 1),
						]
						index = target_end + 1
						continue
		if text.substr(index, 2) == "[[":
			var wiki_end: int = text.find("]]", index + 2)
			if wiki_end >= 0:
				output += escape_bbcode(buffer)
				buffer = ""
				var raw: String = text.substr(index + 2, wiki_end - index - 2).strip_edges()
				var pipe: int = raw.find("|")
				var target: String = raw if pipe < 0 else raw.substr(0, pipe).strip_edges()
				var label: String = target if pipe < 0 else raw.substr(pipe + 1).strip_edges()
				if label.is_empty() and pipe >= 0:
					label = target
				if not target.is_empty():
					# Wiki labels are a literal namespace, not nested Markdown. Rendering
					# the complete visible label as italic keeps underscores, stars and
					# other title characters intact while giving wiki-links one identity.
					output += "[url=note://%s][color=%s][i]%s[/i][/color][/url]" % [
						target.uri_encode(),
						NotLightTheme.semantic_color("accent").to_html(false),
						escape_bbcode(label),
					]
				else:
					output += escape_bbcode(text.substr(index, wiki_end + 2 - index))
				index = wiki_end + 2
				continue
		if text.substr(index, 3) == "***" or text.substr(index, 3) == "___":
			var combined_delimiter: String = text.substr(index, 3)
			var combined_end: int = _find_unescaped(text, combined_delimiter, index + 3)
			if combined_end >= 0:
				output += escape_bbcode(buffer)
				buffer = ""
				output += "[b][i]%s[/i][/b]" % to_bbcode(text.substr(index + 3, combined_end - index - 3), depth + 1)
				index = combined_end + 3
				continue
		if text.substr(index, 2) == "**" or text.substr(index, 2) == "__":
			var delimiter: String = text.substr(index, 2)
			var strong_end: int = _find_strong_end(text, delimiter, index + 2)
			if strong_end >= 0:
				output += escape_bbcode(buffer)
				buffer = ""
				output += "[b]%s[/b]" % to_bbcode(text.substr(index + 2, strong_end - index - 2), depth + 1)
				index = strong_end + 2
				continue
		if text.substr(index, 2) == "~~":
			var strike_end: int = _find_unescaped(text, "~~", index + 2)
			if strike_end >= 0:
				output += escape_bbcode(buffer)
				buffer = ""
				output += "[s]%s[/s]" % to_bbcode(text.substr(index + 2, strike_end - index - 2), depth + 1)
				index = strike_end + 2
				continue
		if text.substr(index, 2) == "==":
			var highlight_end: int = _find_unescaped(text, "==", index + 2)
			if highlight_end >= 0:
				output += escape_bbcode(buffer)
				buffer = ""
				output += "[bgcolor=%s]%s[/bgcolor]" % [
					NotLightTheme.semantic_color("warning_soft").to_html(false),
					to_bbcode(text.substr(index + 2, highlight_end - index - 2), depth + 1),
				]
				index = highlight_end + 2
				continue
		if text.substr(index, 1) == "`":
			var code_end: int = _find_unescaped(text, "`", index + 1)
			if code_end >= 0:
				output += escape_bbcode(buffer)
				buffer = ""
				output += "[bgcolor=%s][code]%s[/code][/bgcolor]" % [
					NotLightTheme.semantic_color("surface_alt").to_html(false),
					escape_bbcode(text.substr(index + 1, code_end - index - 1)),
				]
				index = code_end + 1
				continue
		var marker: String = text.substr(index, 1)
		if (marker == "*" or marker == "_") and _is_single_emphasis_opener(text, index, marker):
			var emphasis_end: int = _find_single_emphasis_end(text, marker, index + 1)
			if emphasis_end > index + 1:
				output += escape_bbcode(buffer)
				buffer = ""
				output += "[i]%s[/i]" % to_bbcode(text.substr(index + 1, emphasis_end - index - 1), depth + 1)
				index = emphasis_end + 1
				continue
		buffer += marker
		index += 1
	output += escape_bbcode(buffer)
	return output


static func escape_bbcode(value: String) -> String:
	var output: String = ""
	for character: String in value:
		if character == "[":
			output += "[lb]"
		elif character == "]":
			output += "[rb]"
		else:
			output += character
	return output


static func strip_markup(text: String, depth: int = 0) -> String:
	# Produce presentation-only plain text from exactly the inline constructs that
	# this renderer understands. Do not strip arbitrary bracket pairs from the
	# source: literal Markdown must remain literal when a construct is unsupported.
	if depth >= MAX_RECURSION_DEPTH:
		return text
	var output: String = ""
	var index: int = 0
	while index < text.length():
		if text.substr(index, 1) == "\\" and index + 1 < text.length():
			output += text.substr(index + 1, 1)
			index += 2
			continue
		if text.substr(index, NoteResourceEmbed.PREFIX.length()) == NoteResourceEmbed.PREFIX:
			var embed_end: int = text.find(NoteResourceEmbed.SUFFIX, index + NoteResourceEmbed.PREFIX.length())
			if embed_end >= 0:
				var embed_raw: String = text.substr(index, embed_end + NoteResourceEmbed.SUFFIX.length() - index)
				var embed: Dictionary = NoteResourceEmbed.parse_exact(embed_raw)
				if not embed.is_empty():
					var caption: String = str(embed.get("caption", "")).strip_edges()
					output += caption if not caption.is_empty() else NotLightL10n.text("notes.embed.inline_placeholder")
					index = embed_end + NoteResourceEmbed.SUFFIX.length()
					continue
		if text.substr(index, NoteModuleEmbed.PREFIX.length()) == NoteModuleEmbed.PREFIX:
			var module_end: int = text.find(NoteModuleEmbed.SUFFIX, index + NoteModuleEmbed.PREFIX.length())
			if module_end >= 0:
				var module_raw: String = text.substr(index, module_end + NoteModuleEmbed.SUFFIX.length() - index)
				var module_embed: Dictionary = NoteModuleEmbed.parse_exact(module_raw)
				if not module_embed.is_empty():
					var module_caption: String = str(module_embed.get("caption", "")).strip_edges()
					output += module_caption if not module_caption.is_empty() else NotLightL10n.text("notes.module_embed.inline_placeholder")
					index = module_end + NoteModuleEmbed.SUFFIX.length()
					continue
		if text.substr(index, 2) == "[[":
			var wiki_end: int = text.find("]]", index + 2)
			if wiki_end >= 0:
				var raw: String = text.substr(index + 2, wiki_end - index - 2).strip_edges()
				var pipe: int = raw.find("|")
				var visible: String = raw if pipe < 0 else raw.substr(pipe + 1).strip_edges()
				if visible.is_empty() and pipe >= 0:
					visible = raw.substr(0, pipe).strip_edges()
				output += visible
				index = wiki_end + 2
				continue
		if text.substr(index, 1) == "[" and text.substr(index, 2) != "[[" and not (index > 0 and text.substr(index - 1, 1) == "!"):
			var label_end: int = _find_unescaped(text, "](", index + 1)
			if label_end > index + 1:
				var target_end: int = _find_unescaped(text, ")", label_end + 2)
				if target_end > label_end + 2:
					var target: String = text.substr(label_end + 2, target_end - label_end - 2).strip_edges()
					if _is_safe_external_target(target):
						output += strip_markup(text.substr(index + 1, label_end - index - 1), depth + 1)
						index = target_end + 1
						continue
		var triple: String = text.substr(index, 3)
		if triple == "***" or triple == "___":
			var triple_end: int = _find_unescaped(text, triple, index + 3)
			if triple_end >= 0:
				output += strip_markup(text.substr(index + 3, triple_end - index - 3), depth + 1)
				index = triple_end + 3
				continue
		var pair: String = text.substr(index, 2)
		if pair == "**" or pair == "__" or pair == "~~" or pair == "==":
			var pair_end: int = _find_strong_end(text, pair, index + 2) if pair == "**" or pair == "__" else _find_unescaped(text, pair, index + 2)
			if pair_end >= 0:
				output += strip_markup(text.substr(index + 2, pair_end - index - 2), depth + 1)
				index = pair_end + 2
				continue
		if text.substr(index, 1) == "`":
			var code_end: int = _find_unescaped(text, "`", index + 1)
			if code_end >= 0:
				output += text.substr(index + 1, code_end - index - 1)
				index = code_end + 1
				continue
		var marker: String = text.substr(index, 1)
		if (marker == "*" or marker == "_") and _is_single_emphasis_opener(text, index, marker):
			var emphasis_end: int = _find_single_emphasis_end(text, marker, index + 1)
			if emphasis_end > index + 1:
				output += strip_markup(text.substr(index + 1, emphasis_end - index - 1), depth + 1)
				index = emphasis_end + 1
				continue
		output += marker
		index += 1
	return output


static func source_offset_for_visible_index(text: String, visible_index: int) -> int:
	# RichTextLabel exposes visible-character ranges but not a direct pointer-to-
	# source mapping. Build a bounded mapping using the same grammar as to_bbcode()
	# so nested emphasis/link delimiters do not shift the editor caret.
	if text.is_empty() or visible_index <= 0:
		return 0
	var mapping: PackedInt32Array = PackedInt32Array()
	_append_source_mapping(text, 0, text.length(), mapping, 0)
	if mapping.is_empty():
		return mini(text.length(), visible_index)
	if visible_index >= mapping.size():
		return text.length()
	return int(mapping[clampi(visible_index, 0, mapping.size() - 1)])


static func _append_source_mapping(
	text: String,
	start: int,
	finish: int,
	mapping: PackedInt32Array,
	depth: int
) -> void:
	if depth >= MAX_RECURSION_DEPTH:
		for raw_index: int in range(start, finish):
			mapping.append(raw_index)
		return
	var index: int = start
	while index < finish:
		if text.substr(index, 1) == "\\" and index + 1 < finish:
			mapping.append(index + 1)
			index += 2
			continue
		if text.substr(index, NoteResourceEmbed.PREFIX.length()) == NoteResourceEmbed.PREFIX:
			var embed_end: int = text.find(NoteResourceEmbed.SUFFIX, index + NoteResourceEmbed.PREFIX.length())
			if embed_end >= 0 and embed_end + NoteResourceEmbed.SUFFIX.length() <= finish:
				var embed_raw: String = text.substr(index, embed_end + NoteResourceEmbed.SUFFIX.length() - index)
				var embed: Dictionary = NoteResourceEmbed.parse_exact(embed_raw)
				if not embed.is_empty():
					var caption: String = str(embed.get("caption", "")).strip_edges()
					var visible_length: int = caption.length() if not caption.is_empty() else NotLightL10n.text("notes.embed.inline_placeholder").length()
					for _visible_index: int in range(maxi(1, visible_length)):
						mapping.append(index)
					index = embed_end + NoteResourceEmbed.SUFFIX.length()
					continue
		if text.substr(index, NoteModuleEmbed.PREFIX.length()) == NoteModuleEmbed.PREFIX:
			var module_end: int = text.find(NoteModuleEmbed.SUFFIX, index + NoteModuleEmbed.PREFIX.length())
			if module_end >= 0 and module_end + NoteModuleEmbed.SUFFIX.length() <= finish:
				var module_raw: String = text.substr(index, module_end + NoteModuleEmbed.SUFFIX.length() - index)
				var module_embed: Dictionary = NoteModuleEmbed.parse_exact(module_raw)
				if not module_embed.is_empty():
					var module_caption: String = str(module_embed.get("caption", "")).strip_edges()
					var module_visible_length: int = module_caption.length() if not module_caption.is_empty() else NotLightL10n.text("notes.module_embed.inline_placeholder").length()
					for _module_visible_index: int in range(maxi(1, module_visible_length)):
						mapping.append(index)
					index = module_end + NoteModuleEmbed.SUFFIX.length()
					continue
		if text.substr(index, 2) == "[[":
			var wiki_end: int = text.find("]]", index + 2)
			if wiki_end >= 0 and wiki_end + 2 <= finish:
				var visible_range: Vector2i = _wiki_visible_source_range(text, index + 2, wiki_end)
				for source_index: int in range(visible_range.x, visible_range.y):
					mapping.append(source_index)
				index = wiki_end + 2
				continue
		if text.substr(index, 1) == "[" and text.substr(index, 2) != "[[" and not (index > 0 and text.substr(index - 1, 1) == "!"):
			var label_end: int = _find_unescaped(text, "](", index + 1)
			if label_end > index + 1 and label_end < finish:
				var target_end: int = _find_unescaped(text, ")", label_end + 2)
				if target_end > label_end + 2 and target_end < finish:
					var target: String = text.substr(label_end + 2, target_end - label_end - 2).strip_edges()
					if _is_safe_external_target(target):
						_append_source_mapping(text, index + 1, label_end, mapping, depth + 1)
						index = target_end + 1
						continue
		var triple: String = text.substr(index, 3)
		if triple == "***" or triple == "___":
			var triple_end: int = _find_unescaped(text, triple, index + 3)
			if triple_end >= 0 and triple_end + 3 <= finish:
				_append_source_mapping(text, index + 3, triple_end, mapping, depth + 1)
				index = triple_end + 3
				continue
		var pair: String = text.substr(index, 2)
		if pair == "**" or pair == "__" or pair == "~~" or pair == "==":
			var pair_end: int = _find_strong_end(text, pair, index + 2) if pair == "**" or pair == "__" else _find_unescaped(text, pair, index + 2)
			if pair_end >= 0 and pair_end + 2 <= finish:
				_append_source_mapping(text, index + 2, pair_end, mapping, depth + 1)
				index = pair_end + 2
				continue
		if text.substr(index, 1) == "`":
			var code_end: int = _find_unescaped(text, "`", index + 1)
			if code_end >= 0 and code_end + 1 <= finish:
				for source_index: int in range(index + 1, code_end):
					mapping.append(source_index)
				index = code_end + 1
				continue
		var marker: String = text.substr(index, 1)
		if (marker == "*" or marker == "_") and _is_single_emphasis_opener(text, index, marker):
			var emphasis_end: int = _find_single_emphasis_end(text, marker, index + 1)
			if emphasis_end > index + 1 and emphasis_end + 1 <= finish:
				_append_source_mapping(text, index + 1, emphasis_end, mapping, depth + 1)
				index = emphasis_end + 1
				continue
		mapping.append(index)
		index += 1


static func _find_strong_end(text: String, delimiter: String, start: int) -> int:
	var position: int = _find_unescaped(text, delimiter, start)
	if position < 0:
		return -1
	var marker: String = delimiter.substr(0, 1)
	# Common Markdown nesting closes `**bold and *italic***` with a three-
	# marker run: the first marker closes the nested emphasis and the final two
	# close strong emphasis. Shift the strong delimiter only when there is a
	# genuine unescaped single-marker opener inside the strong span.
	if position + 2 < text.length() and text.substr(position, 3) == marker + marker + marker:
		if _has_single_emphasis_marker(text, marker, start, position):
			return position + 1
	return position


static func _find_single_emphasis_end(text: String, marker: String, start: int) -> int:
	var position: int = _find_unescaped(text, marker, start)
	while position >= 0:
		# `*italic **bold***` closes the outer emphasis on the final marker of
		# the three-marker run; the first two remain available to nested strong.
		if position + 2 < text.length() and text.substr(position, 3) == marker + marker + marker:
			var triple_close: int = position + 2
			if _is_single_emphasis_closer(text, triple_close, marker):
				return triple_close
		var previous: String = text.substr(position - 1, 1) if position > 0 else ""
		var following: String = text.substr(position + 1, 1) if position + 1 < text.length() else ""
		if previous != marker and following != marker and _is_single_emphasis_closer(text, position, marker):
			return position
		position = _find_unescaped(text, marker, position + 1)
	return -1


static func _is_single_emphasis_opener(text: String, index: int, marker: String) -> bool:
	var following: String = text.substr(index + 1, 1) if index + 1 < text.length() else ""
	if following.is_empty() or _is_whitespace(following):
		return false
	if marker == "_":
		var previous: String = text.substr(index - 1, 1) if index > 0 else ""
		if _is_word_character(previous) and _is_word_character(following):
			return false
	return true


static func _is_single_emphasis_closer(text: String, index: int, marker: String) -> bool:
	var previous: String = text.substr(index - 1, 1) if index > 0 else ""
	if previous.is_empty() or _is_whitespace(previous):
		return false
	if marker == "_":
		var following: String = text.substr(index + 1, 1) if index + 1 < text.length() else ""
		if _is_word_character(previous) and _is_word_character(following):
			return false
	return true


static func _is_word_character(character: String) -> bool:
	if character.is_empty():
		return false
	return character.to_lower() != character.to_upper() or (character >= "0" and character <= "9")


static func _is_whitespace(character: String) -> bool:
	return character == " " or character == "\t" or character == "\n" or character == "\r"


static func _wiki_visible_source_range(text: String, start: int, finish: int) -> Vector2i:
	var pipe: int = text.find("|", start)
	if pipe < 0 or pipe >= finish:
		return _trim_source_range(text, start, finish)
	var alias_range: Vector2i = _trim_source_range(text, pipe + 1, finish)
	if alias_range.x < alias_range.y:
		return alias_range
	return _trim_source_range(text, start, pipe)


static func _trim_source_range(text: String, start: int, finish: int) -> Vector2i:
	var clean_start: int = start
	var clean_finish: int = finish
	while clean_start < clean_finish and _is_whitespace(text.substr(clean_start, 1)):
		clean_start += 1
	while clean_finish > clean_start and _is_whitespace(text.substr(clean_finish - 1, 1)):
		clean_finish -= 1
	return Vector2i(clean_start, clean_finish)


static func _has_single_emphasis_marker(text: String, marker: String, start: int, finish: int) -> bool:
	var position: int = _find_unescaped(text, marker, start)
	while position >= 0 and position < finish:
		var previous: String = text.substr(position - 1, 1) if position > start else ""
		var following: String = text.substr(position + 1, 1) if position + 1 < finish else ""
		if previous != marker and following != marker:
			return true
		position = _find_unescaped(text, marker, position + 1)
	return false


static func _find_unescaped(text: String, needle: String, start: int) -> int:
	var position: int = text.find(needle, start)
	while position >= 0:
		var slash_count: int = 0
		var cursor: int = position - 1
		while cursor >= 0 and text.substr(cursor, 1) == "\\":
			slash_count += 1
			cursor -= 1
		if slash_count % 2 == 0:
			return position
		position = text.find(needle, position + needle.length())
	return -1


static func _is_safe_external_target(target: String) -> bool:
	var lower: String = target.strip_edges().to_lower()
	return lower.begins_with("https://") or lower.begins_with("http://") or lower.begins_with("mailto:")
