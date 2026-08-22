# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardModel
extends RefCounted

signal entity_created(entity_id: int, type_id: StringName)
signal entity_removed(entity_id: int, type_id: StringName)
signal entity_transform_changed(entity_id: int, old_bounds: Rect2, new_bounds: Rect2)
signal entity_data_changed(entity_id: int)
signal reset_completed

var allocator: EntityIdAllocator = EntityIdAllocator.new()
var entities: BoardEntityRegistry = BoardEntityRegistry.new()
var transforms: BoardTransformStore = BoardTransformStore.new()
var stores: BoardStoreRegistry = BoardStoreRegistry.new()
var text_blocks: TextBlockStore = TextBlockStore.new()
var images: ImageStore = ImageStore.new()
var pdfs: PdfStore = PdfStore.new()
var formulas: FormulaStore = FormulaStore.new()
var modules: ModuleStore = ModuleStore.new()
var note_portals: NotePortalStore = NotePortalStore.new()
var videos: VideoStore = VideoStore.new()
var audios: AudioStore = AudioStore.new()
var strokes: StrokeStore = StrokeStore.new()
var connectors: ConnectorStore = ConnectorStore.new()
var revision: int = 0
var text_revision: int = 0
var image_revision: int = 0
var pdf_revision: int = 0
var formula_revision: int = 0
var module_revision: int = 0
var note_portal_revision: int = 0
var video_revision: int = 0
var audio_revision: int = 0
var stroke_revision: int = 0
var connector_revision: int = 0


func _init() -> void:
	stores.register_store(text_blocks)
	stores.register_store(images)
	stores.register_store(pdfs)
	stores.register_store(formulas)
	stores.register_store(modules)
	stores.register_store(note_portals)
	stores.register_store(videos)
	stores.register_store(audios)
	stores.register_store(strokes)
	stores.register_store(connectors)
	text_blocks.block_added.connect(_on_text_block_data_changed)
	text_blocks.block_changed.connect(_on_text_block_data_changed)
	text_blocks.block_removed.connect(_on_text_block_data_changed)
	images.image_added.connect(_on_image_data_changed)
	images.image_changed.connect(_on_image_data_changed)
	images.image_removed.connect(_on_image_data_changed)
	pdfs.pdf_added.connect(_on_pdf_data_changed)
	pdfs.pdf_changed.connect(_on_pdf_data_changed)
	pdfs.pdf_removed.connect(_on_pdf_data_changed)
	formulas.formula_added.connect(_on_formula_data_changed)
	formulas.formula_changed.connect(_on_formula_data_changed)
	formulas.formula_removed.connect(_on_formula_data_changed)
	modules.module_added.connect(_on_module_data_changed)
	modules.module_changed.connect(_on_module_data_changed)
	modules.module_removed.connect(_on_module_data_changed)
	note_portals.portal_added.connect(_on_note_portal_data_changed)
	note_portals.portal_changed.connect(_on_note_portal_data_changed)
	note_portals.portal_removed.connect(_on_note_portal_data_changed)
	videos.video_added.connect(_on_video_data_changed)
	videos.video_changed.connect(_on_video_data_changed)
	videos.video_removed.connect(_on_video_data_changed)
	audios.audio_added.connect(_on_audio_data_changed)
	audios.audio_changed.connect(_on_audio_data_changed)
	audios.audio_removed.connect(_on_audio_data_changed)
	strokes.stroke_added.connect(_on_stroke_data_changed)
	strokes.stroke_changed.connect(_on_stroke_data_changed)
	strokes.stroke_removed.connect(_on_stroke_data_changed)
	connectors.connector_added.connect(_on_connector_data_changed)
	connectors.connector_changed.connect(_on_connector_data_changed)
	connectors.connector_removed.connect(_on_connector_data_changed)


func create_entity(
	type_id: StringName,
	bounds: Rect2,
	rotation: float = 0.0,
	z_order: int = 0,
	entity_flags: int = BoardTransformStore.FLAG_VISIBLE
) -> int:
	var entity_id: int = allocator.allocate()
	if not entities.register_entity(entity_id, type_id):
		return 0
	if not transforms.add(entity_id, bounds.position, bounds.size, rotation, z_order, entity_flags):
		entities.unregister_entity(entity_id)
		return 0
	revision += 1
	_increment_type_revision(type_id)
	entity_created.emit(entity_id, type_id)
	return entity_id


