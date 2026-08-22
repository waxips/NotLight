# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportContentValidator
extends RefCounted

const PREFIX_BYTES: int = 64 * 1024
const MAX_SVG_BYTES: int = 32 * 1024 * 1024
const PROBE_TIMEOUT_MSEC: int = 12 * 1000
const PROBE_OUTPUT_LIMIT_BYTES: int = 192 * 1024
const POLL_DELAY_MSEC: int = 8
const MAX_NOTE_BYTES: int = 8 * 1024 * 1024

const PNG_SIGNATURE: Array[int] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
const EXR_SIGNATURE: Array[int] = [0x76, 0x2F, 0x31, 0x01]
const KTX1_SIGNATURE: Array[int] = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]
const KTX2_SIGNATURE: Array[int] = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]


static func validate(
	source_path: String,
	expected_kind: int = AssetKinds.ANY,
	extension_override: String = "",
	cancel_check: Callable = Callable()
) -> Dictionary:
	var clean_path: String = source_path.strip_edges()
	var filename: String = clean_path.get_file()
	var extension: String = extension_override.strip_edges().trim_prefix(".").to_lower()
	if extension.is_empty():
		extension = filename.get_extension().to_lower()
	var kind: int = expected_kind
	var base: Dictionary = {
		"source_path": source_path,
		"filename": filename,
		"extension": extension,
		"expected_kind": kind,
		"detected_kind": AssetKinds.OTHER,
		"byte_size": 0,
		"valid": false,
		"rejection_code": ImportCandidateResult.REJECTION_NONE,
		"technical_detail": "",
		"metadata_preview": {},
	}
	if _is_cancelled(cancel_check):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	if clean_path.is_empty() or not FileAccess.file_exists(clean_path):
		return _reject(base, ImportCandidateResult.REJECTION_MISSING)
	if kind != AssetKinds.IMAGE and kind != AssetKinds.VIDEO and kind != AssetKinds.AUDIO and kind != AssetKinds.PDF and kind != AssetKinds.NOTE:
		return _reject(base, ImportCandidateResult.REJECTION_UNSUPPORTED_EXTENSION)

	var file: FileAccess = FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		return _reject(base, ImportCandidateResult.REJECTION_MISSING)
	var byte_size: int = int(file.get_length())
	base["byte_size"] = byte_size
	if byte_size <= 0 and kind != AssetKinds.NOTE:
		file.close()
		return _reject(base, ImportCandidateResult.REJECTION_EMPTY)
	var prefix: PackedByteArray = file.get_buffer(mini(PREFIX_BYTES, byte_size))
	file.close()
	if prefix.is_empty() and kind != AssetKinds.NOTE:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	if _is_cancelled(cancel_check):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)

	var result: Dictionary = {}
	match kind:
		AssetKinds.IMAGE:
			result = _validate_image(clean_path, extension, prefix, base, cancel_check)
		AssetKinds.PDF:
			result = _validate_pdf(clean_path, prefix, base, cancel_check)
		AssetKinds.VIDEO:
			result = _validate_av(clean_path, true, base, cancel_check)
		AssetKinds.AUDIO:
			result = _validate_audio(clean_path, extension, prefix, base, cancel_check)
		AssetKinds.NOTE:
			result = _validate_note(clean_path, base, cancel_check)
		_:
			result = _reject(base, ImportCandidateResult.REJECTION_UNSUPPORTED_EXTENSION)
	return result


static func _validate_note(path: String, base: Dictionary, cancel_check: Callable) -> Dictionary:
	if _is_cancelled(cancel_check):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _reject(base, ImportCandidateResult.REJECTION_MISSING)
	var byte_size: int = int(file.get_length())
	if byte_size < 0:
		file.close()
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	if byte_size > MAX_NOTE_BYTES:
		file.close()
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT, NotLightL10n.text("runtime.assets.import.markdown_too_large"))
	var bytes: PackedByteArray = file.get_buffer(byte_size)
	file.close()
	if bytes.size() != byte_size:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT, NotLightL10n.text("runtime.assets.import.markdown_read_incomplete"))
	if not _is_valid_utf8(bytes):
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT, NotLightL10n.text("runtime.assets.import.markdown_utf8_invalid"))
	for value: int in bytes:
		if value == 0:
			return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT, NotLightL10n.text("runtime.assets.import.markdown_nul"))
	if _is_cancelled(cancel_check):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	var text: String = bytes.get_string_from_utf8()
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	var line_count: int = 1
	for character: String in text:
		if character == "\n":
			line_count += 1
	var result: Dictionary = base.duplicate(true)
	result["detected_kind"] = AssetKinds.NOTE
	result["valid"] = true
	result["metadata_preview"] = {
		"line_count": line_count,
		"character_count": text.length(),
	}
	return result


