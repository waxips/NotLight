# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotesGraphModel
extends RefCounted

# Dense graph snapshot used by NotesGraphCanvas. String IDs stay at the boundary;
# drawing/hit testing works on packed index-addressed arrays. The model never
# materializes a Control per note, which keeps the global graph viable for large
# repositories.
const NODE_MIN_RADIUS: float = 17.0
const NODE_MAX_RADIUS: float = 34.0
const NODE_CULL_MARGIN: float = 42.0
const GRID_CELL: float = 180.0
const MAX_NODES: int = 20000
const MAX_EDGES: int = 120000
const EDGE_TEXTUAL: int = 1
const EDGE_EXPLICIT: int = 2
const LAYOUT_NODE_GAP: float = 14.0
const LAYOUT_RING_STEP: float = 96.0
const LAYOUT_MIN_SPACING: float = NODE_MAX_RADIUS * 2.0 + LAYOUT_NODE_GAP
const MAX_COLLISION_RESOLVE_RINGS: int = 24

var note_ids: PackedStringArray = PackedStringArray()
var titles: PackedStringArray = PackedStringArray()
var positions: PackedVector2Array = PackedVector2Array()
var hops: PackedByteArray = PackedByteArray()
var degrees: PackedInt32Array = PackedInt32Array()
var source_indices: PackedInt32Array = PackedInt32Array()
var target_indices: PackedInt32Array = PackedInt32Array()
var edge_flags: PackedByteArray = PackedByteArray()
var textual_relation_count: int = 0
var explicit_relation_count: int = 0
var mixed_relation_count: int = 0
var _index_by_id: Dictionary = {}
var _spatial_cells: Dictionary = {}
var _edge_indices_by_node: Array[PackedInt32Array] = []


func rebuild(snapshot: Dictionary, preserved_positions: Dictionary = {}) -> void:
	clear()
	var nodes: Array = snapshot.get("nodes", []) as Array
	var safe_count: int = mini(nodes.size(), MAX_NODES)
	for source_index: int in range(safe_count):
		var raw: Variant = nodes[source_index]
		if raw is not Dictionary:
			continue
		var node: Dictionary = raw as Dictionary
		var note_id: String = str(node.get("id", "")).strip_edges()
		if note_id.is_empty() or _index_by_id.has(note_id):
			continue
		var model_index: int = note_ids.size()
		note_ids.append(note_id)
		titles.append(str(node.get("title", NotLightL10n.text("asset.kind.note"))).strip_edges().left(160))
		var hop_value: int = clampi(int(node.get("hop", -1)), -1, 255)
		hops.append(255 if hop_value < 0 else hop_value)
		degrees.append(0)
		_index_by_id[note_id] = model_index
		_edge_indices_by_node.append(PackedInt32Array())

	var hop_totals: Dictionary = {}
	for model_index: int in range(note_ids.size()):
		var hop_value: int = get_hop(model_index)
		if hop_value >= 0:
			hop_totals[hop_value] = int(hop_totals.get(hop_value, 0)) + 1
	var hop_offsets: Dictionary = {}
	for model_index: int in range(note_ids.size()):
		var note_id: String = note_ids[model_index]
		if preserved_positions.has(note_id) and preserved_positions[note_id] is Vector2:
			positions.append(preserved_positions[note_id] as Vector2)
			continue
		var hop_value: int = get_hop(model_index)
		var hop_offset: int = int(hop_offsets.get(hop_value, 0))
		hop_offsets[hop_value] = hop_offset + 1
		positions.append(_default_position(model_index, note_ids.size(), hop_value, hop_offset, int(hop_totals.get(hop_value, 0))))

	var edges: Array = snapshot.get("edges", []) as Array
	var edge_seen: Dictionary = {}
	for raw: Variant in edges:
		if source_indices.size() >= MAX_EDGES or raw is not Dictionary:
			break
		var edge: Dictionary = raw as Dictionary
		var source_id: String = str(edge.get("source", "")).strip_edges()
		var target_id: String = str(edge.get("target", "")).strip_edges()
		if not _index_by_id.has(source_id) or not _index_by_id.has(target_id):
			continue
		var source_index: int = int(_index_by_id[source_id])
		var target_index: int = int(_index_by_id[target_id])
		if source_index == target_index:
			continue
		var key: String = "%d>%d" % [source_index, target_index]
		if edge_seen.has(key):
			continue
		edge_seen[key] = true
		source_indices.append(source_index)
		target_indices.append(target_index)
		var flags: int = 0
		if bool(edge.get("textual", false)):
			flags |= EDGE_TEXTUAL
		if bool(edge.get("explicit", false)):
			flags |= EDGE_EXPLICIT
		edge_flags.append(flags)
		if (flags & EDGE_TEXTUAL) != 0:
			textual_relation_count += 1
		if (flags & EDGE_EXPLICIT) != 0:
			explicit_relation_count += 1
		if (flags & EDGE_TEXTUAL) != 0 and (flags & EDGE_EXPLICIT) != 0:
			mixed_relation_count += 1
		var edge_index: int = source_indices.size() - 1
		var source_edges: PackedInt32Array = _edge_indices_by_node[source_index]
		source_edges.append(edge_index)
		_edge_indices_by_node[source_index] = source_edges
		var target_edges: PackedInt32Array = _edge_indices_by_node[target_index]
		target_edges.append(edge_index)
		_edge_indices_by_node[target_index] = target_edges
		degrees[source_index] = int(degrees[source_index]) + 1
		degrees[target_index] = int(degrees[target_index]) + 1
	_rebuild_spatial_index()


