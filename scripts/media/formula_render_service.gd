# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaRenderService
extends Node

signal backend_status_changed
signal texture_ready(cache_key: String)
signal render_failed(cache_key: String, message: String, detail: String)

const CACHE_ROOT: String = "user://notlight/cache/formulas"
const JOB_ROOT: String = CACHE_ROOT + "/.jobs"
const WRAPPER_VERSION: String = "notlight-formula-mitex-wrapper-v4-vector-guard-band"
const VECTOR_CONTRACT_VERSION: String = "typst-svg-white-mask-godot-tint-v2"
const MAX_PENDING_JOBS: int = 8
const MAX_WAITING_REQUESTS: int = 64
const MAX_DOCUMENT_WAITERS: int = 12
const MAX_PENDING_RASTER_REQUESTS: int = 32
const RASTER_SUBMITS_PER_FRAME: int = 2
const MAX_SOURCE_LENGTH: int = FormulaStore.MAX_SOURCE_LENGTH
const COMPILE_TIMEOUT_MSEC: int = 7000
const VERSION_TIMEOUT_MSEC: int = 4000
const PROCESS_OUTPUT_LIMIT_BYTES: int = 128 * 1024
const MAX_FAILURE_RECORDS: int = 2048
const MAX_SVG_BYTES: int = 4 * 1024 * 1024
const MAX_MEMORY_CACHE_BYTES: int = 64 * 1024 * 1024
const MAX_DISK_CACHE_BYTES: int = 96 * 1024 * 1024
const MAX_DISK_CACHE_FILES: int = 768
const MAX_DISK_SCAN_FILES: int = 4096
const UPLOADS_PER_FRAME: int = 2
const PRUNE_EVERY_COMPLETIONS: int = 24
const DISK_DELETIONS_PER_FRAME: int = 4

const _TIER_VALUES: PackedInt32Array = [256, 384, 512, 768, 1024, 1536, 2048]
# FormulaObject accepts a math snippet, not an arbitrary TeX document. These
# commands are rejected before MiTeX sees the source. The source itself is stored
# in a separate text file and passed as data to the fixed Typst wrapper.
const _BLOCKED_TEX_TOKENS: PackedStringArray = [
	"\\documentclass",
	"\\usepackage",
	"\\begin{document}",
	"\\end{document}",
	"\\input",
	"\\include",
	"\\includegraphics",
	"\\openin",
	"\\openout",
	"\\newread",
	"\\newwrite",
	"\\read",
	"\\write",
	"\\immediate",
	"\\special",
	"\\catcode",
	"\\csname",
	"\\shipout",
	"\\iftypst",
]

