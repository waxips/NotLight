# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const TEST_ROOT: String = "user://notlight_stage11_notes_core_smoke"


func _initialize() -> void:
	_delete_directory_recursive(TEST_ROOT)
	var library: AssetLibraryService = AssetLibraryService.new()
	library.name = "SmokeAssetLibrary"
	root.add_child(library)
	_check(library.setup(null, TEST_ROOT), "notes smoke Library setup failed")

	var repository: NoteRepository = NoteRepository.new()
	repository.name = "SmokeNoteRepository"
	root.add_child(repository)
	repository.configure(library)

	_test_markdown_blocks()
	_test_embed_and_cyrillic_markup()
	_test_logical_identity(repository, library)
	_test_relations(repository)
	_test_folder_management(repository)
	_test_portal_persistence(repository)
	_test_graph_model(repository)
	_test_empty_revision(repository)

	_check(repository.flush_pending_saves(), "notes smoke final save flush failed")
	repository.free()
	library.free()
	_delete_directory_recursive(TEST_ROOT)
	print("NotLight Stage 11.8 Notes core smoke test passed.")
	quit(0)


func _test_markdown_blocks() -> void:
	var markdown: String = "---\r\ntags: [alpha, beta]\r\nstatus: draft\r\n---\r\n# Heading\r\n\r\nParagraph"
	var blocks: Array[Dictionary] = NoteMarkdownBlocks.parse(markdown)
	_check(blocks.size() >= 3, "Markdown block parser omitted front matter/body blocks")
	_check(StringName(str(blocks[0].get("type", ""))) == NoteMarkdownBlocks.TYPE_FRONTMATTER, "front matter was misclassified as a thematic break")
	_check(str(blocks[0].get("raw", "")).contains("\r\n"), "front matter source span did not preserve CRLF bytes")
	_check(StringName(str(blocks[1].get("type", ""))) == NoteMarkdownBlocks.TYPE_HEADING, "heading after front matter was not parsed")
	var math_blocks: Array[Dictionary] = NoteMarkdownBlocks.parse("$$\nx^2 + y^2 = z^2\n$$")
	_check(math_blocks.size() == 1 and StringName(str(math_blocks[0].get("type", ""))) == NoteMarkdownBlocks.TYPE_MATH, "block LaTeX was not classified as a math block")
	var board_preview: Array[Dictionary] = NoteBoardPreviewExtractor.extract("# H\n\n```gdscript\nvar value: int = 1\n```\n\n$$x^2$$")
	var preview_kinds: Dictionary = {}
	for run: Dictionary in board_preview:
		preview_kinds[str(run.get("kind", ""))] = true
	_check(preview_kinds.has("heading") and preview_kinds.has("code") and preview_kinds.has("math"), "retained board preview omitted structured Markdown runs")
	var escaped_links: PackedStringArray = NoteLinkParser.extract_wikilink_targets("`[[Code]]` \\[[Escaped]] [[Real|Alias]]")
	_check(escaped_links.size() == 1 and escaped_links[0] == "Real", "wiki-link parser did not ignore code/escaped links")


func _test_embed_and_cyrillic_markup() -> void:
	var cyrillic: String = "**Жирный текст** *Курсивный текст* ***Жирный курсив***"
	var bbcode: String = NoteInlineMarkup.to_bbcode(cyrillic)
	_check(bbcode.contains("[b]Жирный текст[/b]"), "Cyrillic strong Markdown was not preserved in BBCode")
	_check(bbcode.contains("[i]Курсивный текст[/i]"), "Cyrillic emphasis Markdown was not preserved in BBCode")
	_check(bbcode.contains("[b][i]Жирный курсив[/i][/b]"), "Cyrillic combined emphasis was not preserved in BBCode")
	var hash_sha256: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var syntax: String = NoteResourceEmbed.syntax_for_hash(hash_sha256, "Тестовый ресурс")
	_check(not syntax.is_empty(), "resource embed syntax generation failed")
	var parsed: Dictionary = NoteResourceEmbed.parse_exact(syntax)
	_check(str(parsed.get("hash_sha256", "")) == hash_sha256, "resource embed SHA-256 did not roundtrip")
	_check(str(parsed.get("caption", "")) == "Тестовый ресурс", "resource embed Cyrillic caption did not roundtrip")
	var blocks: Array[Dictionary] = NoteMarkdownBlocks.parse(syntax)
	_check(blocks.size() == 1 and StringName(str(blocks[0].get("type", ""))) == NoteMarkdownBlocks.TYPE_EMBED, "standalone resource embed was not parsed as its own block")
	var links: PackedStringArray = NoteLinkParser.extract_wikilink_targets("%s [[Настоящая заметка]]" % syntax)
	_check(links.size() == 1 and links[0] == "Настоящая заметка", "resource embed polluted wiki-link graph semantics")
	var ignored: PackedStringArray = NoteResourceEmbed.extract_hashes("```text\n%s\n```\n`%s`" % [syntax, syntax])
	_check(ignored.is_empty(), "resource embed parser activated inside fenced/inline code")



