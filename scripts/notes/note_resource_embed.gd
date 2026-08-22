# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteResourceEmbed
extends RefCounted

# Canonical pinned Library embed syntax. The SHA-256 is the identity of the
# embedded bytes, so portable import never needs to rewrite Markdown if logical
# asset IDs are remapped. The optional caption is presentation-only.
#
#   ![[resource-sha256:<64 lowercase/uppercase hex>]]
#   ![[resource-sha256:<64 hex>|Optional caption]]
#
# Only Library media kinds are embeddable for now. Notes continue to use
# [[wiki-links]] so note relations remain semantic and graph-aware.
const PREFIX: String = "![[resource-sha256:"
const SUFFIX: String = "]]"
const MAX_EMBEDS_PER_NOTE: int = 512
const MAX_CAPTION_LENGTH: int = 240
const HEX_DIGITS: String = "0123456789abcdefABCDEF"


static func syntax_for_hash(hash_sha256: String, caption: String = "") -> String:
	var clean_hash: String = hash_sha256.strip_edges().to_lower()
	if not is_sha256(clean_hash):
		return ""
	var clean_caption: String = caption.replace("\r", " ").replace("\n", " ").replace("|", " ").replace("[", "(").replace("]", ")").strip_edges().left(MAX_CAPTION_LENGTH)
	if clean_caption.is_empty():
		return "%s%s%s" % [PREFIX, clean_hash, SUFFIX]
	return "%s%s|%s%s" % [PREFIX, clean_hash, clean_caption, SUFFIX]


static func parse_exact(text: String) -> Dictionary:
	var clean: String = text.strip_edges()
	if not clean.begins_with(PREFIX) or not clean.ends_with(SUFFIX):
		return {}
	var body: String = clean.substr(PREFIX.length(), clean.length() - PREFIX.length() - SUFFIX.length())
	var separator: int = body.find("|")
	var hash_sha256: String = body if separator < 0 else body.substr(0, separator)
	var caption: String = "" if separator < 0 else body.substr(separator + 1)
	hash_sha256 = hash_sha256.strip_edges().to_lower()
	caption = caption.strip_edges().left(MAX_CAPTION_LENGTH)
	if not is_sha256(hash_sha256):
		return {}
	return {
		"hash_sha256": hash_sha256,
		"caption": caption,
	}


static func extract_hashes(markdown: String) -> PackedStringArray:
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
			var hash_sha256: String = str(parsed.get("hash_sha256", ""))
			if not hash_sha256.is_empty() and not seen.has(hash_sha256):
				seen[hash_sha256] = true
				result.append(hash_sha256)
			index = close_index + SUFFIX.length()
			continue
		index += 1
	return result


static func is_embeddable_kind(kind: int) -> bool:
	return kind == AssetKinds.IMAGE or kind == AssetKinds.VIDEO or kind == AssetKinds.AUDIO or kind == AssetKinds.PDF


static func is_sha256(value: String) -> bool:
	var clean: String = value.strip_edges()
	if clean.length() != 64:
		return false
	for character: String in clean:
		if not HEX_DIGITS.contains(character):
			return false
	return true


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
