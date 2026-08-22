# SPDX-License-Identifier: GPL-3.0-or-later
extends AssetLibraryView

var rebuild_count: int = 0


func _rebuild_folder_tree() -> void:
	rebuild_count += 1
	super._rebuild_folder_tree()
