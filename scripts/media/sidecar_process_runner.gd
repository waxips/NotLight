# SPDX-License-Identifier: GPL-3.0-or-later
class_name SidecarProcessRunner
extends RefCounted

const DEFAULT_OUTPUT_LIMIT_BYTES: int = 64 * 1024
const MAX_DRAIN_BYTES_PER_POLL: int = 256 * 1024
const PIPE_CHUNK_BYTES: int = 16 * 1024

var _pid: int = -1
var _stdio: FileAccess
var _stderr: FileAccess
var _stdout_capture: PackedByteArray = PackedByteArray()
var _stderr_capture: PackedByteArray = PackedByteArray()
var _output_limit_bytes: int = DEFAULT_OUTPUT_LIMIT_BYTES
var _started_msec: int = 0
var _timeout_msec: int = 0
var _cancel_requested: bool = false
var _timed_out: bool = false
var _finished: bool = false
var _exit_code: int = -1


func start(
	executable: String,
	arguments: PackedStringArray,
	timeout_msec: int,
	output_limit_bytes: int = DEFAULT_OUTPUT_LIMIT_BYTES
) -> bool:
	close()
	var clean_executable: String = executable.strip_edges()
	if clean_executable.is_empty():
		return false
	var process: Dictionary = OS.execute_with_pipe(clean_executable, arguments, false)
	if process.is_empty():
		return false
	var stdio_value: Variant = process.get("stdio")
	var stderr_value: Variant = process.get("stderr")
	_stdio = stdio_value as FileAccess if stdio_value is FileAccess else null
	_stderr = stderr_value as FileAccess if stderr_value is FileAccess else null
	_pid = int(process.get("pid", -1))
	if _pid <= 0 or _stdio == null or _stderr == null:
		if _pid > 0 and OS.is_process_running(_pid):
			OS.kill(_pid)
		close()
		return false
	_output_limit_bytes = maxi(1024, output_limit_bytes)
	_timeout_msec = maxi(1000, timeout_msec)
	_started_msec = Time.get_ticks_msec()
	_cancel_requested = false
	_timed_out = false
	_finished = false
	_exit_code = -1
	return true


func poll() -> Dictionary:
	if _pid <= 0:
		return {"finished": _finished, "exit_code": _exit_code}
	# Godot 4.4.1 implements pipe get_length() with PeekNamedPipe() on Windows.
	# A child can close its write end between an is_process_running() check and
	# PeekNamedPipe(), producing noisy debugger errors during normal completion.
	# All draining therefore uses bounded non-blocking get_buffer() reads instead.
	var process_running: bool = OS.is_process_running(_pid)
	if process_running:
		_drain_available()
	if not _finished and not _cancel_requested and Time.get_ticks_msec() - _started_msec >= _timeout_msec:
		_timed_out = true
		_cancel_requested = true
	# A kill request can fail transiently. Retry while polling rather than leaving
	# a cancelled/expired sidecar alive forever after one failed attempt.
	if not _finished and _cancel_requested and process_running:
		OS.kill(_pid)
	process_running = OS.is_process_running(_pid)
	if not _finished and not process_running:
		_drain_after_exit()
		_exit_code = OS.get_process_exit_code(_pid)
		_finished = true
		_close_pipes()
	if not _finished:
		return {"finished": false}
	return {
		"finished": true,
		"exit_code": _exit_code,
		"stdout": _decode_text_capture(_stdout_capture),
		"stderr": _decode_text_capture(_stderr_capture),
		"cancelled": _cancel_requested and not _timed_out,
		"timed_out": _timed_out,
	}


