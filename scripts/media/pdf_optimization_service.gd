# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfOptimizationService
extends Node

signal optimization_started(asset_id: String, preset: String)
signal optimization_progress(asset_id: String, progress: float, message: String)
signal optimization_completed(asset_id: String, optimized_path: String, saved_bytes: int)
signal optimization_failed(asset_id: String, message: String)

const PRESET_LOSSLESS: String = QpdfTools.PRESET_LOSSLESS
const PRESET_BALANCED: String = QpdfTools.PRESET_BALANCED
const MAX_PENDING_JOBS: int = 4
const MIN_SAVING_BYTES: int = 64 * 1024
const MIN_SAVING_RATIO: float = 0.03
const PROCESS_OUTPUT_LIMIT_BYTES: int = 128 * 1024

const STAGE_NONE: String = ""
const STAGE_VERSION: String = "version"
const STAGE_SOURCE_HASH: String = "source_hash"
const STAGE_SOURCE_CHECK: String = "source_check"
const STAGE_SOURCE_PROBE: String = "source_probe"
const STAGE_OPTIMIZE: String = "optimize"
const STAGE_RESULT_CHECK: String = "result_check"
const STAGE_RESULT_PROBE: String = "result_probe"
const STAGE_RENDER_FIRST: String = "render_first"
const STAGE_RENDER_LAST: String = "render_last"
const STAGE_RESULT_HASH: String = "result_hash"
const STAGE_COMMIT: String = "commit"

var library: AssetLibraryService
var pdf_media: PdfMediaService
var _queue: Array[Dictionary] = []
var _queued_asset_ids: Dictionary = {}
var _active: Dictionary = {}
var _runner: SidecarProcessRunner = SidecarProcessRunner.new()
var _active_stage: String = STAGE_NONE
var _qpdf_version_line: String = ""
var _qpdf_version: String = ""
var _qpdf_version_verified: bool = false
var _qpdf_version_error: String = ""
var _hash_worker: FileHashWorker = FileHashWorker.new()
var _hash_worker_started: bool = false
var _hash_job_key: String = ""


func _ready() -> void:
	_hash_worker_started = _hash_worker.start()
	set_process(false)


func _exit_tree() -> void:
	_runner.cancel()
	_runner.close()
	if not _hash_job_key.is_empty():
		_hash_worker.cancel(_hash_job_key)
	_hash_worker.stop()
	_hash_worker_started = false
	_hash_job_key = ""
	_cleanup_active_files()


func configure(asset_library: AssetLibraryService, media_service: PdfMediaService) -> void:
	library = asset_library
	pdf_media = media_service
	_cleanup_stale_optimizer_files()


func _process(_delta: float) -> void:
	if _active.is_empty():
		_start_next_job()
		if _active.is_empty():
			set_process(not _queue.is_empty())
			return
	if _active_stage == STAGE_SOURCE_HASH or _active_stage == STAGE_RESULT_HASH:
		_poll_hash_stage()
		return
	var result: Dictionary = _runner.poll()
	if not bool(result.get("finished", false)):
		return
	_handle_process_result(result)


func tools_available() -> bool:
	if library == null or pdf_media == null or not pdf_media.tools_available() or not _hash_worker_started:
		return false
	if OS.has_feature("windows"):
		return QpdfTools.bundled_tools_available()
	return QpdfTools.candidate_available()


func status_text() -> String:
	if not _hash_worker_started:
		return NotLightL10n.text("pdf.optimize.worker_unavailable")
	if pdf_media == null or not pdf_media.tools_available():
		return NotLightL10n.text("pdf.optimize.poppler_missing")
	if OS.has_feature("windows") and not QpdfTools.bundled_tools_available():
		return NotLightL10n.text("pdf.optimize.qpdf_missing")
	if not QpdfTools.candidate_available():
		return NotLightL10n.text("pdf.optimize.qpdf_missing")
	if not _qpdf_version_error.is_empty():
		return _qpdf_version_error
	return _qpdf_version_line if _qpdf_version_verified and not _qpdf_version_line.is_empty() else NotLightL10n.text("pdf.optimize.available")


