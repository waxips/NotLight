# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaCacheScanWorker
extends RefCounted

# Disk-cache metadata traversal can involve hundreds of filesystem stats. Keep it
# off the scene-tree thread; deletion itself is deliberately returned to the
# service and performed in a tiny per-frame budget so files currently entering a
# raster job can be re-checked before removal.
const MAX_SCAN_FILES_HARD_LIMIT: int = 4096
const MAX_SCAN_DIRECTORIES_HARD_LIMIT: int = 8192

var _thread: Thread = Thread.new()
var _mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _running: bool = false
var _working: bool = false
var _request: Dictionary = {}
var _result: Dictionary = {}


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
	_working = false
	_request.clear()
	_result.clear()
	_mutex.unlock()
	_semaphore.post()
	if _thread.is_started():
		_thread.wait_to_finish()


func request_scan(cache_root: String, maximum_files: int) -> bool:
	var clean_root: String = cache_root.strip_edges()
	if clean_root.is_empty():
		return false
	_mutex.lock()
	if not _running or _working or not _request.is_empty() or not _result.is_empty():
		_mutex.unlock()
		return false
	_request = {
		"cache_root": clean_root,
		"maximum_files": clampi(maximum_files, 1, MAX_SCAN_FILES_HARD_LIMIT),
	}
	_mutex.unlock()
	_semaphore.post()
	return true


func poll_result() -> Dictionary:
	_mutex.lock()
	var output: Dictionary = _result
	_result = {}
	_mutex.unlock()
	return output


func has_pending_work() -> bool:
	_mutex.lock()
	var pending: bool = _working or not _request.is_empty() or not _result.is_empty()
	_mutex.unlock()
	return pending


func _thread_loop() -> void:
	while true:
		_semaphore.wait()
		var request: Dictionary = {}
		_mutex.lock()
		if not _running:
			_mutex.unlock()
			break
		if not _request.is_empty():
			request = _request
			_request = {}
			_working = true
		_mutex.unlock()
		if request.is_empty():
			continue
		var result: Dictionary = _scan(request)
		_mutex.lock()
		_working = false
		if _running:
			_result = result
		_mutex.unlock()


func _scan(request: Dictionary) -> Dictionary:
	var root: String = str(request.get("cache_root", ""))
	var maximum_files: int = int(request.get("maximum_files", MAX_SCAN_FILES_HARD_LIMIT))
	var files: Array[Dictionary] = []
	var state: Dictionary = {"directories": 0}
	_collect(root, files, maximum_files, state)
	return {"files": files, "directories_scanned": int(state.get("directories", 0))}


func _collect(directory_path: String, output: Array[Dictionary], maximum_files: int, state: Dictionary) -> void:
	if output.size() >= maximum_files or int(state.get("directories", 0)) >= MAX_SCAN_DIRECTORIES_HARD_LIMIT or not DirAccess.dir_exists_absolute(directory_path):
		return
	state["directories"] = int(state.get("directories", 0)) + 1
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return
	var child_directories: PackedStringArray = PackedStringArray()
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty() and output.size() < maximum_files:
		if entry != "." and entry != "..":
			var path: String = directory_path.path_join(entry)
			if directory.current_is_dir():
				if entry != ".jobs":
					child_directories.append(path)
			elif entry == "formula.svg" or entry == "formula.svg.part":
				var file: FileAccess = FileAccess.open(path, FileAccess.READ)
				if file != null:
					var size_bytes: int = maxi(0, int(file.get_length()))
					file.close()
					output.append({
						"path": path,
						"bytes": size_bytes,
						"modified": int(FileAccess.get_modified_time(path)),
						"stale_part": entry.ends_with(".part"),
					})
		entry = directory.get_next()
	directory.list_dir_end()
	child_directories.sort()
	for child: String in child_directories:
		if output.size() >= maximum_files or int(state.get("directories", 0)) >= MAX_SCAN_DIRECTORIES_HARD_LIMIT:
			break
		_collect(child, output, maximum_files, state)
