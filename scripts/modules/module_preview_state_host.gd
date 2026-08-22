# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModulePreviewStateHost
extends ModuleEphemeralStateHost

# Module Library preview uses the same generic ephemeral state boundary as Notes
# module embeds. The specialized class keeps the Library API descriptive while
# preventing a second persistence implementation from drifting away over time.


func configure(target_module_id: String, initial_state: Dictionary, state_schema_version: int) -> void:
	var clean_module_id: String = target_module_id.strip_edges().to_lower()
	configure_ephemeral(
		clean_module_id,
		"library-preview:%s" % clean_module_id,
		initial_state,
		state_schema_version
	)