func enqueue_optimization(asset_id: String, preset: String = PRESET_LOSSLESS) -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty() or library == null or pdf_media == null:
		return false
	if is_optimizing(clean_id):
		return false
	if pending_job_count() >= MAX_PENDING_JOBS:
		optimization_failed.emit(clean_id, NotLightL10n.text("pdf.optimize.queue_full"))
		return false
	if not tools_available():
		optimization_failed.emit(clean_id, status_text())
		return false
	var asset: Dictionary = library.get_asset(clean_id)
	if asset.is_empty() or int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.PDF:
		return false
	var state: Dictionary = pdf_media.get_variant_state(clean_id)
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var original_value: Variant = variants.get(PdfMediaService.VARIANT_ORIGINAL, {})
	if original_value is not Dictionary:
		return false
	var original: Dictionary = original_value as Dictionary
	var source_relpath: String = str(original.get("blob_relpath", "")).strip_edges()
	var source_path: String = library.resolve_blob_relative(source_relpath)
	if source_path.is_empty() or not _is_nonempty_file(source_path):
		optimization_failed.emit(clean_id, NotLightL10n.text("pdf.optimize.source_unavailable"))
		return false
	var source_hash: String = str(original.get("hash_sha256", "")).strip_edges().to_lower()
	if not _is_sha256(source_hash):
		optimization_failed.emit(clean_id, NotLightL10n.text("pdf.optimize.source_invalid"))
		return false
	_queue.append({
		"asset_id": clean_id,
		"preset": QpdfTools.normalize_preset(preset),
		"source_path": source_path,
		"source_hash_sha256": source_hash,
		"source_byte_size": _file_size(source_path),
	})
	_queued_asset_ids[clean_id] = true
	set_process(true)
	return true


func cancel_optimization(asset_id: String) -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return false
	if not _active.is_empty() and str(_active.get("asset_id", "")) == clean_id:
		if _active_stage == STAGE_SOURCE_HASH or _active_stage == STAGE_RESULT_HASH:
			if not _hash_job_key.is_empty():
				_hash_worker.cancel(_hash_job_key)
		else:
			_runner.cancel()
		return true
	for index: int in range(_queue.size()):
		if str(_queue[index].get("asset_id", "")) == clean_id:
			_queue.remove_at(index)
			_queued_asset_ids.erase(clean_id)
			optimization_failed.emit(clean_id, NotLightL10n.text("pdf.optimize.cancelled"))
			if _queue.is_empty() and _active.is_empty():
				set_process(false)
			return true
	return false


func is_optimizing(asset_id: String = "") -> bool:
	var clean_id: String = asset_id.strip_edges()
	if clean_id.is_empty():
		return not _active.is_empty() or not _queue.is_empty()
	if not _active.is_empty() and str(_active.get("asset_id", "")) == clean_id:
		return true
	return _queued_asset_ids.has(clean_id)


func pending_job_count() -> int:
	return _queue.size() + (0 if _active.is_empty() else 1)


func _start_next_job() -> void:
	if _queue.is_empty():
		return
	_active = _queue.pop_front().duplicate(true)
	var asset_id: String = str(_active.get("asset_id", ""))
	_queued_asset_ids.erase(asset_id)
	var job_token: String = AssetId.make_temporary_id("pdfopt")
	var output_path: String = library.blobs.make_temp_path(job_token)
	_active["output_path"] = output_path
	_active["verify_first_prefix"] = output_path + ".verify_first"
	_active["verify_last_prefix"] = output_path + ".verify_last"
	_active["source_info"] = {}
	_active["result_info"] = {}
	optimization_started.emit(asset_id, str(_active.get("preset", PRESET_LOSSLESS)))
	if not _qpdf_version_verified:
		_start_sidecar(
			STAGE_VERSION,
			QpdfTools.qpdf_path(),
			QpdfTools.version_arguments(),
			15 * 1000,
			0.03,
			NotLightL10n.text("pdf.optimize.checking_backend")
		)
	else:
		_start_source_hash()


func _start_source_hash() -> void:
	var source_path: String = str(_active.get("source_path", ""))
	var source_size: int = int(_active.get("source_byte_size", 0))
	if source_size <= 0 or not _start_hash_job(
		source_path,
		STAGE_SOURCE_HASH,
		0.05,
		NotLightL10n.text("pdf.optimize.hashing_source")
	):
		_fail_active(NotLightL10n.text("pdf.optimize.hash_failed"))


func _start_source_check() -> void:
	_start_sidecar(
		STAGE_SOURCE_CHECK,
		QpdfTools.qpdf_path(),
		QpdfTools.check_arguments(str(_active.get("source_path", ""))),
		_timeout_for_file(str(_active.get("source_path", "")), 30, 180),
		0.10,
		NotLightL10n.text("pdf.optimize.checking_source")
	)


