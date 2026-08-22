<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# PDF Support Architecture

NotLight treats PDF files as Resource Library assets and renders board PDF objects through a centralized media service. PDF processing is local and uses external sidecar tools rather than embedding a second PDF engine into the Godot PCK.

## Runtime components

- `PdfMediaService` owns PDF document metadata, page requests, render caching, and preferred durable variants.
- `PopplerTools` locates the bundled `pdfinfo` and `pdftoppm` utilities.
- `PdfRenderWorker` performs bounded page rasterization work outside the main UI path.
- `PdfBatchRenderer` draws PDF entities on the board.
- `PdfOptimizationService` optionally creates an optimized durable variant through qpdf.
- `QpdfTools` exposes the pinned qpdf sidecar using fixed command construction.

The Windows runtime provenance and licenses for Poppler and qpdf are documented in `tools/poppler/SOURCE_INFO.md`, `tools/qpdf/SOURCE_INFO.md`, and `THIRD_PARTY_NOTICES.md`.

## Import and identity

A PDF enters the application through the Resource Library. Board objects store the stable asset ID rather than depending on an arbitrary external path. PDF object state is kept in `PdfStore`, including the selected page and document information needed for rendering.

## Rendering

`PdfMediaService` probes documents with `pdfinfo` and requests rasterized pages from `pdftoppm`. Rendered pages are cached and selected by requested display extent. The service imposes memory/upload budgets and keeps sidecar work away from the main UI path.

The original imported PDF remains the canonical source asset. Rendering may use a preferred durable variant when one has been explicitly created and validated.

## Optional qpdf optimization

qpdf optimization is intentionally conservative. `PdfOptimizationService` stages the operation, validates the source, runs qpdf with bounded/cancellable execution, validates the result, probes/renders the candidate, and only then registers an optimized durable variant.

The optimization workflow does not expose an operation that deletes the original PDF. The user can switch between the original and an accepted optimized variant without losing the canonical source asset.

NotLight's release package intentionally ships only `qpdf.exe` and `qpdf30.dll` from the pinned qpdf package. Microsoft VC runtime DLL copies from that archive are not redistributed; the supported Microsoft Visual C++ Redistributable x64 is a Windows prerequisite.

## Portable packages

Portable board/library exchange preserves asset identity and registered durable variants through the central durable-variant registry. Imported packages are validated before payload materialization.

## Release requirements

The Windows export must include the Poppler/qpdf sidecars and their required notices outside the PCK. Before public redistribution, follow `RELEASE_COMPLIANCE.md` and `CORRESPONDING_SOURCE.md`, especially the source-delivery requirement for the GPL-covered Poppler runtime.
