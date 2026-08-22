# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardRenderPolicy
extends RefCounted

enum LodLevel {
	FULL,
	MEDIUM,
	LOW,
	PLACEHOLDER,
}

const DEFAULT_WORLD_MARGIN: float = 240.0
const LOD_HYSTERESIS_RATIO: float = 0.08

var world_margin: float = DEFAULT_WORLD_MARGIN
var max_visible_text_blocks: int = 12000
var max_visible_text_previews: int = 2400
var max_visible_connectors: int = 4000
var max_visible_connector_segments: int = 120000
var max_text_lines_per_block: int = 14
var max_visible_images: int = 1200
var max_visible_videos: int = 240
var max_visible_audios: int = 480
var max_visible_pdf_pages: int = 300
var max_visible_formulas: int = 1200
var max_visible_note_portals: int = 2400
var max_visible_stroke_segments: int = 160000
# Drawing quality is intentionally independent from object count. It controls
# how densely pointer samples are retained and how much spray detail is built.
var stroke_smoothing_steps: int = 3
var stroke_input_spacing_scale: float = 1.0
var spray_density: float = 0.85
var max_spray_particles_per_stroke: int = 1400
var spray_preview_particles: int = 110
var max_rebuilds_per_frame: int = 12
var max_image_uploads_per_frame: int = 3
var max_pdf_uploads_per_frame: int = 2
var max_texture_memory_mb: int = 512


func lod_for_zoom(zoom: float) -> LodLevel:
	if zoom >= 0.7:
		return LodLevel.FULL
	if zoom >= 0.28:
		return LodLevel.MEDIUM
	if zoom >= 0.10:
		return LodLevel.LOW
	return LodLevel.PLACEHOLDER


func lod_for_zoom_hysteretic(zoom: float, previous_lod: int) -> LodLevel:
	var candidate: LodLevel = lod_for_zoom(zoom)
	if previous_lod < int(LodLevel.FULL) or previous_lod > int(LodLevel.PLACEHOLDER):
		return candidate
	if int(candidate) == previous_lod:
		return candidate
	var enter_scale: float = 1.0 + LOD_HYSTERESIS_RATIO
	var leave_scale: float = 1.0 - LOD_HYSTERESIS_RATIO
	match previous_lod:
		LodLevel.FULL:
			return candidate if zoom < 0.7 * leave_scale else LodLevel.FULL
		LodLevel.MEDIUM:
			if zoom >= 0.7 * enter_scale or zoom < 0.28 * leave_scale:
				return candidate
			return LodLevel.MEDIUM
		LodLevel.LOW:
			if zoom >= 0.28 * enter_scale or zoom < 0.10 * leave_scale:
				return candidate
			return LodLevel.LOW
		_:
			return candidate if zoom >= 0.10 * enter_scale else LodLevel.PLACEHOLDER


func visible_world_rect(camera_position: Vector2, viewport_size: Vector2, zoom: float) -> Rect2:
	var safe_zoom: float = maxf(zoom, 0.001)
	var world_size: Vector2 = viewport_size / safe_zoom
	return Rect2(camera_position - world_size * 0.5, world_size).grow(world_margin / safe_zoom)


func serialize() -> Dictionary:
	return {
		"world_margin": world_margin,
		"max_visible_text_blocks": max_visible_text_blocks,
		"max_visible_text_previews": max_visible_text_previews,
		"max_text_lines_per_block": max_text_lines_per_block,
		"max_visible_connectors": max_visible_connectors,
		"max_visible_connector_segments": max_visible_connector_segments,
		"max_visible_images": max_visible_images,
		"max_visible_videos": max_visible_videos,
		"max_visible_audios": max_visible_audios,
		"max_visible_pdf_pages": max_visible_pdf_pages,
		"max_visible_formulas": max_visible_formulas,
		"max_visible_note_portals": max_visible_note_portals,
		"max_visible_stroke_segments": max_visible_stroke_segments,
		"stroke_smoothing_steps": stroke_smoothing_steps,
		"stroke_input_spacing_scale": stroke_input_spacing_scale,
		"spray_density": spray_density,
		"max_spray_particles_per_stroke": max_spray_particles_per_stroke,
		"spray_preview_particles": spray_preview_particles,
		"max_rebuilds_per_frame": max_rebuilds_per_frame,
		"max_image_uploads_per_frame": max_image_uploads_per_frame,
		"max_pdf_uploads_per_frame": max_pdf_uploads_per_frame,
		"max_texture_memory_mb": max_texture_memory_mb,
	}