var _image_worker: FormulaImageLoadWorker = FormulaImageLoadWorker.new()
var _cache_scan_worker: FormulaCacheScanWorker = FormulaCacheScanWorker.new()
var _runner: SidecarProcessRunner = SidecarProcessRunner.new()
var _package_root: String = ""
var _package_path: String = ""
var _package_sha256: String = ""
var _typst_executable: String = ""
var _typst_version: String = ""
var _backend_error: String = ""
var _initialization_started: bool = false
var _version_pending: bool = false
var _ready_for_render: bool = false
var _waiting_requests: Dictionary = {}
var _queue: Array[Dictionary] = []
var _queued_documents: Dictionary = {}
# One vector compile can satisfy multiple raster tiers (board + editor preview).
# Keep consumers per document so a preview can never get stuck just because the
# board requested the same source at a different tier first.
var _document_waiters: Dictionary = {}
var _active_job: Dictionary = {}
var _loading_keys: Dictionary = {}
var _raster_requests: Dictionary = {}
var _raster_order: Array[String] = []
var _texture_cache: Dictionary = {}
var _texture_bytes: int = 0
var _use_serial: int = 0
var _failures: Dictionary = {}
var _job_serial: int = 0
var _completion_count: int = 0
var _disk_delete_queue: Array[Dictionary] = []
var _latest_preview_token: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_ROOT))
	# A process crash can leave one tiny private formula job behind. It is never
	# canonical data, so clear it before accepting work and recreate the root.
	_remove_tree(ProjectSettings.globalize_path(JOB_ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(JOB_ROOT))
	_image_worker.start()
	_cache_scan_worker.start()
	_request_disk_cache_scan()
	_begin_initialization()
	set_process(true)


func _exit_tree() -> void:
	_runner.cancel()
	_runner.close()
	_image_worker.stop()
	_cache_scan_worker.stop()
	_cleanup_job(_active_job)
	_disk_delete_queue.clear()
	_queue.clear()
	_waiting_requests.clear()
	_queued_documents.clear()
	_document_waiters.clear()
	_raster_requests.clear()
	_raster_order.clear()


func _process(_delta: float) -> void:
	_poll_version_check()
	_poll_active_process()
	_poll_image_worker()
	_poll_disk_cache_scan()
	_drain_disk_delete_queue()
	if _ready_for_render:
		_drain_waiting_requests()
		_drain_raster_queue()
		_start_next_job_if_possible()
	set_process(_should_process())


func request_texture(record: Dictionary, desired_extent: float) -> Texture2D:
	var normalized: Dictionary = normalize_record(record)
	var source: String = str(normalized.get("source_latex", ""))
	if source.strip_edges().is_empty():
		return null
	var tier: int = _tier_for_extent(desired_extent * float(normalized.get("font_scale", 1.0)))
	if not _ready_for_render:
		_queue_waiting_request(normalized, tier)
		set_process(true)
		return null
	var key: String = _cache_key(normalized, tier)
	var cached: Texture2D = _memory_texture(key)
	if cached != null:
		return cached
	_request_ready(normalized, tier, key)
	return null


func request_preview_texture(record: Dictionary, desired_extent: float, preview_token: int) -> Texture2D:
	var token: int = maxi(1, preview_token)
	if token < _latest_preview_token:
		return null
	var normalized: Dictionary = normalize_record(record)
	if token > _latest_preview_token:
		_latest_preview_token = token
		# Preserve an already-running vector compile when the new preview asks for
		# the exact same document. This avoids a cancel/requeue race where the fresh
		# waiter could otherwise be attached to a process that is already terminating.
		var preserve_document_key: String = _document_key(normalized) if _ready_for_render else ""
		_cancel_stale_preview_work(token, preserve_document_key)
	var source: String = str(normalized.get("source_latex", ""))
	if source.strip_edges().is_empty():
		return null
	var tier: int = _tier_for_extent(desired_extent * float(normalized.get("font_scale", 1.0)))
	if not _ready_for_render:
		_queue_waiting_request(normalized, tier, token)
		set_process(true)
		return null
	var key: String = _cache_key(normalized, tier)
	var cached: Texture2D = _memory_texture(key)
	if cached != null:
		return cached
	_request_ready(normalized, tier, key, token)
	return null


func cache_key_for_record(record: Dictionary, desired_extent: float) -> String:
	if not _ready_for_render:
		return ""
	var normalized: Dictionary = normalize_record(record)
	if str(normalized.get("source_latex", "")).strip_edges().is_empty():
		return ""
	return _cache_key(normalized, _tier_for_extent(desired_extent * float(normalized.get("font_scale", 1.0))))


func get_cached_texture(record: Dictionary, desired_extent: float) -> Texture2D:
	var key: String = cache_key_for_record(record, desired_extent)
	return _memory_texture(key) if not key.is_empty() else null


func get_failure_message(cache_key: String) -> String:
	var failure: Dictionary = _failures.get(cache_key, {}) as Dictionary
	return str(failure.get("message", ""))


func get_failure_detail(cache_key: String) -> String:
	var failure: Dictionary = _failures.get(cache_key, {}) as Dictionary
	return str(failure.get("detail", ""))


func backend_available() -> bool:
	return _ready_for_render


func backend_status_text() -> String:
	if _ready_for_render:
		return NotLightL10n.text("formula.backend.ready", {"version": _typst_version, "mitex": TypstMiTexTools.MITEX_VERSION})
	if not _backend_error.is_empty():
		return _backend_error
	if _version_pending:
		return NotLightL10n.text("formula.backend.checking_tool")
	return NotLightL10n.text("formula.backend.unavailable")


func package_sha256() -> String:
	return _package_sha256


func typst_version() -> String:
	return _typst_version


func pending_job_count() -> int:
	return _queue.size() + (1 if not _active_job.is_empty() else 0) + _loading_keys.size() + _raster_requests.size()


static func normalize_record(record: Dictionary) -> Dictionary:
	var foreground_value: Variant = record.get("foreground", FormulaStore.DEFAULT_FOREGROUND)
	var foreground: Color = FormulaStore.DEFAULT_FOREGROUND
	if foreground_value is Color:
		foreground = foreground_value as Color
	else:
		foreground = Color.from_string(str(foreground_value), FormulaStore.DEFAULT_FOREGROUND)
	return {
		"source_latex": FormulaStore.normalize_source(str(record.get("source_latex", ""))),
		"display_mode": FormulaStore.normalize_display_mode(int(record.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE))),
		"font_scale": clampf(float(record.get("font_scale", FormulaStore.DEFAULT_FONT_SCALE)), FormulaStore.MIN_FONT_SCALE, FormulaStore.MAX_FONT_SCALE),
		"foreground": foreground,
	}


func _begin_initialization() -> void:
	if _initialization_started:
		return
	_initialization_started = true
	_package_root = TypstMiTexTools.package_root()
	_package_path = TypstMiTexTools.mitex_package_path()
	if _package_root.is_empty() or _package_path.is_empty():
		_set_backend_error(NotLightL10n.text("formula.backend.package_missing"))
		return
	_package_sha256 = TypstMiTexTools.package_content_digest(_package_path)
	if _package_sha256.length() != 64:
		_set_backend_error(NotLightL10n.text("formula.backend.package_hash_failed"))
		return
	_typst_executable = TypstMiTexTools.typst_path()
	if _typst_executable.is_empty():
		_set_backend_error(NotLightL10n.text("formula.backend.tool_missing"))
		return
	if not _runner.start(_typst_executable, TypstMiTexTools.version_arguments(), VERSION_TIMEOUT_MSEC, 16 * 1024):
		_set_backend_error(NotLightL10n.text("formula.backend.tool_missing"))
		return
	_version_pending = true


