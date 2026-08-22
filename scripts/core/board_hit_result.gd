# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardHitResult
extends RefCounted

var entity_id: int = 0
var type_id: StringName = StringName()
var world_position: Vector2 = Vector2.ZERO
var local_position: Vector2 = Vector2.ZERO
var z_order: int = 0


func is_valid() -> bool:
	return entity_id > 0