func clear() -> void:
	note_ids = PackedStringArray()
	titles = PackedStringArray()
	positions = PackedVector2Array()
	hops = PackedByteArray()
	degrees = PackedInt32Array()
	source_indices = PackedInt32Array()
	target_indices = PackedInt32Array()
	edge_flags = PackedByteArray()
	textual_relation_count = 0
	explicit_relation_count = 0
	mixed_relation_count = 0
	_index_by_id.clear()
	_spatial_cells.clear()
	_edge_indices_by_node.clear()


func size() -> int:
	return note_ids.size()


func edge_count() -> int:
	return source_indices.size()


func relation_counts() -> Dictionary:
	return {
		"textual": textual_relation_count,
		"explicit": explicit_relation_count,
		"mixed": mixed_relation_count,
	}


func get_index(note_id: String) -> int:
	return int(_index_by_id.get(note_id.strip_edges(), -1))


func get_note_id(index: int) -> String:
	return note_ids[index] if index >= 0 and index < note_ids.size() else ""


func get_title(index: int) -> String:
	return titles[index] if index >= 0 and index < titles.size() else ""


func get_hop(index: int) -> int:
	if index < 0 or index >= hops.size():
		return -1
	var packed: int = int(hops[index])
	return -1 if packed == 255 else packed


func get_degree(index: int) -> int:
	return int(degrees[index]) if index >= 0 and index < degrees.size() else 0


func get_node_radius(index: int) -> float:
	if index < 0 or index >= note_ids.size():
		return NODE_MIN_RADIUS
	var degree: int = get_degree(index)
	var radius: float = NODE_MIN_RADIUS + minf(9.0, sqrt(float(maxi(0, degree))) * 2.1)
	var hop_value: int = get_hop(index)
	if hop_value == 0:
		radius += 7.0
	elif hop_value == 1:
		radius += 2.5
	return clampf(radius, NODE_MIN_RADIUS, NODE_MAX_RADIUS)


func get_node_rect(index: int) -> Rect2:
	if index < 0 or index >= positions.size():
		return Rect2()
	var radius: float = get_node_radius(index)
	return Rect2(positions[index] - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))


func set_position(index: int, position: Vector2) -> bool:
	if index < 0 or index >= positions.size():
		return false
	var old_rect: Rect2 = get_node_rect(index)
	positions[index] = position
	_remove_from_cells(index, old_rect)
	_insert_into_cells(index, get_node_rect(index))
	return true


func hit_test(point: Vector2) -> int:
	var cell: Vector2i = _cell_for_point(point)
	var candidates: Variant = _spatial_cells.get(cell, PackedInt32Array())
	if candidates is not PackedInt32Array:
		return -1
	var packed: PackedInt32Array = candidates as PackedInt32Array
	for offset: int in range(packed.size() - 1, -1, -1):
		var index: int = int(packed[offset])
		var radius: float = get_node_radius(index)
		if positions[index].distance_squared_to(point) <= radius * radius:
			return index
	return -1


func query_rect(rect: Rect2) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var seen: Dictionary = {}
	var min_cell: Vector2i = _cell_for_point(rect.position)
	var max_cell: Vector2i = _cell_for_point(rect.end)
	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var value: Variant = _spatial_cells.get(Vector2i(x, y), PackedInt32Array())
			if value is not PackedInt32Array:
				continue
			for index: int in (value as PackedInt32Array):
				if seen.has(index) or not get_node_rect(index).intersects(rect, true):
					continue
				seen[index] = true
				result.append(index)
	return result