func _poll_version_check() -> void:
	if not _version_pending:
		return
	var result: Dictionary = _runner.poll()
	if not bool(result.get("finished", false)):
		return
	_version_pending = false
	var output: String = str(result.get("stdout", "")) + "\n" + str(result.get("stderr", ""))
	if int(result.get("exit_code", -1)) != 0:
		_set_backend_error(NotLightL10n.text("formula.backend.tool_start_failed"))
		return
	_typst_version = TypstMiTexTools.parse_version_value(output)
	if _typst_version != TypstMiTexTools.BUNDLED_TYPST_VERSION:
		_set_backend_error(NotLightL10n.text("formula.backend.version_mismatch", {"expected": TypstMiTexTools.BUNDLED_TYPST_VERSION, "actual": _typst_version if not _typst_version.is_empty() else "?"}))
		return
	_update_ready_state()


func _update_ready_state() -> void:
	var next_ready: bool = (
		not _package_sha256.is_empty()
		and _typst_version == TypstMiTexTools.BUNDLED_TYPST_VERSION
		and _backend_error.is_empty()
	)
	if _ready_for_render == next_ready:
		return
	_ready_for_render = next_ready
	backend_status_changed.emit()
	set_process(true)


func _set_backend_error(message: String) -> void:
	_backend_error = message
	_ready_for_render = false
	backend_status_changed.emit()
	set_process(true)


func _queue_waiting_request(record: Dictionary, tier: int, preview_token: int = 0) -> void:
	var identity: String = _small_sha256(JSON.stringify({"record": _record_key_data(record), "tier": tier}))
	var entry: Dictionary = _waiting_requests.get(identity, {}) as Dictionary
	if entry.is_empty():
		if _waiting_requests.size() >= MAX_WAITING_REQUESTS:
			var keys: Array = _waiting_requests.keys()
			if not keys.is_empty():
				_waiting_requests.erase(keys[0])
		entry = {
			"record": record.duplicate(true),
			"tier": tier,
			"has_board_request": false,
			"preview_token": 0,
		}
	if preview_token > 0:
		entry["preview_token"] = maxi(int(entry.get("preview_token", 0)), preview_token)
	else:
		entry["has_board_request"] = true
	_waiting_requests[identity] = entry


func _drain_waiting_requests() -> void:
	if _waiting_requests.is_empty():
		return
	var requests: Array = _waiting_requests.values()
	_waiting_requests.clear()
	for raw_request: Variant in requests:
		if raw_request is not Dictionary:
			continue
		var request: Dictionary = raw_request as Dictionary
		var record: Dictionary = request.get("record", {}) as Dictionary
		var tier: int = int(request.get("tier", 512))
		var has_board_request: bool = bool(request.get("has_board_request", false))
		var preview_token: int = int(request.get("preview_token", 0))
		if has_board_request:
			_request_ready(record, tier, _cache_key(record, tier), 0)
		elif preview_token == _latest_preview_token:
			_request_ready(record, tier, _cache_key(record, tier), preview_token)


func _request_ready(record: Dictionary, tier: int, key: String, preview_token: int = 0) -> void:
	# Deterministic compile/decode failures are sticky for this exact cache key.
	# Editing source/style/backend inputs creates a new key and therefore a new try.
	if (
		key.is_empty()
		or _texture_cache.has(key)
		or _loading_keys.has(key)
		or _raster_requests.has(key)
		or _failures.has(key)
	):
		return
	var doc_key: String = _document_key(record)
	var cache_directory: String = CACHE_ROOT.path_join(doc_key.left(2)).path_join(doc_key)
	var svg_path: String = cache_directory.path_join("formula.svg")
	if FileAccess.file_exists(svg_path):
		_queue_raster_request(key, svg_path, tier, preview_token)
		return

	# One vector document is shared by all raster tiers. Every consumer is recorded
	# before returning so an editor preview and a board render can safely converge on
	# one Typst process without losing the tier that was requested second.
	if _queued_documents.has(doc_key):
		_add_document_waiter(doc_key, key, tier, preview_token)
		return
	if _queue.size() >= MAX_PENDING_JOBS:
		_queue_waiting_request(record, tier, preview_token)
		set_process(true)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))
	_add_document_waiter(doc_key, key, tier, preview_token)
	var job: Dictionary = {
		"cache_key": key,
		"document_key": doc_key,
		"record": record.duplicate(true),
		"tier": tier,
		"cache_directory": cache_directory,
		"svg_path": svg_path,
		"preview_token": preview_token,
	}
	_queue.append(job)
	_queued_documents[doc_key] = true
	set_process(true)


