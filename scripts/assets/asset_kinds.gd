# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetKinds
extends RefCounted

const ANY: int = -1
const IMAGE: int = 0
const VIDEO: int = 1
const AUDIO: int = 2
const PDF: int = 3
const MODEL_3D: int = 4
const FONT: int = 5
const OTHER: int = 6
const NOTE: int = 7

# These two lists are legacy classification only. They are intentionally not part
# of AssetImportCapabilities and therefore do not make 3D/font files importable.
# They preserve old catalog normalization for records that predate an explicit
# kind field without duplicating the supported-import registry.
const LEGACY_MODEL_EXTENSIONS: Array[String] = ["glb", "gltf", "obj", "fbx", "dae", "blend", "3ds", "stl"]
const LEGACY_FONT_EXTENSIONS: Array[String] = ["ttf", "otf", "woff", "woff2"]


static func from_extension(extension: String) -> int:
	# Legacy-only fallback for persisted records that predate an explicit kind.
	# Current user-import formats deliberately live only in AssetImportCapabilities;
	# keeping this class independent also avoids a cyclic class dependency.
	var clean: String = extension.strip_edges().trim_prefix(".").to_lower()
	if LEGACY_MODEL_EXTENSIONS.has(clean):
		return MODEL_3D
	if LEGACY_FONT_EXTENSIONS.has(clean):
		return FONT
	return OTHER


static func label(kind: int) -> String:
	match kind:
		IMAGE:
			return NotLightL10n.text("asset.kind.image")
		VIDEO:
			return NotLightL10n.text("asset.kind.video")
		AUDIO:
			return NotLightL10n.text("asset.kind.audio")
		PDF:
			return NotLightL10n.text("asset.kind.pdf")
		NOTE:
			return NotLightL10n.text("asset.kind.note")
		MODEL_3D:
			return NotLightL10n.text("asset.kind.model3d")
		FONT:
			return NotLightL10n.text("asset.kind.font")
		_:
			return NotLightL10n.text("asset.kind.file")


static func short_label(kind: int) -> String:
	match kind:
		IMAGE:
			return NotLightL10n.text("asset.kind.short.image")
		VIDEO:
			return NotLightL10n.text("asset.kind.short.video")
		AUDIO:
			return NotLightL10n.text("asset.kind.short.audio")
		PDF:
			return NotLightL10n.text("library.kind.pdf")
		NOTE:
			return NotLightL10n.text("asset.kind.short.note")
		MODEL_3D:
			return NotLightL10n.text("library.kind.3d")
		FONT:
			return NotLightL10n.text("asset.kind.short.font")
		_:
			return NotLightL10n.text("asset.kind.short.file")


static func symbol(kind: int) -> String:
	match kind:
		IMAGE:
			return "▧"
		VIDEO:
			return "▶"
		AUDIO:
			return "♪"
		PDF:
			return "▤"
		NOTE:
			return "✎"
		MODEL_3D:
			return "◇"
		FONT:
			return "Aa"
		_:
			return "□"

static func is_board_insertable(kind: int) -> bool:
	return kind == IMAGE or kind == VIDEO or kind == AUDIO or kind == PDF or kind == NOTE


static func is_previewable(kind: int) -> bool:
	return is_board_insertable(kind)