static func _is_valid_utf8(bytes: PackedByteArray) -> bool:
	var index: int = 0
	while index < bytes.size():
		var first: int = int(bytes[index])
		if first <= 0x7F:
			index += 1
			continue
		var needed: int = 0
		var codepoint: int = 0
		var minimum: int = 0
		if first >= 0xC2 and first <= 0xDF:
			needed = 1
			codepoint = first & 0x1F
			minimum = 0x80
		elif first >= 0xE0 and first <= 0xEF:
			needed = 2
			codepoint = first & 0x0F
			minimum = 0x800
		elif first >= 0xF0 and first <= 0xF4:
			needed = 3
			codepoint = first & 0x07
			minimum = 0x10000
		else:
			return false
		if index + needed >= bytes.size():
			return false
		for offset: int in range(1, needed + 1):
			var continuation: int = int(bytes[index + offset])
			if continuation < 0x80 or continuation > 0xBF:
				return false
			codepoint = (codepoint << 6) | (continuation & 0x3F)
		if codepoint < minimum or codepoint > 0x10FFFF:
			return false
		if codepoint >= 0xD800 and codepoint <= 0xDFFF:
			return false
		index += needed + 1
	return true


static func rejection(
	source_path: String,
	filename: String,
	extension: String,
	expected_kind: int,
	code: String,
	detail: String = ""
) -> Dictionary:
	return _reject({
		"source_path": source_path,
		"filename": filename,
		"extension": extension,
		"expected_kind": expected_kind,
		"detected_kind": AssetKinds.OTHER,
		"byte_size": 0,
		"valid": false,
		"rejection_code": ImportCandidateResult.REJECTION_NONE,
		"technical_detail": "",
		"metadata_preview": {},
	}, code, detail)


static func _validate_image(
	path: String,
	extension: String,
	prefix: PackedByteArray,
	base: Dictionary,
	cancel_check: Callable
) -> Dictionary:
	var valid_signature: bool = false
	if extension == "png":
		valid_signature = _starts_with(prefix, PNG_SIGNATURE)
	elif extension == "jpg" or extension == "jpeg":
		valid_signature = prefix.size() >= 3 and prefix[0] == 0xFF and prefix[1] == 0xD8 and prefix[2] == 0xFF
	elif extension == "webp":
		valid_signature = _ascii_at(prefix, 0, "RIFF") and _ascii_at(prefix, 8, "WEBP")
	elif extension == "bmp":
		valid_signature = _ascii_at(prefix, 0, "BM")
	elif extension == "svg":
		return _validate_svg(path, prefix, base, cancel_check)
	elif extension == "tga":
		valid_signature = _looks_like_tga(prefix)
	elif extension == "exr":
		valid_signature = _starts_with(prefix, EXR_SIGNATURE)
	elif extension == "hdr":
		valid_signature = _ascii_at(prefix, 0, "#?RADIANCE") or _ascii_at(prefix, 0, "#?RGBE")
	elif extension == "ktx":
		valid_signature = _starts_with(prefix, KTX1_SIGNATURE) or _starts_with(prefix, KTX2_SIGNATURE)
	if not valid_signature:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	return _accept(base, AssetKinds.IMAGE, {})


