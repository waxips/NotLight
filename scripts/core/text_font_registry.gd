# SPDX-License-Identifier: GPL-3.0-or-later
class_name TextFontRegistry
extends RefCounted

const DEFAULT_FAMILY: String = "Noto Sans"
const FALLBACK_SANS: String = "sans-serif"
const FALLBACK_SERIF: String = "serif"
const FALLBACK_MONO: String = "monospace"
const MAX_MENU_FONTS: int = 48

var _cache: Dictionary = {}


func get_font(family: String, style_flags: int = 0) -> Font:
	var safe_family: String = family.strip_edges()
	if safe_family.is_empty():
		safe_family = DEFAULT_FAMILY
	var bold: bool = (style_flags & TextBlockStore.FONT_STYLE_BOLD) != 0
	var italic: bool = (style_flags & TextBlockStore.FONT_STYLE_ITALIC) != 0
	var key: String = "%s|%d|%d" % [safe_family, int(bold), int(italic)]
	var cached: Variant = _cache.get(key)
	if cached is Font:
		return cached as Font
	var font: SystemFont = SystemFont.new()
	font.font_names = _fallback_chain(safe_family)
	font.font_weight = 700 if bold else 400
	font.font_italic = italic
	font.allow_system_fallback = true
	font.multichannel_signed_distance_field = true
	_cache[key] = font
	return font


func clear_cache() -> void:
	_cache.clear()


static func available_font_families() -> PackedStringArray:
	var installed: PackedStringArray = OS.get_system_fonts()
	var installed_lookup: Dictionary = {}
	for font_name: String in installed:
		installed_lookup[font_name.to_lower()] = font_name
	var preferred: Array[String] = [
		"Noto Sans",
		"Inter",
		"Segoe UI",
		"Arial",
		"Verdana",
		"Trebuchet MS",
		"Georgia",
		"Times New Roman",
		"Noto Serif",
		"IBM Plex Sans",
		"IBM Plex Mono",
		"JetBrains Mono",
		"Consolas",
		"Courier New",
	]
	var result: PackedStringArray = PackedStringArray()
	var added: Dictionary = {}
	for requested: String in preferred:
		var resolved_value: Variant = installed_lookup.get(requested.to_lower())
		if resolved_value is String:
			var resolved: String = resolved_value as String
			result.append(resolved)
			added[resolved.to_lower()] = true
	if result.is_empty():
		result.append(DEFAULT_FAMILY)
		added[DEFAULT_FAMILY.to_lower()] = true
	var sorted_installed: Array[String] = []
	for font_name: String in installed:
		sorted_installed.append(font_name)
	sorted_installed.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for font_name: String in sorted_installed:
		if result.size() >= MAX_MENU_FONTS:
			break
		if added.has(font_name.to_lower()):
			continue
		result.append(font_name)
		added[font_name.to_lower()] = true
	return result


static func is_family_available(family: String) -> bool:
	if family.is_empty():
		return false
	return not OS.get_system_font_path(family).is_empty()


func _fallback_chain(family: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	names.append(family)
	var lower: String = family.to_lower()
	if lower.contains("mono") or lower.contains("courier") or lower.contains("consol"):
		names.append(FALLBACK_MONO)
	elif lower.contains("serif") or lower.contains("georgia") or lower.contains("times"):
		names.append(FALLBACK_SERIF)
	else:
		names.append(FALLBACK_SANS)
	return names
