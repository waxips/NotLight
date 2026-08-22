# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const TEST_ROOT: String = "user://notlight_stage9_6_2_import_smoke"
const WAIT_TIMEOUT_MSEC: int = 5000


func _initialize() -> void:
	_delete_directory_recursive(TEST_ROOT)
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT)) == OK, "failed to create smoke directory")
	_test_registry_contract()
	_test_staging_worker()
	_test_worker_validation()
	_delete_directory_recursive(TEST_ROOT)
	print("NotLight Stage 9.6.2 safe-import smoke test passed.")
	quit(0)


func _test_registry_contract() -> void:
	_check(AssetImportCapabilities.kind_for_extension("PNG") == AssetKinds.IMAGE, "uppercase PNG was not classified")
	_check(AssetImportCapabilities.kind_for_extension(".pdf") == AssetKinds.PDF, "dot-prefixed PDF was not classified")
	_check(AssetImportCapabilities.kind_for_extension("zip") == AssetKinds.OTHER, "unsupported ZIP became importable")
	_check(not AssetImportCapabilities.is_supported_extension("ttf"), "legacy font unexpectedly became importable")
	_check(AssetKinds.from_extension("ttf") == AssetKinds.FONT, "legacy font classification was lost")
	_check(AssetKinds.from_extension("glb") == AssetKinds.MODEL_3D, "legacy 3D classification was lost")
	var filters: PackedStringArray = AssetImportCapabilities.file_dialog_filters()
	_check(filters.size() == 5, "import filter registry should expose all + four supported kinds")
	var filter_text: String = "\n".join(filters)
	_check(filter_text.find("*.png") >= 0, "image filter is missing PNG")
	_check(filter_text.find("*.ktx") >= 0, "image filter is missing KTX")
	_check(filter_text.find("*.pdf") >= 0, "PDF filter is missing PDF")
	_check(filter_text.find("*.*") < 0, "safe import filter unexpectedly exposes All Files")
	_check(AssetImportValidationWorker.MAX_PENDING_BATCHES == 2, "validation worker batch bound drifted")
	_check(AssetImportValidationWorker.MAX_FILES_PER_BATCH == 256, "validation worker file bound drifted")
	_check(AssetImportStagingWorker.MAX_PENDING_JOBS == 1, "staging worker job bound drifted")
	_check(AssetImportPipeline.MAX_PENDING_JOBS == 256, "import queue bound drifted")
	_check(HashingContext.HASH_SHA256 >= 0, "SHA-256 hash mode is unavailable")


func _test_staging_worker() -> void:
	var source_path: String = TEST_ROOT.path_join("staging source.bin")
	var staging_path: String = TEST_ROOT.path_join("staging copy.part")
	var payload: PackedByteArray = "NotLight safe import staging smoke".to_utf8_buffer()
	_write_bytes(source_path, payload)
	var worker: AssetImportStagingWorker = AssetImportStagingWorker.new()
	_check(worker.start(), "staging worker failed to start")
	_check(worker.request("stage-smoke", source_path, staging_path), "staging request was rejected")
	var result: Dictionary = _wait_for_staging_result(worker)
	worker.stop()
	_check(not result.is_empty(), "staging worker timed out")
	_check(not bool(result.get("cancelled", true)), "staging worker unexpectedly cancelled")
	_check(str(result.get("error_code", "")).is_empty(), "staging worker reported an error")
	_check(int(result.get("byte_size", 0)) == payload.size(), "staging byte size changed")
	_check(str(result.get("hash_sha256", "")).length() == 64, "staging SHA-256 was not produced")
	var copy: FileAccess = FileAccess.open(staging_path, FileAccess.READ)
	_check(copy != null, "staging worker did not create its output")
	var copied: PackedByteArray = copy.get_buffer(copy.get_length())
	copy.close()
	_check(copied == payload, "staging worker changed copied bytes")


func _wait_for_staging_result(worker: AssetImportStagingWorker) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_msec < WAIT_TIMEOUT_MSEC:
		var results: Array[Dictionary] = worker.poll_results(1)
		if not results.is_empty():
			return results[0]
		OS.delay_msec(5)
	return {}


