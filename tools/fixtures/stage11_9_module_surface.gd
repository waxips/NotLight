# SPDX-License-Identifier: GPL-3.0-or-later
extends Control

var attached_context: ModuleInstanceContext
var attached_state: Dictionary = {}


func notlight_attach_context(context: ModuleInstanceContext, state: Dictionary) -> void:
	attached_context = context
	attached_state = state.duplicate(true)