func _add_document_waiter(doc_key: String, key: String, tier: int, preview_token: int) -> void:
	if doc_key.is_empty() or key.is_empty():
		return
	var waiters: Dictionary = _document_waiters.get(doc_key, {}) as Dictionary
	var entry: Dictionary = waiters.get(key, {}) as Dictionary
	if entry.is_empty() and waiters.size() >= MAX_DOCUMENT_WAITERS:
		# There are only seven supported raster tiers, so reaching this guard means
		# duplicate/abusive requests. Keep the existing bounded set; a future redraw
		# can request the missing tier after the vector has been committed.
		return
	if entry.is_empty():
		entry = {"tier": tier, "has_board_request": false, "preview_token": 0}
	if preview_token > 0:
		entry["preview_token"] = maxi(int(entry.get("preview_token", 0)), preview_token)
	else:
		entry["has_board_request"] = true
	waiters[key] = entry
	_document_waiters[doc_key] = waiters


func _queue_raster_request(key: String, svg_path: String, tier: int, preview_token: int = 0, has_board_request: bool = false) -> void:
	if key.is_empty() or svg_path.is_empty() or _texture_cache.has(key) or _loading_keys.has(key) or _failures.has(key):
		return
	var board_request: bool = has_board_request or preview_token <= 0
	if _raster_requests.has(key):
		var existing: Dictionary = _raster_requests[key] as Dictionary
		existing["has_board_request"] = bool(existing.get("has_board_request", false)) or board_request
		if preview_token > 0:
			existing["preview_token"] = maxi(int(existing.get("preview_token", 0)), preview_token)
		_raster_requests[key] = existing
		return
	if _image_worker.request_svg(key, svg_path, tier):
		_loading_keys[key] = {"path": svg_path, "tier": tier}
		set_process(true)
		return
	if _raster_requests.size() >= MAX_PENDING_RASTER_REQUESTS:
		# Backpressure is not a formula failure. Board renders naturally retry on a
		# later redraw; preview requests are also re-issued by their debounce cycle.
		return
	_raster_requests[key] = {
		"path": svg_path,
		"tier": tier,
		"has_board_request": board_request,
		"preview_token": preview_token if preview_token > 0 else 0,
	}
	_raster_order.append(key)
	set_process(true)


func _drain_raster_queue() -> void:
	var submitted: int = 0
	while submitted < RASTER_SUBMITS_PER_FRAME and not _raster_order.is_empty():
		var key: String = _raster_order[0]
		var request: Dictionary = _raster_requests.get(key, {}) as Dictionary
		if request.is_empty():
			_raster_order.pop_front()
			continue
		var preview_token: int = int(request.get("preview_token", 0))
		if (
			not bool(request.get("has_board_request", false))
			and preview_token > 0
			and preview_token != _latest_preview_token
		):
			_raster_requests.erase(key)
			_raster_order.pop_front()
			continue
		var svg_path: String = str(request.get("path", ""))
		var tier: int = int(request.get("tier", 512))
		if not FileAccess.file_exists(svg_path):
			_raster_requests.erase(key)
			_raster_order.pop_front()
			continue
		if not _image_worker.request_svg(key, svg_path, tier):
			break
		_raster_requests.erase(key)
		_raster_order.pop_front()
		_loading_keys[key] = {"path": svg_path, "tier": tier}
		submitted += 1


func _cancel_stale_preview_work(current_token: int, preserve_document_key: String = "") -> void:
	# Drop stale preview-only consumers, but never cancel work that the board also
	# needs. This is essential when the preview and the selected object share the
	# same content-addressed vector document.
	for raw_doc_key: Variant in _document_waiters.keys():
		var doc_key: String = str(raw_doc_key)
		var waiters: Dictionary = _document_waiters[doc_key] as Dictionary
		for raw_key: Variant in waiters.keys():
			var key: String = str(raw_key)
			var entry: Dictionary = waiters[key] as Dictionary
			var token: int = int(entry.get("preview_token", 0))
			if token > 0 and token != current_token:
				if bool(entry.get("has_board_request", false)):
					entry["preview_token"] = 0
					waiters[key] = entry
				else:
					waiters.erase(key)
		if waiters.is_empty():
			_document_waiters.erase(doc_key)
		else:
			_document_waiters[doc_key] = waiters

	for index: int in range(_queue.size() - 1, -1, -1):
		var job: Dictionary = _queue[index]
		var doc_key: String = str(job.get("document_key", ""))
		if not _document_waiters.has(doc_key):
			_queued_documents.erase(doc_key)
			_queue.remove_at(index)

	for raw_key: Variant in _waiting_requests.keys():
		var waiting: Dictionary = _waiting_requests[raw_key] as Dictionary
		var token: int = int(waiting.get("preview_token", 0))
		if token > 0 and token != current_token:
			if bool(waiting.get("has_board_request", false)):
				waiting["preview_token"] = 0
				_waiting_requests[raw_key] = waiting
			else:
				_waiting_requests.erase(raw_key)

	for key: String in _raster_order.duplicate():
		var request: Dictionary = _raster_requests.get(key, {}) as Dictionary
		var token: int = int(request.get("preview_token", 0))
		if token > 0 and token != current_token:
			if bool(request.get("has_board_request", false)):
				request["preview_token"] = 0
				_raster_requests[key] = request
			else:
				_raster_requests.erase(key)
				_raster_order.erase(key)

	if not _active_job.is_empty():
		var active_doc_key: String = str(_active_job.get("document_key", ""))
		if not _document_waiters.has(active_doc_key) and active_doc_key != preserve_document_key:
			_active_job["cancelled_as_stale"] = true
			_runner.cancel()
	set_process(true)


