# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotLightPortablePackageService
extends Node

# High-level Local-First exchange service for boards and Resource Libraries.
# Package parsing is intentionally separated from durable storage mutation:
# every manifest and payload checksum is verified first, new blobs are committed
# content-addressably, then the catalog is committed as one batch, and a board
# is written last. On failure, the previous catalog snapshot and newly created
# blobs are restored/removed.

const STAGING_ROOT: String = "user://notlight/package_staging"
const STROKE_PAYLOAD_KEY: String = "board.stroke_payload"
const MAX_PORTABLE_FOLDERS: int = 100000
const MAX_PORTABLE_ASSETS: int = 100000

var repository: BoardRepository
var library: AssetLibraryService
var note_repository: NoteRepository
var _last_error: String = ""
var _staging_root: String = STAGING_ROOT


func configure(
	board_repository: BoardRepository,
	asset_library: AssetLibraryService,
	notes: NoteRepository = null
) -> void:
	repository = board_repository
	library = asset_library
	note_repository = notes
	_staging_root = STAGING_ROOT
	if library != null:
		var library_root: String = library.get_root_directory().strip_edges()
		if not library_root.is_empty():
			_staging_root = library_root.path_join("package_staging")
	# Keep package staging on the Library volume whenever possible. This avoids
	# silently consuming the system drive for multi-gigabyte imports after the
	# user intentionally moved the Library to another disk.
	# A crash or forced shutdown may leave only verified temporary payload copies.
	# They are never part of durable state, so clearing them once at service startup
	# prevents multi-gigabyte orphan staging directories from accumulating.
	NotLightPortablePackageFormat.cleanup_directory(_staging_root)


func get_last_error() -> String:
	return _last_error


func export_board(board_id: String, destination_path: String) -> Dictionary:
	return export_board_profile(board_id, destination_path, {
		"resource_mode": "all",
		"include_derived_variants": true,
		"include_notes": true,
		"include_note_embeds": true,
	})