static func _validate_svg(
	path: String,
	prefix: PackedByteArray,
	base: Dictionary,
	cancel_check: Callable
) -> Dictionary:
	var prefix_text: String = prefix.get_string_from_utf8().strip_edges()
	var prefix_lowered: String = prefix_text.to_lower()
	var svg_index: int = prefix_lowered.find("<svg")
	if svg_index < 0 or svg_index > 4096:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	var byte_size: int = int(base.get("byte_size", 0))
	if byte_size > MAX_SVG_BYTES:
		return _reject(base, ImportCandidateResult.REJECTION_SVG_TOO_LARGE)
	if _is_cancelled(cancel_check):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)

	# SVG is untrusted text. Scan the whole bounded document, not just the
	# signature prefix: active content may legally appear near the end of a file.
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _reject(base, ImportCandidateResult.REJECTION_MISSING)
	var svg_bytes: PackedByteArray = file.get_buffer(byte_size)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or svg_bytes.size() != byte_size:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	if _is_cancelled(cancel_check):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	var lowered: String = svg_bytes.get_string_from_utf8().to_lower()
	# Godot's SVG loader does not require scripts or external network/file
	# references for NotLight board images. Reject those capabilities rather than
	# allowing a local document to reach outward. The canonical SVG namespace
	# itself uses http:// and therefore must not be rejected generically.
	var compact: String = lowered.replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "")
	for marker: String in [
		"<script", "javascript:", "file://", "@import", "<!doctype", "<!entity",
		"<foreignobject", "<iframe", "<object", "<embed",
		"onload=", "onerror=", "onclick=", "onbegin=", "onend=", "onrepeat=",
	]:
		if compact.find(marker) >= 0:
			return _reject(base, ImportCandidateResult.REJECTION_UNSAFE_SVG)
	if _svg_has_external_href(compact) or _svg_has_external_url(compact):
		return _reject(base, ImportCandidateResult.REJECTION_UNSAFE_SVG)
	return _accept(base, AssetKinds.IMAGE, {})


static func _svg_has_external_href(compact: String) -> bool:
	var search_from: int = 0
	while search_from < compact.length():
		var index: int = compact.find("href=", search_from)
		if index < 0:
			return false
		var value_start: int = index + 5
		if value_start >= compact.length():
			return true
		var quote: String = compact.substr(value_start, 1)
		if quote != "\"" and quote != "'":
			return true
		var end_index: int = compact.find(quote, value_start + 1)
		if end_index < 0:
			return true
		var value: String = compact.substr(value_start + 1, end_index - value_start - 1)
		if not _svg_reference_is_local_and_safe(value):
			return true
		search_from = end_index + 1
	return false


static func _svg_has_external_url(compact: String) -> bool:
	var search_from: int = 0
	while search_from < compact.length():
		var index: int = compact.find("url(", search_from)
		if index < 0:
			return false
		var value_start: int = index + 4
		var end_index: int = compact.find(")", value_start)
		if end_index < 0:
			return true
		var value: String = compact.substr(value_start, end_index - value_start).strip_edges()
		if (value.begins_with("\"") and value.ends_with("\"")) or (value.begins_with("'") and value.ends_with("'")):
			value = value.substr(1, value.length() - 2)
		if not _svg_reference_is_local_and_safe(value):
			return true
		search_from = end_index + 1
	return false


static func _svg_reference_is_local_and_safe(value: String) -> bool:
	var clean: String = value.strip_edges().to_lower()
	if clean.begins_with("#"):
		return true
	# Do not treat arbitrary data: payloads as safe merely because they are local.
	# Nested SVG/HTML/XML payloads can carry active content. Keep only raster image
	# data URIs required by the image workflow; all other schemes/relative paths are
	# rejected by the same boundary as network/file references.
	for prefix: String in [
		"data:image/png;base64,",
		"data:image/jpeg;base64,",
		"data:image/webp;base64,",
	]:
		if clean.begins_with(prefix):
			return true
	return false


