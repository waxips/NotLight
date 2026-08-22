# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardSession
extends Node

enum SaveState {
	CLOSED,
	SAVED,
	DIRTY,
	SAVING,
	ERROR,
}

signal board_opened(metadata: Dictionary, document: Dictionary)
signal board_closed
signal metadata_changed(metadata: Dictionary)
signal document_changed(document: Dictionary)
signal save_state_changed(state: SaveState, message: String)
signal runtime_ready(runtime: BoardRuntime)

const AUTOSAVE_IDLE_SECONDS: float = 1.25
const MIN_SAVE_INTERVAL_SECONDS: float = 0.75

var repository: BoardRepository
var runtime: BoardRuntime = BoardRuntime.new()
var current_board_id: String = ""
var metadata: Dictionary = {}
var document: Dictionary = {}
var revision: int = 0
var saved_revision: int = 0
var save_state: SaveState = SaveState.CLOSED
var _idle_seconds: float = 0.0
var _since_last_save_seconds: float = 999.0
var _save_queued: bool = false
var _save_requires_idle: bool = false
var _loading_runtime: bool = false


func _ready() -> void:
	runtime.runtime_changed.connect(_on_runtime_changed)


func _process(delta: float) -> void:
	if current_board_id.is_empty():
		return
	_since_last_save_seconds += delta
	if revision == saved_revision or save_state == SaveState.SAVING:
		return
	_idle_seconds += delta
	if _idle_seconds >= AUTOSAVE_IDLE_SECONDS and _since_last_save_seconds >= MIN_SAVE_INTERVAL_SECONDS:
		request_save(true)


func configure(board_repository: BoardRepository) -> void:
	repository = board_repository


func open_board(board_id: String) -> bool:
	if repository == null:
		_set_state(SaveState.ERROR, NotLightL10n.text("runtime.data.board_session.a99c80d3fa"))
		return false
	var loaded: Dictionary = repository.load_board(board_id)
	if loaded.is_empty():
		_set_state(SaveState.ERROR, repository.get_last_error())
		return false
	current_board_id = board_id
	metadata = (loaded.get("metadata", {}) as Dictionary).duplicate(true)
	document = BoardDocumentSchema.normalize(loaded.get("document", {}) as Dictionary)
	var stroke_payload: PackedByteArray = PackedByteArray()
	var stroke_payload_value: Variant = loaded.get("stroke_payload", PackedByteArray())
	if stroke_payload_value is PackedByteArray:
		stroke_payload = stroke_payload_value as PackedByteArray
	_loading_runtime = true
	runtime.load_document(document, stroke_payload)
	_loading_runtime = false
	revision = 0
	saved_revision = 0
	_idle_seconds = 0.0
	_since_last_save_seconds = 999.0
	_save_queued = false
	_save_requires_idle = false
	_set_state(SaveState.SAVED, NotLightL10n.text("library.inspector.saved"))
	runtime_ready.emit(runtime)
	board_opened.emit(metadata.duplicate(true), document.duplicate(true))
	return true


func close_board(save_changes: bool = true) -> bool:
	if current_board_id.is_empty():
		return true
	if save_changes and revision != saved_revision:
		if not save_now_sync():
			return false
	current_board_id = ""
	metadata.clear()
	document.clear()
	runtime.load_document(BoardDocumentSchema.make_empty())
	revision = 0
	saved_revision = 0
	_save_queued = false
	_save_requires_idle = false
	_set_state(SaveState.CLOSED, "")
	board_closed.emit()
	return true


func get_view_state() -> Dictionary:
	if document.is_empty():
		return {
			"camera_position": {"x": 0.0, "y": 0.0},
			"zoom": 1.0,
		}
	var view: Dictionary = document.get("view", {}) as Dictionary
	return view.duplicate(true)


func update_view_state(view_state: Dictionary) -> void:
	if current_board_id.is_empty():
		return
	var current_view: Dictionary = document.get("view", {}) as Dictionary
	var camera_source: Dictionary = view_state.get("camera_position", {}) as Dictionary
	var normalized: Dictionary = {
		"camera_position": {
			"x": float(camera_source.get("x", 0.0)),
			"y": float(camera_source.get("y", 0.0)),
		},
		"zoom": clampf(float(view_state.get("zoom", 1.0)), 0.08, 8.0),
	}
	if _view_states_equal(current_view, normalized):
		return
	document["view"] = normalized
	mark_dirty()
	document_changed.emit(document.duplicate(true))