func _start_source_probe() -> void:
	_start_sidecar(
		STAGE_SOURCE_PROBE,
		PopplerTools.pdfinfo_path(),
		PackedStringArray([_native_path(str(_active.get("source_path", "")))]),
		_timeout_for_file(str(_active.get("source_path", "")), 30, 180),
		0.18,
		NotLightL10n.text("pdf.optimize.reading_source")
	)


func _start_optimize() -> void:
	var source_path: String = str(_active.get("source_path", ""))
	var output_path: String = str(_active.get("output_path", ""))
	library.blobs.remove_temp(output_path)
	_start_sidecar(
		STAGE_OPTIMIZE,
		QpdfTools.qpdf_path(),
		QpdfTools.optimize_arguments(source_path, output_path, str(_active.get("preset", PRESET_LOSSLESS))),
		_timeout_for_file(source_path, 120, 10 * 60),
		0.35,
		NotLightL10n.text("pdf.optimize.optimizing")
	)


func _start_result_check() -> void:
	_start_sidecar(
		STAGE_RESULT_CHECK,
		QpdfTools.qpdf_path(),
		QpdfTools.check_arguments(str(_active.get("output_path", ""))),
		_timeout_for_file(str(_active.get("output_path", "")), 30, 180),
		0.64,
		NotLightL10n.text("pdf.optimize.checking_result")
	)


func _start_result_probe() -> void:
	_start_sidecar(
		STAGE_RESULT_PROBE,
		PopplerTools.pdfinfo_path(),
		PackedStringArray([_native_path(str(_active.get("output_path", "")))]),
		_timeout_for_file(str(_active.get("output_path", "")), 30, 180),
		0.72,
		NotLightL10n.text("pdf.optimize.reading_result")
	)


func _start_render_verification(page_number: int, last_page: bool) -> void:
	var prefix_key: String = "verify_last_prefix" if last_page else "verify_first_prefix"
	var prefix: String = str(_active.get(prefix_key, ""))
	_remove_file(prefix + ".png")
	var arguments: PackedStringArray = PackedStringArray([
		"-png",
		"-f", str(page_number),
		"-l", str(page_number),
		"-singlefile",
		"-scale-to", "256",
		_native_path(str(_active.get("output_path", ""))),
		_native_path(prefix),
	])
	_start_sidecar(
		STAGE_RENDER_LAST if last_page else STAGE_RENDER_FIRST,
		PopplerTools.pdftoppm_path(),
		arguments,
		_timeout_for_file(str(_active.get("output_path", "")), 30, 180),
		0.82 if last_page else 0.78,
		NotLightL10n.text("pdf.optimize.verifying_render")
	)


func _start_sidecar(
	stage: String,
	executable: String,
	arguments: PackedStringArray,
	timeout_msec: int,
	progress: float,
	message: String
) -> void:
	_active_stage = stage
	if not _runner.start(executable, arguments, timeout_msec, PROCESS_OUTPUT_LIMIT_BYTES):
		if stage == STAGE_VERSION:
			_qpdf_version_verified = false
			_qpdf_version_error = NotLightL10n.text("pdf.optimize.qpdf_missing")
			_fail_active(_qpdf_version_error)
		else:
			_fail_active(NotLightL10n.text("pdf.optimize.process_start_failed"))
		return
	_emit_progress(progress, message)


