# SPDX-License-Identifier: GPL-3.0-or-later
class_name PdfDocumentProbe
extends RefCounted


static func parse_pdfinfo(output: String, poppler_version: String = "") -> Dictionary:
	var page_count: int = 0
	var width_points: float = 595.0
	var height_points: float = 842.0
	var encrypted: bool = false
	for raw_line: String in output.split("\n", false):
		var line: String = raw_line.strip_edges()
		if line.begins_with("Pages:"):
			page_count = maxi(0, int(line.get_slice(":", 1).strip_edges()))
		elif line.begins_with("Page size:"):
			var size_text: String = line.get_slice(":", 1).strip_edges()
			var tokens: PackedStringArray = size_text.split(" ", false)
			for index: int in range(tokens.size()):
				if tokens[index] == "x" and index > 0 and index + 1 < tokens.size():
					width_points = maxf(1.0, float(tokens[index - 1]))
					height_points = maxf(1.0, float(tokens[index + 1]))
					break
		elif line.begins_with("Encrypted:"):
			encrypted = line.get_slice(":", 1).strip_edges().to_lower().begins_with("yes")
	if page_count <= 0:
		return {"ok": false, "error": NotLightL10n.text("pdf.error.metadata")}
	return {
		"ok": true,
		"page_count": page_count,
		"page_width_points": width_points,
		"page_height_points": height_points,
		"page_size": Vector2i(maxi(1, int(round(width_points))), maxi(1, int(round(height_points)))),
		"encrypted": encrypted,
		"poppler_version": poppler_version,
	}
