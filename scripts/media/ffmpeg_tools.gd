# SPDX-License-Identifier: GPL-3.0-or-later
class_name FFmpegTools
extends RefCounted

const WIN_RELATIVE: String = "tools/ffmpeg/windows/bin"
const LINUX_RELATIVE: String = "tools/ffmpeg/linux/bin"
const MACOS_RELATIVE: String = "tools/ffmpeg/macos/bin"


static func ffmpeg_path() -> String:
	return _tool_path("ffmpeg")


static func ffprobe_path() -> String:
	return _tool_path("ffprobe")


static func is_ffmpeg_available() -> bool:
	return _can_run(ffmpeg_path())


static func is_ffprobe_available() -> bool:
	return _can_run(ffprobe_path())


static func version_line(tool: String) -> String:
	var executable: String = _tool_path(tool)
	if executable.is_empty():
		return ""
	var output: Array = []
	var code: int = OS.execute(executable, PackedStringArray(["-version"]), output, true, false)
	if code != 0 or output.is_empty():
		return ""
	return str(output[0]).split("\n")[0].strip_edges()


static func probe(path: String, check_available: bool = true) -> Dictionary:
	var executable: String = ffprobe_path()
	if executable.is_empty() or (check_available and not _can_run(executable)):
		return {"ok": false, "error": NotLightL10n.text("runtime.media.ffmpeg_tools.71bfe815ea")}
	var output: Array = []
	var native_path: String = _native_path(path)
	var arguments: PackedStringArray = PackedStringArray([
		"-v", "error",
		"-show_entries",
		"format=duration,size,bit_rate,format_name:stream=index,codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,sample_rate,channels,pix_fmt",
		"-of", "json",
		native_path,
	])
	var code: int = OS.execute(executable, arguments, output, true, false)
	if code != 0 or output.is_empty():
		return {"ok": false, "error": NotLightL10n.text("runtime.media.ffmpeg_tools.62b8dcbb85") % code}
	var parsed: Variant = JSON.parse_string(str(output[0]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": NotLightL10n.text("runtime.media.ffmpeg_tools.03d631b13a")}

	var result: Dictionary = {
		"ok": true,
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
		"pixel_format": "",
	}
	var root: Dictionary = parsed as Dictionary
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
			var stream_data: Dictionary = stream_value as Dictionary
			var codec_type: String = str(stream_data.get("codec_type", ""))
			if codec_type == "video" and str(result.get("video_codec", "")).is_empty():
				result["video_codec"] = str(stream_data.get("codec_name", ""))
				result["width"] = int(stream_data.get("width", 0))
				result["height"] = int(stream_data.get("height", 0))
				result["fps"] = _parse_fraction(str(stream_data.get("avg_frame_rate", stream_data.get("r_frame_rate", "0/1"))))
				result["pixel_format"] = str(stream_data.get("pix_fmt", ""))
			elif codec_type == "audio" and str(result.get("audio_codec", "")).is_empty():
				result["audio_codec"] = str(stream_data.get("codec_name", ""))
				result["sample_rate"] = int(stream_data.get("sample_rate", 0))
				result["channels"] = int(stream_data.get("channels", 0))
	return result


static func _parse_fraction(value: String) -> float:
	var parts: PackedStringArray = value.split("/")
	if parts.size() != 2:
		return float(value)
	var denominator: float = float(parts[1])
	if is_zero_approx(denominator):
		return 0.0
	return float(parts[0]) / denominator


static func _tool_path(tool: String) -> String:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return ""
	var executable: String = tool + (".exe" if OS.has_feature("windows") else "")
	var relative: String = WIN_RELATIVE
	if OS.has_feature("linux"):
		relative = LINUX_RELATIVE
	elif OS.has_feature("macos"):
		relative = MACOS_RELATIVE

	# Editor/dev layout: the executable is a real file in the project directory.
	var project_candidate: String = ProjectSettings.globalize_path("res://" + relative.path_join(executable))
	if FileAccess.file_exists(project_candidate):
		return project_candidate

	# Export layout: the build script copies tools next to the application executable.
	var app_candidate: String = OS.get_executable_path().get_base_dir().path_join(relative).path_join(executable)
	if FileAccess.file_exists(app_candidate):
		return app_candidate

	# Developer fallback for Linux/macOS or machines with FFmpeg in PATH. Resolve
	# it without launching a process: availability checks are used by selection/UI
	# hot paths and must never block the main thread on a cold sidecar start.
	return _find_on_path(executable)


static func _can_run(path: String) -> bool:
	var clean_path: String = path.strip_edges()
	return not clean_path.is_empty() and FileAccess.file_exists(clean_path)


static func _find_on_path(executable: String) -> String:
	var path_value: String = OS.get_environment("PATH")
	if path_value.is_empty():
		return ""
	var separator: String = ";" if OS.has_feature("windows") else ":"
	for raw_directory: String in path_value.split(separator, false):
		var directory: String = raw_directory.strip_edges().trim_prefix("\"").trim_suffix("\"")
		if directory.is_empty():
			continue
		var candidate: String = directory.path_join(executable)
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


static func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
