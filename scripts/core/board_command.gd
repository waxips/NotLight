# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardCommand
extends RefCounted

var label: String = NotLightL10n.text("runtime.core.board_command.8ed6089103")
var merge_key: StringName = StringName()


func execute(_runtime: BoardRuntime) -> bool:
	return false


func undo(_runtime: BoardRuntime) -> bool:
	return false


func redo(runtime: BoardRuntime) -> bool:
	return execute(runtime)


func can_merge_with(_newer_command: BoardCommand) -> bool:
	return false


func merge_from(_newer_command: BoardCommand) -> void:
	pass
