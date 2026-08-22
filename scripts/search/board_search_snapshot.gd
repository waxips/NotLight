# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardSearchSnapshot
extends RefCounted

# Read-only DOD snapshot for the future board-wide search UI. Building it is an
# explicit operation, so normal board interaction pays no indexing cost.
static func build(model: BoardModel, library: AssetLibraryService, notes: NoteRepository = null) -> Dictionary:
	var entity_ids: PackedInt64Array = PackedInt64Array()
	var type_ids: PackedStringArray = PackedStringArray()
	var titles: PackedStringArray = PackedStringArray()
	var bodies: PackedStringArray = PackedStringArray()
	var search_texts: PackedStringArray = PackedStringArray()
	if model == null:
		return _result(entity_ids, type_ids, titles, bodies, search_texts)
	for entity_id: int in model.text_blocks.entity_ids:
		if not model.contains(entity_id):
			continue
		var body: String = model.text_blocks.get_text(entity_id)
		_append(entity_ids, type_ids, titles, bodies, search_texts, entity_id, BoardEntityTypes.TEXT, _text_title(body), body, body)
	for entity_id: int in model.formulas.entity_ids:
		if not model.contains(entity_id):
			continue
		var latex: String = model.formulas.get_source(entity_id)
		_append(entity_ids, type_ids, titles, bodies, search_texts, entity_id, BoardEntityTypes.FORMULA, _formula_title(latex), latex, latex)
	_append_media_store(model, library, BoardEntityTypes.IMAGE, model.images.entity_ids, entity_ids, type_ids, titles, bodies, search_texts)
	_append_media_store(model, library, BoardEntityTypes.PDF, model.pdfs.entity_ids, entity_ids, type_ids, titles, bodies, search_texts)
	_append_media_store(model, library, BoardEntityTypes.VIDEO, model.videos.entity_ids, entity_ids, type_ids, titles, bodies, search_texts)
	_append_media_store(model, library, BoardEntityTypes.AUDIO, model.audios.entity_ids, entity_ids, type_ids, titles, bodies, search_texts)
	_append_module_store(model, entity_ids, type_ids, titles, bodies, search_texts)
	_append_note_portals(model, library, notes, entity_ids, type_ids, titles, bodies, search_texts)
	return _result(entity_ids, type_ids, titles, bodies, search_texts)


static func _append_note_portals(
	model: BoardModel,
	library: AssetLibraryService,
	notes: NoteRepository,
	entity_ids: PackedInt64Array,
	type_ids: PackedStringArray,
	titles: PackedStringArray,
	bodies: PackedStringArray,
	search_texts: PackedStringArray
) -> void:
	for entity_id: int in model.note_portals.entity_ids:
		if not model.contains(entity_id):
			continue
		var note_id: String = model.note_portals.get_note_id(entity_id)
		var asset: Dictionary = library.get_asset(note_id) if library != null and not note_id.is_empty() else {}
		var title: String = str(asset.get("display_name", "")).strip_edges()
		var excerpt: String = notes.peek_cached_excerpt(note_id, 420) if notes != null and not note_id.is_empty() else ""
		var description: String = str(asset.get("description", "")).strip_edges()
		var terms: String = "%s %s %s %s" % [title, excerpt, description, note_id]
		_append(
			entity_ids, type_ids, titles, bodies, search_texts,
			entity_id, BoardEntityTypes.NOTE_PORTAL, title, excerpt, terms
		)


static func _append_module_store(
	model: BoardModel,
	entity_ids: PackedInt64Array,
	type_ids: PackedStringArray,
	titles: PackedStringArray,
	bodies: PackedStringArray,
	search_texts: PackedStringArray
) -> void:
	for entity_id: int in model.modules.entity_ids:
		if not model.contains(entity_id):
			continue
		var module_id: String = model.modules.get_module_id(entity_id)
		var title: String = model.modules.get_instance_title(entity_id).strip_edges()
		if title.is_empty():
			title = module_id
		_append(
			entity_ids,
			type_ids,
			titles,
			bodies,
			search_texts,
			entity_id,
			BoardEntityTypes.MODULE,
			title,
			module_id,
			"%s %s" % [title, module_id]
		)


static func _append_media_store(
	model: BoardModel,
	library: AssetLibraryService,
	type_id: StringName,
	media_ids: PackedInt64Array,
	entity_ids: PackedInt64Array,
	type_ids: PackedStringArray,
	titles: PackedStringArray,
	bodies: PackedStringArray,
	search_texts: PackedStringArray
) -> void:
	for entity_id: int in media_ids:
		if not model.contains(entity_id):
			continue
		var asset_id: String = ""
		var local_title: String = ""
		match type_id:
			BoardEntityTypes.IMAGE:
				asset_id = model.images.get_asset_id(entity_id)
				local_title = model.images.get_instance_title(entity_id)
			BoardEntityTypes.PDF:
				asset_id = model.pdfs.get_asset_id(entity_id)
				local_title = model.pdfs.get_instance_title(entity_id)
			BoardEntityTypes.VIDEO:
				asset_id = model.videos.get_asset_id(entity_id)
				local_title = model.videos.get_instance_title(entity_id)
			BoardEntityTypes.AUDIO:
				asset_id = model.audios.get_asset_id(entity_id)
				local_title = model.audios.get_instance_title(entity_id)
		var asset: Dictionary = library.get_asset(asset_id) if library != null and not asset_id.is_empty() else {}
		var asset_title: String = str(asset.get("display_name", "")).strip_edges()
		var title: String = local_title if not local_title.is_empty() else asset_title
		var description: String = str(asset.get("description", "")).strip_edges()
		var tags: PackedStringArray = PackedStringArray()
		var raw_tags: Variant = asset.get("tags", [])
		if raw_tags is Array or raw_tags is PackedStringArray:
			for raw_tag: Variant in raw_tags:
				tags.append(str(raw_tag).strip_edges())
		var terms: PackedStringArray = PackedStringArray([title, asset_title, description, " ".join(tags)])
		_append(entity_ids, type_ids, titles, bodies, search_texts, entity_id, type_id, title, description, " ".join(terms).strip_edges())


static func _append(
	entity_ids: PackedInt64Array,
	type_ids: PackedStringArray,
	titles: PackedStringArray,
	bodies: PackedStringArray,
	search_texts: PackedStringArray,
	entity_id: int,
	type_id: StringName,
	title: String,
	body: String,
	search_text: String
) -> void:
	entity_ids.append(entity_id)
	type_ids.append(str(type_id))
	titles.append(title)
	bodies.append(body)
	search_texts.append(search_text.to_lower())


static func _result(
	entity_ids: PackedInt64Array,
	type_ids: PackedStringArray,
	titles: PackedStringArray,
	bodies: PackedStringArray,
	search_texts: PackedStringArray
) -> Dictionary:
	return {
		"entity_ids": entity_ids,
		"type_ids": type_ids,
		"titles": titles,
		"bodies": bodies,
		"search_texts": search_texts,
	}


static func _text_title(body: String) -> String:
	var clean: String = body.strip_edges()
	if clean.is_empty():
		return ""
	var first_line: String = clean.split("\n", false, 1)[0].strip_edges()
	return first_line.left(96)


static func _formula_title(latex: String) -> String:
	var clean: String = latex.strip_edges().replace("\n", " ")
	return clean.left(96)