func rename_current_board(new_name: String) -> bool:
	var clean_name: String = new_name.strip_edges()
	if current_board_id.is_empty() or clean_name.is_empty():
		return false
	if str(metadata.get("name", "")) == clean_name:
		return true
	metadata["name"] = clean_name
	mark_dirty()
	metadata_changed.emit(metadata.duplicate(true))
	request_save()
	return true


func mark_dirty() -> void:
	if current_board_id.is_empty():
		return
	revision += 1
	_idle_seconds = 0.0
	_set_state(SaveState.DIRTY, NotLightL10n.text("runtime.data.board_session.9c62d3177b"))


func notify_user_activity() -> void:
	# runtime_changed resets this clock for content edits, but camera/input gestures
	# do not mutate the document until their debounced view-state commit. Without
	# this hook a pending stroke autosave could serialize the entire stroke payload
	# on the main thread while the user was actively panning or zooming.
	if current_board_id.is_empty():
		return
	_idle_seconds = 0.0


func request_save(require_idle: bool = false) -> void:
	if current_board_id.is_empty() or revision == saved_revision:
		return
	if _save_queued:
		# Explicit saves (toolbar/rename) must upgrade an already queued autosave so
		# they are never cancelled merely because the user is still interacting.
		if not require_idle:
			_save_requires_idle = false
		return
	_save_queued = true
	_save_requires_idle = require_idle
	_set_state(SaveState.SAVING, NotLightL10n.text("runtime.data.board_session.73bfb5e424"))
	call_deferred("_perform_queued_save")


func save_now_sync() -> bool:
	if current_board_id.is_empty():
		return true
	if revision == saved_revision:
		_set_state(SaveState.SAVED, NotLightL10n.text("library.inspector.saved"))
		return true
	_save_queued = false
	_save_requires_idle = false
	_set_state(SaveState.SAVING, NotLightL10n.text("runtime.data.board_session.73bfb5e424"))
	var target_revision: int = revision
	document = runtime.write_document(document)
	var saved_metadata: Dictionary = repository.save_board(current_board_id, metadata, document, runtime.export_stroke_payload())
	_since_last_save_seconds = 0.0
	_idle_seconds = 0.0
	if saved_metadata.is_empty():
		_set_state(SaveState.ERROR, repository.get_last_error())
		return false
	metadata = saved_metadata.duplicate(true)
	saved_revision = target_revision
	metadata_changed.emit(metadata.duplicate(true))
	if revision == saved_revision:
		_set_state(SaveState.SAVED, NotLightL10n.text("library.inspector.saved"))
	else:
		_set_state(SaveState.DIRTY, NotLightL10n.text("runtime.data.board_session.9c62d3177b"))
	return true


func execute_command(command: BoardCommand) -> bool:
	return runtime.commands.execute(command, runtime)


func undo() -> bool:
	return runtime.commands.undo(runtime)


func redo() -> bool:
	return runtime.commands.redo(runtime)


func _perform_queued_save() -> void:
	var require_idle: bool = _save_requires_idle
	_save_queued = false
	_save_requires_idle = false
	if require_idle and _idle_seconds < AUTOSAVE_IDLE_SECONDS:
		# Input may arrive after request_save(true) but before this deferred call. Do
		# not let that one-frame race reintroduce a synchronous stroke serialization
		# in the middle of pan/zoom; the normal idle timer will queue it again later.
		_set_state(SaveState.DIRTY, NotLightL10n.text("runtime.data.board_session.9c62d3177b"))
		return
	save_now_sync()


func _set_state(new_state: SaveState, message: String) -> void:
	if save_state == new_state and message.is_empty():
		return
	save_state = new_state
	save_state_changed.emit(save_state, message)


func _view_states_equal(left: Dictionary, right: Dictionary) -> bool:
	var left_camera: Dictionary = left.get("camera_position", {}) as Dictionary
	var right_camera: Dictionary = right.get("camera_position", {}) as Dictionary
	var left_position: Vector2 = Vector2(
		float(left_camera.get("x", 0.0)),
		float(left_camera.get("y", 0.0))
	)
	var right_position: Vector2 = Vector2(
		float(right_camera.get("x", 0.0)),
		float(right_camera.get("y", 0.0))
	)
	return left_position.is_equal_approx(right_position) and is_equal_approx(
		float(left.get("zoom", 1.0)),
		float(right.get("zoom", 1.0))
	)


func _on_runtime_changed() -> void:
	if _loading_runtime or current_board_id.is_empty():
		return
	mark_dirty()
