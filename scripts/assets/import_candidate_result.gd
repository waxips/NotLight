# SPDX-License-Identifier: GPL-3.0-or-later
class_name ImportCandidateResult
extends RefCounted

const REJECTION_NONE: String = ""
const REJECTION_MISSING: String = "missing"
const REJECTION_EMPTY: String = "empty"
const REJECTION_UNSUPPORTED_EXTENSION: String = "unsupported_extension"
const REJECTION_KIND_MISMATCH: String = "kind_mismatch"
const REJECTION_INVALID_CONTENT: String = "invalid_content"
const REJECTION_UNSAFE_SVG: String = "unsafe_svg"
const REJECTION_SVG_TOO_LARGE: String = "svg_too_large"
const REJECTION_PROBE_UNAVAILABLE: String = "probe_unavailable"
const REJECTION_PROBE_FAILED: String = "probe_failed"
const REJECTION_ENCRYPTED_PDF: String = "encrypted_pdf"
const REJECTION_HASH_FAILED: String = "hash_failed"
const REJECTION_SOURCE_CHANGED: String = "source_changed"
const REJECTION_CANCELLED: String = "cancelled"

var source_path: String = ""
var filename: String = ""
var extension: String = ""
var expected_kind: int = AssetKinds.OTHER
var detected_kind: int = AssetKinds.OTHER
var byte_size: int = 0
var hash_sha256: String = ""
var valid: bool = false
var duplicate: bool = false
var duplicate_in_batch: bool = false
var repair_existing: bool = false
var existing_asset_id: String = ""
var rejection_code: String = REJECTION_NONE
var technical_detail: String = ""
var metadata_preview: Dictionary = {}


static func from_worker_dictionary(data: Dictionary) -> ImportCandidateResult:
	var result: ImportCandidateResult = ImportCandidateResult.new()
	result.source_path = str(data.get("source_path", ""))
	result.filename = str(data.get("filename", result.source_path.get_file()))
	result.extension = str(data.get("extension", result.filename.get_extension())).strip_edges().to_lower()
	result.expected_kind = int(data.get("expected_kind", AssetKinds.OTHER))
	result.detected_kind = int(data.get("detected_kind", AssetKinds.OTHER))
	result.byte_size = maxi(0, int(data.get("byte_size", 0)))
	result.hash_sha256 = str(data.get("hash_sha256", "")).strip_edges().to_lower()
	result.valid = bool(data.get("valid", false))
	result.rejection_code = str(data.get("rejection_code", REJECTION_NONE))
	result.technical_detail = str(data.get("technical_detail", ""))
	var metadata_value: Variant = data.get("metadata_preview", {})
	if metadata_value is Dictionary:
		result.metadata_preview = (metadata_value as Dictionary).duplicate(true)
	return result


func is_importable() -> bool:
	return valid and not duplicate


func rejection_message() -> String:
	return localized_rejection_message(rejection_code, extension, technical_detail)


static func localized_rejection_message(code: String, extension_value: String = "", detail: String = "") -> String:
	var clean_extension: String = extension_value.strip_edges().trim_prefix(".").to_lower()
	match code:
		REJECTION_MISSING:
			return NotLightL10n.text("library.import.reject.missing")
		REJECTION_EMPTY:
			return NotLightL10n.text("library.import.reject.empty")
		REJECTION_UNSUPPORTED_EXTENSION:
			return NotLightL10n.text("library.import.reject.unsupported", {"extension": _extension_label(clean_extension)})
		REJECTION_KIND_MISMATCH:
			return NotLightL10n.text("library.import.reject.kind_mismatch")
		REJECTION_INVALID_CONTENT:
			return NotLightL10n.text("library.import.reject.invalid_content", {"extension": _extension_label(clean_extension)})
		REJECTION_UNSAFE_SVG:
			return NotLightL10n.text("library.import.reject.unsafe_svg")
		REJECTION_SVG_TOO_LARGE:
			return NotLightL10n.text("library.import.reject.svg_too_large")
		REJECTION_PROBE_UNAVAILABLE:
			return NotLightL10n.text("library.import.reject.probe_unavailable")
		REJECTION_PROBE_FAILED:
			return NotLightL10n.text("library.import.reject.probe_failed")
		REJECTION_ENCRYPTED_PDF:
			return NotLightL10n.text("library.import.reject.encrypted_pdf")
		REJECTION_HASH_FAILED:
			return NotLightL10n.text("library.import.reject.hash_failed")
		REJECTION_SOURCE_CHANGED:
			return NotLightL10n.text("library.import.reject.source_changed")
		REJECTION_CANCELLED:
			return NotLightL10n.text("library.import.reject.cancelled")
		_:
			return detail if not detail.strip_edges().is_empty() else NotLightL10n.text("library.import.reject.generic")


static func _extension_label(extension_value: String) -> String:
	return ".%s" % extension_value if not extension_value.is_empty() else NotLightL10n.text("library.import.no_extension")


func status_message() -> String:
	if not valid:
		return rejection_message()
	if duplicate_in_batch:
		return NotLightL10n.text("library.preflight.status.duplicate_batch")
	if duplicate:
		return NotLightL10n.text("library.preflight.status.duplicate")
	if repair_existing:
		return NotLightL10n.text("library.preflight.status.repair")
	return NotLightL10n.text("library.preflight.status.new")


func to_import_request() -> Dictionary:
	return {
		"source_path": source_path,
		"hash_sha256": hash_sha256,
		"byte_size": byte_size,
		"filename": filename,
		"expected_kind": expected_kind,
	}