func _handle_process_result(result: Dictionary) -> void:
	if bool(result.get("timed_out", false)):
		_fail_active(NotLightL10n.text("pdf.optimize.timeout"))
		return
	if bool(result.get("cancelled", false)):
		_fail_active(NotLightL10n.text("pdf.optimize.cancelled"))
		return
	var exit_code: int = int(result.get("exit_code", -1))
	var stdout_text: String = str(result.get("stdout", ""))
	var stderr_text: String = str(result.get("stderr", ""))
	match _active_stage:
		STAGE_VERSION:
			if exit_code != 0:
				_qpdf_version_verified = false
				_qpdf_version_error = NotLightL10n.text("pdf.optimize.qpdf_missing")
				_fail_active(_qpdf_version_error)
				return
			var version_output: String = stdout_text if not stdout_text.strip_edges().is_empty() else stderr_text
			var detected_line: String = QpdfTools.parse_version_line(version_output)
			var detected_version: String = QpdfTools.parse_version_value(version_output)
			if detected_version.is_empty():
				_qpdf_version_verified = false
				_qpdf_version_error = NotLightL10n.text("pdf.optimize.qpdf_version_unknown")
				_fail_active(_qpdf_version_error)
				return
			if OS.has_feature("windows") and detected_version != QpdfTools.BUNDLED_VERSION:
				_qpdf_version_verified = false
				_qpdf_version_error = NotLightL10n.text("pdf.optimize.qpdf_version_mismatch", {
					"expected": QpdfTools.BUNDLED_VERSION,
					"actual": detected_version,
				})
				_fail_active(_qpdf_version_error)
				return
			_qpdf_version_line = detected_line
			_qpdf_version = detected_version
			_qpdf_version_verified = true
			_qpdf_version_error = ""
			_start_source_hash()
		STAGE_SOURCE_CHECK:
			if not _accept_qpdf_check(exit_code, true, stderr_text):
				return
			_start_source_probe()
		STAGE_SOURCE_PROBE:
			if exit_code != 0:
				_fail_active(NotLightL10n.text("pdf.optimize.poppler_failed"))
				return
			var source_info: Dictionary = PdfDocumentProbe.parse_pdfinfo(stdout_text, "")
			if not bool(source_info.get("ok", false)):
				_fail_active(str(source_info.get("error", NotLightL10n.text("pdf.optimize.source_invalid"))))
				return
			if bool(source_info.get("encrypted", false)):
				_fail_active(NotLightL10n.text("pdf.optimize.encrypted_unsupported"))
				return
			_active["source_info"] = source_info
			_start_optimize()
		STAGE_OPTIMIZE:
			if exit_code == 3:
				_fail_active(NotLightL10n.text("pdf.optimize.qpdf_warning"))
				return
			if exit_code != 0 or not _is_nonempty_file(str(_active.get("output_path", ""))):
				_fail_active(NotLightL10n.text("pdf.optimize.qpdf_failed", {"code": exit_code}))
				return
			_start_result_check()
		STAGE_RESULT_CHECK:
			if not _accept_qpdf_check(exit_code, false, stderr_text):
				return
			_start_result_probe()
		STAGE_RESULT_PROBE:
			if exit_code != 0:
				_fail_active(NotLightL10n.text("pdf.optimize.poppler_failed"))
				return
			var result_info: Dictionary = PdfDocumentProbe.parse_pdfinfo(stdout_text, "")
			if not bool(result_info.get("ok", false)):
				_fail_active(NotLightL10n.text("pdf.optimize.result_invalid"))
				return
			var source_info: Dictionary = _active.get("source_info", {}) as Dictionary
			if int(result_info.get("page_count", 0)) != int(source_info.get("page_count", 0)):
				_fail_active(NotLightL10n.text("pdf.optimize.page_count_mismatch"))
				return
			if bool(result_info.get("encrypted", false)):
				_fail_active(NotLightL10n.text("pdf.optimize.result_invalid"))
				return
			_active["result_info"] = result_info
			_start_render_verification(1, false)
		STAGE_RENDER_FIRST:
			if exit_code != 0 or not _is_nonempty_file(str(_active.get("verify_first_prefix", "")) + ".png"):
				_fail_active(NotLightL10n.text("pdf.optimize.render_verify_failed"))
				return
			var result_info: Dictionary = _active.get("result_info", {}) as Dictionary
			var page_count: int = maxi(1, int(result_info.get("page_count", 1)))
			if page_count > 1:
				_start_render_verification(page_count, true)
			else:
				_start_hash_if_worthwhile()
		STAGE_RENDER_LAST:
			if exit_code != 0 or not _is_nonempty_file(str(_active.get("verify_last_prefix", "")) + ".png"):
				_fail_active(NotLightL10n.text("pdf.optimize.render_verify_failed"))
				return
			_start_hash_if_worthwhile()
		_:
			_fail_active(NotLightL10n.text("pdf.optimize.internal_error"))


func _accept_qpdf_check(exit_code: int, source: bool, _stderr_text: String) -> bool:
	if exit_code == 0:
		return true
	if exit_code == 3:
		_fail_active(NotLightL10n.text("pdf.optimize.qpdf_warning"))
		return false
	_fail_active(NotLightL10n.text("pdf.optimize.source_invalid" if source else "pdf.optimize.result_invalid"))
	return false


