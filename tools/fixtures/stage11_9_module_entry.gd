# SPDX-License-Identifier: GPL-3.0-or-later
extends RefCounted

const SURFACE_SCRIPT: Script = preload("res://tools/fixtures/stage11_9_module_surface.gd")


func notlight_get_default_state() -> Dictionary:
	return {"value": 0.0, "normalized": true}


func notlight_normalize_state(source: Dictionary) -> Dictionary:
	return {
		"value": clampf(float(source.get("value", 0.0)), 0.0, 100.0),
		"normalized": true,
	}


func notlight_create_surface() -> Control:
	var surface: Control = SURFACE_SCRIPT.new() as Control
	return surface
