# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree


func _initialize() -> void:
	_test_qpdf_contract()
	_test_hash_worker_contract()
	_test_pdf_probe()
	_test_durable_variant_registry()
	print("NotLight Stage 9.6 PDF optimization static/runtime smoke test passed.")
	quit(0)


func _test_qpdf_contract() -> void:
	_check(QpdfTools.BUNDLED_VERSION == "12.4.0", "qpdf version pin drifted")
	_check(QpdfTools.EXPECTED_ARCHIVE_NAME == "qpdf-12.4.0-msvc64.zip", "qpdf archive pin drifted")
	_check(
		QpdfTools.EXPECTED_ARCHIVE_SHA256 == "5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72",
		"qpdf archive SHA-256 pin drifted"
	)
	var version_output: String = "qpdf version 12.4.0\nRun qpdf --copyright for copyright and license information.\n"
	_check(QpdfTools.parse_version_value(version_output) == "12.4.0", "qpdf version parsing failed")
	_check(QpdfTools.bundled_version_matches(version_output), "pinned qpdf version was rejected")
	_check(not QpdfTools.bundled_version_matches("qpdf version 12.3.0"), "wrong qpdf version was accepted")

	var source_path: String = "user://source with spaces.pdf"
	var output_path: String = "user://optimized with spaces.pdf"
	var lossless: PackedStringArray = QpdfTools.optimize_arguments(source_path, output_path, QpdfTools.PRESET_LOSSLESS)
	_check(lossless.size() >= 7, "lossless qpdf argument list is incomplete")
	_check(lossless.has("--compress-streams=y"), "lossless preset lost stream compression")
	_check(lossless.has("--decode-level=generalized"), "lossless preset lost decode level")
	_check(lossless.has("--recompress-flate"), "lossless preset lost Flate recompression")
	_check(lossless.has("--compression-level=9"), "lossless preset lost compression level")
	_check(lossless.has("--object-streams=generate"), "lossless preset lost object streams")
	_check(not lossless.has("--optimize-images"), "lossless preset unexpectedly became lossy")
	_check(not lossless.has("--jpeg-quality=90"), "lossless preset unexpectedly sets JPEG quality")

	var balanced: PackedStringArray = QpdfTools.optimize_arguments(source_path, output_path, QpdfTools.PRESET_BALANCED)
	_check(balanced.has("--optimize-images"), "balanced preset lost image optimization")
	_check(balanced.has("--jpeg-quality=90"), "balanced preset lost JPEG quality pin")
	_check(QpdfTools.preset_is_lossy(QpdfTools.PRESET_BALANCED), "balanced preset must be marked lossy")
	_check(not QpdfTools.preset_is_lossy(QpdfTools.PRESET_LOSSLESS), "lossless preset must not be marked lossy")


func _test_hash_worker_contract() -> void:
	_check(FileHashWorker.MAX_PENDING_JOBS == 4, "SHA-256 worker queue bound drifted")
	_check(FileHashWorker.HASH_CHUNK_BYTES == 4 * 1024 * 1024, "SHA-256 worker chunk size drifted")


func _test_pdf_probe() -> void:
	var sample: String = "Pages:          12\nPage size:      595.276 x 841.89 pts (A4)\nEncrypted:      no\n"
	var parsed: Dictionary = PdfDocumentProbe.parse_pdfinfo(sample, "poppler-test")
	_check(bool(parsed.get("ok", false)), "pdfinfo parser rejected a valid sample")
	_check(int(parsed.get("page_count", 0)) == 12, "pdfinfo parser lost page count")
	_check(not bool(parsed.get("encrypted", true)), "pdfinfo parser misread encryption state")
	_check(str(parsed.get("poppler_version", "")) == "poppler-test", "pdfinfo parser lost backend provenance")
	var page_size: Vector2i = parsed.get("page_size", Vector2i.ZERO) as Vector2i
	_check(page_size.x > 0 and page_size.y > 0, "pdfinfo parser produced an invalid page size")

	var encrypted: Dictionary = PdfDocumentProbe.parse_pdfinfo("Pages: 1\nEncrypted: yes (print:no copy:no)\n", "")
	_check(bool(encrypted.get("ok", false)), "encrypted pdfinfo sample should still parse structurally")
	_check(bool(encrypted.get("encrypted", false)), "pdfinfo parser failed to mark encryption")


func _test_durable_variant_registry() -> void:
	_check(AssetDurableVariants.SUPPORTED_NAMESPACES.has("pdf"), "PDF durable namespace is not registered")
	_check(AssetDurableVariants.namespace_for_kind(AssetKinds.PDF) == "pdf", "PDF kind mapping is wrong")
	var asset: Dictionary = {
		"kind": AssetKinds.PDF,
		"blob_relpath": "blobs/aa/original.pdf",
		"metadata": {
			"pdf": {
				"variants": {
					"original": {"blob_relpath": "blobs/aa/original.pdf"},
					"optimized": {"blob_relpath": "blobs/bb/optimized.pdf"},
				},
			},
		},
	}
	var relpaths: PackedStringArray = AssetDurableVariants.blob_relpaths(asset)
	_check(relpaths.size() == 2, "durable blob registry did not deduplicate primary/original")
	_check(relpaths.has("blobs/aa/original.pdf"), "durable blob registry lost original")
	_check(relpaths.has("blobs/bb/optimized.pdf"), "durable blob registry lost optimized PDF")


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