func _start_next_job_if_possible() -> void:
	if not _active_job.is_empty() or _version_pending or _queue.is_empty():
		return
	_active_job = _queue.pop_front()
	var key: String = str(_active_job.get("cache_key", ""))
	_job_serial += 1
	var temp_directory: String = JOB_ROOT.path_join("job_%d_%d" % [Time.get_ticks_msec(), _job_serial])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_directory))
	_active_job["temp_directory"] = temp_directory
	_start_compile_stage()
	if key.is_empty():
		_finish_active_failure(NotLightL10n.text("formula.error.internal"), "")


func _start_compile_stage() -> void:
	var record: Dictionary = _active_job.get("record", {}) as Dictionary
	var source: String = str(record.get("source_latex", ""))
	var source_error: String = _validate_source(source)
	if not source_error.is_empty():
		_finish_active_failure(source_error, "")
		return
	var temp_directory: String = str(_active_job.get("temp_directory", ""))
	var source_path: String = temp_directory.path_join("formula.txt")
	var wrapper_path: String = temp_directory.path_join("formula.typ")
	var output_path: String = temp_directory.path_join("formula.svg")
	var package_cache_path: String = temp_directory.path_join("package-cache")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(package_cache_path))
	if not _write_text_file(source_path, FormulaStore.normalize_source(source)):
		_finish_active_failure(NotLightL10n.text("formula.error.temp_write"), "source")
		return
	if not _write_text_file(wrapper_path, _build_typst_document(record)):
		_finish_active_failure(NotLightL10n.text("formula.error.temp_write"), "wrapper")
		return
	_active_job["generated_svg_path"] = output_path
	var started: bool = _runner.start(
		_typst_executable,
		TypstMiTexTools.compile_arguments(wrapper_path, output_path, temp_directory, _package_root, package_cache_path),
		COMPILE_TIMEOUT_MSEC,
		PROCESS_OUTPUT_LIMIT_BYTES
	)
	if not started:
		_finish_active_failure(NotLightL10n.text("formula.error.typst_start"), "")


func _poll_active_process() -> void:
	if _active_job.is_empty():
		return
	var result: Dictionary = _runner.poll()
	if not bool(result.get("finished", false)):
		return
	var diagnostic: String = _bounded_diagnostic(str(result.get("stderr", "")) + "\n" + str(result.get("stdout", "")))
	if bool(result.get("timed_out", false)):
		_finish_active_failure(NotLightL10n.text("formula.error.timeout"), diagnostic)
		return
	if bool(result.get("cancelled", false)):
		if bool(_active_job.get("cancelled_as_stale", false)):
			_finish_active_job()
		else:
			_finish_active_failure(NotLightL10n.text("formula.error.cancelled"), diagnostic)
		return
	if int(result.get("exit_code", -1)) != 0:
		_finish_active_failure(_friendly_compile_error(diagnostic), diagnostic)
		return
	_handle_compile_success()


func _handle_compile_success() -> void:
	var generated_svg: String = str(_active_job.get("generated_svg_path", ""))
	var size_bytes: int = _file_size(generated_svg)
	if size_bytes <= 0 or size_bytes > MAX_SVG_BYTES:
		_finish_active_failure(NotLightL10n.text("formula.error.svg_invalid"), "")
		return
	if not _svg_header_valid(generated_svg):
		_finish_active_failure(NotLightL10n.text("formula.error.svg_invalid"), NotLightL10n.text("runtime.formula.technical.svg_root_missing"))
		return
	var final_svg: String = str(_active_job.get("svg_path", ""))
	var part_svg: String = final_svg + ".part"
	_remove_file_if_exists(part_svg)
	var move_error: Error = DirAccess.rename_absolute(_native_path(generated_svg), _native_path(part_svg))
	if move_error != OK:
		_finish_active_failure(NotLightL10n.text("formula.error.cache_commit"), NotLightL10n.text("runtime.formula.technical.svg_staging_move") % error_string(move_error))
		return
	# Atomic replace: the content-addressed document key means another valid SVG at
	# this path is equivalent, but remove a stale derived file before promotion.
	_remove_file_if_exists(final_svg)
	move_error = DirAccess.rename_absolute(_native_path(part_svg), _native_path(final_svg))
	if move_error != OK:
		_remove_file_if_exists(part_svg)
		_finish_active_failure(NotLightL10n.text("formula.error.cache_commit"), NotLightL10n.text("runtime.formula.technical.svg_commit_move") % error_string(move_error))
		return

	var document_key: String = str(_active_job.get("document_key", ""))
	var waiters: Dictionary = _document_waiters.get(document_key, {}) as Dictionary
	for raw_key: Variant in waiters.keys():
		var key: String = str(raw_key)
		var waiter: Dictionary = waiters[key] as Dictionary
		_queue_raster_request(
			key,
			final_svg,
			int(waiter.get("tier", 512)),
			int(waiter.get("preview_token", 0)),
			bool(waiter.get("has_board_request", false))
		)
	_document_waiters.erase(document_key)
	_finish_active_job()