func _test_logical_identity(repository: NoteRepository, library: AssetLibraryService) -> void:
	var first_id: String = repository.create_note("Same bytes A", "identical canonical markdown")
	var second_id: String = repository.create_note("Same bytes B", "identical canonical markdown")
	_check(not first_id.is_empty() and not second_id.is_empty(), "same-content note creation failed")
	_check(first_id != second_id, "same-content notes collapsed their logical IDs")
	var first: Dictionary = repository.get_note(first_id)
	var second: Dictionary = repository.get_note(second_id)
	_check(str(first.get("hash_sha256", "")) == str(second.get("hash_sha256", "")), "same-content notes do not share the expected content hash")
	_check(str(first.get("blob_relpath", "")) == str(second.get("blob_relpath", "")), "same-content notes did not physically deduplicate their blob")
	_check(library.catalog.find_asset_by_hash(str(first.get("hash_sha256", ""))).is_empty(), "Note SHA unexpectedly became a logical-asset identity")


func _test_relations(repository: NoteRepository) -> void:
	var target_a: String = repository.create_note("Target", "A")
	var target_b: String = repository.create_note("Target", "B")
	var source: String = repository.create_note("Source", "See [[Target]].")
	_check(not target_a.is_empty() and not target_b.is_empty() and not source.is_empty(), "relation note creation failed")
	_check(repository.resolve_title("Target").is_empty(), "ambiguous wiki title was guessed instead of rejected")
	_check(repository.get_outgoing_links(source).is_empty(), "ambiguous textual link resolved unexpectedly")

	_check(repository.rename_note(target_b, "Target 2"), "relation target rename failed")
	_check(repository.resolve_title("Target") == target_a, "unique title did not resolve after ambiguity was removed")
	var textual: PackedStringArray = repository.get_outgoing_links(source)
	_check(textual.size() == 1 and textual[0] == target_a, "textual wiki relation was not rebuilt after title rename")

	_check(repository.add_explicit_link(source, target_b), "explicit graph relation create failed")
	var combined: PackedStringArray = repository.get_outgoing_links(source)
	_check(combined.has(target_a) and combined.has(target_b) and combined.size() == 2, "textual and explicit relations were not unioned")
	_check(repository.get_backlinks(target_b).has(source), "explicit relation backlink was not indexed")
	_check(not repository.add_explicit_link(source, source), "self relation was accepted")
	_check(repository.remove_explicit_link(source, target_b), "explicit graph relation delete failed")
	var after_remove: PackedStringArray = repository.get_outgoing_links(source)
	_check(after_remove.size() == 1 and after_remove[0] == target_a, "removing explicit relation damaged textual relation semantics")

	var alias_target: String = repository.create_note("Alias Original", "alias payload")
	var alias_source: String = repository.create_note("Alias Source", "[[Alias Original]]")
	_check(repository.get_outgoing_links(alias_source).has(alias_target), "baseline alias relation did not resolve")
	_check(repository.rename_note(alias_target, "Alias Renamed"), "unique relation target rename failed")
	_check(repository.resolve_title("Alias Original") == alias_target, "historical title alias did not preserve a wiki relation after rename")
	_check(repository.get_outgoing_links(alias_source).has(alias_target), "wiki relation was lost after its unique target was renamed")


func _test_folder_management(repository: NoteRepository) -> void:
	var parent_id: String = repository.create_folder("Smoke Parent")
	_check(not parent_id.is_empty(), "notes smoke folder creation failed")
	var child_id: String = repository.create_folder("Smoke Child", parent_id)
	_check(not child_id.is_empty(), "notes smoke nested folder creation failed")
	var note_id: String = repository.create_note("Folder note", "folder payload", child_id)
	_check(not note_id.is_empty(), "notes smoke note creation inside folder failed")
	_check(str(repository.get_note(note_id).get("folder_id", "")) == child_id, "note did not retain folder identity")
	_check(repository.rename_folder(child_id, "Smoke Child Renamed"), "notes smoke folder rename failed")
	_check(repository.move_note(note_id, parent_id), "notes smoke note move failed")
	_check(repository.delete_folder(child_id), "empty nested folder delete failed")