func _test_worker_validation() -> void:
	var png_path: String = TEST_ROOT.path_join("valid image.PNG")
	var bad_png_path: String = TEST_ROOT.path_join("renamed.png")
	var valid_svg_path: String = TEST_ROOT.path_join("valid.svg")
	var unsafe_svg_path: String = TEST_ROOT.path_join("unsafe.svg")
	var internal_svg_path: String = TEST_ROOT.path_join("internal-link.svg")
	var relative_svg_path: String = TEST_ROOT.path_join("relative-link.svg")
	var late_unsafe_svg_path: String = TEST_ROOT.path_join("late-unsafe.svg")
	var unsafe_data_svg_path: String = TEST_ROOT.path_join("unsafe-data.svg")
	var empty_path: String = TEST_ROOT.path_join("empty.jpg")
	_write_bytes(png_path, PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]))
	_write_bytes(bad_png_path, "this is not a png".to_utf8_buffer())
	_write_bytes(valid_svg_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0h1v1z\"/></svg>".to_utf8_buffer())
	_write_bytes(unsafe_svg_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>".to_utf8_buffer())
	_write_bytes(internal_svg_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"><defs><path id=\"p\" d=\"M0 0h1v1z\"/></defs><use href=\"#p\"/></svg>".to_utf8_buffer())
	_write_bytes(relative_svg_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"outside.png\"/></svg>".to_utf8_buffer())
	var late_svg: String = "<svg xmlns=\"http://www.w3.org/2000/svg\"><desc>" + "x".repeat(AssetImportContentValidator.PREFIX_BYTES + 1024) + "</desc><script>alert(1)</script></svg>"
	_write_bytes(late_unsafe_svg_path, late_svg.to_utf8_buffer())
	_write_bytes(unsafe_data_svg_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"data:text/html;base64,PHNjcmlwdD4=\"/></svg>".to_utf8_buffer())
	_write_bytes(empty_path, PackedByteArray())

	var worker: AssetImportValidationWorker = AssetImportValidationWorker.new()
	_check(worker.start(), "validation worker failed to start")
	var candidates: Array[Dictionary] = [
		{"source_path": png_path, "filename": "valid image.PNG", "extension": "png", "expected_kind": AssetKinds.IMAGE},
		{"source_path": bad_png_path, "filename": "renamed.png", "extension": "png", "expected_kind": AssetKinds.IMAGE},
		{"source_path": valid_svg_path, "filename": "valid.svg", "extension": "svg", "expected_kind": AssetKinds.IMAGE},
		{"source_path": unsafe_svg_path, "filename": "unsafe.svg", "extension": "svg", "expected_kind": AssetKinds.IMAGE},
		{"source_path": internal_svg_path, "filename": "internal-link.svg", "extension": "svg", "expected_kind": AssetKinds.IMAGE},
		{"source_path": relative_svg_path, "filename": "relative-link.svg", "extension": "svg", "expected_kind": AssetKinds.IMAGE},
		{"source_path": late_unsafe_svg_path, "filename": "late-unsafe.svg", "extension": "svg", "expected_kind": AssetKinds.IMAGE},
		{"source_path": unsafe_data_svg_path, "filename": "unsafe-data.svg", "extension": "svg", "expected_kind": AssetKinds.IMAGE},
		{"source_path": empty_path, "filename": "empty.jpg", "extension": "jpg", "expected_kind": AssetKinds.IMAGE},
	]
	_check(worker.request_batch("smoke", candidates, true), "validation batch was rejected")
	var result: Dictionary = _wait_for_worker_result(worker)
	worker.stop()
	_check(not result.is_empty(), "validation worker timed out")
	_check(not bool(result.get("cancelled", true)), "validation worker unexpectedly cancelled")
	var values_value: Variant = result.get("results", [])
	_check(values_value is Array, "validation worker returned no result array")
	var values: Array = values_value as Array
	_check(values.size() == 9, "validation worker lost candidates")
	var valid_png: Dictionary = values[0] as Dictionary
	_check(bool(valid_png.get("valid", false)), "valid PNG signature was rejected")
	_check(int(valid_png.get("detected_kind", AssetKinds.OTHER)) == AssetKinds.IMAGE, "valid PNG kind mismatch")
	_check(str(valid_png.get("hash_sha256", "")).length() == 64, "preflight SHA-256 was not produced")
	var bad_png: Dictionary = values[1] as Dictionary
	_check(not bool(bad_png.get("valid", true)), "renamed non-PNG passed validation")
	_check(str(bad_png.get("rejection_code", "")) == ImportCandidateResult.REJECTION_INVALID_CONTENT, "renamed non-PNG rejection changed")
	var valid_svg: Dictionary = values[2] as Dictionary
	_check(bool(valid_svg.get("valid", false)), "normal SVG namespace was mistaken for an external reference")
	var unsafe_svg: Dictionary = values[3] as Dictionary
	_check(not bool(unsafe_svg.get("valid", true)), "active SVG passed validation")
	_check(str(unsafe_svg.get("rejection_code", "")) == ImportCandidateResult.REJECTION_UNSAFE_SVG, "unsafe SVG rejection changed")
	var internal_svg: Dictionary = values[4] as Dictionary
	_check(bool(internal_svg.get("valid", false)), "internal SVG fragment reference was rejected")
	var relative_svg: Dictionary = values[5] as Dictionary
	_check(not bool(relative_svg.get("valid", true)), "relative external SVG reference passed validation")
	_check(str(relative_svg.get("rejection_code", "")) == ImportCandidateResult.REJECTION_UNSAFE_SVG, "external SVG reference rejection changed")
	var late_unsafe_svg: Dictionary = values[6] as Dictionary
	_check(not bool(late_unsafe_svg.get("valid", true)), "active SVG content after the prefix scan boundary passed validation")
	_check(str(late_unsafe_svg.get("rejection_code", "")) == ImportCandidateResult.REJECTION_UNSAFE_SVG, "late unsafe SVG rejection changed")
	var unsafe_data_svg: Dictionary = values[7] as Dictionary
	_check(not bool(unsafe_data_svg.get("valid", true)), "unsafe SVG data URI passed validation")
	_check(str(unsafe_data_svg.get("rejection_code", "")) == ImportCandidateResult.REJECTION_UNSAFE_SVG, "unsafe SVG data URI rejection changed")
	var empty_file: Dictionary = values[8] as Dictionary
	_check(not bool(empty_file.get("valid", true)), "empty file passed validation")
	_check(str(empty_file.get("rejection_code", "")) == ImportCandidateResult.REJECTION_EMPTY, "empty-file rejection changed")


func _wait_for_worker_result(worker: AssetImportValidationWorker) -> Dictionary:
	var started_msec: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_msec < WAIT_TIMEOUT_MSEC:
		var results: Array[Dictionary] = worker.poll_results(1)
		if not results.is_empty():
			return results[0]
		OS.delay_msec(5)
	return {}


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "failed to create smoke file")
	file.store_buffer(bytes)
	file.flush()
	file.close()


func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.current_is_dir():
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				if directory.remove(entry) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