func restore_entity(
	entity_id: int,
	type_id: StringName,
	bounds: Rect2,
	rotation: float,
	z_order: int,
	entity_flags: int
) -> bool:
	if entity_id <= 0 or entities.contains(entity_id):
		return false
	allocator.reserve(entity_id)
	if not entities.register_entity(entity_id, type_id):
		return false
	if not transforms.add(entity_id, bounds.position, bounds.size, rotation, z_order, entity_flags):
		entities.unregister_entity(entity_id)
		return false
	revision += 1
	_increment_type_revision(type_id)
	return true


func remove_entity(entity_id: int) -> bool:
	if not entities.contains(entity_id):
		return false
	var type_id: StringName = entities.get_type(entity_id)
	stores.remove_entity(entity_id)
	transforms.remove(entity_id)
	entities.unregister_entity(entity_id)
	revision += 1
	_increment_type_revision(type_id)
	if type_id != BoardEntityTypes.CONNECTOR:
		# A removed endpoint can invalidate retained connector geometry even when
		# the connector records themselves are cleaned up by a higher-level batch.
		connector_revision += 1
	entity_removed.emit(entity_id, type_id)
	return true


func set_entity_transform(entity_id: int, bounds: Rect2, rotation: float = 0.0) -> bool:
	if not transforms.contains(entity_id):
		return false
	var old_bounds: Rect2 = transforms.get_bounds(entity_id)
	var old_rotation: float = transforms.get_rotation(entity_id)
	if not transforms.set_transform(entity_id, bounds.position, bounds.size, rotation):
		return false
	var new_bounds: Rect2 = transforms.get_bounds(entity_id)
	if old_bounds != new_bounds or not is_equal_approx(old_rotation, rotation):
		revision += 1
		var type_id: StringName = entities.get_type(entity_id)
		_increment_type_revision(type_id)
		if type_id != BoardEntityTypes.CONNECTOR:
			# Connectors derive their route from endpoint bounds. Give their renderer
			# a dedicated dependency revision instead of forcing every renderer to use
			# the board-wide revision for unrelated model changes.
			connector_revision += 1
		entity_transform_changed.emit(entity_id, old_bounds, new_bounds)
	return true


func set_entity_z_order(entity_id: int, z_order: int) -> bool:
	if not transforms.contains(entity_id):
		return false
	var previous: int = transforms.get_z_order(entity_id)
	if not transforms.set_z_order(entity_id, z_order):
		return false
	if previous != z_order:
		revision += 1
		var type_id: StringName = entities.get_type(entity_id)
		_increment_type_revision(type_id)
		entity_data_changed.emit(entity_id)
	return true


func set_entity_flags(entity_id: int, entity_flags: int) -> bool:
	if not transforms.contains(entity_id):
		return false
	var previous: int = transforms.get_flags(entity_id)
	if not transforms.set_flags(entity_id, entity_flags):
		return false
	if previous != entity_flags:
		revision += 1
		var type_id: StringName = entities.get_type(entity_id)
		_increment_type_revision(type_id)
		if type_id != BoardEntityTypes.CONNECTOR:
			connector_revision += 1
		entity_data_changed.emit(entity_id)
	return true


func get_entity_bounds(entity_id: int) -> Rect2:
	return transforms.get_bounds(entity_id)


func get_entity_type(entity_id: int) -> StringName:
	return entities.get_type(entity_id)


func get_entity_z_order(entity_id: int) -> int:
	return transforms.get_z_order(entity_id)


func contains(entity_id: int) -> bool:
	return entities.contains(entity_id)


func serialize_core() -> Dictionary:
	return {
		"next_entity_id": allocator.serialize_next_id(),
		"entities": transforms.serialize_entries(entities),
	}