func _test_portal_persistence(repository: NoteRepository) -> void:
	var note_id: String = repository.create_note("Portal target", "portal payload")
	_check(not note_id.is_empty(), "portal target creation failed")
	var runtime: BoardRuntime = BoardRuntime.new()
	var command: CreateNotePortalCommand = CreateNotePortalCommand.new(Rect2(120.0, 80.0, 360.0, 240.0), note_id)
	_check(command.execute(runtime), "NotePortal command execute failed")
	var portal_id: int = command.created_entity_id
	_check(portal_id > 0 and runtime.model.note_portals.contains(portal_id), "NotePortal store record is missing")
	_check(runtime.model.note_portals.get_note_id(portal_id) == note_id, "NotePortal does not point at canonical note ID")
	var document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	var refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	_check(refs.has(note_id), "NotePortal asset_id was not collected as a board resource reference")
	var content: Dictionary = document.get("content", {}) as Dictionary
	var portal_records: Array = content.get("note_portals", []) as Array
	_check(portal_records.size() == 1 and str((portal_records[0] as Dictionary).get("asset_id", "")) == note_id, "NotePortal did not serialize canonical asset_id")
	var tab_note_id: String = repository.create_note("Workspace second tab", "second tab")
	_check(not tab_note_id.is_empty(), "workspace tab target creation failed")
	runtime.model.note_portals.set_view_mode(portal_id, NotePortalStore.VIEW_WORKSPACE)
	_check(runtime.model.note_portals.set_workspace_state(portal_id, PackedStringArray([note_id, tab_note_id]), 1), "workspace tab state update failed")
	var workspace_document: Dictionary = runtime.write_document(BoardDocumentSchema.make_empty())
	var workspace_refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(workspace_document)
	_check(workspace_refs.has(note_id) and workspace_refs.has(tab_note_id), "workspace tabs were not collected as board resource references")
	var workspace_record: Dictionary = runtime.model.note_portals.get_record(portal_id)
	var serialized_tabs: Array = workspace_record.get("workspace_tabs", []) as Array
	_check(serialized_tabs.size() == 2 and str(serialized_tabs[1]) == tab_note_id, "workspace tabs did not serialize in stable order")
	_check(command.undo(runtime), "NotePortal command undo failed")
	_check(not runtime.model.note_portals.contains(portal_id), "NotePortal record survived undo")
	_check(repository.contains(note_id), "removing a portal deleted the canonical note")
	_check(command.execute(runtime), "NotePortal command redo-style execute failed")
	_check(runtime.model.note_portals.get_note_id(command.created_entity_id) == note_id, "restored NotePortal changed note identity")


