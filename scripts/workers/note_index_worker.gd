# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteIndexWorker
extends RefCounted

# Reads immutable Markdown blobs away from the UI thread and extracts only the
# bounded derived data required by search/graph previews. The worker never owns
# canonical state and never mutates Library files.
const MAX_PENDING_JOBS: int = 8
const MAX_EXCERPT_CHARS: int = 640

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {}
var _cancelled_keys: Dictionary = {}
var _results: Array[Dictionary] = []


func start() -> bool:
	if _running:
		return true
	_running = true
	var start_error: Error = _thread.start(_thread_loop)
	if start_error != OK:
		_running = false
		return false
	return true


func stop() -> void:
	_mutex.lock()
	_running = false
	_queue.clear()
	_cancelled_keys.clear()
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()
	_mutex.lock()
	_queued_keys.clear()
	_results.clear()
	_mutex.unlock()


func request(
	job_key: String,
	note_id: String,
	path: String,
	expected_hash: String,
	expected_byte_size: int
) -> bool:
	var clean_key: String = job_key.strip_edges()
	var clean_id: String = note_id.strip_edges()
	var clean_path: String = path.strip_edges()
	if clean_key.is_empty() or clean_id.is_empty() or clean_path.is_empty():
		return false
	if expected_byte_size < 0 or expected_byte_size > AssetImportContentValidator.MAX_NOTE_BYTES:
		return false
	_mutex.lock()
	if not _running or _queued_keys.has(clean_key) or _queued_keys.size() + _results.size() >= MAX_PENDING_JOBS:
		_mutex.unlock()
		return false
	_queued_keys[clean_key] = true
	_cancelled_keys.erase(clean_key)
	_queue.append({
		"job_key": clean_key,
		"note_id": clean_id,
		"path": _native_path(clean_path),
		"expected_hash": expected_hash.strip_edges().to_lower(),
		"expected_byte_size": expected_byte_size,
	})
	_mutex.unlock()
	_semaphore.post()
	return true


func cancel(job_key: String) -> bool:
	var clean_key: String = job_key.strip_edges()
	if clean_key.is_empty():
		return false
	_mutex.lock()
	var pending: bool = _queued_keys.has(clean_key)
	if pending:
		_cancelled_keys[clean_key] = true
	_mutex.unlock()
	return pending


func poll_results(maximum_count: int = 4) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	_mutex.lock()
	var take_count: int = mini(maxi(1, maximum_count), _results.size())
	for _index: int in range(take_count):
		output.append(_results.pop_front())
	_mutex.unlock()
	return output


func pending_work_count() -> int:
	_mutex.lock()
	var count: int = _queued_keys.size() + _results.size()
	_mutex.unlock()
	return count


func _thread_loop() -> void:
	while true:
		_semaphore.wait()
		var job: Dictionary = {}
		_mutex.lock()
		if not _running:
			_mutex.unlock()
			break
		if not _queue.is_empty():
			job = _queue.pop_front()
		_mutex.unlock()
		if job.is_empty():
			continue
		var result: Dictionary = _index(job)
		var job_key: String = str(job.get("job_key", ""))
		_mutex.lock()
		_queued_keys.erase(job_key)
		_cancelled_keys.erase(job_key)
		if _running:
			_results.append(result)
		_mutex.unlock()


