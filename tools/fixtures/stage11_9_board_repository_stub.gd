# SPDX-License-Identifier: GPL-3.0-or-later
extends BoardRepository

# Runtime-smoke-only in-memory BoardRepository facade. It deliberately avoids
# touching BoardRepository.ROOT_DIR so test execution can never delete or replace
# a user's real NotLight boards.
var _stored_board_id: String = ""
var _stored_metadata: Dictionary = {}
var _stored_document: Dictionary = {}
var _last_stub_error: String = ""
var _import_serial: int = 0


func seed_board(board_id: String, board_name: String, document: Dictionary) -> void:
	_stored_board_id = board_id.strip_edges()
	_stored_metadata = {
		"id": _stored_board_id,
		"name": board_name.strip_edges(),
		"created_at_unix": 1,
		"updated_at_unix": 2,
	}
	_stored_document = BoardDocumentSchema.normalize(document)
	_last_stub_error = ""


func load_board(board_id: String) -> Dictionary:
	if board_id.strip_edges() != _stored_board_id or _stored_document.is_empty():
		_last_stub_error = "Smoke board not found."
		return {}
	_last_stub_error = ""
	return {
		"metadata": _stored_metadata.duplicate(true),
		"document": _stored_document.duplicate(true),
		"stroke_payload": PackedByteArray(),
	}


func get_last_error() -> String:
	return _last_stub_error


func get_board_directory(_board_id: String) -> String:
	return "user://notlight_stage11_9_runtime_stub_board"


func import_board_snapshot(metadata: Dictionary, document: Dictionary, _stroke_payload: PackedByteArray = PackedByteArray()) -> Dictionary:
	_import_serial += 1
	var source_id: String = str(metadata.get("id", "stage11_9_import")).strip_edges()
	if source_id.is_empty():
		source_id = "stage11_9_import"
	_stored_board_id = "%s_%d" % [source_id, _import_serial]
	_stored_metadata = {
		"id": _stored_board_id,
		"name": str(metadata.get("name", "Stage 11.9 import")),
		"created_at_unix": int(metadata.get("created_at_unix", 0)),
		"updated_at_unix": int(metadata.get("updated_at_unix", 0)),
	}
	_stored_document = BoardDocumentSchema.normalize(document)
	_last_stub_error = ""
	return _stored_metadata.duplicate(true)


func get_stored_document() -> Dictionary:
	return _stored_document.duplicate(true)
