# SPDX-License-Identifier: GPL-3.0-or-later
class_name PowerStatusProvider
extends RefCounted


func is_supported() -> bool:
	return false


func executable_path() -> String:
	return ""


func arguments() -> PackedStringArray:
	return PackedStringArray()


func parse_output(_stdout_text: String, _stderr_text: String, _exit_code: int) -> Dictionary:
	return {"supported": false, "present": false, "percent": -1, "charging": false}