func _test_graph_model(repository: NoteRepository) -> void:
	var alpha: String = repository.create_note("Graph Alpha", "[[Graph Beta]]")
	var beta: String = repository.create_note("Graph Beta", "[[Graph Gamma]]")
	var gamma: String = repository.create_note("Graph Gamma", "[[Graph Delta]]")
	var delta: String = repository.create_note("Graph Delta", "[[Graph Epsilon]]")
	var epsilon: String = repository.create_note("Graph Epsilon", "Epsilon")
	_check(not alpha.is_empty() and not beta.is_empty() and not gamma.is_empty() and not delta.is_empty() and not epsilon.is_empty(), "graph note creation failed")
	_check(repository.add_explicit_link(alpha, beta), "graph explicit overlay relation failed")
	var snapshot: Dictionary = repository.relation_snapshot()
	var model: NotesGraphModel = NotesGraphModel.new()
	model.rebuild(snapshot)
	_check(model.get_index(alpha) >= 0 and model.get_index(beta) >= 0, "native graph model omitted known notes")
	var alpha_index: int = model.get_index(alpha)
	var visible: PackedInt32Array = PackedInt32Array([alpha_index])
	var candidate_edges: PackedInt32Array = model.query_edges_for_nodes(visible)
	_check(not candidate_edges.is_empty(), "native graph adjacency query missed a visible relation")
	var matched_both: bool = false
	for edge_index: int in candidate_edges:
		if edge_index < 0 or edge_index >= model.edge_count():
			continue
		var source_index: int = int(model.source_indices[edge_index])
		var target_index: int = int(model.target_indices[edge_index])
		if model.get_note_id(source_index) == alpha and model.get_note_id(target_index) == beta:
			var flags: int = int(model.edge_flags[edge_index])
			matched_both = (flags & NotesGraphModel.EDGE_TEXTUAL) != 0 and (flags & NotesGraphModel.EDGE_EXPLICIT) != 0
			break
	_check(matched_both, "native graph did not preserve textual+explicit edge provenance")
	var relation_counts: Dictionary = model.relation_counts()
	_check(int(relation_counts.get("textual", 0)) == 4, "native graph textual relation count mixed provenance incorrectly")
	_check(int(relation_counts.get("explicit", 0)) == 1, "native graph explicit relation count mixed provenance incorrectly")
	_check(int(relation_counts.get("mixed", 0)) == 1, "native graph mixed-provenance diagnostic count is incorrect")
	_check(model.edge_count() == 4, "native graph visual edge count changed while splitting provenance statistics")

	var local: Dictionary = repository.local_relation_snapshot(alpha, 3, 128)
	var local_nodes: Array = local.get("nodes", []) as Array
	var local_ids: Dictionary = {}
	var maximum_hop: int = 0
	for raw_node: Variant in local_nodes:
		if raw_node is not Dictionary:
			continue
		var node: Dictionary = raw_node as Dictionary
		local_ids[str(node.get("id", ""))] = true
		maximum_hop = maxi(maximum_hop, int(node.get("hop", 0)))
	_check(local_ids.has(alpha), "local graph omitted the center note")
	_check(local_ids.has(delta), "local graph omitted a note at three hops")
	_check(not local_ids.has(epsilon), "local graph included a note beyond three hops")
	_check(maximum_hop <= 3, "local graph exceeded the requested three-hop depth")
	var local_model: NotesGraphModel = NotesGraphModel.new()
	local_model.rebuild(local)
	_check(local_model.get_hop(local_model.get_index(alpha)) == 0, "local graph center hop metadata is invalid")

	var reset_layout: Dictionary = model.build_reset_layout()
	_check(reset_layout.size() == model.size(), "graph reset layout omitted nodes")
	model.apply_positions(reset_layout)
	for left: int in range(model.size()):
		for right: int in range(left + 1, model.size()):
			var minimum_distance: float = model.get_node_radius(left) + model.get_node_radius(right) + NotesGraphModel.LAYOUT_NODE_GAP
			_check(
				model.positions[left].distance_squared_to(model.positions[right]) + 0.001 >= minimum_distance * minimum_distance,
				"graph reset layout allowed node circles to overlap"
			)


func _test_empty_revision(repository: NoteRepository) -> void:
	var empty_initial_id: String = repository.create_note("Empty initial", "")
	_check(not empty_initial_id.is_empty(), "empty initial Markdown note creation failed")
	var empty_initial: Dictionary = repository.get_note(empty_initial_id)
	_check(int(empty_initial.get("byte_size", -1)) == 0, "empty initial Markdown note was not stored as zero bytes")
	_check(str(empty_initial.get("hash_sha256", "")) == _sha256(PackedByteArray()), "empty initial Markdown SHA-256 mismatch")
	var note_id: String = repository.create_note("Empty revision", "non-empty")
	_check(not note_id.is_empty(), "empty revision note creation failed")
	_check(repository.request_save(note_id, ""), "empty Markdown revision was rejected")
	_check(repository.flush_pending_saves(), "empty Markdown revision flush failed")
	var note: Dictionary = repository.get_note(note_id)
	_check(int(note.get("byte_size", -1)) == 0, "empty Markdown revision did not commit as zero bytes")
	_check(str(note.get("hash_sha256", "")) == _sha256(PackedByteArray()), "empty Markdown revision SHA-256 mismatch")
	_check(repository.read_content(note_id).is_empty(), "empty Markdown revision did not roundtrip")
	_check(repository.get_last_error().is_empty(), "reading valid empty Markdown incorrectly reported an error")


func _sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	_check(context.start(HashingContext.HASH_SHA256) == OK, "notes smoke SHA-256 start failed")
	if not bytes.is_empty():
		_check(context.update(bytes) == OK, "notes smoke SHA-256 update failed")
	var digest: PackedByteArray = context.finish()
	_check(digest.size() == 32, "notes smoke SHA-256 digest size mismatch")
	return digest.hex_encode()


func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.current_is_dir():
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				if directory.remove(entry) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