static func _validate_pdf(
	path: String,
	prefix: PackedByteArray,
	base: Dictionary,
	cancel_check: Callable
) -> Dictionary:
	var header_text: String = prefix.slice(0, mini(1024, prefix.size())).get_string_from_ascii()
	if header_text.find("%PDF-") < 0:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	var process: Dictionary = _execute_bounded(
		PopplerTools.pdfinfo_path(),
		PackedStringArray([_native_path(path)]),
		cancel_check
	)
	if bool(process.get("cancelled", false)):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	if not bool(process.get("started", false)):
		return _reject(base, ImportCandidateResult.REJECTION_PROBE_UNAVAILABLE)
	var code: int = int(process.get("exit_code", -1))
	var stdout_text: String = str(process.get("stdout", ""))
	var stderr_text: String = str(process.get("stderr", ""))
	var diagnostics: String = (stdout_text + "\n" + stderr_text).strip_edges()
	if code != 0:
		var lower_output: String = diagnostics.to_lower()
		if lower_output.find("password") >= 0 or lower_output.find("encrypted") >= 0:
			return _reject(base, ImportCandidateResult.REJECTION_ENCRYPTED_PDF, diagnostics)
		return _reject(base, ImportCandidateResult.REJECTION_PROBE_FAILED, diagnostics)
	var parsed: Dictionary = PdfDocumentProbe.parse_pdfinfo(stdout_text, PopplerTools.version_line())
	if not bool(parsed.get("ok", false)):
		return _reject(base, ImportCandidateResult.REJECTION_PROBE_FAILED, str(parsed.get("error", "")))
	if bool(parsed.get("encrypted", false)):
		return _reject(base, ImportCandidateResult.REJECTION_ENCRYPTED_PDF)
	var metadata: Dictionary = {
		"page_count": int(parsed.get("page_count", 0)),
		"page_width_points": float(parsed.get("page_width_points", 0.0)),
		"page_height_points": float(parsed.get("page_height_points", 0.0)),
		"poppler_version": str(parsed.get("poppler_version", "")),
	}
	return _accept(base, AssetKinds.PDF, metadata)


static func _validate_audio(
	path: String,
	extension: String,
	prefix: PackedByteArray,
	base: Dictionary,
	cancel_check: Callable
) -> Dictionary:
	var strong_signature: bool = false
	if extension == "wav":
		strong_signature = _ascii_at(prefix, 0, "RIFF") and _ascii_at(prefix, 8, "WAVE")
	elif extension == "flac":
		strong_signature = _ascii_at(prefix, 0, "fLaC")
	elif extension == "mp3":
		strong_signature = _ascii_at(prefix, 0, "ID3") or _looks_like_mpeg_audio(prefix)
	elif extension == "aac":
		strong_signature = _looks_like_aac_adts(prefix)
	elif extension == "opus":
		strong_signature = _ascii_at(prefix, 0, "OggS") and _contains_ascii(prefix, "OpusHead")
	elif extension == "ogg":
		strong_signature = _ascii_at(prefix, 0, "OggS") and (
			_contains_ascii(prefix, "vorbis") or _contains_ascii(prefix, "OpusHead") or _contains_ascii(prefix, "Speex")
		)
	elif extension == "m4a":
		strong_signature = _looks_like_iso_base_media(prefix)
	if not strong_signature:
		return _reject(base, ImportCandidateResult.REJECTION_INVALID_CONTENT)
	# Container-ish audio is additionally probed to ensure a renamed video is not
	# accepted as an audio asset. For simple elementary formats, a missing ffprobe
	# does not invalidate the strong signature; NotLight still remains usable when
	# an optional media backend is absent.
	var probe_required: bool = ["m4a", "ogg", "opus", "mp3", "aac"].has(extension)
	var probe: Dictionary = _probe_av(path, cancel_check)
	if bool(probe.get("cancelled", false)):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	if not bool(probe.get("started", false)):
		if probe_required:
			return _reject(base, ImportCandidateResult.REJECTION_PROBE_UNAVAILABLE)
		return _accept(base, AssetKinds.AUDIO, {"probe_available": false})
	if not bool(probe.get("ok", false)):
		return _reject(base, ImportCandidateResult.REJECTION_PROBE_FAILED, str(probe.get("technical_detail", "")))
	if str(probe.get("audio_codec", "")).is_empty():
		return _reject(base, ImportCandidateResult.REJECTION_KIND_MISMATCH)
	if (extension == "m4a" or extension == "ogg") and not str(probe.get("video_codec", "")).is_empty():
		return _reject(base, ImportCandidateResult.REJECTION_KIND_MISMATCH)
	return _accept(base, AssetKinds.AUDIO, _probe_metadata(probe))