func _poll_image_worker() -> void:
	for result: Dictionary in _image_worker.poll_results(UPLOADS_PER_FRAME):
		var key: String = str(result.get("cache_key", ""))
		var loading: Dictionary = _loading_keys.get(key, {}) as Dictionary
		var loading_path: String = str(loading.get("path", ""))
		_loading_keys.erase(key)
		var error: String = str(result.get("error", ""))
		var image_value: Variant = result.get("image")
		if not error.is_empty() or image_value is not Image:
			# A corrupt derived vector should not survive into future sessions. The
			# sticky in-memory failure prevents a hot compile loop in this session.
			if not loading_path.is_empty():
				_remove_file_if_exists(loading_path)
			_register_failure(key, NotLightL10n.text("formula.error.image_decode"), error)
			continue
		var image: Image = image_value as Image
		var texture: ImageTexture = ImageTexture.create_from_image(image)
		if texture == null:
			if not loading_path.is_empty():
				_remove_file_if_exists(loading_path)
			_register_failure(key, NotLightL10n.text("formula.error.image_decode"), NotLightL10n.text("runtime.formula.technical.texture_create_failed"))
			continue
		_store_texture(key, texture)
		_failures.erase(key)
		texture_ready.emit(key)
		_completion_count += 1
		if _completion_count % PRUNE_EVERY_COMPLETIONS == 0:
			_request_disk_cache_scan()


func _finish_active_failure(message: String, detail: String) -> void:
	var document_key: String = str(_active_job.get("document_key", ""))
	var waiters: Dictionary = _document_waiters.get(document_key, {}) as Dictionary
	if waiters.is_empty():
		var key: String = str(_active_job.get("cache_key", ""))
		_register_failure(key, message, detail)
	else:
		for raw_key: Variant in waiters.keys():
			var key: String = str(raw_key)
			_register_failure(key, message, detail)
		_document_waiters.erase(document_key)
	_finish_active_job()


func _finish_active_job() -> void:
	var document_key: String = str(_active_job.get("document_key", ""))
	_queued_documents.erase(document_key)
	_runner.close()
	_cleanup_job(_active_job)
	_active_job.clear()
	set_process(true)


func _register_failure(key: String, message: String, detail: String) -> void:
	if key.is_empty():
		return
	if _failures.size() >= MAX_FAILURE_RECORDS and not _failures.has(key):
		var keys: Array = _failures.keys()
		if not keys.is_empty():
			_failures.erase(keys[0])
	_failures[key] = {"message": message, "detail": _bounded_diagnostic(detail)}
	render_failed.emit(key, message, _bounded_diagnostic(detail))


func _cache_key(record: Dictionary, tier: int) -> String:
	var payload: Dictionary = _record_key_data(record)
	payload["tier"] = tier
	payload["wrapper"] = WRAPPER_VERSION
	payload["typst"] = _typst_version
	payload["mitex"] = TypstMiTexTools.MITEX_VERSION
	payload["mitex_sha256"] = _package_sha256
	payload["vector_contract"] = VECTOR_CONTRACT_VERSION
	return _small_sha256(JSON.stringify(payload))


func _document_key(record: Dictionary) -> String:
	var payload: Dictionary = _record_key_data(record)
	payload["wrapper"] = WRAPPER_VERSION
	payload["typst"] = _typst_version
	payload["mitex"] = TypstMiTexTools.MITEX_VERSION
	payload["mitex_sha256"] = _package_sha256
	payload["vector_contract"] = VECTOR_CONTRACT_VERSION
	return _small_sha256(JSON.stringify(payload))


func _record_key_data(record: Dictionary) -> Dictionary:
	# Foreground color is deliberately excluded from the vector/raster cache key.
	# Typst renders a neutral white alpha mask once and Godot applies FormulaStore
	# foreground at draw time. Color edits therefore never spawn a sidecar process.
	return {
		"source": FormulaStore.normalize_source(str(record.get("source_latex", ""))),
		"display_mode": FormulaStore.normalize_display_mode(int(record.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE))),
		"font_scale": snappedf(clampf(float(record.get("font_scale", 1.0)), FormulaStore.MIN_FONT_SCALE, FormulaStore.MAX_FONT_SCALE), 0.01),
	}


