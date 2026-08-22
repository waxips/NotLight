# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleArtworkLoader
extends RefCounted

const MAX_TEXTURE_EXTENT: int = 2048
const MAX_SOURCE_BYTES: int = 8 * 1024 * 1024


static func load_texture(path: String) -> Texture2D:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty() or not FileAccess.file_exists(clean_path):
		return null
	var file: FileAccess = FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		return null
	var byte_size: int = int(file.get_length())
	if byte_size <= 0 or byte_size > MAX_SOURCE_BYTES:
		file.close()
		return null
	var bytes: PackedByteArray = file.get_buffer(byte_size)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or bytes.size() != byte_size:
		return null

	var image: Image = Image.new()
	var extension: String = clean_path.get_extension().to_lower()
	var load_error: Error = ERR_UNAVAILABLE
	match extension:
		"png":
			load_error = image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			load_error = image.load_jpg_from_buffer(bytes)
		"webp":
			load_error = image.load_webp_from_buffer(bytes)
		"svg":
			load_error = image.load_svg_from_buffer(bytes, 1.0)
		_:
			return null
	if load_error != OK or image.is_empty():
		return null

	var width: int = image.get_width()
	var height: int = image.get_height()
	var maximum: int = maxi(width, height)
	if maximum > MAX_TEXTURE_EXTENT and width > 0 and height > 0:
		var scale: float = float(MAX_TEXTURE_EXTENT) / float(maximum)
		image.resize(
			maxi(1, int(round(float(width) * scale))),
			maxi(1, int(round(float(height) * scale))),
			Image.INTERPOLATE_LANCZOS
		)
	return ImageTexture.create_from_image(image)