static func _validate_av(
	path: String,
	require_video: bool,
	base: Dictionary,
	cancel_check: Callable
) -> Dictionary:
	var probe: Dictionary = _probe_av(path, cancel_check)
	if bool(probe.get("cancelled", false)):
		return _reject(base, ImportCandidateResult.REJECTION_CANCELLED)
	if not bool(probe.get("started", false)):
		return _reject(base, ImportCandidateResult.REJECTION_PROBE_UNAVAILABLE)
	if not bool(probe.get("ok", false)):
		return _reject(base, ImportCandidateResult.REJECTION_PROBE_FAILED, str(probe.get("technical_detail", "")))
	if require_video and str(probe.get("video_codec", "")).is_empty():
		return _reject(base, ImportCandidateResult.REJECTION_KIND_MISMATCH)
	return _accept(base, AssetKinds.VIDEO if require_video else AssetKinds.AUDIO, _probe_metadata(probe))


static func _probe_av(path: String, cancel_check: Callable) -> Dictionary:
	var arguments: PackedStringArray = PackedStringArray([
		"-v", "error",
		"-show_entries",
		"format=duration,size,bit_rate,format_name:stream=index,codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,sample_rate,channels,pix_fmt:stream_disposition=attached_pic",
		"-of", "json",
		_native_path(path),
	])
	var process: Dictionary = _execute_bounded(FFmpegTools.ffprobe_path(), arguments, cancel_check)
	if bool(process.get("cancelled", false)):
		return {"cancelled": true, "started": bool(process.get("started", false))}
	if not bool(process.get("started", false)):
		return {"ok": false, "started": false}
	if int(process.get("exit_code", -1)) != 0:
		return {
			"ok": false,
			"started": true,
			"technical_detail": str(process.get("stderr", "")),
		}
	var parsed: Variant = JSON.parse_string(str(process.get("stdout", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "started": true, "technical_detail": NotLightL10n.text("runtime.assets.import.ffprobe_json_invalid")}
	var root: Dictionary = parsed as Dictionary
	var result: Dictionary = {
		"ok": true,
		"started": true,
		"duration": 0.0,
		"size": 0,
		"bitrate": 0,
		"format": "",
		"video_codec": "",
		"audio_codec": "",
		"width": 0,
		"height": 0,
		"fps": 0.0,
		"sample_rate": 0,
		"channels": 0,
	}
	var format_value: Variant = root.get("format", {})
	if format_value is Dictionary:
		var format_data: Dictionary = format_value as Dictionary
		result["duration"] = float(format_data.get("duration", 0.0))
		result["size"] = int(format_data.get("size", 0))
		result["bitrate"] = int(format_data.get("bit_rate", 0))
		result["format"] = str(format_data.get("format_name", ""))
	var streams_value: Variant = root.get("streams", [])
	if streams_value is Array:
		for stream_value: Variant in streams_value as Array:
			if stream_value is not Dictionary:
				continue
			var stream: Dictionary = stream_value as Dictionary
			var codec_type: String = str(stream.get("codec_type", ""))
			var disposition_value: Variant = stream.get("disposition", {})
			var attached_picture: bool = false
			if disposition_value is Dictionary:
				attached_picture = int((disposition_value as Dictionary).get("attached_pic", 0)) != 0
			if codec_type == "video" and not attached_picture and str(result.get("video_codec", "")).is_empty():
				result["video_codec"] = str(stream.get("codec_name", ""))
				result["width"] = int(stream.get("width", 0))
				result["height"] = int(stream.get("height", 0))
				result["fps"] = _parse_fraction(str(stream.get("avg_frame_rate", stream.get("r_frame_rate", "0/1"))))
			elif codec_type == "audio" and str(result.get("audio_codec", "")).is_empty():
				result["audio_codec"] = str(stream.get("codec_name", ""))
				result["sample_rate"] = int(stream.get("sample_rate", 0))
				result["channels"] = int(stream.get("channels", 0))
	return result


static func _probe_metadata(probe: Dictionary) -> Dictionary:
	return {
		"duration": float(probe.get("duration", 0.0)),
		"format": str(probe.get("format", "")),
		"video_codec": str(probe.get("video_codec", "")),
		"audio_codec": str(probe.get("audio_codec", "")),
		"width": int(probe.get("width", 0)),
		"height": int(probe.get("height", 0)),
		"fps": float(probe.get("fps", 0.0)),
		"sample_rate": int(probe.get("sample_rate", 0)),
		"channels": int(probe.get("channels", 0)),
	}


static func _execute_bounded(executable: String, arguments: PackedStringArray, cancel_check: Callable) -> Dictionary:
	var runner: SidecarProcessRunner = SidecarProcessRunner.new()
	if not runner.start(executable, arguments, PROBE_TIMEOUT_MSEC, PROBE_OUTPUT_LIMIT_BYTES):
		return {"started": false, "exit_code": -1, "stdout": "", "stderr": ""}
	while true:
		if _is_cancelled(cancel_check):
			runner.cancel()
		var state: Dictionary = runner.poll()
		if bool(state.get("finished", false)):
			var result: Dictionary = {
				"started": true,
				"exit_code": int(state.get("exit_code", -1)),
				"stdout": str(state.get("stdout", "")),
				"stderr": str(state.get("stderr", "")),
				"cancelled": bool(state.get("cancelled", false)),
				"timed_out": bool(state.get("timed_out", false)),
			}
			runner.close()
			return result
		OS.delay_msec(POLL_DELAY_MSEC)
	return {"started": false}


static func _accept(base: Dictionary, detected_kind: int, metadata: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result["valid"] = true
	result["detected_kind"] = detected_kind
	result["rejection_code"] = ImportCandidateResult.REJECTION_NONE
	result["technical_detail"] = ""
	result["metadata_preview"] = metadata.duplicate(true)
	return result


static func _reject(base: Dictionary, code: String, detail: String = "") -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	result["valid"] = false
	result["rejection_code"] = code
	result["technical_detail"] = _bounded_detail(detail)
	return result


static func _bounded_detail(detail: String) -> String:
	var clean: String = detail.strip_edges()
	return clean.substr(0, mini(clean.length(), 2048))


static func _starts_with(data: PackedByteArray, signature: Array[int]) -> bool:
	if data.size() < signature.size():
		return false
	for index: int in range(signature.size()):
		if data[index] != signature[index]:
			return false
	return true


static func _ascii_at(data: PackedByteArray, offset: int, value: String) -> bool:
	var bytes: PackedByteArray = value.to_ascii_buffer()
	if offset < 0 or offset + bytes.size() > data.size():
		return false
	for index: int in range(bytes.size()):
		if data[offset + index] != bytes[index]:
			return false
	return true


static func _contains_ascii(data: PackedByteArray, value: String) -> bool:
	var haystack: String = data.get_string_from_ascii()
	return haystack.find(value) >= 0


static func _looks_like_tga(data: PackedByteArray) -> bool:
	if data.size() < 18:
		return false
	var image_type: int = int(data[2])
	if not [1, 2, 3, 9, 10, 11].has(image_type):
		return false
	var width: int = int(data[12]) | (int(data[13]) << 8)
	var height: int = int(data[14]) | (int(data[15]) << 8)
	var bits_per_pixel: int = int(data[16])
	return width > 0 and height > 0 and [8, 15, 16, 24, 32].has(bits_per_pixel)


static func _looks_like_mpeg_audio(data: PackedByteArray) -> bool:
	var maximum: int = mini(data.size() - 1, 4096)
	for index: int in range(maxi(0, maximum)):
		if data[index] == 0xFF and (data[index + 1] & 0xE0) == 0xE0:
			return true
	return false


static func _looks_like_aac_adts(data: PackedByteArray) -> bool:
	return data.size() >= 2 and data[0] == 0xFF and (data[1] & 0xF0) == 0xF0


static func _looks_like_iso_base_media(data: PackedByteArray) -> bool:
	return data.size() >= 12 and _ascii_at(data, 4, "ftyp")


static func _parse_fraction(value: String) -> float:
	var parts: PackedStringArray = value.split("/")
	if parts.size() != 2:
		return float(value)
	var denominator: float = float(parts[1])
	if is_zero_approx(denominator):
		return 0.0
	return float(parts[0]) / denominator


static func _is_cancelled(cancel_check: Callable) -> bool:
	return cancel_check.is_valid() and bool(cancel_check.call())


static func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