func deserialize_core(core_data: Dictionary) -> void:
	clear()
	allocator.restore_serialized(core_data.get("next_entity_id", "1"))
	var raw_entities: Variant = core_data.get("entities", [])
	if raw_entities is Array:
		var entity_records: Array = raw_entities as Array
		for raw_record: Variant in entity_records:
			if raw_record is Dictionary:
				_restore_record(raw_record as Dictionary)
	revision = 0
	text_revision = 0
	image_revision = 0
	pdf_revision = 0
	formula_revision = 0
	module_revision = 0
	note_portal_revision = 0
	video_revision = 0
	audio_revision = 0
	stroke_revision = 0
	connector_revision = 0
	reset_completed.emit()


func clear() -> void:
	stores.clear()
	transforms.clear()
	entities.clear()
	allocator.reset()
	revision = 0
	text_revision = 0
	image_revision = 0
	pdf_revision = 0
	formula_revision = 0
	module_revision = 0
	note_portal_revision = 0
	video_revision = 0
	audio_revision = 0
	stroke_revision = 0
	connector_revision = 0


func _restore_record(record: Dictionary) -> void:
	var entity_id: int = int(str(record.get("id", "0")))
	var type_id: StringName = StringName(str(record.get("type", "")))
	if entity_id <= 0 or type_id == StringName():
		return
	var position_data: Dictionary = record.get("position", {}) as Dictionary
	var size_data: Dictionary = record.get("size", {}) as Dictionary
	var position: Vector2 = Vector2(
		float(position_data.get("x", 0.0)),
		float(position_data.get("y", 0.0))
	)
	var size: Vector2 = Vector2(
		maxf(float(size_data.get("x", 0.0)), 0.0),
		maxf(float(size_data.get("y", 0.0)), 0.0)
	)
	var rotation: float = float(record.get("rotation", 0.0))
	var z_order: int = int(record.get("z_order", 0))
	var entity_flags: int = int(record.get("flags", BoardTransformStore.FLAG_VISIBLE))
	restore_entity(entity_id, type_id, Rect2(position, size), rotation, z_order, entity_flags)


func get_max_z_order() -> int:
	return transforms.get_max_z_order()


func _on_text_block_data_changed(entity_id: int) -> void:
	revision += 1
	text_revision += 1
	entity_data_changed.emit(entity_id)


func _on_image_data_changed(entity_id: int) -> void:
	revision += 1
	image_revision += 1
	entity_data_changed.emit(entity_id)


func _on_pdf_data_changed(entity_id: int) -> void:
	revision += 1
	pdf_revision += 1
	entity_data_changed.emit(entity_id)


func _on_formula_data_changed(entity_id: int) -> void:
	revision += 1
	formula_revision += 1
	entity_data_changed.emit(entity_id)


func _on_module_data_changed(entity_id: int) -> void:
	revision += 1
	module_revision += 1
	entity_data_changed.emit(entity_id)


func _on_note_portal_data_changed(entity_id: int) -> void:
	revision += 1
	note_portal_revision += 1
	entity_data_changed.emit(entity_id)


func _on_video_data_changed(entity_id: int) -> void:
	revision += 1
	video_revision += 1
	entity_data_changed.emit(entity_id)



func _on_audio_data_changed(entity_id: int) -> void:
	revision += 1
	audio_revision += 1
	entity_data_changed.emit(entity_id)


func _on_stroke_data_changed(entity_id: int) -> void:
	revision += 1
	stroke_revision += 1
	entity_data_changed.emit(entity_id)

func _on_connector_data_changed(entity_id: int) -> void:
	revision += 1
	connector_revision += 1
	entity_data_changed.emit(entity_id)


func _increment_type_revision(type_id: StringName) -> void:
	match type_id:
		BoardEntityTypes.TEXT:
			text_revision += 1
		BoardEntityTypes.IMAGE:
			image_revision += 1
		BoardEntityTypes.PDF:
			pdf_revision += 1
		BoardEntityTypes.FORMULA:
			formula_revision += 1
		BoardEntityTypes.MODULE:
			module_revision += 1
		BoardEntityTypes.NOTE_PORTAL:
			note_portal_revision += 1
		BoardEntityTypes.VIDEO:
			video_revision += 1
		BoardEntityTypes.AUDIO:
			audio_revision += 1
		BoardEntityTypes.STROKE:
			stroke_revision += 1
		BoardEntityTypes.CONNECTOR:
			connector_revision += 1