func _start_hash_if_worthwhile() -> void:
	var output_path: String = str(_active.get("output_path", ""))
	var output_size: int = _file_size(output_path)
	var source_size: int = maxi(0, int(_active.get("source_byte_size", 0)))
	if output_size <= 0 or source_size <= 0:
		_fail_active(NotLightL10n.text("pdf.optimize.result_invalid"))
		return
	var required_saving: int = maxi(MIN_SAVING_BYTES, int(ceil(float(source_size) * MIN_SAVING_RATIO)))
	var saved_bytes: int = source_size - output_size
	if saved_bytes < required_saving:
		_fail_active(NotLightL10n.text("pdf.optimize.not_worthwhile"))
		return
	var state: Dictionary = pdf_media.get_variant_state(str(_active.get("asset_id", "")))
	var existing_value: Variant = (state.get("variants", {}) as Dictionary).get(PdfMediaService.VARIANT_OPTIMIZED, {})
	if existing_value is Dictionary:
		var existing_size: int = int((existing_value as Dictionary).get("byte_size", 0))
		if existing_size > 0 and output_size >= existing_size:
			_fail_active(NotLightL10n.text("pdf.optimize.existing_smaller"))
			return
	_active["output_byte_size"] = output_size
	_active["saved_bytes"] = saved_bytes
	if not _start_hash_job(
		output_path,
		STAGE_RESULT_HASH,
		0.88,
		NotLightL10n.text("pdf.optimize.hashing")
	):
		_fail_active(NotLightL10n.text("pdf.optimize.hash_failed"))


func _start_hash_job(path: String, stage: String, progress: float, message: String) -> bool:
	if not _hash_worker_started or not _hash_job_key.is_empty() or path.is_empty():
		return false
	# Discard completed results from a previously cancelled job before assigning
	# a new key. Results are keyed as an additional stale-job guard.
	_hash_worker.poll_results(FileHashWorker.MAX_PENDING_JOBS)
	var job_key: String = AssetId.make_temporary_id("pdfhash")
	if not _hash_worker.request(job_key, path):
		return false
	_hash_job_key = job_key
	_active_stage = stage
	_emit_progress(progress, message)
	return true


func _poll_hash_stage() -> void:
	if not _hash_worker_started or _hash_job_key.is_empty():
		_fail_active(NotLightL10n.text("pdf.optimize.hash_failed"))
		return
	var results: Array[Dictionary] = _hash_worker.poll_results(FileHashWorker.MAX_PENDING_JOBS)
	if results.is_empty():
		return
	var matching_result: Dictionary = {}
	for result: Dictionary in results:
		if str(result.get("job_key", "")) == _hash_job_key:
			matching_result = result
			break
	if matching_result.is_empty():
		return
	var completed_stage: String = _active_stage
	_hash_job_key = ""
	if bool(matching_result.get("cancelled", false)):
		_fail_active(NotLightL10n.text("pdf.optimize.cancelled"))
		return
	if not str(matching_result.get("error", "")).is_empty():
		_fail_active(NotLightL10n.text("pdf.optimize.hash_failed"))
		return
	var hash_sha256: String = str(matching_result.get("hash_sha256", "")).strip_edges().to_lower()
	var actual_byte_size: int = int(matching_result.get("byte_size", 0))
	if not _is_sha256(hash_sha256) or actual_byte_size <= 0:
		_fail_active(NotLightL10n.text("pdf.optimize.hash_failed"))
		return
	if completed_stage == STAGE_SOURCE_HASH:
		var expected_size: int = int(_active.get("source_byte_size", 0))
		if actual_byte_size != expected_size:
			_fail_active(NotLightL10n.text("pdf.optimize.source_hash_mismatch"))
			return
		var expected_hash: String = str(_active.get("source_hash_sha256", "")).strip_edges().to_lower()
		if hash_sha256 != expected_hash:
			_fail_active(NotLightL10n.text("pdf.optimize.source_hash_mismatch"))
			return
		_start_source_check()
		return
	if completed_stage == STAGE_RESULT_HASH:
		var expected_output_size: int = int(_active.get("output_byte_size", 0))
		if actual_byte_size != expected_output_size:
			_fail_active(NotLightL10n.text("pdf.optimize.result_changed"))
			return
		_active["output_hash_sha256"] = hash_sha256
		_active_stage = STAGE_COMMIT
		_commit_active_variant()
		return
	_fail_active(NotLightL10n.text("pdf.optimize.internal_error"))


