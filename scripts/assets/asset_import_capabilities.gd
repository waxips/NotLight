# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportCapabilities
extends RefCounted

# This registry is the single source of truth for *new user imports*. AssetKinds
# still describes persisted/legacy kinds, including kinds that NotLight may have
# stored in older catalogs, but only the formats below are accepted by Import v1.
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "exr", "hdr", "ktx"]
const VIDEO_EXTENSIONS: Array[String] = ["mp4", "m4v", "mov", "mkv", "webm", "avi", "ogv", "mpeg", "mpg", "wmv", "flv", "ts", "mts", "m2ts", "3gp", "vob"]
const AUDIO_EXTENSIONS: Array[String] = ["mp3", "wav", "ogg", "opus", "flac", "m4a", "aac"]
const PDF_EXTENSIONS: Array[String] = ["pdf"]
const NOTE_EXTENSIONS: Array[String] = ["md", "markdown"]

const IMPORTABLE_KINDS: Array[int] = [
	AssetKinds.IMAGE,
	AssetKinds.VIDEO,
	AssetKinds.AUDIO,
	AssetKinds.PDF,
	AssetKinds.NOTE,
]

const MIME_BY_EXTENSION: Dictionary = {
	"png": "image/png",
	"jpg": "image/jpeg",
	"jpeg": "image/jpeg",
	"webp": "image/webp",
	"bmp": "image/bmp",
	"svg": "image/svg+xml",
	"tga": "image/x-tga",
	"exr": "image/x-exr",
	"hdr": "image/vnd.radiance",
	"ktx": "image/ktx",
	"mp4": "video/mp4",
	"m4v": "video/x-m4v",
	"mov": "video/quicktime",
	"mkv": "video/x-matroska",
	"webm": "video/webm",
	"avi": "video/x-msvideo",
	"ogv": "video/ogg",
	"mpeg": "video/mpeg",
	"mpg": "video/mpeg",
	"wmv": "video/x-ms-wmv",
	"flv": "video/x-flv",
	"ts": "video/mp2t",
	"mts": "video/mp2t",
	"m2ts": "video/mp2t",
	"3gp": "video/3gpp",
	"vob": "video/mpeg",
	"mp3": "audio/mpeg",
	"wav": "audio/wav",
	"ogg": "audio/ogg",
	"opus": "audio/opus",
	"flac": "audio/flac",
	"m4a": "audio/mp4",
	"aac": "audio/aac",
	"pdf": "application/pdf",
	"md": "text/markdown",
	"markdown": "text/markdown",
}


static func supported_kinds() -> Array[int]:
	return IMPORTABLE_KINDS.duplicate()


static func supported_extensions(kind: int = AssetKinds.ANY) -> Array[String]:
	if kind == AssetKinds.IMAGE:
		return IMAGE_EXTENSIONS.duplicate()
	if kind == AssetKinds.VIDEO:
		return VIDEO_EXTENSIONS.duplicate()
	if kind == AssetKinds.AUDIO:
		return AUDIO_EXTENSIONS.duplicate()
	if kind == AssetKinds.PDF:
		return PDF_EXTENSIONS.duplicate()
	if kind == AssetKinds.NOTE:
		return NOTE_EXTENSIONS.duplicate()
	if kind != AssetKinds.ANY:
		return []
	var output: Array[String] = []
	for import_kind: int in IMPORTABLE_KINDS:
		output.append_array(supported_extensions(import_kind))
	return output


static func is_importable_kind(kind: int) -> bool:
	return IMPORTABLE_KINDS.has(kind)


static func is_supported_extension(extension: String) -> bool:
	return kind_for_extension(extension) != AssetKinds.OTHER


static func kind_for_extension(extension: String) -> int:
	var clean: String = extension.strip_edges().trim_prefix(".").to_lower()
	if IMAGE_EXTENSIONS.has(clean):
		return AssetKinds.IMAGE
	if VIDEO_EXTENSIONS.has(clean):
		return AssetKinds.VIDEO
	if AUDIO_EXTENSIONS.has(clean):
		return AssetKinds.AUDIO
	if PDF_EXTENSIONS.has(clean):
		return AssetKinds.PDF
	if NOTE_EXTENSIONS.has(clean):
		return AssetKinds.NOTE
	return AssetKinds.OTHER


static func kind_for_path(path: String) -> int:
	return kind_for_extension(path.get_extension())


static func file_dialog_filters(kind: int = AssetKinds.ANY) -> PackedStringArray:
	var filters: PackedStringArray = PackedStringArray()
	if kind == AssetKinds.ANY:
		filters.append(_filter_string(supported_extensions(), NotLightL10n.text("library.import.filter.all")))
		for import_kind: int in IMPORTABLE_KINDS:
			filters.append(_filter_string(supported_extensions(import_kind), _filter_label(import_kind)))
		return filters
	if not is_importable_kind(kind):
		return filters
	filters.append(_filter_string(supported_extensions(kind), _filter_label(kind)))
	return filters


static func validate_candidate(
	source_path: String,
	expected_kind: int = AssetKinds.ANY,
	extension_override: String = "",
	cancel_check: Callable = Callable()
) -> Dictionary:
	# Classification stays here so every caller shares one extension policy. This
	# call may invoke bounded external probes; scene-tree/UI code must use the
	# preflight service rather than call it synchronously.
	var clean_path: String = source_path.strip_edges()
	var filename: String = clean_path.get_file()
	var extension: String = extension_override.strip_edges().trim_prefix(".").to_lower()
	if extension.is_empty():
		extension = filename.get_extension().to_lower()
	var inferred_kind: int = kind_for_extension(extension)
	var safe_kind: int = inferred_kind if expected_kind == AssetKinds.ANY else expected_kind
	if inferred_kind == AssetKinds.OTHER or not is_importable_kind(safe_kind):
		return AssetImportContentValidator.rejection(
			source_path, filename, extension, safe_kind,
			ImportCandidateResult.REJECTION_UNSUPPORTED_EXTENSION
		)
	if inferred_kind != safe_kind:
		return AssetImportContentValidator.rejection(
			source_path, filename, extension, safe_kind,
			ImportCandidateResult.REJECTION_KIND_MISMATCH
		)
	return AssetImportContentValidator.validate(
		source_path,
		safe_kind,
		extension,
		cancel_check
	)


static func rejection_message(code: String, extension: String = "", detail: String = "") -> String:
	return ImportCandidateResult.localized_rejection_message(code, extension, detail)


static func _filter_string(extensions: Array[String], description: String) -> String:
	var patterns: PackedStringArray = PackedStringArray()
	var mimes: PackedStringArray = PackedStringArray()
	var seen_mimes: Dictionary = {}
	for extension: String in extensions:
		patterns.append("*.%s" % extension)
		var mime: String = str(MIME_BY_EXTENSION.get(extension, "application/octet-stream"))
		if not seen_mimes.has(mime):
			seen_mimes[mime] = true
			mimes.append(mime)
	return "%s;%s;%s" % [",".join(patterns), description, ",".join(mimes)]


static func _filter_label(kind: int) -> String:
	match kind:
		AssetKinds.IMAGE:
			return NotLightL10n.text("library.import.filter.images")
		AssetKinds.VIDEO:
			return NotLightL10n.text("library.import.filter.video")
		AssetKinds.AUDIO:
			return NotLightL10n.text("library.import.filter.audio")
		AssetKinds.PDF:
			return NotLightL10n.text("library.import.filter.pdf")
		AssetKinds.NOTE:
			return NotLightL10n.text("library.import.filter.notes")
		_:
			return NotLightL10n.text("library.import.filter.all")