func _build_typst_document(record: Dictionary) -> String:
	var mode: int = FormulaStore.normalize_display_mode(int(record.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE)))
	var scale: float = clampf(float(record.get("font_scale", 1.0)), FormulaStore.MIN_FONT_SCALE, FormulaStore.MAX_FONT_SCALE)
	var render_call: String = "mi(source)" if mode == FormulaStore.DISPLAY_INLINE else "mitex(source)"
	# Render a neutral white alpha mask. Formula color is a lightweight Godot
	# draw-time tint, so opening/dragging the color picker cannot trigger Typst.
	return """#import \"%s\": mi, mitex
#set page(width: auto, height: auto, margin: 16pt, fill: none)
#set text(size: %.2fpt, fill: rgb(\"#FFFFFF\"))
#let source = read(\"formula.txt\")
#box(inset: 20pt)[#%s]
""" % [TypstMiTexTools.expected_local_import(), 18.0 * scale, render_call]


func _validate_source(source: String) -> String:
	var clean: String = FormulaStore.normalize_source(source)
	if clean.strip_edges().is_empty():
		return NotLightL10n.text("formula.error.empty")
	if clean.length() > MAX_SOURCE_LENGTH:
		return NotLightL10n.text("formula.error.too_long")
	var lower: String = clean.to_lower()
	for token: String in _BLOCKED_TEX_TOKENS:
		if lower.find(token) >= 0:
			return NotLightL10n.text("formula.error.blocked_command", {"command": token})
	return ""


func _friendly_compile_error(diagnostic: String) -> String:
	var clean: String = diagnostic.strip_edges()
	if clean.is_empty():
		return NotLightL10n.text("formula.error.compile_failed")
	for raw_line: String in clean.split("\n", false):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		# Typst short diagnostics usually start with `error:`. Keep the user-facing
		# excerpt bounded and leave the full bounded diagnostic behind "Подробнее".
		var error_index: int = line.find("error:")
		if error_index >= 0:
			return line.substr(error_index + 6).strip_edges().left(220)
	return NotLightL10n.text("formula.error.compile_failed")


func _bounded_diagnostic(value: String) -> String:
	return value.replace("\r", "").strip_edges().left(4096)


func _tier_for_extent(desired_extent: float) -> int:
	var target: int = clampi(int(ceil(maxf(desired_extent, 160.0))), 160, 2048)
	for tier: int in _TIER_VALUES:
		if tier >= target:
			return tier
	return 2048


func _memory_texture(key: String) -> Texture2D:
	var entry: Dictionary = _texture_cache.get(key, {}) as Dictionary
	var texture_value: Variant = entry.get("texture")
	if texture_value is not Texture2D:
		return null
	_use_serial += 1
	entry["last_use"] = _use_serial
	_texture_cache[key] = entry
	return texture_value as Texture2D


func _store_texture(key: String, texture: Texture2D) -> void:
	if texture == null:
		return
	var previous: Dictionary = _texture_cache.get(key, {}) as Dictionary
	_texture_bytes -= int(previous.get("bytes", 0))
	var texture_size: Vector2 = texture.get_size()
	var estimated_bytes: int = maxi(1, int(texture_size.x) * int(texture_size.y) * 4)
	_use_serial += 1
	_texture_cache[key] = {"texture": texture, "bytes": estimated_bytes, "last_use": _use_serial}
	_texture_bytes += estimated_bytes
	while _texture_bytes > MAX_MEMORY_CACHE_BYTES and _texture_cache.size() > 1:
		_evict_oldest_texture(key)


func _evict_oldest_texture(protected_key: String) -> void:
	var oldest_key: String = ""
	var oldest_use: int = 2147483647
	for raw_key: Variant in _texture_cache.keys():
		var candidate: String = str(raw_key)
		if candidate == protected_key:
			continue
		var entry: Dictionary = _texture_cache[candidate] as Dictionary
		var use_value: int = int(entry.get("last_use", 0))
		if use_value < oldest_use:
			oldest_use = use_value
			oldest_key = candidate
	if oldest_key.is_empty():
		return
	var removed: Dictionary = _texture_cache[oldest_key] as Dictionary
	_texture_bytes -= int(removed.get("bytes", 0))
	_texture_cache.erase(oldest_key)


func _request_disk_cache_scan() -> void:
	if not _disk_delete_queue.is_empty():
		return
	_cache_scan_worker.request_scan(ProjectSettings.globalize_path(CACHE_ROOT), MAX_DISK_SCAN_FILES)


