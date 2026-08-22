# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardCommandHistory
extends RefCounted

signal history_changed(can_undo: bool, can_redo: bool, undo_label: String, redo_label: String)
signal command_executed(label: String)

const DEFAULT_LIMIT: int = 256

var limit: int = DEFAULT_LIMIT
var _undo_stack: Array[BoardCommand] = []
var _redo_stack: Array[BoardCommand] = []


func execute(command: BoardCommand, runtime: BoardRuntime) -> bool:
	if command == null or runtime == null:
		return false
	if not command.execute(runtime):
		return false
	if not _undo_stack.is_empty():
		var previous: BoardCommand = _undo_stack[_undo_stack.size() - 1]
		if previous.can_merge_with(command):
			previous.merge_from(command)
		else:
			_undo_stack.append(command)
			_trim_to_limit()
	else:
		_undo_stack.append(command)
	_redo_stack.clear()
	command_executed.emit(command.label)
	_emit_changed()
	return true


func record_applied(command: BoardCommand) -> bool:
	if command == null:
		return false
	if not _undo_stack.is_empty():
		var previous: BoardCommand = _undo_stack[_undo_stack.size() - 1]
		if previous.can_merge_with(command):
			previous.merge_from(command)
		else:
			_undo_stack.append(command)
			_trim_to_limit()
	else:
		_undo_stack.append(command)
	_redo_stack.clear()
	command_executed.emit(command.label)
	_emit_changed()
	return true


func discard_last_applied(command: BoardCommand, runtime: BoardRuntime) -> bool:
	if command == null or runtime == null or _undo_stack.is_empty():
		return false
	var last_index: int = _undo_stack.size() - 1
	if _undo_stack[last_index] != command:
		return false
	if not command.undo(runtime):
		return false
	_undo_stack.remove_at(last_index)
	_redo_stack.clear()
	_emit_changed()
	return true


func undo(runtime: BoardRuntime) -> bool:
	if runtime == null or _undo_stack.is_empty():
		return false
	var last_index: int = _undo_stack.size() - 1
	var command: BoardCommand = _undo_stack[last_index]
	_undo_stack.remove_at(last_index)
	if not command.undo(runtime):
		_undo_stack.append(command)
		return false
	_redo_stack.append(command)
	_emit_changed()
	return true


func redo(runtime: BoardRuntime) -> bool:
	if runtime == null or _redo_stack.is_empty():
		return false
	var last_index: int = _redo_stack.size() - 1
	var command: BoardCommand = _redo_stack[last_index]
	_redo_stack.remove_at(last_index)
	if not command.redo(runtime):
		_redo_stack.append(command)
		return false
	_undo_stack.append(command)
	_trim_to_limit()
	_emit_changed()
	return true


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func get_undo_label() -> String:
	if not can_undo():
		return ""
	return _undo_stack[_undo_stack.size() - 1].label


func get_redo_label() -> String:
	if not can_redo():
		return ""
	return _redo_stack[_redo_stack.size() - 1].label


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_emit_changed()


func _trim_to_limit() -> void:
	while _undo_stack.size() > maxi(limit, 1):
		_undo_stack.remove_at(0)


func _emit_changed() -> void:
	history_changed.emit(can_undo(), can_redo(), get_undo_label(), get_redo_label())