func get_board_export_plan(board_id: String) -> Dictionary:
	_clear_error()
	if not _require_services():
		return _error_result()
	var loaded: Dictionary = repository.load_board(board_id)
	if loaded.is_empty():
		return _fail_result(repository.get_last_error())
	var document: Dictionary = loaded.get("document", {}) as Dictionary
	var asset_ids: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	var note_ids: PackedStringArray = BoardDocumentSchema.collect_note_references(document)
	var note_set: Dictionary = _string_set(note_ids)
	var assets: Array[Dictionary] = []
	var seen_plan_ids: Dictionary = {}
	var primary_bytes: int = 0
	var durable_bytes: int = 0
	for asset_id: String in asset_ids:
		var asset: Dictionary = library.get_asset(asset_id)
		if asset.is_empty():
			if note_set.has(asset_id):
				seen_plan_ids[asset_id] = true
				assets.append({
					"id": asset_id,
					"display_name": asset_id,
					"kind": AssetKinds.NOTE,
					"extension": "md",
					"primary_bytes": 0,
					"durable_bytes": 0,
					"missing": true,
				})
				continue
			return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.b48218e181") % asset_id)
		var primary_size: int = maxi(0, int(asset.get("byte_size", 0)))
		var total_size: int = _asset_durable_byte_size(asset)
		primary_bytes += primary_size
		durable_bytes += total_size
		seen_plan_ids[asset_id] = true
		assets.append({
			"id": asset_id,
			"display_name": str(asset.get("display_name", asset_id)),
			"kind": int(asset.get("kind", AssetKinds.OTHER)),
			"extension": str(asset.get("extension", "")),
			"primary_bytes": primary_size,
			"durable_bytes": total_size,
		})
	var note_embed_dependency_ids: PackedStringArray = PackedStringArray()
	var missing_note_embed_hashes: PackedStringArray = PackedStringArray()
	if not note_ids.is_empty():
		var dependency_result: Dictionary = _collect_note_embed_dependencies(note_ids, false)
		if not bool(dependency_result.get("ok", false)):
			return _fail_result(str(dependency_result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.1a8adb566d"))))
		note_embed_dependency_ids = _string_array(dependency_result.get("asset_ids", []))
		missing_note_embed_hashes = _string_array(dependency_result.get("missing_hashes", []))
		for dependency_id: String in note_embed_dependency_ids:
			if seen_plan_ids.has(dependency_id):
				for asset_index: int in range(assets.size()):
					var existing_record: Dictionary = assets[asset_index]
					if str(existing_record.get("id", "")) == dependency_id:
						existing_record["note_embed_dependency"] = true
						assets[asset_index] = existing_record
						break
				continue
			var dependency_asset: Dictionary = library.get_asset(dependency_id)
			if dependency_asset.is_empty():
				return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.e555275d92") % dependency_id)
			var dependency_primary: int = maxi(0, int(dependency_asset.get("byte_size", 0)))
			var dependency_total: int = _asset_durable_byte_size(dependency_asset)
			primary_bytes += dependency_primary
			durable_bytes += dependency_total
			seen_plan_ids[dependency_id] = true
			assets.append({
				"id": dependency_id,
				"display_name": str(dependency_asset.get("display_name", dependency_id)),
				"kind": int(dependency_asset.get("kind", AssetKinds.OTHER)),
				"extension": str(dependency_asset.get("extension", "")),
				"primary_bytes": dependency_primary,
				"durable_bytes": dependency_total,
				"note_embed_dependency": true,
			})
	return {
		"ok": true,
		"assets": assets,
		"asset_ids": asset_ids,
		"note_ids": note_ids,
		"note_embed_dependency_ids": note_embed_dependency_ids,
		"missing_note_embed_hashes": missing_note_embed_hashes,
		"primary_bytes": primary_bytes,
		"durable_bytes": durable_bytes,
	}


func export_board_profile(board_id: String, destination_path: String, options: Dictionary) -> Dictionary:
	_clear_error()
	if not _require_services():
		return _error_result()
	var destination_error: String = _validate_export_destination(destination_path)
	if not destination_error.is_empty():
		return _fail_result(destination_error)
	if library.has_pending_imports():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.87930b97cf"))
	var loaded: Dictionary = repository.load_board(board_id)
	if loaded.is_empty():
		return _fail_result(repository.get_last_error())
	var metadata: Dictionary = loaded.get("metadata", {}) as Dictionary
	var document: Dictionary = loaded.get("document", {}) as Dictionary
	var asset_ids: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	var note_ids: PackedStringArray = BoardDocumentSchema.collect_note_references(document)
	var note_set: Dictionary = _string_set(note_ids)
	var include_notes: bool = bool(options.get("include_notes", true))
	var include_note_embeds: bool = include_notes and bool(options.get("include_note_embeds", true))
	if include_notes and note_repository != null and not note_repository.flush_pending_saves():
		return _fail_result(note_repository.get_last_error())
	var resource_mode: String = str(options.get("resource_mode", "all")).strip_edges().to_lower()
	if resource_mode != "all" and resource_mode != "none" and resource_mode != "custom":
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.9f75e4e002"))
	var export_asset_ids: PackedStringArray = PackedStringArray()
	var non_note_set: Dictionary = {}
	for asset_id: String in asset_ids:
		if note_set.has(asset_id):
			if include_notes:
				export_asset_ids.append(asset_id)
			continue
		export_asset_ids.append(asset_id)
		non_note_set[asset_id] = true
	var note_embed_asset_ids: PackedStringArray = PackedStringArray()
	if include_note_embeds:
		var dependency_result: Dictionary = _collect_note_embed_dependencies(note_ids)
		if not bool(dependency_result.get("ok", false)):
			return _fail_result(str(dependency_result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.30a75ce509"))))
		note_embed_asset_ids = _string_array(dependency_result.get("asset_ids", []))
		var export_seen: Dictionary = _string_set(export_asset_ids)
		for dependency_id: String in note_embed_asset_ids:
			if not export_seen.has(dependency_id):
				export_seen[dependency_id] = true
				export_asset_ids.append(dependency_id)
			non_note_set[dependency_id] = true
	var embedded_set: Dictionary = {}
	# Notes are a separate privacy/portability decision. When enabled they are
	# always embedded canonically, independent of the generic resource profile.
	if include_notes:
		for note_id: String in note_ids:
			embedded_set[note_id] = true
	if include_note_embeds:
		for dependency_id: String in note_embed_asset_ids:
			embedded_set[dependency_id] = true
	if resource_mode == "all":
		for raw_id: Variant in non_note_set.keys():
			embedded_set[str(raw_id)] = true
	elif resource_mode == "custom":
		for asset_id: String in _string_array(options.get("embedded_asset_ids", [])):
			if note_set.has(asset_id):
				continue
			if not non_note_set.has(asset_id):
				return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.16b87844c9") % asset_id)
			embedded_set[asset_id] = true
	var include_derived_variants: bool = bool(options.get("include_derived_variants", false))
	var asset_export: Dictionary = _build_export_asset_bundle_profile(
		export_asset_ids,
		false,
		embedded_set,
		include_derived_variants
	)
	if not bool(asset_export.get("ok", false)):
		return _fail_result(str(asset_export.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.33b59e1b9e"))))
	var payload_sources: Array[Dictionary] = _dictionary_array(asset_export.get("payload_sources", []))
	var content: Dictionary = document.get("content", {}) as Dictionary
	var stroke_records: Array = content.get("strokes", []) as Array
	var storage: Dictionary = document.get("storage", {}) as Dictionary
	var stroke_filename: String = str(storage.get("stroke_payload", "")).strip_edges()
	if not stroke_records.is_empty():
		if stroke_filename.is_empty():
			return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.16979f33ed"))
		if stroke_filename.get_file() != stroke_filename or stroke_filename.contains("/") or stroke_filename.contains("\\"):
			return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.982fb760c2"))
		var stroke_path: String = repository.get_board_directory(board_id).path_join(stroke_filename)
		if not FileAccess.file_exists(stroke_path):
			return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.aa148212c5"))
		payload_sources.append({
			"key": STROKE_PAYLOAD_KEY,
			"source_path": stroke_path,
			"purpose": "board_strokes",
		})
	else:
		stroke_filename = ""
	var manifest: Dictionary = {
		"package_type": NotLightPortablePackageFormat.PACKAGE_TYPE_BOARD,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"producer": {"name": "NotLight", "godot": "4.4.1"},
		"board": {
			"metadata": _portable_board_metadata(metadata),
			"document": BoardDocumentSchema.normalize(document),
			"module_dependencies": _module_dependencies_for_document(document),
			"stroke_payload_key": STROKE_PAYLOAD_KEY if not stroke_filename.is_empty() else "",
			"resource_policy": {
				"mode": resource_mode,
				"include_derived_variants": include_derived_variants,
				"include_notes": include_notes,
				"include_note_embeds": include_note_embeds,
				"note_embed_asset_ids": _packed_string_array_to_array(note_embed_asset_ids),
				"omitted_note_ids": [] if include_notes else _packed_string_array_to_array(note_ids),
			},
		},
		"folders": asset_export.get("folders", []),
		"assets": asset_export.get("assets", []),
	}
	var result: Dictionary = NotLightPortablePackageFormat.write_package(destination_path, manifest, payload_sources)
	if not bool(result.get("ok", false)):
		return _fail_result(str(result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.b7b229e179"))))
	var payload_verification: Dictionary = NotLightPortablePackageFormat.verify_payload_hashes(destination_path)
	if not bool(payload_verification.get("ok", false)):
		return _fail_result(str(payload_verification.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.56a9fc761a"))))
	var verification: Dictionary = NotLightPortablePackageFormat.inspect(destination_path)
	if not bool(verification.get("ok", false)) or str(verification.get("package_type", "")) != NotLightPortablePackageFormat.PACKAGE_TYPE_BOARD:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.6e2cd1bf53"))
	result["board_name"] = str(metadata.get("name", NotLightL10n.text("modules.library.board_fallback")))
	result["asset_count"] = export_asset_ids.size()
	result["embedded_asset_count"] = embedded_set.size()
	result["external_asset_count"] = export_asset_ids.size() - embedded_set.size()
	result["omitted_note_count"] = 0 if include_notes else note_ids.size()
	result["note_embed_asset_count"] = note_embed_asset_ids.size()
	return result


func export_library(destination_path: String) -> Dictionary:
	return export_library_profile(destination_path, true)


func export_library_profile(destination_path: String, include_notes: bool = true) -> Dictionary:
	_clear_error()
	if not _require_services():
		return _error_result()
	var destination_error: String = _validate_export_destination(destination_path)
	if not destination_error.is_empty():
		return _fail_result(destination_error)
	if library.has_pending_imports():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.dfe1100f65"))
	var asset_ids: PackedStringArray = PackedStringArray()
	for asset: Dictionary in library.list_assets():
		if not include_notes and int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			continue
		var asset_id: String = str(asset.get("id", "")).strip_edges()
		if not asset_id.is_empty():
			asset_ids.append(asset_id)
	var asset_export: Dictionary = _build_export_asset_bundle_profile(
		asset_ids,
		include_notes,
		_string_set(asset_ids),
		true
	)
	if not bool(asset_export.get("ok", false)):
		return _fail_result(str(asset_export.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.6619b679c5"))))
	var manifest: Dictionary = {
		"package_type": NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"producer": {"name": "NotLight", "godot": "4.4.1"},
		"library": {
			"catalog_schema": AssetCatalog.SCHEMA_ID,
			"catalog_schema_version": AssetCatalog.SCHEMA_VERSION,
			"include_notes": include_notes,
		},
		"folders": asset_export.get("folders", []),
		"assets": asset_export.get("assets", []),
	}
	var payload_sources: Array[Dictionary] = _dictionary_array(asset_export.get("payload_sources", []))
	var result: Dictionary = NotLightPortablePackageFormat.write_package(destination_path, manifest, payload_sources)
	if not bool(result.get("ok", false)):
		return _fail_result(str(result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.fb2cbcf963"))))
	var payload_verification: Dictionary = NotLightPortablePackageFormat.verify_payload_hashes(destination_path)
	if not bool(payload_verification.get("ok", false)):
		return _fail_result(str(payload_verification.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.8bf6ddf008"))))
	var verification: Dictionary = NotLightPortablePackageFormat.inspect(destination_path)
	if not bool(verification.get("ok", false)) or str(verification.get("package_type", "")) != NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.271156bdff"))
	result["asset_count"] = asset_ids.size()
	result["folder_count"] = (_dictionary_array(asset_export.get("folders", []))).size()
	result["include_notes"] = include_notes
	return result


func export_library_selection(destination_path: String, asset_ids: PackedStringArray) -> Dictionary:
	_clear_error()
	if not _require_services():
		return _error_result()
	var clean_asset_ids: PackedStringArray = PackedStringArray()
	var seen_asset_ids: Dictionary = {}
	for raw_asset_id: String in asset_ids:
		var asset_id: String = raw_asset_id.strip_edges()
		if asset_id.is_empty() or seen_asset_ids.has(asset_id):
			continue
		seen_asset_ids[asset_id] = true
		clean_asset_ids.append(asset_id)
	if clean_asset_ids.is_empty():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.1a18bef387"))
	var destination_error: String = _validate_export_destination(destination_path)
	if not destination_error.is_empty():
		return _fail_result(destination_error)
	if library.has_pending_imports():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.dfe1100f65"))
	if note_repository != null and not note_repository.flush_pending_saves():
		return _fail_result(note_repository.get_last_error())
	var selected_note_ids: PackedStringArray = PackedStringArray()
	for selected_id: String in clean_asset_ids:
		var selected_asset: Dictionary = library.get_asset(selected_id)
		if int(selected_asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			selected_note_ids.append(selected_id)
	var dependency_ids: PackedStringArray = PackedStringArray()
	if not selected_note_ids.is_empty():
		var dependency_result: Dictionary = _collect_note_embed_dependencies(selected_note_ids)
		if not bool(dependency_result.get("ok", false)):
			return _fail_result(str(dependency_result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.7207e58bee"))))
		dependency_ids = _string_array(dependency_result.get("asset_ids", []))
		var selected_seen: Dictionary = _string_set(clean_asset_ids)
		for dependency_id: String in dependency_ids:
			if not selected_seen.has(dependency_id):
				selected_seen[dependency_id] = true
				clean_asset_ids.append(dependency_id)
	var asset_export: Dictionary = _build_export_asset_bundle(clean_asset_ids, false)
	if not bool(asset_export.get("ok", false)):
		return _fail_result(str(asset_export.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.1ed97c2350"))))
	var manifest: Dictionary = {
		"package_type": NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"producer": {"name": "NotLight", "godot": "4.4.1"},
		"library": {
			"catalog_schema": AssetCatalog.SCHEMA_ID,
			"catalog_schema_version": AssetCatalog.SCHEMA_VERSION,
			"selection_only": true,
			"note_embed_dependency_ids": _packed_string_array_to_array(dependency_ids),
		},
		"folders": asset_export.get("folders", []),
		"assets": asset_export.get("assets", []),
	}
	var payload_sources: Array[Dictionary] = _dictionary_array(asset_export.get("payload_sources", []))
	var result: Dictionary = NotLightPortablePackageFormat.write_package(destination_path, manifest, payload_sources)
	if not bool(result.get("ok", false)):
		return _fail_result(str(result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.02bede21d3"))))
	var payload_verification: Dictionary = NotLightPortablePackageFormat.verify_payload_hashes(destination_path)
	if not bool(payload_verification.get("ok", false)):
		return _fail_result(str(payload_verification.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.130b536952"))))
	var verification: Dictionary = NotLightPortablePackageFormat.inspect(destination_path)
	if not bool(verification.get("ok", false)) or str(verification.get("package_type", "")) != NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.a54c3f7fe2"))
	result["asset_count"] = clean_asset_ids.size()
	result["note_embed_dependency_count"] = dependency_ids.size()
	return result


func import_board(package_path: String) -> Dictionary:
	_clear_error()
	if not _require_services():
		return _error_result()
	if library.has_pending_imports():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.5b5c0259dc"))
	var package_info: Dictionary = NotLightPortablePackageFormat.inspect(package_path)
	if not bool(package_info.get("ok", false)):
		return _fail_result(str(package_info.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.a66f42e644"))))
	if str(package_info.get("package_type", "")) != NotLightPortablePackageFormat.PACKAGE_TYPE_BOARD:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.0f94294d92"))
	var manifest: Dictionary = package_info.get("manifest", {}) as Dictionary
	var board_value: Variant = manifest.get("board", {})
	if board_value is not Dictionary:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.3f6e614be7"))
	var board: Dictionary = board_value as Dictionary
	var metadata_value: Variant = board.get("metadata", {})
	var document_value: Variant = board.get("document", {})
	if metadata_value is not Dictionary or document_value is not Dictionary:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.12cba474ca"))
	var source_document: Dictionary = document_value as Dictionary
	if not BoardDocumentSchema.is_supported(source_document):
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.3356a8166d"))
	var board_policy_error: String = _validate_board_resource_policy(manifest)
	if not board_policy_error.is_empty():
		return _fail_result(board_policy_error)
	var board_folder_error: String = _validate_board_folder_manifest(manifest)
	if not board_folder_error.is_empty():
		return _fail_result(board_folder_error)
	var plan: Dictionary = _build_import_plan(manifest, package_info)
	if not bool(plan.get("ok", false)):
		return _fail_result(str(plan.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.8be4dbd65e"))))
	_prune_unused_board_folders(plan)
	var stroke_key: String = str(board.get("stroke_payload_key", "")).strip_edges()
	if not stroke_key.is_empty() and stroke_key != STROKE_PAYLOAD_KEY:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.fa89a76338"))
	var normalized_document: Dictionary = BoardDocumentSchema.normalize(source_document)
	var module_record_error: String = _validate_board_module_records(normalized_document)
	if not module_record_error.is_empty():
		return _fail_result(module_record_error)
	var module_dependency_error: String = _validate_board_module_dependencies(board, normalized_document)
	if not module_dependency_error.is_empty():
		return _fail_result(module_dependency_error)
	var board_asset_error: String = _validate_board_asset_manifest(normalized_document, plan, manifest)
	if not board_asset_error.is_empty():
		return _fail_result(board_asset_error)
	var content: Dictionary = normalized_document.get("content", {}) as Dictionary
	var stroke_records: Array = content.get("strokes", []) as Array
	if not stroke_records.is_empty() and stroke_key.is_empty():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.7d5ab028a4"))
	if stroke_records.is_empty() and not stroke_key.is_empty():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.152e8e51fb"))
	var required_keys: Dictionary = (plan.get("required_payload_keys", {}) as Dictionary).duplicate(true)
	if not stroke_key.is_empty():
		required_keys[stroke_key] = true
	var referenced_keys: Dictionary = (plan.get("referenced_payload_keys", {}) as Dictionary).duplicate(true)
	if not stroke_key.is_empty():
		referenced_keys[stroke_key] = true
	var payload_validation: String = _validate_payload_key_set(package_info, referenced_keys)
	if not payload_validation.is_empty():
		return _fail_result(payload_validation)
	var staging: String = _new_staging_directory()
	var materialized: Dictionary = NotLightPortablePackageFormat.materialize_payloads(package_info, required_keys, staging)
	if not bool(materialized.get("ok", false)):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _fail_result(str(materialized.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.9c19feb271"))))
	var note_embed_validation: String = _validate_materialized_note_embed_closure(
		manifest,
		plan,
		materialized.get("files", {}) as Dictionary
	)
	if not note_embed_validation.is_empty():
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _fail_result(note_embed_validation)
	var catalog_snapshot: Dictionary = library.make_catalog_snapshot()
	if catalog_snapshot.is_empty():
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.68869d9eca"))
	var commit: Dictionary = _commit_import_plan(plan, materialized.get("files", {}) as Dictionary)
	if not bool(commit.get("ok", false)):
		return _rollback_and_fail(
			str(commit.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.675e51b824"))),
			catalog_snapshot,
			_string_array(commit.get("new_blob_paths", [])),
			staging
		)
	var asset_id_map: Dictionary = commit.get("asset_id_map", {}) as Dictionary
	var remapped_document: Dictionary = BoardDocumentSchema.remap_asset_references(normalized_document, asset_id_map)
	var omitted_note_ids: PackedStringArray = _board_omitted_note_ids(manifest)
	var final_reference_error: String = _validate_local_asset_references(remapped_document, omitted_note_ids)
	if not final_reference_error.is_empty():
		return _rollback_and_fail(
			final_reference_error,
			catalog_snapshot,
			_string_array(commit.get("new_blob_paths", [])),
			staging
		)
	var stroke_payload: PackedByteArray = PackedByteArray()
	if not stroke_key.is_empty():
		var staged_files: Dictionary = materialized.get("files", {}) as Dictionary
		var stroke_path: String = str(staged_files.get(stroke_key, ""))
		if stroke_path.is_empty() or not FileAccess.file_exists(stroke_path):
			return _rollback_and_fail(
				NotLightL10n.text("runtime.portable.notlight_portable_package_service.41a8f4fdb0"),
				catalog_snapshot,
				_string_array(commit.get("new_blob_paths", [])),
				staging
			)
		stroke_payload = FileAccess.get_file_as_bytes(stroke_path)
		if stroke_payload.is_empty():
			return _rollback_and_fail(
				NotLightL10n.text("runtime.portable.notlight_portable_package_service.d7d52ae8de"),
				catalog_snapshot,
				_string_array(commit.get("new_blob_paths", [])),
				staging
			)
	var imported_metadata: Dictionary = repository.import_board_snapshot(
		metadata_value as Dictionary,
		remapped_document,
		stroke_payload
	)
	if imported_metadata.is_empty():
		return _rollback_and_fail(
			repository.get_last_error(),
			catalog_snapshot,
			_string_array(commit.get("new_blob_paths", [])),
			staging
		)
	NotLightPortablePackageFormat.cleanup_directory(staging)
	return {
		"ok": true,
		"board_id": str(imported_metadata.get("id", "")),
		"board_name": str(imported_metadata.get("name", NotLightL10n.text("modules.library.board_fallback"))),
		"assets_added": int(commit.get("assets_added", 0)),
		"assets_reused": int(commit.get("assets_reused", 0)),
		"folders_added": int(commit.get("folders_added", 0)),
		"module_ids": BoardDocumentSchema.collect_module_references(remapped_document),
	}


func import_library(package_path: String) -> Dictionary:
	_clear_error()
	if not _require_services():
		return _error_result()
	if library.has_pending_imports():
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.554b180090"))
	var package_info: Dictionary = NotLightPortablePackageFormat.inspect(package_path)
	if not bool(package_info.get("ok", false)):
		return _fail_result(str(package_info.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.bc8a651f5f"))))
	if str(package_info.get("package_type", "")) != NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY:
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.3b73c6cc81"))
	var manifest: Dictionary = package_info.get("manifest", {}) as Dictionary
	var library_manifest_error: String = _validate_library_manifest(manifest)
	if not library_manifest_error.is_empty():
		return _fail_result(library_manifest_error)
	var plan: Dictionary = _build_import_plan(manifest, package_info)
	if not bool(plan.get("ok", false)):
		return _fail_result(str(plan.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.9a60eac7f4"))))
	var referenced_keys: Dictionary = plan.get("referenced_payload_keys", {}) as Dictionary
	var payload_validation: String = _validate_payload_key_set(package_info, referenced_keys)
	if not payload_validation.is_empty():
		return _fail_result(payload_validation)
	var staging: String = _new_staging_directory()
	var required_keys: Dictionary = plan.get("required_payload_keys", {}) as Dictionary
	var materialized: Dictionary = NotLightPortablePackageFormat.materialize_payloads(package_info, required_keys, staging)
	if not bool(materialized.get("ok", false)):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _fail_result(str(materialized.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.3b1aa484a1"))))
	var note_embed_validation: String = _validate_materialized_note_embed_closure(
		manifest,
		plan,
		materialized.get("files", {}) as Dictionary
	)
	if not note_embed_validation.is_empty():
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _fail_result(note_embed_validation)
	var catalog_snapshot: Dictionary = library.make_catalog_snapshot()
	if catalog_snapshot.is_empty():
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _fail_result(NotLightL10n.text("runtime.portable.notlight_portable_package_service.68869d9eca"))
	var commit: Dictionary = _commit_import_plan(plan, materialized.get("files", {}) as Dictionary)
	if not bool(commit.get("ok", false)):
		return _rollback_and_fail(
			str(commit.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.ef7aeaa41b"))),
			catalog_snapshot,
			_string_array(commit.get("new_blob_paths", [])),
			staging
		)
	NotLightPortablePackageFormat.cleanup_directory(staging)
	return {
		"ok": true,
		"assets_added": int(commit.get("assets_added", 0)),
		"assets_reused": int(commit.get("assets_reused", 0)),
		"folders_added": int(commit.get("folders_added", 0)),
	}


func _collect_note_embed_dependencies(note_ids: PackedStringArray, strict: bool = true) -> Dictionary:
	var asset_ids: PackedStringArray = PackedStringArray()
	var seen_asset_ids: Dictionary = {}
	var seen_hashes: Dictionary = {}
	var missing_hashes: PackedStringArray = PackedStringArray()
	for note_id: String in note_ids:
		var note: Dictionary = library.get_asset(note_id)
		if note.is_empty() or int(note.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.8769d39721") % note_id}
		var path: String = library.resolve_asset_path(note_id)
		if path.is_empty() or not FileAccess.file_exists(path):
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.d0341972fd") % note_id}
		var expected_size: int = int(note.get("byte_size", -1))
		if expected_size < 0 or expected_size > AssetImportContentValidator.MAX_NOTE_BYTES:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.59f7ae8f23") % note_id}
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.37f4176ea1") % note_id}
		if int(file.get_length()) != expected_size:
			file.close()
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.933b5544dc") % note_id}
		var bytes: PackedByteArray = file.get_buffer(expected_size)
		file.close()
		if bytes.size() != expected_size or not AssetImportContentValidator._is_valid_utf8(bytes):
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.7671a7b249") % note_id}
		var expected_hash: String = str(note.get("hash_sha256", "")).to_lower()
		if expected_hash.length() != 64 or FileAccess.get_sha256(path).to_lower() != expected_hash:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.0f11910f6b") % note_id}
		var content: String = bytes.get_string_from_utf8()
		for hash_sha256: String in NoteResourceEmbed.extract_hashes(content):
			if seen_hashes.has(hash_sha256):
				continue
			seen_hashes[hash_sha256] = true
			var embedded_asset: Dictionary = library.find_asset_by_hash(hash_sha256)
			if embedded_asset.is_empty():
				missing_hashes.append(hash_sha256)
				if strict:
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.942ade4383") % hash_sha256}
				continue
			var embedded_kind: int = int(embedded_asset.get("kind", AssetKinds.OTHER))
			if not NoteResourceEmbed.is_embeddable_kind(embedded_kind):
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.2ea8ee6b9f") % AssetKinds.label(embedded_kind)}
			var embedded_hash: String = str(embedded_asset.get("hash_sha256", "")).strip_edges().to_lower()
			if embedded_hash != hash_sha256 or not NoteResourceEmbed.is_sha256(embedded_hash):
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.464cc5463a")}
			var embedded_id: String = str(embedded_asset.get("id", "")).strip_edges()
			var embedded_path: String = library.resolve_asset_path(embedded_id)
			if embedded_path.is_empty() or not FileAccess.file_exists(embedded_path):
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.c8774d9f5e")}
			if FileAccess.get_sha256(embedded_path).to_lower() != embedded_hash:
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.b9b15a3a25")}
			if embedded_id.is_empty() or seen_asset_ids.has(embedded_id):
				continue
			seen_asset_ids[embedded_id] = true
			asset_ids.append(embedded_id)
	return {"ok": true, "asset_ids": asset_ids, "missing_hashes": missing_hashes}


func _validate_materialized_note_embed_closure(
	manifest: Dictionary,
	plan: Dictionary,
	staged_files: Dictionary
) -> String:
	var dependency_ids: PackedStringArray = _note_embed_dependency_ids_for_manifest(manifest)
	if dependency_ids.is_empty():
		return ""
	var items: Array[Dictionary] = _dictionary_array(plan.get("asset_items", []))
	var item_by_source_id: Dictionary = {}
	for item: Dictionary in items:
		var source_id: String = str(item.get("source_id", "")).strip_edges()
		if not source_id.is_empty():
			item_by_source_id[source_id] = item
	var dependency_hashes: Dictionary = {}
	for dependency_id: String in dependency_ids:
		if not item_by_source_id.has(dependency_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.0170b89076") % dependency_id
		var dependency_item: Dictionary = item_by_source_id[dependency_id] as Dictionary
		var dependency_record: Dictionary = dependency_item.get("record", {}) as Dictionary
		if not NoteResourceEmbed.is_embeddable_kind(int(dependency_record.get("kind", AssetKinds.OTHER))):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.2d8dbece8a")
		var dependency_hash: String = str(dependency_record.get("hash_sha256", "")).strip_edges().to_lower()
		if not NoteResourceEmbed.is_sha256(dependency_hash) or dependency_hashes.has(dependency_hash):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.21e5a75d09")
		dependency_hashes[dependency_hash] = true
	var referenced_hashes: Dictionary = {}
	for item: Dictionary in items:
		var record: Dictionary = item.get("record", {}) as Dictionary
		if int(record.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE:
			continue
		var read_result: Dictionary = _read_import_note_content(item, staged_files)
		if not bool(read_result.get("ok", false)):
			return str(read_result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.c334c43a6d")))
		var content: String = str(read_result.get("content", ""))
		for hash_sha256: String in NoteResourceEmbed.extract_hashes(content):
			referenced_hashes[hash_sha256] = true
			if not dependency_hashes.has(hash_sha256):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.3242c3b712") % hash_sha256
	for raw_hash: Variant in dependency_hashes.keys():
		var dependency_hash: String = str(raw_hash)
		if not referenced_hashes.has(dependency_hash):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.ab73752081") % dependency_hash
	return ""


func _note_embed_dependency_ids_for_manifest(manifest: Dictionary) -> PackedStringArray:
	var package_type: String = str(manifest.get("package_type", ""))
	if package_type == NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY:
		var library_value: Variant = manifest.get("library", {})
		if library_value is Dictionary:
			return _string_array((library_value as Dictionary).get("note_embed_dependency_ids", []))
		return PackedStringArray()
	if package_type == NotLightPortablePackageFormat.PACKAGE_TYPE_BOARD:
		var board_value: Variant = manifest.get("board", {})
		if board_value is not Dictionary:
			return PackedStringArray()
		var policy_value: Variant = (board_value as Dictionary).get("resource_policy", {})
		if policy_value is not Dictionary or not bool((policy_value as Dictionary).get("include_note_embeds", false)):
			return PackedStringArray()
		return _string_array((policy_value as Dictionary).get("note_embed_asset_ids", []))
	return PackedStringArray()


func _read_import_note_content(item: Dictionary, staged_files: Dictionary) -> Dictionary:
	var record: Dictionary = item.get("record", {}) as Dictionary
	var expected_hash: String = str(record.get("hash_sha256", "")).strip_edges().to_lower()
	var expected_size: int = int(record.get("byte_size", -1))
	if not NoteResourceEmbed.is_sha256(expected_hash) or expected_size < 0 or expected_size > AssetImportContentValidator.MAX_NOTE_BYTES:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.479c2e35af")}
	var source_path: String = ""
	var primary_binding: Dictionary = _primary_binding({
		"record": record,
		"blobs": item.get("blobs", []),
	})
	if not primary_binding.is_empty():
		var payload_key: String = str(primary_binding.get("payload_key", "")).strip_edges()
		if staged_files.has(payload_key):
			source_path = str(staged_files.get(payload_key, ""))
	if source_path.is_empty():
		var target_id: String = str(item.get("target_id", item.get("source_id", ""))).strip_edges()
		source_path = library.resolve_asset_path(target_id)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.17e2d74a94")}
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.62109d64ff")}
	var actual_size: int = int(file.get_length())
	if actual_size != expected_size:
		file.close()
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.dd5a636b16")}
	var bytes: PackedByteArray = file.get_buffer(actual_size)
	file.close()
	if bytes.size() != actual_size or not AssetImportContentValidator._is_valid_utf8(bytes):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.130fcbb069")}
	for value: int in bytes:
		if value == 0:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.deaae55ebe")}
	if FileAccess.get_sha256(source_path).to_lower() != expected_hash:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.c559c7ebf3")}
	return {"ok": true, "content": bytes.get_string_from_utf8()}


func _build_export_asset_bundle(asset_ids: PackedStringArray, include_all_folders: bool) -> Dictionary:
	var embedded_set: Dictionary = {}
	for asset_id: String in asset_ids:
		embedded_set[asset_id] = true
	return _build_export_asset_bundle_profile(asset_ids, include_all_folders, embedded_set, true)


func _build_export_asset_bundle_profile(
	asset_ids: PackedStringArray,
	include_all_folders: bool,
	embedded_set: Dictionary,
	include_derived_variants: bool
) -> Dictionary:
	var assets: Array[Dictionary] = []
	var payload_sources: Array[Dictionary] = []
	var payload_keys: Dictionary = {}
	var required_folder_ids: Dictionary = {}
	var all_folders: Array[Dictionary] = library.list_folders()
	var folder_by_id: Dictionary = {}
	for folder: Dictionary in all_folders:
		folder_by_id[str(folder.get("id", ""))] = folder
	for asset_id: String in asset_ids:
		var asset: Dictionary = library.get_asset(asset_id)
		if asset.is_empty():
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.b48218e181") % asset_id}
		var is_embedded: bool = embedded_set.has(asset_id)
		var entry_result: Dictionary = (
			_build_export_asset_entry(asset, payload_keys, payload_sources, include_derived_variants)
			if is_embedded
			else _build_external_asset_entry(asset)
		)
		if not bool(entry_result.get("ok", false)):
			return entry_result
		assets.append(entry_result.get("entry", {}) as Dictionary)
		if not is_embedded:
			continue
		var folder_id: String = str(asset.get("folder_id", "")).strip_edges()
		while not folder_id.is_empty():
			if required_folder_ids.has(folder_id):
				break
			if not folder_by_id.has(folder_id):
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.e128af7564")}
			required_folder_ids[folder_id] = true
			var folder: Dictionary = folder_by_id[folder_id] as Dictionary
			folder_id = str(folder.get("parent_id", "")).strip_edges()
	var folders: Array[Dictionary] = []
	for folder: Dictionary in all_folders:
		var folder_id: String = str(folder.get("id", ""))
		if include_all_folders or required_folder_ids.has(folder_id):
			folders.append(folder.duplicate(true))
	var folder_validation: String = _validate_source_folders(folders)
	if not folder_validation.is_empty():
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.17ceb38cb3") % folder_validation}
	return {
		"ok": true,
		"assets": assets,
		"folders": folders,
		"payload_sources": payload_sources,
	}


func _build_external_asset_entry(asset: Dictionary) -> Dictionary:
	var record: Dictionary = _portable_asset_record(asset, false)
	var asset_id: String = str(record.get("id", "")).strip_edges()
	var display_name: String = str(record.get("display_name", "")).strip_edges()
	var original_filename: String = str(record.get("original_filename", "")).strip_edges()
	if asset_id.is_empty() or asset_id.length() > 128:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.64e2674a4f")}
	if display_name.length() > 120 or original_filename.length() > 512:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.e6d2b5d0a9")}
	var primary_relpath: String = str(record.get("blob_relpath", "")).strip_edges()
	var primary_hash: String = str(record.get("hash_sha256", "")).strip_edges().to_lower()
	var primary_extension: String = str(record.get("extension", "")).strip_edges().to_lower()
	var validation: Dictionary = _make_export_blob_binding(primary_relpath, primary_hash, primary_extension)
	if not bool(validation.get("ok", false)):
		return validation
	record["folder_id"] = ""
	return {"ok": true, "entry": {"embedded": false, "record": record, "blobs": []}}


func _build_export_asset_entry(
	asset: Dictionary,
	payload_keys: Dictionary,
	payload_sources: Array[Dictionary],
	include_derived_variants: bool = true
) -> Dictionary:
	var record: Dictionary = _portable_asset_record(asset, include_derived_variants)
	var asset_id: String = str(record.get("id", "")).strip_edges()
	var display_name: String = str(record.get("display_name", "")).strip_edges()
	var original_filename: String = str(record.get("original_filename", "")).strip_edges()
	var folder_id: String = str(record.get("folder_id", "")).strip_edges()
	if asset_id.is_empty() or asset_id.length() > 128 or folder_id.length() > 128:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.64e2674a4f")}
	if display_name.length() > 120 or original_filename.length() > 512:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.e6d2b5d0a9")}
	var bindings: Array[Dictionary] = []
	var seen_relpaths: Dictionary = {}
	var primary_relpath: String = str(record.get("blob_relpath", "")).strip_edges()
	var primary_hash: String = str(record.get("hash_sha256", "")).strip_edges().to_lower()
	var primary_extension: String = str(record.get("extension", "")).strip_edges().to_lower()
	var primary_binding: Dictionary = _make_export_blob_binding(primary_relpath, primary_hash, primary_extension)
	if not bool(primary_binding.get("ok", false)):
		return primary_binding
	_bind_export_blob(primary_binding, bindings, seen_relpaths, payload_keys, payload_sources)
	if include_derived_variants:
		var metadata_value: Variant = record.get("metadata", {})
		if metadata_value is not Dictionary:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.50efcb93d8")}
		var metadata: Dictionary = metadata_value as Dictionary
		for media_key: String in AssetDurableVariants.SUPPORTED_NAMESPACES:
			var state_value: Variant = metadata.get(media_key, {})
			if state_value is not Dictionary:
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.b493a38baf") % media_key}
			var state: Dictionary = state_value as Dictionary
			var variants_value: Variant = state.get("variants", {})
			if variants_value is not Dictionary:
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.ace0da225d")}
			var variants: Dictionary = variants_value as Dictionary
			for raw_variant_key: Variant in variants.keys():
				var variant_value: Variant = variants[raw_variant_key]
				if variant_value is not Dictionary:
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.65c6df5e49")}
				var variant: Dictionary = variant_value as Dictionary
				var relpath: String = str(variant.get("blob_relpath", "")).strip_edges()
				if relpath.is_empty() or seen_relpaths.has(relpath):
					continue
				var hash_sha256: String = str(variant.get("hash_sha256", "")).strip_edges().to_lower()
				var extension: String = str(variant.get("extension", relpath.get_extension())).strip_edges().to_lower()
				var binding: Dictionary = _make_export_blob_binding(relpath, hash_sha256, extension)
				if not bool(binding.get("ok", false)):
					return binding
				_bind_export_blob(binding, bindings, seen_relpaths, payload_keys, payload_sources)
	return {"ok": true, "entry": {"embedded": true, "record": record, "blobs": bindings}}


func _portable_asset_record(asset: Dictionary, include_derived_variants: bool) -> Dictionary:
	var record: Dictionary = asset.duplicate(true)
	record.erase("usage_count")
	record.erase("used")
	record.erase("used_on_boards")
	if include_derived_variants:
		return record
	var metadata_value: Variant = record.get("metadata", {})
	if metadata_value is not Dictionary:
		return record
	var metadata: Dictionary = (metadata_value as Dictionary).duplicate(true)
	for media_key: String in AssetDurableVariants.SUPPORTED_NAMESPACES:
		var state_value: Variant = metadata.get(media_key, {})
		if state_value is not Dictionary:
			continue
		var state: Dictionary = (state_value as Dictionary).duplicate(true)
		state.erase("variants")
		state.erase("preferred_variant")
		metadata[media_key] = state
	record["metadata"] = metadata
	return record


func _asset_durable_byte_size(asset: Dictionary) -> int:
	var sizes_by_path: Dictionary = {}
	var primary_path: String = str(asset.get("blob_relpath", "")).strip_edges()
	if not primary_path.is_empty():
		sizes_by_path[primary_path] = maxi(0, int(asset.get("byte_size", 0)))
	var metadata_value: Variant = asset.get("metadata", {})
	if metadata_value is Dictionary:
		var metadata: Dictionary = metadata_value as Dictionary
		for media_key: String in AssetDurableVariants.SUPPORTED_NAMESPACES:
			var state_value: Variant = metadata.get(media_key, {})
			if state_value is not Dictionary:
				continue
			var variants_value: Variant = (state_value as Dictionary).get("variants", {})
			if variants_value is not Dictionary:
				continue
			for raw_variant: Variant in (variants_value as Dictionary).values():
				if raw_variant is not Dictionary:
					continue
				var variant: Dictionary = raw_variant as Dictionary
				var relpath: String = str(variant.get("blob_relpath", "")).strip_edges()
				if not relpath.is_empty():
					sizes_by_path[relpath] = maxi(0, int(variant.get("byte_size", 0)))
	var total: int = 0
	for raw_size: Variant in sizes_by_path.values():
		total += maxi(0, int(raw_size))
	return total


func _make_export_blob_binding(relative_path: String, expected_hash: String, extension: String) -> Dictionary:
	var clean_relpath: String = relative_path.strip_edges().replace("\\", "/")
	var source_path: String = library.resolve_blob_relative(clean_relpath)
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.ccdee94c8a") % clean_relpath}
	var hash_sha256: String = FileAccess.get_sha256(source_path).to_lower()
	if not _is_sha256(hash_sha256):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.180de6428d") % clean_relpath}
	var clean_expected: String = expected_hash.strip_edges().to_lower()
	if not clean_expected.is_empty() and clean_expected != hash_sha256:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.58cd13564f") % clean_relpath}
	var clean_extension: String = extension.strip_edges().to_lower()
	if clean_extension.is_empty():
		clean_extension = clean_relpath.get_extension().to_lower()
	if not _is_safe_extension(clean_extension):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.c59791d6aa") % clean_relpath}
	if not _blob_path_matches_hash_and_extension(clean_relpath, hash_sha256, clean_extension):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.be940cc3a3") % clean_relpath}
	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.6b6b637476") % clean_relpath}
	var byte_size: int = int(source_file.get_length())
	source_file.close()
	return {
		"ok": true,
		"source_relpath": clean_relpath,
		"hash_sha256": hash_sha256,
		"extension": clean_extension,
		"byte_size": byte_size,
		"payload_key": _blob_payload_key(hash_sha256, clean_extension),
		"source_path": source_path,
	}


func _bind_export_blob(
	binding: Dictionary,
	bindings: Array[Dictionary],
	seen_relpaths: Dictionary,
	payload_keys: Dictionary,
	payload_sources: Array[Dictionary]
) -> void:
	var clean_binding: Dictionary = binding.duplicate(true)
	clean_binding.erase("ok")
	var source_path: String = str(clean_binding.get("source_path", ""))
	clean_binding.erase("source_path")
	bindings.append(clean_binding)
	seen_relpaths[str(clean_binding.get("source_relpath", ""))] = true
	var payload_key: String = str(clean_binding.get("payload_key", ""))
	if not payload_keys.has(payload_key):
		payload_sources.append({
			"key": payload_key,
			"source_path": source_path,
			"expected_sha256": str(clean_binding.get("hash_sha256", "")),
			"purpose": "asset_blob",
		})
		payload_keys[payload_key] = true


func _build_import_plan(manifest: Dictionary, package_info: Dictionary) -> Dictionary:
	var folders_value: Variant = manifest.get("folders", [])
	var assets_value: Variant = manifest.get("assets", [])
	if folders_value is not Array or assets_value is not Array:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.46e4013275")}
	if (folders_value as Array).size() > MAX_PORTABLE_FOLDERS or (assets_value as Array).size() > MAX_PORTABLE_ASSETS:
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.6e76316939")}
	var package_type: String = str(manifest.get("package_type", ""))
	var manifest_schema_version: int = int(manifest.get("schema_version", 0))
	var allow_external_assets: bool = (
		package_type == NotLightPortablePackageFormat.PACKAGE_TYPE_BOARD
		and manifest_schema_version >= 2
	)
	var source_folders: Array[Dictionary] = []
	for raw_folder: Variant in (folders_value as Array):
		if raw_folder is not Dictionary:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.b14769b9fd")}
		source_folders.append((raw_folder as Dictionary).duplicate(true))
	var folder_error: String = _validate_source_folders(source_folders)
	if not folder_error.is_empty():
		return {"ok": false, "error": folder_error}
	var folder_plan: Dictionary = _plan_folders(source_folders)
	if not bool(folder_plan.get("ok", false)):
		return folder_plan
	var payload_by_key: Dictionary = package_info.get("payload_by_key", {}) as Dictionary
	var source_entries: Array[Dictionary] = []
	var seen_asset_ids: Dictionary = {}
	var seen_hashes: Dictionary = {}
	var referenced_payload_keys: Dictionary = {}
	for raw_entry: Variant in (assets_value as Array):
		if raw_entry is not Dictionary:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.f1c288c9b5")}
		var entry: Dictionary = raw_entry as Dictionary
		var embedded: bool = bool(entry.get("embedded", true))
		if not embedded and not allow_external_assets:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.0499c50752")}
		var record_value: Variant = entry.get("record", {})
		var blobs_value: Variant = entry.get("blobs", [])
		if record_value is not Dictionary or blobs_value is not Array:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.d5e06f5370")}
		if not embedded and not (blobs_value as Array).is_empty():
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.f20f6028de")}
		var record: Dictionary = (record_value as Dictionary).duplicate(true)
		var source_id: String = str(record.get("id", "")).strip_edges()
		var primary_hash: String = str(record.get("hash_sha256", "")).strip_edges().to_lower()
		var original_filename: String = str(record.get("original_filename", "")).strip_edges()
		var display_name: String = str(record.get("display_name", original_filename)).strip_edges()
		var source_folder_id: String = str(record.get("folder_id", "")).strip_edges()
		if not embedded and not source_folder_id.is_empty():
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.31a5708373")}
		if original_filename.length() > 512 or display_name.length() > 120:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.4f7c6ac8dd")}
		if display_name.is_empty():
			display_name = original_filename if not original_filename.is_empty() else NotLightL10n.text("library.resource")
		record["id"] = source_id
		record["hash_sha256"] = primary_hash
		record["original_filename"] = original_filename
		record["display_name"] = display_name
		if source_id.length() > 128 or source_folder_id.length() > 128:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.bdefb344cd")}
		if source_id.is_empty() or seen_asset_ids.has(source_id):
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.8721adf0b3")}
		var source_is_note: bool = int(record.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
		if not _is_sha256(primary_hash):
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.84402c69d9")}
		if not source_is_note and seen_hashes.has(primary_hash):
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.73fc269cfe")}
		var blob_bindings: Array[Dictionary] = []
		var seen_relpaths: Dictionary = {}
		var has_primary: bool = false
		if embedded:
			for raw_binding: Variant in (blobs_value as Array):
				if raw_binding is not Dictionary:
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.d1226d190a")}
				var binding: Dictionary = (raw_binding as Dictionary).duplicate(true)
				var relpath: String = str(binding.get("source_relpath", "")).strip_edges().replace("\\", "/")
				var hash_sha256: String = str(binding.get("hash_sha256", "")).strip_edges().to_lower()
				var payload_key: String = str(binding.get("payload_key", "")).strip_edges()
				var byte_size: int = int(binding.get("byte_size", -1))
				var extension: String = str(binding.get("extension", "")).strip_edges().to_lower()
				if relpath.is_empty() or relpath.length() > 1024 or seen_relpaths.has(relpath):
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.b459ea6621")}
				if not _is_sha256(hash_sha256) or not _is_safe_extension(extension) or payload_key.is_empty() or byte_size < 0:
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.bbed939b73")}
				if not _blob_path_matches_hash_and_extension(relpath, hash_sha256, extension):
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.09156e0759")}
				if payload_key != _blob_payload_key(hash_sha256, extension):
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.84291e94d0")}
				if not payload_by_key.has(payload_key):
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.fe390205d0") % payload_key}
				var payload: Dictionary = payload_by_key[payload_key] as Dictionary
				if str(payload.get("sha256", "")) != hash_sha256 or int(payload.get("byte_size", -1)) != byte_size:
					return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.1e67640c32")}
				if relpath == str(record.get("blob_relpath", "")).replace("\\", "/"):
					has_primary = hash_sha256 == primary_hash
				blob_bindings.append(binding)
				seen_relpaths[relpath] = true
				referenced_payload_keys[payload_key] = true
			if not has_primary:
				return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.a60cd51fa2")}
			var variant_error: String = _validate_media_variant_bindings(record, seen_relpaths)
			if not variant_error.is_empty():
				return {"ok": false, "error": variant_error}
		source_entries.append({"embedded": embedded, "record": record, "blobs": blob_bindings})
		seen_asset_ids[source_id] = true
		if not source_is_note:
			seen_hashes[primary_hash] = true
	var asset_plan: Dictionary = _plan_assets(source_entries, folder_plan.get("folder_id_map", {}) as Dictionary)
	if not bool(asset_plan.get("ok", false)):
		return asset_plan
	var required_payload_keys: Dictionary = asset_plan.get("required_payload_keys", {}) as Dictionary
	return {
		"ok": true,
		"new_folders": folder_plan.get("new_folders", []),
		"folder_id_map": folder_plan.get("folder_id_map", {}),
		"asset_items": asset_plan.get("asset_items", []),
		"asset_id_map": asset_plan.get("asset_id_map", {}),
		"required_payload_keys": required_payload_keys,
		"referenced_payload_keys": referenced_payload_keys,
	}


func _plan_folders(source_folders: Array[Dictionary]) -> Dictionary:
	var local_folders: Array[Dictionary] = library.list_folders()
	var local_by_id: Dictionary = {}
	for folder: Dictionary in local_folders:
		local_by_id[str(folder.get("id", ""))] = folder
	var folder_id_map: Dictionary = {}
	var new_folders: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for folder: Dictionary in source_folders:
		pending.append(folder.duplicate(true))
	var reserved_ids: Dictionary = local_by_id.duplicate()
	while not pending.is_empty():
		var progressed: bool = false
		for index: int in range(pending.size() - 1, -1, -1):
			var source: Dictionary = pending[index]
			var source_id: String = str(source.get("id", ""))
			var source_parent: String = str(source.get("parent_id", ""))
			if not source_parent.is_empty() and not folder_id_map.has(source_parent):
				continue
			var target_parent: String = str(folder_id_map.get(source_parent, ""))
			var existing_id: String = _find_folder_by_name(local_folders, new_folders, str(source.get("name", "")), target_parent)
			if not existing_id.is_empty():
				folder_id_map[source_id] = existing_id
			else:
				var target_id: String = source_id
				if target_id.is_empty() or reserved_ids.has(target_id):
					target_id = AssetId.make_uuid()
					while reserved_ids.has(target_id):
						target_id = AssetId.make_uuid()
				var target: Dictionary = source.duplicate(true)
				target["id"] = target_id
				target["parent_id"] = target_parent
				new_folders.append(target)
				folder_id_map[source_id] = target_id
				reserved_ids[target_id] = target
			pending.remove_at(index)
			progressed = true
		if not progressed:
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.5ee5ba1932")}
	return {"ok": true, "folder_id_map": folder_id_map, "new_folders": new_folders}


func _prune_unused_board_folders(plan: Dictionary) -> void:
	# Folder identity belongs to the Resource Library, not the board. If every
	# packaged asset under a source folder deduplicates to an already-existing
	# local asset, importing that board must not leave an empty copy of the
	# sender's folder tree behind. Keep only new folders required by assets that
	# are actually being added on this machine. Full library import intentionally
	# does not use this pruning because empty folders are part of a library snapshot.
	var new_folders: Array[Dictionary] = _dictionary_array(plan.get("new_folders", []))
	if new_folders.is_empty():
		return
	var new_by_id: Dictionary = {}
	for folder: Dictionary in new_folders:
		new_by_id[str(folder.get("id", ""))] = folder
	var required_ids: Dictionary = {}
	for item: Dictionary in _dictionary_array(plan.get("asset_items", [])):
		if str(item.get("mode", "")) != "add":
			continue
		var cursor: String = str(item.get("target_folder_id", "")).strip_edges()
		while new_by_id.has(cursor) and not required_ids.has(cursor):
			required_ids[cursor] = true
			var folder: Dictionary = new_by_id[cursor] as Dictionary
			cursor = str(folder.get("parent_id", "")).strip_edges()
	var filtered: Array[Dictionary] = []
	for folder: Dictionary in new_folders:
		if required_ids.has(str(folder.get("id", ""))):
			filtered.append(folder)
	plan["new_folders"] = filtered


func _plan_assets(source_entries: Array[Dictionary], folder_id_map: Dictionary) -> Dictionary:
	var local_assets: Array[Dictionary] = library.list_assets()
	var local_by_id: Dictionary = {}
	var local_by_hash: Dictionary = {}
	for asset: Dictionary in local_assets:
		var local_id: String = str(asset.get("id", ""))
		local_by_id[local_id] = asset
		# Hash identity is sufficient for immutable media, but not for Notes. Two
		# logical notes may intentionally contain identical Markdown bytes.
		if int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE:
			var local_hash: String = str(asset.get("hash_sha256", "")).to_lower()
			if not local_hash.is_empty() and not local_by_hash.has(local_hash):
				local_by_hash[local_hash] = asset
	var reserved_ids: Dictionary = local_by_id.duplicate()
	var asset_id_map: Dictionary = {}
	var asset_items: Array[Dictionary] = []
	var required_payload_keys: Dictionary = {}
	for entry: Dictionary in source_entries:
		var embedded: bool = bool(entry.get("embedded", true))
		var record: Dictionary = entry.get("record", {}) as Dictionary
		var source_id: String = str(record.get("id", ""))
		var hash_sha256: String = str(record.get("hash_sha256", "")).to_lower()
		var source_is_note: bool = int(record.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
		var same_id_record: Dictionary = local_by_id.get(source_id, {}) as Dictionary

		if source_is_note:
			var same_logical_note: bool = (
				not same_id_record.is_empty()
				and int(same_id_record.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
				and str(same_id_record.get("hash_sha256", "")).to_lower() == hash_sha256
			)
			if not embedded:
				# A thin package must never bind a NotePortal to an arbitrary different
				# note merely because its current text happens to share the same SHA.
				if not same_logical_note:
					return {
						"ok": false,
						"error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.ad58d77766") % str(record.get("display_name", source_id)),
					}
				var note_external_path: String = library.resolve_asset_path(source_id)
				if (
					note_external_path.is_empty()
					or not FileAccess.file_exists(note_external_path)
					or FileAccess.get_sha256(note_external_path).to_lower() != hash_sha256
				):
					return {
						"ok": false,
						"error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.5e796f9ff4") % str(record.get("display_name", source_id)),
					}
				asset_id_map[source_id] = source_id
				asset_items.append({
					"mode": "reuse_external",
					"source_id": source_id,
					"target_id": source_id,
					"record": record,
					"existing_record": same_id_record,
				})
				continue
			if same_logical_note:
				asset_id_map[source_id] = source_id
				var note_existing_path: String = library.resolve_asset_path(source_id)
				var note_repair_binding: Dictionary = {}
				var note_blob_valid: bool = (
					not note_existing_path.is_empty()
					and FileAccess.file_exists(note_existing_path)
					and FileAccess.get_sha256(note_existing_path).to_lower() == hash_sha256
				)
				if not note_blob_valid:
					note_repair_binding = _primary_binding(entry)
					if note_repair_binding.is_empty():
						return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.cab15cf24f")}
					required_payload_keys[str(note_repair_binding.get("payload_key", ""))] = true
				asset_items.append({
					"mode": "reuse",
					"source_id": source_id,
					"target_id": source_id,
					"record": record,
					"blobs": entry.get("blobs", []),
					"existing_record": same_id_record,
					"repair_binding": note_repair_binding,
				})
				continue
		else:
			if not embedded:
				if not local_by_hash.has(hash_sha256):
					return {
						"ok": false,
						"error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.d6de20ff9c") % [str(record.get("display_name", source_id)), hash_sha256],
					}
				var external_existing: Dictionary = local_by_hash[hash_sha256] as Dictionary
				var external_id: String = str(external_existing.get("id", ""))
				var external_path: String = library.resolve_asset_path(external_id)
				if (
					external_path.is_empty()
					or not FileAccess.file_exists(external_path)
					or FileAccess.get_sha256(external_path).to_lower() != hash_sha256
				):
					return {
						"ok": false,
						"error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.153d444621") % str(record.get("display_name", source_id)),
					}
				asset_id_map[source_id] = external_id
				asset_items.append({
					"mode": "reuse_external",
					"source_id": source_id,
					"target_id": external_id,
					"record": record,
					"existing_record": external_existing,
				})
				continue
			if local_by_hash.has(hash_sha256):
				var existing: Dictionary = local_by_hash[hash_sha256] as Dictionary
				var existing_id: String = str(existing.get("id", ""))
				asset_id_map[source_id] = existing_id
				var existing_path: String = library.resolve_asset_path(existing_id)
				var repair_binding: Dictionary = {}
				var local_blob_is_valid: bool = (
					not existing_path.is_empty()
					and FileAccess.file_exists(existing_path)
					and FileAccess.get_sha256(existing_path).to_lower() == hash_sha256
				)
				if not local_blob_is_valid:
					repair_binding = _primary_binding(entry)
					if repair_binding.is_empty():
						return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.ba7a0609e8")}
					required_payload_keys[str(repair_binding.get("payload_key", ""))] = true
				asset_items.append({
					"mode": "reuse",
					"source_id": source_id,
					"target_id": existing_id,
					"record": record,
					"blobs": entry.get("blobs", []),
					"existing_record": existing,
					"repair_binding": repair_binding,
				})
				continue

		var target_id: String = source_id
		if target_id.is_empty() or reserved_ids.has(target_id):
			target_id = AssetId.make_uuid()
			while reserved_ids.has(target_id):
				target_id = AssetId.make_uuid()
		reserved_ids[target_id] = true
		asset_id_map[source_id] = target_id
		var source_folder_id: String = str(record.get("folder_id", "")).strip_edges()
		if not source_folder_id.is_empty() and not folder_id_map.has(source_folder_id):
			return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.39d0831ca6")}
		var target_folder_id: String = str(folder_id_map.get(source_folder_id, ""))
		for binding: Dictionary in _dictionary_array(entry.get("blobs", [])):
			required_payload_keys[str(binding.get("payload_key", ""))] = true
		asset_items.append({
			"mode": "add",
			"source_id": source_id,
			"target_id": target_id,
			"target_folder_id": target_folder_id,
			"record": record,
			"blobs": entry.get("blobs", []),
		})
	return {
		"ok": true,
		"asset_items": asset_items,
		"asset_id_map": asset_id_map,
		"required_payload_keys": required_payload_keys,
	}


func _commit_import_plan(plan: Dictionary, staged_files: Dictionary) -> Dictionary:
	var new_blob_paths: PackedStringArray = PackedStringArray()
	var committed_by_key: Dictionary = {}
	var new_assets: Array[Dictionary] = []
	var assets_added: int = 0
	var assets_reused: int = 0
	var asset_items: Array[Dictionary] = _dictionary_array(plan.get("asset_items", []))
	for item: Dictionary in asset_items:
		var mode: String = str(item.get("mode", ""))
		if mode == "reuse_external":
			assets_reused += 1
			continue
		if mode == "reuse":
			assets_reused += 1
			var repair_binding: Dictionary = item.get("repair_binding", {}) as Dictionary
			if not repair_binding.is_empty():
				var existing_record: Dictionary = item.get("existing_record", {}) as Dictionary
				var repair_result: Dictionary = _commit_binding(
					repair_binding,
					staged_files,
					str(existing_record.get("extension", repair_binding.get("extension", ""))),
					new_blob_paths
				)
				if not bool(repair_result.get("ok", false)):
					return _commit_failure(str(repair_result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.40f54ee678"))), new_blob_paths)
				committed_by_key[str(repair_binding.get("payload_key", ""))] = repair_result
				var repaired_relpath: String = str(repair_result.get("relative_path", ""))
				if repaired_relpath != str(existing_record.get("blob_relpath", "")):
					if not library.repair_catalog_blob_location(
						str(existing_record.get("id", "")),
						repaired_relpath,
						int(repair_binding.get("byte_size", 0)),
						str(existing_record.get("extension", repair_binding.get("extension", "")))
					):
						return _commit_failure(library.get_last_error(), new_blob_paths)
			continue
		if mode != "add":
			return _commit_failure(NotLightL10n.text("runtime.portable.notlight_portable_package_service.8ad053dba4"), new_blob_paths)
		var relpath_map: Dictionary = {}
		for binding: Dictionary in _dictionary_array(item.get("blobs", [])):
			var payload_key: String = str(binding.get("payload_key", ""))
			var commit_result: Dictionary = {}
			if committed_by_key.has(payload_key):
				commit_result = committed_by_key[payload_key] as Dictionary
			else:
				commit_result = _commit_binding(binding, staged_files, str(binding.get("extension", "")), new_blob_paths)
				if not bool(commit_result.get("ok", false)):
					return _commit_failure(str(commit_result.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_service.e46ea2cc76"))), new_blob_paths)
				committed_by_key[payload_key] = commit_result
			relpath_map[str(binding.get("source_relpath", ""))] = str(commit_result.get("relative_path", ""))
		var imported_record: Dictionary = _rewrite_asset_record(
			item.get("record", {}) as Dictionary,
			str(item.get("target_id", "")),
			str(item.get("target_folder_id", "")),
			relpath_map,
			_dictionary_array(item.get("blobs", []))
		)
		if imported_record.is_empty():
			return _commit_failure(NotLightL10n.text("runtime.portable.notlight_portable_package_service.112e72d439"), new_blob_paths)
		new_assets.append(imported_record)
		assets_added += 1
	var new_folders: Array[Dictionary] = _dictionary_array(plan.get("new_folders", []))
	if not library.apply_catalog_import_batch(new_folders, new_assets):
		return _commit_failure(library.get_last_error(), new_blob_paths)
	return {
		"ok": true,
		"new_blob_paths": new_blob_paths,
		"asset_id_map": plan.get("asset_id_map", {}),
		"assets_added": assets_added,
		"assets_reused": assets_reused,
		"folders_added": new_folders.size(),
	}


func _commit_binding(binding: Dictionary, staged_files: Dictionary, extension_override: String, new_blob_paths: PackedStringArray) -> Dictionary:
	var payload_key: String = str(binding.get("payload_key", ""))
	var staged_path: String = str(staged_files.get(payload_key, ""))
	if staged_path.is_empty() or not FileAccess.file_exists(staged_path):
		return {"ok": false, "error": NotLightL10n.text("runtime.portable.notlight_portable_package_service.c06e791b8f") % payload_key}
	var extension: String = extension_override.strip_edges().to_lower()
	if extension.is_empty():
		extension = str(binding.get("extension", "")).strip_edges().to_lower()
	var result: Dictionary = library.blobs.commit_temp(staged_path, str(binding.get("hash_sha256", "")), extension)
	if result.is_empty():
		return {"ok": false, "error": library.blobs.get_last_error()}
	if not bool(result.get("reused", false)):
		new_blob_paths.append(str(result.get("relative_path", "")))
	result["ok"] = true
	return result


func _rewrite_asset_record(
	source: Dictionary,
	target_id: String,
	target_folder_id: String,
	relpath_map: Dictionary,
	bindings: Array[Dictionary]
) -> Dictionary:
	var record: Dictionary = source.duplicate(true)
	var source_primary: String = str(record.get("blob_relpath", "")).replace("\\", "/")
	if not relpath_map.has(source_primary):
		return {}
	record["id"] = target_id
	record["folder_id"] = target_folder_id
	record["blob_relpath"] = str(relpath_map[source_primary])
	var binding_by_source: Dictionary = {}
	for binding: Dictionary in bindings:
		binding_by_source[str(binding.get("source_relpath", ""))] = binding
	var primary_binding: Dictionary = binding_by_source.get(source_primary, {}) as Dictionary
	if not primary_binding.is_empty():
		record["hash_sha256"] = str(primary_binding.get("hash_sha256", record.get("hash_sha256", "")))
		record["byte_size"] = int(primary_binding.get("byte_size", record.get("byte_size", 0)))
		record["extension"] = str(primary_binding.get("extension", record.get("extension", "")))
	var metadata: Dictionary = record.get("metadata", {}) as Dictionary
	for media_key: String in AssetDurableVariants.SUPPORTED_NAMESPACES:
		if not metadata.has(media_key):
			continue
		var state: Dictionary = (metadata.get(media_key, {}) as Dictionary).duplicate(true)
		var variants: Dictionary = (state.get("variants", {}) as Dictionary).duplicate(true)
		for raw_variant_key: Variant in variants.keys():
			var variant_value: Variant = variants[raw_variant_key]
			if variant_value is not Dictionary:
				continue
			var variant: Dictionary = (variant_value as Dictionary).duplicate(true)
			var source_relpath: String = str(variant.get("blob_relpath", "")).replace("\\", "/")
			if relpath_map.has(source_relpath):
				variant["blob_relpath"] = str(relpath_map[source_relpath])
				var binding: Dictionary = binding_by_source.get(source_relpath, {}) as Dictionary
				if not binding.is_empty():
					variant["hash_sha256"] = str(binding.get("hash_sha256", variant.get("hash_sha256", "")))
					variant["byte_size"] = int(binding.get("byte_size", variant.get("byte_size", 0)))
					variant["extension"] = str(binding.get("extension", variant.get("extension", "")))
			variants[raw_variant_key] = variant
		state["variants"] = variants
		metadata[media_key] = state
	record["metadata"] = metadata
	return record



func _validate_board_module_records(document: Dictionary) -> String:
	var content: Dictionary = document.get("content", {}) as Dictionary
	var records_value: Variant = content.get("module_objects", [])
	if records_value is not Array:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.b909c170f8")
	var seen_entities: Dictionary = {}
	for raw_record: Variant in records_value as Array:
		if raw_record is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.21630f8376")
		var record: Dictionary = raw_record as Dictionary
		var entity_id: int = int(str(record.get("entity_id", "0")))
		if entity_id <= 0 or seen_entities.has(entity_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.c94682b95e")
		seen_entities[entity_id] = true
		var module_id: String = str(record.get("module_id", "")).strip_edges().to_lower()
		if not ModuleManifest.is_valid_module_id(module_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.929069da19")
		var state_schema_version: int = int(record.get("state_schema_version", 0))
		if state_schema_version <= 0 or state_schema_version > 100000:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.2d7ac9cce5")
		var state_value: Variant = record.get("instance_state", {})
		if state_value is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.b847a2d350")
		var bounded_state: Dictionary = ModuleStore.normalize_state(state_value as Dictionary)
		if not bool(bounded_state.get("ok", false)):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.4cdca7e15c") % str(bounded_state.get("error", ""))
		if str(record.get("instance_title", "")).length() > ModuleStore.MAX_TITLE_LENGTH:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.b055dcdd73")
		var asset_ids_value: Variant = record.get("asset_ids", [])
		if asset_ids_value is not Array and asset_ids_value is not PackedStringArray:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.9bf11daba4")
		var asset_ids: PackedStringArray = PackedStringArray()
		for raw_asset_id: Variant in asset_ids_value:
			var asset_id: String = str(raw_asset_id).strip_edges()
			if asset_id.is_empty() or asset_ids.has(asset_id):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.dbc7caa845")
			asset_ids.append(asset_id)
			if asset_ids.size() > ModuleStore.MAX_ASSET_REFS:
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.ec57f54b09")
	return ""


func _module_dependencies_for_document(document: Dictionary) -> Array[Dictionary]:
	var dependencies: Array[Dictionary] = []
	var content: Dictionary = document.get("content", {}) as Dictionary
	var records: Array = content.get("module_objects", []) as Array
	var by_id: Dictionary = {}
	for raw_record: Variant in records:
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var module_id: String = str(record.get("module_id", "")).strip_edges().to_lower()
		if not ModuleManifest.is_valid_module_id(module_id):
			continue
		var schema_version: int = maxi(1, int(record.get("state_schema_version", 1)))
		var versions: Array[int] = []
		var existing_versions: Variant = by_id.get(module_id, [])
		if existing_versions is Array:
			for raw_existing_version: Variant in existing_versions as Array:
				versions.append(int(raw_existing_version))
		if not versions.has(schema_version):
			versions.append(schema_version)
			versions.sort()
		by_id[module_id] = versions
	var ids: Array = by_id.keys()
	ids.sort()
	for raw_id: Variant in ids:
		var module_id: String = str(raw_id)
		dependencies.append({
			"module_id": module_id,
			"state_schema_versions": (by_id[module_id] as Array).duplicate(),
		})
	return dependencies


func _validate_board_module_dependencies(board: Dictionary, document: Dictionary) -> String:
	var expected: Array[Dictionary] = _module_dependencies_for_document(document)
	var raw_value: Variant = board.get("module_dependencies", [])
	if raw_value is not Array:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.6c3d8ed2bc")
	var normalized: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_dependency: Variant in raw_value as Array:
		if raw_dependency is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.78804d1729")
		var dependency: Dictionary = raw_dependency as Dictionary
		var module_id: String = str(dependency.get("module_id", "")).strip_edges().to_lower()
		if not ModuleManifest.is_valid_module_id(module_id) or seen.has(module_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.7679ef6237")
		var versions_value: Variant = dependency.get("state_schema_versions", [])
		if versions_value is not Array:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.698c12edff")
		var versions: Array[int] = []
		for raw_version: Variant in versions_value as Array:
			var version: int = int(raw_version)
			if version <= 0 or versions.has(version):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.d34f2dba9a")
			versions.append(version)
		versions.sort()
		seen[module_id] = true
		normalized.append({"module_id": module_id, "state_schema_versions": versions})
	normalized.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("module_id", "")) < str(right.get("module_id", "")))
	if normalized != expected:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.878d75ddc9")
	return ""


func _validate_board_resource_policy(manifest: Dictionary) -> String:
	var schema_version: int = int(manifest.get("schema_version", 0))
	var assets_value: Variant = manifest.get("assets", [])
	if assets_value is not Array:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.d6d7bb4a30")
	var embedded_count: int = 0
	for raw_entry: Variant in (assets_value as Array):
		if raw_entry is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.37a26bcc7a")
		if bool((raw_entry as Dictionary).get("embedded", true)):
			embedded_count += 1
	if schema_version < 2:
		if embedded_count != (assets_value as Array).size():
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.7fc8a5e7dc")
		return ""
	var board_value: Variant = manifest.get("board", {})
	if board_value is not Dictionary:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.ff8ce53039")
	var policy_value: Variant = (board_value as Dictionary).get("resource_policy", {})
	if policy_value is not Dictionary:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.9c0123e5fe")
	var mode: String = str((policy_value as Dictionary).get("mode", "")).strip_edges().to_lower()
	if mode != "all" and mode != "none" and mode != "custom":
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.27ee22a309")
	# Stage 11.4 schema-2 packages predate the dedicated Notes privacy policy.
	# Preserve their original all/none/custom semantics exactly instead of treating
	# legacy external Notes as malformed. The specialized policy is opt-in by key.
	if not (policy_value as Dictionary).has("include_notes"):
		if mode == "all" and embedded_count != (assets_value as Array).size():
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.33888bdad4")
		if mode == "none" and embedded_count != 0:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.8c3429831d")
		return ""
	var include_notes: bool = bool((policy_value as Dictionary).get("include_notes", true))
	var include_note_embeds: bool = bool((policy_value as Dictionary).get("include_note_embeds", false))
	var note_embed_asset_ids: PackedStringArray = _string_array((policy_value as Dictionary).get("note_embed_asset_ids", []))
	if not include_notes and include_note_embeds:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.54aad7c079")
	if not include_note_embeds and not note_embed_asset_ids.is_empty():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.aac2d33f26")
	var note_embed_set: Dictionary = {}
	for dependency_id: String in note_embed_asset_ids:
		if dependency_id.is_empty() or note_embed_set.has(dependency_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.997a75b86c")
		note_embed_set[dependency_id] = true
	var omitted_note_ids: PackedStringArray = _string_array((policy_value as Dictionary).get("omitted_note_ids", []))
	var seen_omitted: Dictionary = {}
	for note_id: String in omitted_note_ids:
		if note_id.is_empty() or seen_omitted.has(note_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.d602add331")
		seen_omitted[note_id] = true
	if include_notes and not omitted_note_ids.is_empty():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.64287d1e98")
	# Generic resource mode applies only to non-note assets. Enabled Notes are
	# embedded independently so a privacy choice is never weakened by 'none'.
	var non_note_asset_count: int = 0
	var non_note_embedded_count: int = 0
	for raw_entry: Variant in (assets_value as Array):
		var entry: Dictionary = raw_entry as Dictionary
		var record_value: Variant = entry.get("record", {})
		if record_value is Dictionary and int((record_value as Dictionary).get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			if not bool(entry.get("embedded", true)):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.6f1f502cb4")
			continue
		var record: Dictionary = {}
		if record_value is Dictionary:
			record = record_value as Dictionary
		var record_id: String = str(record.get("id", "")).strip_edges()
		if note_embed_set.has(record_id):
			if not bool(entry.get("embedded", true)):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.7b3ee3c814")
			if not NoteResourceEmbed.is_embeddable_kind(int(record.get("kind", AssetKinds.OTHER))):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.c588e29638")
			var embed_hash: String = str(record.get("hash_sha256", "")).strip_edges().to_lower()
			if not NoteResourceEmbed.is_sha256(embed_hash):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.768ba1e9ef")
			note_embed_set.erase(record_id)
			continue
		non_note_asset_count += 1
		if bool(entry.get("embedded", true)):
			non_note_embedded_count += 1
	if not note_embed_set.is_empty():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.83809a49eb")
	if mode == "all" and non_note_embedded_count != non_note_asset_count:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.801c9b73c0")
	if mode == "none" and non_note_embedded_count != 0:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.6d345cc60c")
	return ""


func _validate_board_folder_manifest(manifest: Dictionary) -> String:
	var folders_value: Variant = manifest.get("folders", [])
	var assets_value: Variant = manifest.get("assets", [])
	if folders_value is not Array or assets_value is not Array:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.2ddab35d55")
	var folder_by_id: Dictionary = {}
	for raw_folder: Variant in (folders_value as Array):
		if raw_folder is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.e1425ecb88")
		var folder: Dictionary = raw_folder as Dictionary
		var folder_id: String = str(folder.get("id", "")).strip_edges()
		if folder_id.is_empty() or folder_by_id.has(folder_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.9467bbf056")
		folder_by_id[folder_id] = folder
	var required_folder_ids: Dictionary = {}
	for raw_entry: Variant in (assets_value as Array):
		if raw_entry is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.37a26bcc7a")
		var entry: Dictionary = raw_entry as Dictionary
		var record_value: Variant = entry.get("record", {})
		if record_value is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.49c4dfba1a")
		var record: Dictionary = record_value as Dictionary
		var cursor: String = str(record.get("folder_id", "")).strip_edges()
		while not cursor.is_empty():
			if required_folder_ids.has(cursor):
				break
			if not folder_by_id.has(cursor):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.5ed4dd736e")
			required_folder_ids[cursor] = true
			var folder: Dictionary = folder_by_id[cursor] as Dictionary
			cursor = str(folder.get("parent_id", "")).strip_edges()
	if required_folder_ids.size() != folder_by_id.size():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.dc99cbff9d")
	return ""


func _validate_board_asset_manifest(document: Dictionary, plan: Dictionary, manifest: Dictionary) -> String:
	var source_references: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	var note_references: Dictionary = _string_set(BoardDocumentSchema.collect_note_references(document))
	var omitted_note_ids: PackedStringArray = _board_omitted_note_ids(manifest)
	var omitted_set: Dictionary = _string_set(omitted_note_ids)
	for note_id: String in omitted_note_ids:
		if not note_references.has(note_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.f8ba1c7e01") % note_id
	var expected: Dictionary = {}
	for asset_id: String in source_references:
		if not omitted_set.has(asset_id):
			expected[asset_id] = true
	# SHA-pinned note embeds are package dependencies even though the board
	# document itself does not contain their logical asset IDs. They must still
	# participate in the exact import-plan set so extra/missing resources cannot
	# be smuggled past the board manifest validation.
	for dependency_id: String in _board_note_embed_asset_ids(manifest):
		expected[dependency_id] = true
	var asset_id_map_value: Variant = plan.get("asset_id_map", {})
	if asset_id_map_value is not Dictionary:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.28f2b55ef0")
	var asset_id_map: Dictionary = asset_id_map_value as Dictionary
	if asset_id_map.size() != expected.size():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.3cb0b55340")
	for raw_id: Variant in expected.keys():
		var asset_id: String = str(raw_id)
		if not asset_id_map.has(asset_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.0baf9ec6d5") % asset_id
	return ""


func _validate_local_asset_references(document: Dictionary, omitted_note_ids: PackedStringArray = PackedStringArray()) -> String:
	var omitted_set: Dictionary = _string_set(omitted_note_ids)
	for asset_id: String in BoardDocumentSchema.collect_asset_references(document):
		if omitted_set.has(asset_id):
			continue
		if library.get_asset(asset_id).is_empty():
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.5f631498e9") % asset_id
	return ""


func _board_note_embed_asset_ids(manifest: Dictionary) -> PackedStringArray:
	var board_value: Variant = manifest.get("board", {})
	if board_value is not Dictionary:
		return PackedStringArray()
	var policy_value: Variant = (board_value as Dictionary).get("resource_policy", {})
	if policy_value is not Dictionary:
		return PackedStringArray()
	if not bool((policy_value as Dictionary).get("include_note_embeds", false)):
		return PackedStringArray()
	return _string_array((policy_value as Dictionary).get("note_embed_asset_ids", []))


func _board_omitted_note_ids(manifest: Dictionary) -> PackedStringArray:
	var board_value: Variant = manifest.get("board", {})
	if board_value is not Dictionary:
		return PackedStringArray()
	var policy_value: Variant = (board_value as Dictionary).get("resource_policy", {})
	if policy_value is not Dictionary:
		return PackedStringArray()
	if bool((policy_value as Dictionary).get("include_notes", true)):
		return PackedStringArray()
	return _string_array((policy_value as Dictionary).get("omitted_note_ids", []))


func _validate_library_manifest(manifest: Dictionary) -> String:
	var library_value: Variant = manifest.get("library", {})
	if library_value is not Dictionary:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.b1778cf205")
	var library_manifest: Dictionary = library_value as Dictionary
	if str(library_manifest.get("catalog_schema", "")) != AssetCatalog.SCHEMA_ID:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.c0d9cd2f79")
	var schema_version: int = int(library_manifest.get("catalog_schema_version", 0))
	if schema_version <= 0:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.c3efac0457")
	if schema_version > AssetCatalog.SCHEMA_VERSION:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.d89ccdb045")
	var dependency_value: Variant = library_manifest.get("note_embed_dependency_ids", [])
	if dependency_value is not Array and dependency_value is not PackedStringArray:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.822bf42478")
	var dependency_ids: PackedStringArray = _string_array(dependency_value)
	if dependency_ids.is_empty():
		return ""
	var assets_value: Variant = manifest.get("assets", [])
	if assets_value is not Array:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.e1dc9f4ab5")
	var assets_by_id: Dictionary = {}
	for raw_asset: Variant in assets_value as Array:
		if raw_asset is not Dictionary:
			continue
		var asset: Dictionary = raw_asset as Dictionary
		var record_value: Variant = asset.get("record", {})
		var record: Dictionary = record_value as Dictionary if record_value is Dictionary else asset
		var asset_id: String = str(record.get("id", "")).strip_edges()
		if not asset_id.is_empty():
			assets_by_id[asset_id] = asset
	var seen_dependencies: Dictionary = {}
	for dependency_id: String in dependency_ids:
		if dependency_id.is_empty() or seen_dependencies.has(dependency_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.c1a21dc5f0")
		seen_dependencies[dependency_id] = true
		if not assets_by_id.has(dependency_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.7a10acc53b") % dependency_id
		var dependency_asset: Dictionary = assets_by_id[dependency_id] as Dictionary
		var dependency_record_value: Variant = dependency_asset.get("record", {})
		var dependency_record: Dictionary = dependency_record_value as Dictionary if dependency_record_value is Dictionary else dependency_asset
		if not NoteResourceEmbed.is_embeddable_kind(int(dependency_record.get("kind", AssetKinds.OTHER))):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.1b40d38312")
		var dependency_hash: String = str(dependency_record.get("hash_sha256", "")).strip_edges().to_lower()
		if not NoteResourceEmbed.is_sha256(dependency_hash):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.d7653460ca")
	return ""


func _validate_media_variant_bindings(record: Dictionary, bound_relpaths: Dictionary) -> String:
	var metadata_value: Variant = record.get("metadata", {})
	if metadata_value is not Dictionary:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.12267a00b9")
	var metadata: Dictionary = metadata_value as Dictionary
	for media_key: String in AssetDurableVariants.SUPPORTED_NAMESPACES:
		var state_value: Variant = metadata.get(media_key, {})
		if state_value is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.46600914f7") % media_key
		var state: Dictionary = state_value as Dictionary
		var variants_value: Variant = state.get("variants", {})
		if variants_value is not Dictionary:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.6a0662b663")
		var variants: Dictionary = variants_value as Dictionary
		for raw_variant_key: Variant in variants.keys():
			var variant_value: Variant = variants[raw_variant_key]
			if variant_value is not Dictionary:
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.b350ab56b0")
			var variant: Dictionary = variant_value as Dictionary
			var relpath: String = str(variant.get("blob_relpath", "")).strip_edges().replace("\\", "/")
			if not relpath.is_empty() and not bound_relpaths.has(relpath):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.517f160a42")
	return ""


func _validate_source_folders(folders: Array[Dictionary]) -> String:
	var by_id: Dictionary = {}
	for folder: Dictionary in folders:
		var folder_id: String = str(folder.get("id", "")).strip_edges()
		var name: String = str(folder.get("name", "")).strip_edges()
		if folder_id.length() > 128 or name.length() > 512:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.1496802d51")
		if folder_id.is_empty() or name.is_empty() or by_id.has(folder_id):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.7e1ab55165")
		by_id[folder_id] = folder
	var sibling_names: Dictionary = {}
	for folder: Dictionary in folders:
		var folder_id: String = str(folder.get("id", ""))
		var parent_id: String = str(folder.get("parent_id", "")).strip_edges()
		var sibling_key: String = "%s\u001f%s" % [parent_id, str(folder.get("name", "")).strip_edges().to_lower()]
		if sibling_names.has(sibling_key):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.6e5bbd43b7")
		sibling_names[sibling_key] = true
		if parent_id.length() > 128:
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.5eecb21ecc")
		if parent_id == folder_id or (not parent_id.is_empty() and not by_id.has(parent_id)):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.14c3bed3bc")
		var visited: Dictionary = {}
		visited[folder_id] = true
		var cursor: String = parent_id
		while not cursor.is_empty():
			if visited.has(cursor):
				return NotLightL10n.text("runtime.portable.notlight_portable_package_service.0af3b9e6d8")
			visited[cursor] = true
			var parent: Dictionary = by_id[cursor] as Dictionary
			cursor = str(parent.get("parent_id", "")).strip_edges()
	return ""


func _validate_payload_key_set(package_info: Dictionary, referenced_keys: Dictionary) -> String:
	var payload_by_key: Dictionary = package_info.get("payload_by_key", {}) as Dictionary
	if payload_by_key.size() != referenced_keys.size():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.3d46c0f7e2")
	for raw_key: Variant in referenced_keys.keys():
		if not payload_by_key.has(str(raw_key)):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.725c54edb2") % str(raw_key)
	return ""


func _find_folder_by_name(
	local_folders: Array[Dictionary],
	new_folders: Array[Dictionary],
	name: String,
	parent_id: String
) -> String:
	var needle: String = name.strip_edges().to_lower()
	for folder: Dictionary in local_folders:
		if str(folder.get("parent_id", "")) == parent_id and str(folder.get("name", "")).strip_edges().to_lower() == needle:
			return str(folder.get("id", ""))
	for folder: Dictionary in new_folders:
		if str(folder.get("parent_id", "")) == parent_id and str(folder.get("name", "")).strip_edges().to_lower() == needle:
			return str(folder.get("id", ""))
	return ""


func _primary_binding(entry: Dictionary) -> Dictionary:
	var record: Dictionary = entry.get("record", {}) as Dictionary
	var primary_relpath: String = str(record.get("blob_relpath", "")).replace("\\", "/")
	for binding: Dictionary in _dictionary_array(entry.get("blobs", [])):
		if str(binding.get("source_relpath", "")).replace("\\", "/") == primary_relpath:
			return binding
	return {}



func _validate_export_destination(destination_path: String) -> String:
	var clean_destination: String = destination_path.strip_edges()
	if clean_destination.is_empty():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.476490b47a")
	var managed_roots: PackedStringArray = PackedStringArray([repository.get_root_directory(), library.get_root_directory()])
	for managed_root: String in managed_roots:
		if _path_is_within_or_equal(clean_destination, managed_root):
			return NotLightL10n.text("runtime.portable.notlight_portable_package_service.d54ad7b1b1")
	return ""


func _path_is_within_or_equal(path: String, root: String) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path).simplify_path().trim_suffix("/")
	var absolute_root: String = ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/")
	if OS.get_name() == "Windows":
		absolute_path = absolute_path.to_lower()
		absolute_root = absolute_root.to_lower()
	return absolute_path == absolute_root or absolute_path.begins_with("%s/" % absolute_root)


func _portable_board_metadata(metadata: Dictionary) -> Dictionary:
	return {
		"id": str(metadata.get("id", "")),
		"name": str(metadata.get("name", NotLightL10n.text("hub.new_board"))),
		"created_at_unix": int(metadata.get("created_at_unix", 0)),
		"updated_at_unix": int(metadata.get("updated_at_unix", 0)),
	}


func _rollback_and_fail(
	message: String,
	catalog_snapshot: Dictionary,
	new_blob_paths: PackedStringArray,
	staging_directory: String
) -> Dictionary:
	var rollback_error: String = _rollback_import(catalog_snapshot, new_blob_paths)
	NotLightPortablePackageFormat.cleanup_directory(staging_directory)
	var combined_message: String = message.strip_edges()
	if combined_message.is_empty():
		combined_message = NotLightL10n.text("runtime.portable.notlight_portable_package_service.66037a4bc1")
	if not rollback_error.is_empty():
		combined_message += "\n\n%s" % rollback_error
	return _fail_result(combined_message)


func _rollback_import(catalog_snapshot: Dictionary, new_blob_paths: PackedStringArray) -> String:
	if catalog_snapshot.is_empty():
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.13d3d944a4")
	if not library.restore_catalog_snapshot(catalog_snapshot):
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.13f65f743c") % library.get_last_error()
	var cleanup_failures: int = 0
	for index: int in range(new_blob_paths.size() - 1, -1, -1):
		var relative_path: String = new_blob_paths[index]
		if not relative_path.is_empty() and not library.blobs.delete_blob(relative_path):
			cleanup_failures += 1
	if cleanup_failures > 0:
		return NotLightL10n.text("runtime.portable.notlight_portable_package_service.8d0a22b849") % cleanup_failures
	return ""


func _commit_failure(message: String, new_blob_paths: PackedStringArray) -> Dictionary:
	return {"ok": false, "error": message, "new_blob_paths": new_blob_paths}


func _packed_string_array_to_array(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value: String in values:
		result.append(value)
	return result


func _string_set(values: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for value: String in values:
		var clean: String = value.strip_edges()
		if not clean.is_empty():
			result[clean] = true
	return result


func _new_staging_directory() -> String:
	return _staging_root.path_join(AssetId.make_temporary_id("package"))


func _blob_payload_key(hash_sha256: String, extension: String) -> String:
	var clean_extension: String = extension.strip_edges().to_lower()
	return "blob_%s_%s" % [hash_sha256, clean_extension if not clean_extension.is_empty() else "raw"]


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for raw: Variant in (value as Array):
		if raw is Dictionary:
			result.append(raw as Dictionary)
	return result


func _string_array(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if value is PackedStringArray:
		return (value as PackedStringArray).duplicate()
	if value is Array:
		for raw: Variant in (value as Array):
			result.append(str(raw))
	return result


func _is_safe_extension(value: String) -> bool:
	var clean: String = value.strip_edges().to_lower()
	if clean.length() > 12:
		return false
	const ALLOWED: String = "abcdefghijklmnopqrstuvwxyz0123456789"
	for index: int in range(clean.length()):
		if ALLOWED.find(clean.substr(index, 1)) < 0:
			return false
	return true


func _blob_path_matches_hash_and_extension(relative_path: String, hash_sha256: String, extension: String) -> bool:
	if not _is_sha256(hash_sha256) or not _is_safe_extension(extension):
		return false
	var clean_path: String = relative_path.strip_edges().replace("\\", "/")
	var expected_name: String = hash_sha256
	if not extension.is_empty():
		expected_name += ".%s" % extension
	var expected_path: String = "blobs/%s/%s/%s" % [hash_sha256.substr(0, 2), hash_sha256.substr(2, 2), expected_name]
	return clean_path == expected_path


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	const HEX: String = "0123456789abcdef"
	for index: int in range(value.length()):
		if HEX.find(value.substr(index, 1)) < 0:
			return false
	return true


func _require_services() -> bool:
	if repository == null:
		_fail(NotLightL10n.text("runtime.portable.notlight_portable_package_service.306223fc18"))
		return false
	if library == null or not library.is_available():
		_fail(NotLightL10n.text("runtime.portable.notlight_portable_package_service.88945df9d2"))
		return false
	return true


func _clear_error() -> void:
	_last_error = ""


func _fail(message: String) -> void:
	_last_error = message.strip_edges() if not message.strip_edges().is_empty() else NotLightL10n.text("runtime.portable.notlight_portable_package_service.dcb471b231")


func _error_result() -> Dictionary:
	return {"ok": false, "error": _last_error}


func _fail_result(message: String) -> Dictionary:
	_fail(message)
	return _error_result()