func _poll_disk_cache_scan() -> void:
	var result: Dictionary = _cache_scan_worker.poll_result()
	if result.is_empty():
		return
	var raw_files: Variant = result.get("files", [])
	if raw_files is not Array:
		return
	var files: Array = raw_files as Array
	if files.is_empty():
		return
	var live_files: Array[Dictionary] = []
	var total_bytes: int = 0
	for raw_record: Variant in files:
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		if bool(record.get("stale_part", false)):
			_disk_delete_queue.append(record.duplicate(true))
			continue
		live_files.append(record)
		total_bytes += int(record.get("bytes", 0))
	if live_files.size() <= MAX_DISK_CACHE_FILES and total_bytes <= MAX_DISK_CACHE_BYTES:
		set_process(true)
		return
	live_files.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("modified", 0)) < int(right.get("modified", 0))
	)
	var remaining_files: int = live_files.size()
	for raw_record: Dictionary in live_files:
		if remaining_files <= MAX_DISK_CACHE_FILES and total_bytes <= MAX_DISK_CACHE_BYTES:
			break
		var record: Dictionary = raw_record.duplicate(true)
		_disk_delete_queue.append(record)
		remaining_files = maxi(0, remaining_files - 1)
		total_bytes = maxi(0, total_bytes - int(record.get("bytes", 0)))
	set_process(true)


func _drain_disk_delete_queue() -> void:
	if _disk_delete_queue.is_empty():
		return
	var protected_paths: Dictionary = _disk_cache_protected_paths()
	var deletions: int = 0
	var attempts: int = 0
	var maximum_attempts: int = _disk_delete_queue.size()
	while deletions < DISK_DELETIONS_PER_FRAME and not _disk_delete_queue.is_empty() and attempts < maximum_attempts:
		attempts += 1
		var record: Dictionary = _disk_delete_queue.pop_front()
		var path: String = str(record.get("path", "")).strip_edges()
		if path.is_empty():
			continue
		if protected_paths.has(_native_path(path)):
			_disk_delete_queue.append(record)
			continue
		_remove_cache_vector_and_empty_parents(path)
		deletions += 1


func _remove_cache_vector_and_empty_parents(path: String) -> void:
	var native: String = _native_path(path)
	_remove_file_if_exists(native)
	var document_directory: String = native.get_base_dir()
	var prefix_directory: String = document_directory.get_base_dir()
	var cache_root_native: String = ProjectSettings.globalize_path(CACHE_ROOT)
	DirAccess.remove_absolute(document_directory)
	if prefix_directory != cache_root_native:
		DirAccess.remove_absolute(prefix_directory)


func _disk_cache_protected_paths() -> Dictionary:
	var protected_paths: Dictionary = {}
	if not _active_job.is_empty():
		for field: String in ["svg_path", "generated_svg_path"]:
			var path: String = str(_active_job.get(field, "")).strip_edges()
			if not path.is_empty():
				protected_paths[_native_path(path)] = true
	for raw_loading: Variant in _loading_keys.values():
		if raw_loading is Dictionary:
			var path: String = str((raw_loading as Dictionary).get("path", "")).strip_edges()
			if not path.is_empty():
				protected_paths[_native_path(path)] = true
	for raw_request: Variant in _raster_requests.values():
		if raw_request is Dictionary:
			var path: String = str((raw_request as Dictionary).get("path", "")).strip_edges()
			if not path.is_empty():
				protected_paths[_native_path(path)] = true
	return protected_paths


func _cleanup_job(job: Dictionary) -> void:
	var path: String = str(job.get("temp_directory", ""))
	if path.is_empty():
		return
	_remove_tree(ProjectSettings.globalize_path(path))


func _remove_tree(directory_path: String) -> void:
	if not DirAccess.dir_exists_absolute(directory_path):
		return
	var parent: DirAccess = DirAccess.open(directory_path.get_base_dir())
	var entry_name: String = directory_path.get_file()
	if parent != null and not entry_name.is_empty() and parent.is_link(entry_name):
		DirAccess.remove_absolute(directory_path)
		return
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path: String = directory_path.path_join(entry)
			# Temporary formula cleanup may remove links, but must never follow them.
			if directory.is_link(entry):
				DirAccess.remove_absolute(path)
			elif directory.current_is_dir():
				_remove_tree(path)
			else:
				DirAccess.remove_absolute(path)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(directory_path)


func _write_text_file(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return true


func _svg_header_valid(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var amount: int = mini(4096, int(file.get_length()))
	var head: String = file.get_buffer(amount).get_string_from_utf8().to_lower()
	file.close()
	return head.find("<svg") >= 0


func _native_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path


func _file_size(path: String) -> int:
	var native: String = _native_path(path)
	var file: FileAccess = FileAccess.open(native, FileAccess.READ)
	if file == null:
		return -1
	var value: int = int(file.get_length())
	file.close()
	return value


func _remove_file_if_exists(path: String) -> void:
	var native: String = _native_path(path)
	if FileAccess.file_exists(native):
		DirAccess.remove_absolute(native)


func _small_sha256(value: String) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode().to_lower()


func _should_process() -> bool:
	return (
		_version_pending
		or not _active_job.is_empty()
		or not _queue.is_empty()
		or not _loading_keys.is_empty()
		or not _raster_requests.is_empty()
		or _cache_scan_worker.has_pending_work()
		or not _disk_delete_queue.is_empty()
		or (_ready_for_render and not _waiting_requests.is_empty())
	)