func query_edges_for_nodes(node_indices: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var seen: Dictionary = {}
	for node_index: int in node_indices:
		if node_index < 0 or node_index >= _edge_indices_by_node.size():
			continue
		var edge_indices: PackedInt32Array = _edge_indices_by_node[node_index]
		for edge_index: int in edge_indices:
			if seen.has(edge_index):
				continue
			seen[edge_index] = true
			result.append(edge_index)
	return result


func export_positions() -> Dictionary:
	var result: Dictionary = {}
	for index: int in range(note_ids.size()):
		result[note_ids[index]] = positions[index]
	return result


func rebuild_spatial_index() -> void:
	_rebuild_spatial_index()


func build_reset_layout() -> Dictionary:
	# Deterministic concentric placement with a conservative maximum-node diameter.
	# Ring capacity is computed from chord length, not arc length, so circles from
	# the same or adjacent rings cannot overlap even when high-degree nodes grow to
	# NODE_MAX_RADIUS. This is O(n) and intentionally avoids a live force solver.
	var result: Dictionary = {}
	if note_ids.is_empty():
		return result
	var by_hop: Dictionary = {}
	var has_local_hops: bool = false
	for index: int in range(note_ids.size()):
		var hop: int = get_hop(index)
		if hop >= 0:
			has_local_hops = true
			var bucket: Array = by_hop.get(hop, []) as Array
			bucket.append(index)
			by_hop[hop] = bucket
	if has_local_hops:
		var hops: Array = by_hop.keys()
		hops.sort()
		var previous_radius: float = 0.0
		for raw_hop: Variant in hops:
			var hop: int = int(raw_hop)
			var indices: Array = by_hop[hop] as Array
			if hop == 0:
				for index: int in indices:
					result[note_ids[index]] = Vector2.ZERO
				continue
			var minimum_radius: float = maxf(LAYOUT_RING_STEP * float(hop), previous_radius + LAYOUT_MIN_SPACING)
			var capacity_radius: float = _radius_for_count(indices.size())
			var radius: float = maxf(minimum_radius, capacity_radius)
			_place_ring(result, indices, radius, float(hop) * 0.37)
			previous_radius = radius
		return result
	result[note_ids[0]] = Vector2.ZERO
	var remaining: int = note_ids.size() - 1
	var cursor: int = 1
	var ring: int = 1
	while remaining > 0:
		var radius: float = LAYOUT_RING_STEP * float(ring)
		var capacity: int = mini(remaining, _ring_capacity(radius))
		var indices: Array = []
		for offset: int in range(capacity):
			indices.append(cursor + offset)
		_place_ring(result, indices, radius, float(ring) * 0.38196601125)
		cursor += capacity
		remaining -= capacity
		ring += 1
	return result


func apply_positions(layout: Dictionary) -> void:
	for index: int in range(note_ids.size()):
		var note_id: String = note_ids[index]
		var value: Variant = layout.get(note_id, null)
		if value is Vector2:
			positions[index] = value as Vector2
	_rebuild_spatial_index()


func resolve_non_overlapping_position(index: int, desired: Vector2, gap: float = LAYOUT_NODE_GAP) -> Vector2:
	if index < 0 or index >= positions.size():
		return desired
	if not _position_collides(index, desired, gap):
		return desired
	var step: float = maxf(18.0, get_node_radius(index) + gap * 0.5)
	const GOLDEN_ANGLE: float = 2.399963229728653
	for ring: int in range(1, MAX_COLLISION_RESOLVE_RINGS + 1):
		var samples: int = maxi(8, ring * 8)
		var radius: float = step * float(ring)
		for sample: int in range(samples):
			var angle: float = GOLDEN_ANGLE * float(sample + ring * 3)
			var candidate: Vector2 = desired + Vector2(cos(angle), sin(angle)) * radius
			if not _position_collides(index, candidate, gap):
				return candidate
	# Pathological dense clusters should still never commit an overlapping node.
	# This O(n) fallback is reached only after the bounded spatial search failed:
	# place the node just beyond the right-most occupied circle, which guarantees
	# horizontal separation from every existing node regardless of its Y position.
	return _fallback_non_overlapping_position(index, desired, gap)


func _fallback_non_overlapping_position(index: int, desired: Vector2, gap: float) -> Vector2:
	var right_edge: float = desired.x
	var found_other: bool = false
	for other: int in range(positions.size()):
		if other == index:
			continue
		found_other = true
		right_edge = maxf(right_edge, positions[other].x + get_node_radius(other))
	if not found_other:
		return desired
	return Vector2(right_edge + get_node_radius(index) + maxf(0.0, gap), desired.y)


func _position_collides(index: int, candidate: Vector2, gap: float) -> bool:
	var own_radius: float = get_node_radius(index)
	var query_radius: float = own_radius + NODE_MAX_RADIUS + maxf(0.0, gap)
	var query: Rect2 = Rect2(candidate - Vector2(query_radius, query_radius), Vector2(query_radius * 2.0, query_radius * 2.0))
	for other: int in query_rect(query):
		if other == index:
			continue
		var minimum_distance: float = own_radius + get_node_radius(other) + maxf(0.0, gap)
		if positions[other].distance_squared_to(candidate) < minimum_distance * minimum_distance:
			return true
	return false


func _radius_for_count(count: int) -> float:
	if count <= 1:
		return LAYOUT_RING_STEP
	var denominator: float = 2.0 * sin(PI / float(maxi(2, count)))
	if denominator <= 0.0001:
		return LAYOUT_RING_STEP
	return maxf(LAYOUT_RING_STEP, LAYOUT_MIN_SPACING / denominator)


func _ring_capacity(radius: float) -> int:
	if radius <= LAYOUT_MIN_SPACING * 0.5:
		return 1
	var ratio: float = clampf(LAYOUT_MIN_SPACING / (2.0 * radius), 0.0, 0.999999)
	var angle: float = 2.0 * asin(ratio)
	if angle <= 0.0001:
		return 1
	return maxi(1, int(floor(TAU / angle)))


func _place_ring(result: Dictionary, indices: Array, radius: float, phase: float) -> void:
	if indices.is_empty():
		return
	var count: int = indices.size()
	for offset: int in range(count):
		var angle: float = -PI * 0.5 + phase + TAU * float(offset) / float(count)
		var index: int = indices[offset]
		result[note_ids[index]] = Vector2(cos(angle), sin(angle)) * radius


func _default_position(index: int, count: int, hop: int, hop_index: int, hop_count: int) -> Vector2:
	if hop >= 0:
		if hop == 0:
			return Vector2.ZERO
		var ring_radius: float = 205.0 * float(hop)
		var safe_count: int = maxi(1, hop_count)
		var angle: float = TAU * float(hop_index) / float(safe_count) - PI * 0.5
		# A deterministic sub-ring jitter prevents perfectly rigid circles when a
		# local neighborhood contains many notes, without requiring a live physics
		# simulation or per-frame layout work.
		var jitter: float = 1.0 + 0.08 * sin(float(hop_index) * 2.399963229728653)
		return Vector2(cos(angle), sin(angle)) * ring_radius * jitter
	if count <= 1 or index <= 0:
		return Vector2.ZERO
	# Golden-angle placement is O(n), deterministic and distributes a large global
	# knowledge base without running a force solver on the main thread.
	const GOLDEN_ANGLE: float = 2.399963229728653
	var radius: float = 74.0 * sqrt(float(index))
	var angle: float = float(index) * GOLDEN_ANGLE
	return Vector2(cos(angle), sin(angle)) * radius


func _rebuild_spatial_index() -> void:
	_spatial_cells.clear()
	for index: int in range(note_ids.size()):
		_insert_into_cells(index, get_node_rect(index))


func _insert_into_cells(index: int, rect: Rect2) -> void:
	var min_cell: Vector2i = _cell_for_point(rect.position)
	var max_cell: Vector2i = _cell_for_point(rect.end)
	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var key: Vector2i = Vector2i(x, y)
			var packed: PackedInt32Array = _spatial_cells.get(key, PackedInt32Array()) as PackedInt32Array
			if not packed.has(index):
				packed.append(index)
				_spatial_cells[key] = packed


func _remove_from_cells(index: int, rect: Rect2) -> void:
	var min_cell: Vector2i = _cell_for_point(rect.position)
	var max_cell: Vector2i = _cell_for_point(rect.end)
	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var key: Vector2i = Vector2i(x, y)
			if not _spatial_cells.has(key):
				continue
			var packed: PackedInt32Array = _spatial_cells[key] as PackedInt32Array
			var found: int = packed.find(index)
			if found >= 0:
				packed.remove_at(found)
			if packed.is_empty():
				_spatial_cells.erase(key)
			else:
				_spatial_cells[key] = packed


func _cell_for_point(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / GRID_CELL), floori(point.y / GRID_CELL))