func _index(job: Dictionary) -> Dictionary:
	var job_key: String = str(job.get("job_key", ""))
	var note_id: String = str(job.get("note_id", ""))
	var path: String = str(job.get("path", ""))
	var expected_hash: String = str(job.get("expected_hash", ""))
	var expected_byte_size: int = int(job.get("expected_byte_size", -1))
	if _should_cancel(job_key):
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], "", true)
	if not FileAccess.file_exists(path):
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], NotLightL10n.text("runtime.worker.note_blob.missing"), false)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], NotLightL10n.text("runtime.worker.note_blob.open_failed"), false)
	var byte_size: int = int(file.get_length())
	if byte_size != expected_byte_size or byte_size < 0 or byte_size > AssetImportContentValidator.MAX_NOTE_BYTES:
		file.close()
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], NotLightL10n.text("runtime.worker.note_blob.size_mismatch"), false)
	var bytes: PackedByteArray = file.get_buffer(byte_size)
	file.close()
	if bytes.size() != byte_size or not AssetImportContentValidator._is_valid_utf8(bytes):
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], NotLightL10n.text("runtime.worker.note_blob.utf8_invalid"), false)
	for value: int in bytes:
		if value == 0:
			return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], NotLightL10n.text("runtime.worker.note_blob.nul_bytes"), false)
	var actual_hash: String = _sha256_hex(bytes)
	if actual_hash.is_empty() or actual_hash != expected_hash:
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], NotLightL10n.text("runtime.worker.note_blob.hash_mismatch"), false)
	if _should_cancel(job_key):
		return _result(job_key, note_id, expected_hash, PackedStringArray(), "", [], "", true)
	var content: String = bytes.get_string_from_utf8()
	if content.begins_with("\uFEFF"):
		content = content.substr(1)
	var targets: PackedStringArray = NoteLinkParser.extract_wikilink_targets(content)
	var embed_hashes: PackedStringArray = NoteResourceEmbed.extract_hashes(content)
	var excerpt: String = _make_excerpt(content)
	var board_preview: Array[Dictionary] = NoteBoardPreviewExtractor.extract(content)
	var indexed: Dictionary = _result(job_key, note_id, expected_hash, targets, excerpt, board_preview, "", false)
	indexed["embed_hashes"] = embed_hashes
	return indexed


func _make_excerpt(content: String) -> String:
	var output: PackedStringArray = PackedStringArray()
	var in_fence: bool = false
	var in_frontmatter: bool = false
	var line_index: int = 0
	for line: String in content.split("\n", false):
		var clean: String = line.strip_edges()
		if line_index == 0 and clean == "---":
			in_frontmatter = true
			line_index += 1
			continue
		if in_frontmatter:
			if clean == "---":
				in_frontmatter = false
			line_index += 1
			continue
		if clean.begins_with("```") or clean.begins_with("~~~"):
			in_fence = not in_fence
			line_index += 1
			continue
		if in_fence or clean.is_empty():
			line_index += 1
			continue
		while clean.begins_with("#") or clean.begins_with(">"):
			clean = clean.substr(1).strip_edges()
		if clean.begins_with("- [ ] ") or clean.begins_with("- [x] ") or clean.begins_with("- [X] "):
			clean = clean.substr(6).strip_edges()
		elif clean.begins_with("- ") or clean.begins_with("* ") or clean.begins_with("+ "):
			clean = clean.substr(2).strip_edges()
		clean = NoteInlineMarkup.strip_markup(clean)
		if not clean.is_empty():
			output.append(clean)
		if " ".join(output).length() >= MAX_EXCERPT_CHARS:
			break
		line_index += 1
	return " ".join(output).strip_edges().left(MAX_EXCERPT_CHARS)


func _should_cancel(job_key: String) -> bool:
	_mutex.lock()
	var cancelled: bool = not _running or _cancelled_keys.has(job_key)
	_mutex.unlock()
	return cancelled


func _result(
	job_key: String,
	note_id: String,
	hash_sha256: String,
	targets: PackedStringArray,
	excerpt: String,
	board_preview: Array[Dictionary],
	error: String,
	cancelled: bool
) -> Dictionary:
	return {
		"job_key": job_key,
		"note_id": note_id,
		"hash_sha256": hash_sha256,
		"targets": targets,
		"excerpt": excerpt,
		"board_preview": board_preview,
		"error": error,
		"cancelled": cancelled,
	}


func _sha256_hex(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if not bytes.is_empty() and context.update(bytes) != OK:
		return ""
	var digest: PackedByteArray = context.finish()
	return digest.hex_encode().to_lower() if digest.size() == 32 else ""


func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
