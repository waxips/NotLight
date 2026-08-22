# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardToolController
extends RefCounted

signal active_tool_changed(tool_id: StringName)

const TOOL_HAND: StringName = &"hand"
const TOOL_SELECT: StringName = &"select"
const TOOL_TEXT: StringName = &"text"
const TOOL_DRAW: StringName = &"draw"
const TOOL_FORMULA: StringName = &"formula"

var active_tool_id: StringName = StringName()
var _tools: Dictionary = {}


func setup_defaults() -> void:
	register_tool(BoardTool.new(TOOL_HAND, NotLightL10n.text("runtime.core.board_tool_controller.c51da268c2"), Control.CURSOR_DRAG))
	register_tool(BoardTool.new(TOOL_SELECT, NotLightL10n.text("runtime.core.board_tool_controller.3fb2d64b4c"), Control.CURSOR_ARROW))
	register_tool(BoardTool.new(TOOL_TEXT, NotLightL10n.text("board.search.type.text"), Control.CURSOR_VSPLIT))
	register_tool(BoardTool.new(TOOL_DRAW, NotLightL10n.text("drawing.title"), Control.CURSOR_CROSS))
	register_tool(BoardTool.new(TOOL_FORMULA, NotLightL10n.text("formula.context.title"), Control.CURSOR_HELP))
	set_active_tool(TOOL_SELECT)


func register_tool(tool: BoardTool) -> bool:
	if tool == null or tool.tool_id == StringName() or _tools.has(tool.tool_id):
		return false
	_tools[tool.tool_id] = tool
	return true


func unregister_tool(tool_id: StringName) -> bool:
	if tool_id == active_tool_id or not _tools.has(tool_id):
		return false
	_tools.erase(tool_id)
	return true


func set_active_tool(tool_id: StringName) -> bool:
	if not _tools.has(tool_id):
		return false
	if active_tool_id == tool_id:
		return true
	var previous: BoardTool = get_active_tool()
	if previous != null:
		previous.deactivate()
	active_tool_id = tool_id
	var current: BoardTool = get_active_tool()
	if current != null:
		current.activate()
	active_tool_changed.emit(active_tool_id)
	return true


func get_active_tool() -> BoardTool:
	var value: Variant = _tools.get(active_tool_id)
	return value as BoardTool


func get_tool(tool_id: StringName) -> BoardTool:
	var value: Variant = _tools.get(tool_id)
	return value as BoardTool


func handle_event(event: InputEvent, world_position: Vector2) -> bool:
	var tool: BoardTool = get_active_tool()
	return tool.handle_event(event, world_position) if tool != null else false
