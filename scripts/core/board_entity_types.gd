# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardEntityTypes
extends RefCounted

const TEXT: StringName = &"text"
const IMAGE: StringName = &"image"
const VIDEO: StringName = &"video"
const AUDIO: StringName = &"audio"
const PDF: StringName = &"pdf"
const FORMULA: StringName = &"formula"
const MODULE: StringName = &"module"
const NOTE_PORTAL: StringName = &"note_portal"
const STROKE: StringName = &"stroke"
const SHAPE: StringName = &"shape"
const FRAME: StringName = &"frame"
const CONNECTOR: StringName = &"connector"

const BUILTIN_TYPES: Array[StringName] = [
	TEXT,
	IMAGE,
	VIDEO,
	AUDIO,
	PDF,
	FORMULA,
	MODULE,
	NOTE_PORTAL,
	STROKE,
	SHAPE,
	FRAME,
	CONNECTOR,
]


static func is_builtin(type_id: StringName) -> bool:
	return BUILTIN_TYPES.has(type_id)
