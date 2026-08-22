# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardLiveSurfaceProjection
extends RefCounted

# Live board Controls are expensive when their logical size changes continuously:
# Containers recompute minimum sizes, rich text reshapes, and media/UI surfaces may
# rebuild GPU-backed presentation. Keep their logical resolution in coarse zoom
# buckets and use the Control transform between bucket boundaries.
#
# The bucket range is intentionally bounded. At extreme board zoom we prefer a
# cheap CanvasItem scale over materializing an 8x UI hierarchy or collapsing it to
# a few dozen logical pixels.
const LAYOUT_ZOOM_BASE: float = 1.32
const MIN_LAYOUT_ZOOM: float = 0.50
const MAX_LAYOUT_ZOOM: float = 2.00
const MIN_VIEW_ZOOM: float = 0.01


static func layout_zoom_for(view_zoom: float) -> float:
	var safe_zoom: float = clampf(view_zoom, MIN_VIEW_ZOOM, 64.0)
	var normalized: float = log(safe_zoom) / log(LAYOUT_ZOOM_BASE)
	var bucket: int = int(round(normalized))
	return clampf(pow(LAYOUT_ZOOM_BASE, float(bucket)), MIN_LAYOUT_ZOOM, MAX_LAYOUT_ZOOM)


static func transform_scale_for(view_zoom: float, layout_zoom: float) -> float:
	var safe_layout_zoom: float = maxf(layout_zoom, MIN_VIEW_ZOOM)
	return maxf(view_zoom, MIN_VIEW_ZOOM) / safe_layout_zoom


static func projected_rect(board_view: NativeBoardView, bounds: Rect2) -> Rect2:
	if board_view == null:
		return Rect2()
	var top_left: Vector2 = board_view.world_to_screen(bounds.position)
	var bottom_right: Vector2 = board_view.world_to_screen(bounds.end)
	return Rect2(
		Vector2(minf(top_left.x, bottom_right.x), minf(top_left.y, bottom_right.y)),
		Vector2(absf(bottom_right.x - top_left.x), absf(bottom_right.y - top_left.y))
	)