func _commit_active_variant() -> void:
	var asset_id: String = str(_active.get("asset_id", ""))
	var output_path: String = str(_active.get("output_path", ""))
	var output_hash: String = str(_active.get("output_hash_sha256", ""))
	var output_size: int = int(_active.get("output_byte_size", 0))
	_emit_progress(0.97, NotLightL10n.text("pdf.optimize.committing"))
	var commit: Dictionary = library.blobs.commit_preverified_temp(output_path, output_hash, "pdf", output_size)
	if commit.is_empty():
		_fail_active(NotLightL10n.text("pdf.optimize.commit_failed"))
		return
	var source_info: Dictionary = _active.get("source_info", {}) as Dictionary
	var result_info: Dictionary = _active.get("result_info", {}) as Dictionary
	var preset: String = str(_active.get("preset", PRESET_LOSSLESS))
	var variant: Dictionary = {
		"blob_relpath": str(commit.get("relative_path", "")),
		"hash_sha256": output_hash,
		"byte_size": output_size,
		"extension": "pdf",
		"source_hash_sha256": str(_active.get("source_hash_sha256", "")),
		"source_byte_size": int(_active.get("source_byte_size", 0)),
		"backend": "qpdf",
		"backend_version": _qpdf_version,
		"preset": preset,
		"lossy": QpdfTools.preset_is_lossy(preset),
		"page_count_before": int(source_info.get("page_count", 0)),
		"page_count_after": int(result_info.get("page_count", 0)),
		"created_at_unix": int(Time.get_unix_time_from_system()),
	}
	if QpdfTools.preset_is_lossy(preset):
		variant["jpeg_quality"] = 90
	if not pdf_media.register_optimized_variant(asset_id, variant):
		library.delete_blob_if_unreferenced_path(str(commit.get("relative_path", "")))
		_fail_active(NotLightL10n.text("pdf.optimize.register_failed"))
		return
	var optimized_path: String = library.resolve_blob_relative(str(commit.get("relative_path", "")))
	var saved_bytes: int = int(_active.get("saved_bytes", 0))
	_cleanup_active_files()
	_active_stage = STAGE_NONE
	_active = {}
	_hash_job_key = ""
	optimization_progress.emit(asset_id, 1.0, NotLightL10n.text("pdf.optimize.completed"))
	optimization_completed.emit(asset_id, optimized_path, saved_bytes)
	if _queue.is_empty():
		set_process(false)
	else:
		set_process(true)


func _fail_active(message: String) -> void:
	var asset_id: String = str(_active.get("asset_id", ""))
	_runner.cancel()
	_runner.close()
	if not _hash_job_key.is_empty():
		_hash_worker.cancel(_hash_job_key)
	_hash_job_key = ""
	_cleanup_active_files()
	_active_stage = STAGE_NONE
	_active = {}
	if not asset_id.is_empty():
		optimization_failed.emit(asset_id, message)
	if _queue.is_empty():
		set_process(false)
	else:
		set_process(true)


func _emit_progress(progress: float, message: String) -> void:
	if _active.is_empty():
		return
	optimization_progress.emit(str(_active.get("asset_id", "")), clampf(progress, 0.0, 1.0), message)


func _cleanup_active_files() -> void:
	if _active.is_empty():
		return
	_remove_file(str(_active.get("output_path", "")))
	_remove_file(str(_active.get("verify_first_prefix", "")) + ".png")
	_remove_file(str(_active.get("verify_last_prefix", "")) + ".png")


func _cleanup_stale_optimizer_files() -> void:
	if library == null or library.blobs == null:
		return
	var directory: DirAccess = DirAccess.open(library.blobs.temp_dir)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.begins_with("pdfopt_"):
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()


func _timeout_for_file(path: String, base_seconds: int, maximum_seconds: int) -> int:
	var byte_size: int = _file_size(path)
	var extra_seconds: int = int(ceil(float(byte_size) / float(10 * 1024 * 1024))) * 2
	return mini(maximum_seconds, base_seconds + extra_seconds) * 1000


func _file_size(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = int(file.get_length())
	file.close()
	return size


func _is_nonempty_file(path: String) -> bool:
	return _file_size(path) > 0


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		var is_digit: bool = codepoint >= 48 and codepoint <= 57
		var is_hex_letter: bool = codepoint >= 97 and codepoint <= 102
		if not is_digit and not is_hex_letter:
			return false
	return true


func _remove_file(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