func _decode_text_capture(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return ""
	# Windows PowerShell 5.x may write redirected stdout/stderr as UTF-16LE.
	# Detect that encoding before removing stray NUL bytes: removing UTF-16 zero
	# bytes first would silently corrupt non-ASCII output. Sidecar stdout/stderr is
	# textual by contract; an isolated U+0000 has no useful diagnostic meaning and
	# is discarded from the UTF-8 path instead of reaching Godot's String decoder.
	if _looks_like_utf16(bytes):
		return bytes.get_string_from_utf16()
	var clean_bytes: PackedByteArray = _without_nul_bytes(bytes)
	return clean_bytes.get_string_from_utf8()


func _without_nul_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var nul_count: int = 0
	for byte_value: int in bytes:
		if byte_value == 0:
			nul_count += 1
	if nul_count == 0:
		return bytes
	var clean: PackedByteArray = PackedByteArray()
	clean.resize(bytes.size() - nul_count)
	var write_index: int = 0
	for byte_value: int in bytes:
		if byte_value == 0:
			continue
		clean[write_index] = byte_value
		write_index += 1
	return clean


func _looks_like_utf16(bytes: PackedByteArray) -> bool:
	if bytes.size() >= 2:
		if (bytes[0] == 0xFF and bytes[1] == 0xFE) or (bytes[0] == 0xFE and bytes[1] == 0xFF):
			return true
	var sample_size: int = mini(bytes.size(), 512)
	if sample_size < 8:
		return false
	var even_zeroes: int = 0
	var odd_zeroes: int = 0
	var even_slots: int = 0
	var odd_slots: int = 0
	for index: int in range(sample_size):
		if index % 2 == 0:
			even_slots += 1
			if bytes[index] == 0:
				even_zeroes += 1
		else:
			odd_slots += 1
			if bytes[index] == 0:
				odd_zeroes += 1
	var even_ratio: float = float(even_zeroes) / float(maxi(1, even_slots))
	var odd_ratio: float = float(odd_zeroes) / float(maxi(1, odd_slots))
	return (odd_ratio >= 0.35 and even_ratio <= 0.08) or (even_ratio >= 0.35 and odd_ratio <= 0.08)


func cancel() -> void:
	if _pid <= 0 or _finished:
		return
	_cancel_requested = true
	if OS.is_process_running(_pid):
		OS.kill(_pid)


func is_running() -> bool:
	return _pid > 0 and not _finished and OS.is_process_running(_pid)


func process_id() -> int:
	return _pid


func close() -> void:
	if _pid > 0 and not _finished and OS.is_process_running(_pid):
		OS.kill(_pid)
	_close_pipes()
	_pid = -1
	_stdout_capture = PackedByteArray()
	_stderr_capture = PackedByteArray()
	_started_msec = 0
	_timeout_msec = 0
	_cancel_requested = false
	_timed_out = false
	_finished = false
	_exit_code = -1


func _drain_available() -> void:
	# execute_with_pipe(..., false) gives non-blocking pipes. On Windows Godot
	# 4.4.1 maps get_length() to PeekNamedPipe(), which can emit debugger errors
	# when the child closes the remote handle between polling operations. Read a
	# bounded chunk directly instead: the Windows pipe backend uses non-blocking
	# ReadFile() and returns the number of bytes actually read.
	# Split the budget so noisy stdout can never starve stderr and deadlock a child.
	var per_pipe_budget: int = MAX_DRAIN_BYTES_PER_POLL / 2
	_drain_pipe(_stdio, _stdout_capture, per_pipe_budget, true)
	_drain_pipe(_stderr, _stderr_capture, per_pipe_budget, false)


func _drain_after_exit() -> void:
	# Do not call get_length() here: the Windows 4.4.1 backend maps it to
	# PeekNamedPipe(), which reports a debugger error after the remote handle is
	# closed. A bounded direct read safely consumes any bytes already buffered.
	var per_pipe_budget: int = MAX_DRAIN_BYTES_PER_POLL / 2
	_drain_pipe_after_exit(_stdio, _stdout_capture, per_pipe_budget, true)
	_drain_pipe_after_exit(_stderr, _stderr_capture, per_pipe_budget, false)


func _drain_pipe(pipe: FileAccess, capture: PackedByteArray, budget: int, is_stdout: bool) -> void:
	if pipe == null or not pipe.is_open() or budget <= 0:
		return
	var remaining_budget: int = budget
	while remaining_budget > 0:
		var read_size: int = mini(PIPE_CHUNK_BYTES, remaining_budget)
		var chunk: PackedByteArray = pipe.get_buffer(read_size)
		if chunk.is_empty():
			break
		capture = _append_capped(capture, chunk)
		remaining_budget -= chunk.size()
		if is_stdout:
			_stdout_capture = capture
		else:
			_stderr_capture = capture
		# Non-blocking Windows pipes report a short read as ERR_FILE_CANT_READ,
		# even though the returned bytes are valid. Keep those bytes and stop this
		# poll; the next poll will continue when more output arrives.
		if chunk.size() < read_size or pipe.get_error() != OK:
			break


func _drain_pipe_after_exit(pipe: FileAccess, capture: PackedByteArray, budget: int, is_stdout: bool) -> void:
	if pipe == null or not pipe.is_open() or budget <= 0:
		return
	var remaining_budget: int = budget
	while remaining_budget > 0:
		var read_size: int = mini(PIPE_CHUNK_BYTES, remaining_budget)
		var chunk: PackedByteArray = pipe.get_buffer(read_size)
		if chunk.is_empty():
			break
		capture = _append_capped(capture, chunk)
		remaining_budget -= chunk.size()
		if is_stdout:
			_stdout_capture = capture
		else:
			_stderr_capture = capture
		# A short read is the normal terminal condition once the writer is gone.
		if chunk.size() < read_size:
			break


func _append_capped(target: PackedByteArray, chunk: PackedByteArray) -> PackedByteArray:
	if target.size() >= _output_limit_bytes or chunk.is_empty():
		return target
	var writable: int = mini(chunk.size(), _output_limit_bytes - target.size())
	target.append_array(chunk.slice(0, writable))
	return target


func _close_pipes() -> void:
	if _stdio != null:
		_stdio.close()
	if _stderr != null:
		_stderr.close()
	_stdio = null
	_stderr = null
