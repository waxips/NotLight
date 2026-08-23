#!/usr/bin/env python3
"""Static validation for NotLight Stage 9.7.4 runtime hardening + FormulaObject/Typst/MiTeX.

This does not replace the Godot parser. It verifies repository boundaries,
resource paths, SVG/XML assets, license headers, global class uniqueness,
strict declarations, public API names, DOD board contracts, centralized
settings/localization/theme services, performance telemetry, the global
content-addressed Asset Library, PDF optimization and safe import boundaries.
"""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".gd", ".tscn", ".godot", ".md", ".svg"}
TEXT_INTEGRITY_SUFFIXES = {".gd", ".gdshader", ".tscn", ".tres", ".godot", ".md", ".svg", ".json", ".txt", ".cfg", ".toml", ".ps1", ".py", ".cs", ".typ"}
RESOURCE_RE = re.compile(r'res://[^\s"\')\]]+')
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", re.MULTILINE)
INFERRED_DECLARATION_RE = re.compile(r"^\s*(?:@onready\s+)?(?:var|const)\s+[A-Za-z_][A-Za-z0-9_]*\s*:=")
UNTYPED_DECLARATION_RE = re.compile(r"^\s*(?:@onready\s+)?(?:var|const)\s+[A-Za-z_][A-Za-z0-9_]*\s*=")
SHADOWED_GLOBAL_DECLARATION_RE = re.compile(
    r"^\s*(?:@onready\s+)?(?:var|const)\s+"
    r"(range|str|len|type|typeof|print|load|preload|abs|min|max|round|floor|ceil|pow|sqrt|log|exp|clamp|lerp)\s*:"
)
FORBIDDEN_RUNTIME_TERMS = ("GraphEdit", "GraphNode", "NodeCardRenderer", "ConnectionStore")

# Exact reserved identifiers emitted by the Godot 4.4.1-stable GDScript tokenizer.
# Keep hidden tokenizer-reserved words such as namespace/trait/void/when/yield here
# even if a language-reference keyword table omits them.
GODOT_441_RESERVED_IDENTIFIERS = {
    "and",
    "as",
    "assert",
    "await",
    "break",
    "breakpoint",
    "class",
    "class_name",
    "const",
    "continue",
    "elif",
    "else",
    "enum",
    "extends",
    "false",
    "for",
    "func",
    "if",
    "in",
    "INF",
    "is",
    "match",
    "NAN",
    "namespace",
    "not",
    "null",
    "or",
    "pass",
    "PI",
    "preload",
    "return",
    "self",
    "signal",
    "static",
    "super",
    "TAU",
    "trait",
    "true",
    "var",
    "void",
    "when",
    "while",
    "yield",
}
DECLARED_IDENTIFIER_PATTERNS = (
    ("variable", re.compile(r"^\s*(?:@onready\s+)?(?:var|const)\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
    ("loop variable", re.compile(r"^\s*for\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
    ("function", re.compile(r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
    ("signal", re.compile(r"^\s*signal\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
    ("class_name", re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
)

# Godot 4.4 compatibility guards for mistakes that are easy to miss in a
# pure text validator but have already caused runtime/parser failures.
GODOT_44_FORBIDDEN_CALLS = {
    ".set_item_hidden(": "PopupMenu.set_item_hidden() does not exist in Godot 4.4; rebuild/remove menu items instead",
}
PACKED_CONST_CONSTRUCTOR_RE = re.compile(
    r"^\s*const\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*(Packed[A-Za-z0-9_]+Array)\s*=\s*\1\(",
    re.MULTILINE,
)
PACKED_ARRAY_VARIABLE_RE = re.compile(
    r"^\s*(?:@onready\s+)?(?:var|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Packed[A-Za-z0-9_]+Array\b",
    re.MULTILINE,
)
SLIDER_VARIABLE_RE = re.compile(
    r"^\s*(?:@onready\s+)?(?:var|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:HSlider|VSlider|Slider)\b",
    re.MULTILINE,
)
BOARD_COMMAND_SUPER_INIT_RE = re.compile(r"^\s*super\s*\(", re.MULTILINE)
BOARD_ENTITY_TYPE_CONST_RE = re.compile(
    r"^const\s+([A-Z][A-Z0-9_]*)\s*(?::[^=]+)?=", re.MULTILINE
)
BOARD_ENTITY_TYPE_USE_RE = re.compile(r"\bBoardEntityTypes\.([A-Z][A-Z0-9_]*)\b")
PROJECT_CLASS_CONSTANT_USE_RE = re.compile(
    r"\b([A-Z][A-Za-z0-9_]*)\.([A-Z][A-Z0-9_]*)\b"
)
ENUM_BLOCK_RE = re.compile(r"^enum(?:\s+[A-Za-z_][A-Za-z0-9_]*)?\s*\{([^}]*)\}", re.MULTILINE | re.DOTALL)
GET_ENTITY_TYPE_INT_ASSIGN_RE = re.compile(
    r"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*int\s*=.*\bget_entity_type\s*\(",
    re.MULTILINE,
)
STROKE_POPOVER_WRONG_PRESET_RE = re.compile(
    r"DrawingToolPalette\.QUICK_COLORS\s*\)", re.MULTILINE
)
STROKE_PAYLOAD_MISINDENT_RE = re.compile(
    r'^\tstorage\["stroke_payload"\] = payload_filename\n\telse:', re.MULTILINE
)
REQUIRED_CLASSES = {
    "AppSettingsStore",
    "LocalizationRuntimeService",
    "NotLightL10n",
    "NotLightCoreRuFallback",
    "BoardCommandHistory",
    "BoardDocumentSchema",
    "BoardEntityRegistry",
    "BoardGridRenderer",
    "BoardHitTestSystem",
    "BoardModel",
    "BoardRenderPolicy",
    "BoardRuntime",
    "BoardSelectionState",
    "BoardStoreRegistry",
    "BoardToolController",
    "BoardTransformStore",
    "StrokeGeometry",
    "StrokeStore",
    "StrokeBatchRenderer",
    "CreateStrokeCommand",
    "UpdateStrokeStyleCommand",
    "DrawingToolPalette",
    "StrokeContextToolbar",
    "DeveloperDiagnosticsPanel",
    "ChunkSpatialIndex",
    "CreateEntityCommand",
    "CreateTextBlockCommand",
    "DeleteEntitiesCommand",
    "EditTextBlockCommand",
    "EntityIdAllocator",
    "NativeBoardView",
    "TextBlockBatchRenderer",
    "TextBlockRenderWorker",
    "TextBlockStore",
    "TextContextToolbar",
    "TextLayoutUtils",
    "TextFontRegistry",
    "ConnectorStore",
    "ConnectorGeometry",
    "ConnectorBatchRenderer",
    "CreateConnectorCommand",
    "BoardClipboardService",
    "PasteBoardObjectsCommand",
    "TransformEntitiesCommand",
    "UpdateTextPropertiesCommand",
    "UpdateConnectorCommand",
    "BoardColorPopover",
    "ConnectorContextToolbar",
    "AssetKinds",
    "AssetImportCapabilities",
    "AssetImportContentValidator",
    "ImportCandidateResult",
    "AssetImportValidationWorker",
    "AssetImportStagingWorker",
    "AssetImportPreflightService",
    "AssetImportPreflightDialog",
    "AssetId",
    "AssetCatalog",
    "AssetBlobStore",
    "AssetReferenceIndex",
    "AssetImportPipeline",
    "AssetLibraryService",
    "AssetLibraryCard",
    "AssetFolderPickerDialog",
    "AssetLibraryView",
    "AssetPreviewOverlay",
    "BoardExportOptionsDialog",
    "ImageStore",
    "CreateImageCommand",
    "ImageDecodeWorker",
    "ImageAssetCache",
    "ImageBatchRenderer",
    "ImageContextToolbar",
    "VideoStore",
    "CreateVideoCommand",
    "FFmpegTools",
    "VideoMediaService",
    "VideoBatchRenderer",
    "VideoPlayerOverlay",
    "VideoBoardPlayer",
    "VideoPlayerPool",
    "VideoContextToolbar",
    "NotLightPalette",
    "PerformanceTelemetryService",
    "PerformanceMonitorStrip",
    "AssetInspectorPanel",
    "UpdateAssetInstanceTitleCommand",
    "AudioStore",
    "CreateAudioCommand",
    "AudioMediaService",
    "VoiceRecordingService",
    "AudioBatchRenderer",
    "AudioBoardPlayer",
    "AudioWaveformView",
    "AudioPlayerPool",
    "AudioContextToolbar",
    "BoardSearchSnapshot",
    "CreditsDialog",
    "MicrophonePermissionDialog",
    "NotLightPortablePackageFormat",
    "NotLightPortablePackageService",
    "ModuleInstanceStateHost",
    "ModuleEphemeralStateHost",
    "BoardModuleInstanceStateHost",
    "ModuleSurfaceHost",
    "HubAmbientPhraseLayer",
    "NoteSaveWorker",
    "NoteReadWorker",
    "NoteIndexWorker",
    "NoteLinkParser",
    "NoteModuleEmbed",
    "NoteModuleEmbedBlock",
    "NoteMarkdownBlocks",
    "NoteInlineMarkup",
    "NotePreviewEditor",
    "NoteRepository",
    "NoteWorkspaceOverlay",
    "NotePortalStore",
    "CreateNotePortalCommand",
    "NotePortalBatchRenderer",
    "NotesGraphModel",
    "NotesGraphCanvas",
}


def split_parameters(parameter_text: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    quote = ""
    escaped = False
    for char in parameter_text:
        if quote:
            current.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in {"\"", "'"}:
            quote = char
            current.append(char)
        elif char in "([{":
            depth += 1
            current.append(char)
        elif char in ")]}":
            depth -= 1
            current.append(char)
        elif char == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def validate_delimiters(text: str) -> str | None:
    stack: list[tuple[str, int]] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    opening = set(pairs.values())
    quote = ""
    triple = False
    escaped = False
    line = 1
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\n":
            line += 1
            if not quote:
                escaped = False
            index += 1
            continue
        if quote:
            if triple:
                token = quote * 3
                if text.startswith(token, index):
                    quote = ""
                    triple = False
                    index += 3
                    continue
                index += 1
                continue
            if escaped:
                escaped = False
                index += 1
                continue
            if char == "\\":
                escaped = True
                index += 1
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char == "#":
            newline = text.find("\n", index)
            if newline < 0:
                break
            index = newline
            continue
        if char in {"\"", "'"}:
            if text.startswith(char * 3, index):
                quote = char
                triple = True
                index += 3
                continue
            quote = char
            triple = False
            index += 1
            continue
        if char in opening:
            stack.append((char, line))
        elif char in pairs:
            if not stack or stack[-1][0] != pairs[char]:
                return f"unexpected {char} at line {line}"
            stack.pop()
        index += 1
    if quote:
        return f"unterminated string near line {line}"
    if stack:
        char, open_line = stack[-1]
        return f"unclosed {char} from line {open_line}"
    return None


def validate_indentation_structure(text: str) -> list[str]:
    """Catch block-indentation jumps that the delimiter checks cannot see.

    This is intentionally conservative: indentation is evaluated only at the start
    of complete logical statements (not inside (), [] or {} continuations). An
    increased indentation level is legal only after a statement ending in ':'.
    It catches parser failures such as an accidentally dedented while-body line
    followed by a re-indented declaration.
    """

    failures: list[str] = []
    bracket_depth = 0
    triple_quote = ""
    previous_indent: int | None = None
    previous_opens_block = False

    def structural_line(raw_line: str) -> str:
        nonlocal triple_quote
        result: list[str] = []
        index = 0
        quote = ""
        escaped = False
        while index < len(raw_line):
            if triple_quote:
                terminator = triple_quote * 3
                closing = raw_line.find(terminator, index)
                if closing < 0:
                    return "".join(result)
                index = closing + 3
                triple_quote = ""
                continue
            char = raw_line[index]
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = ""
                index += 1
                continue
            if char == "#":
                break
            if char in {"\"", "'"}:
                if raw_line.startswith(char * 3, index):
                    triple_quote = char
                    index += 3
                    continue
                quote = char
                index += 1
                continue
            result.append(char)
            index += 1
        return "".join(result)

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        stripped = raw_line.lstrip(" \t")
        if not stripped:
            continue
        prefix = raw_line[: len(raw_line) - len(stripped)]
        clean_line = structural_line(raw_line)
        if not clean_line.strip():
            continue

        continuation = bracket_depth > 0
        indent_columns = 0
        for char in prefix:
            indent_columns += 4 if char == "\t" else 1

        if not continuation:
            if (
                previous_indent is not None
                and indent_columns > previous_indent
                and not previous_opens_block
            ):
                failures.append(
                    f"unexpected indentation at line {line_number}: "
                    "indentation increased after a statement that does not open a block"
                )
            previous_indent = indent_columns

        for char in clean_line:
            if char in "([{":
                bracket_depth += 1
            elif char in ")]}":
                bracket_depth = max(0, bracket_depth - 1)

        if bracket_depth == 0:
            previous_opens_block = clean_line.rstrip().endswith(":")
        elif not continuation:
            previous_opens_block = False

    return failures


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def validate() -> list[str]:
    failures: list[str] = []
    files = sorted(path for path in ROOT.rglob("*") if path.is_file())

    # Source/config files are required to be clean UTF-8 text. A literal NUL is
    # valid at the byte level but is never intentional in NotLight source and can
    # otherwise surface later as opaque U+FFFD/NUL diagnostics at runtime.
    for path in files:
        if path.suffix.lower() not in TEXT_INTEGRITY_SUFFIXES:
            continue
        raw: bytes = path.read_bytes()
        if b"\x00" in raw:
            fail(f"NUL byte found in text source: {path.relative_to(ROOT)}", failures)
        try:
            raw.decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            fail(f"not valid UTF-8: {path.relative_to(ROOT)}", failures)

    project_path = ROOT / "project.godot"
    if not project_path.is_file():
        fail("project.godot is missing", failures)
        project_text = ""
    else:
        project_text = project_path.read_text(encoding="utf-8")
        if 'config/features=PackedStringArray("4.4"' not in project_text:
            fail("project.godot is not pinned to the Godot 4.4 feature set", failures)
        display_match = re.search(r"(?ms)^\[display\]\s*\n(?P<body>.*?)(?=^\[|\Z)", project_text)
        if display_match is not None:
            display_body = "\n".join(
                line for line in display_match.group("body").splitlines()
                if line.strip() and not line.lstrip().startswith((";", "#"))
            ).strip()
            if not display_body:
                fail("project.godot contains an empty [display] section", failures)
        if 'stretch/mode="canvas_items"' in project_text or 'stretch/aspect=' in project_text:
            fail("desktop UI must not preserve a fixed content-scale aspect; it causes application-wide letterboxing", failures)

    license_path = ROOT / "LICENSE"
    if not license_path.is_file() or "GNU GENERAL PUBLIC LICENSE" not in license_path.read_text(encoding="utf-8"):
        fail("LICENSE does not contain the GNU GPL text", failures)

    global_classes: dict[str, Path] = {}
    for path in files:
        if path.suffix not in TEXT_SUFFIXES and path.name not in {"LICENSE", "COPYRIGHT"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            fail(f"not valid UTF-8: {path.relative_to(ROOT)}", failures)
            continue

        if path.suffix == ".gd":
            if not text.startswith("# SPDX-License-Identifier: GPL-3.0-or-later"):
                fail(f"missing SPDX header: {path.relative_to(ROOT)}", failures)
            delimiter_error = validate_delimiters(text)
            if delimiter_error is not None:
                fail(f"delimiter mismatch in {path.relative_to(ROOT)}: {delimiter_error}", failures)
            for indentation_error in validate_indentation_structure(text):
                fail(
                    f"GDScript indentation error in {path.relative_to(ROOT)}: {indentation_error}",
                    failures,
                )
            for forbidden_call, explanation in GODOT_44_FORBIDDEN_CALLS.items():
                if forbidden_call in text:
                    fail(
                        f"Godot 4.4 incompatible call {forbidden_call} in "
                        f"{path.relative_to(ROOT)}: {explanation}",
                        failures,
                    )
            packed_const_match = PACKED_CONST_CONSTRUCTOR_RE.search(text)
            if packed_const_match is not None:
                line_number = text[: packed_const_match.start()].count("\n") + 1
                fail(
                    f"non-constant packed-array constructor in const declaration at "
                    f"{path.relative_to(ROOT)}:{line_number}; use a typed literal instead",
                    failures,
                )
            for packed_match in PACKED_ARRAY_VARIABLE_RE.finditer(text):
                packed_name = packed_match.group(1)
                erase_match = re.search(rf"\b{re.escape(packed_name)}\.erase\s*\(", text)
                if erase_match is not None:
                    line_number = text[: erase_match.start()].count("\n") + 1
                    fail(
                        f"Godot 4.4 PackedArray has no erase() method at "
                        f"{path.relative_to(ROOT)}:{line_number} ({packed_name}); "
                        f"use find()/remove_at() or an explicit indexed removal",
                        failures,
                    )
            for slider_match in SLIDER_VARIABLE_RE.finditer(text):
                slider_name = slider_match.group(1)
                disabled_match = re.search(rf"\b{re.escape(slider_name)}\.disabled\s*=", text)
                if disabled_match is not None:
                    line_number = text[: disabled_match.start()].count("\n") + 1
                    fail(
                        f"Godot 4.4 Slider has no disabled property at "
                        f"{path.relative_to(ROOT)}:{line_number} ({slider_name}); "
                        f"use Slider.editable instead",
                        failures,
                    )
            if "extends BoardCommand" in text and BOARD_COMMAND_SUPER_INIT_RE.search(text):
                fail(
                    f"BoardCommand subclass calls super(...) even though BoardCommand has no _init constructor: "
                    f"{path.relative_to(ROOT)}; assign label/merge_key directly instead",
                    failures,
                )
            class_match = CLASS_RE.search(text)
            if class_match:
                class_name = class_match.group(1)
                if class_name in global_classes:
                    fail(
                        f"duplicate class_name {class_name}: "
                        f"{global_classes[class_name].relative_to(ROOT)} and {path.relative_to(ROOT)}",
                        failures,
                    )
                global_classes[class_name] = path
            gd_lines = text.splitlines()
            function_names: list[str] = re.findall(r"^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text, re.MULTILINE)
            duplicate_functions = sorted({name for name in function_names if function_names.count(name) > 1})
            for function_name in duplicate_functions:
                fail(
                    f"duplicate function {function_name} in {path.relative_to(ROOT)}",
                    failures,
                )
            for line_number, line in enumerate(gd_lines, start=1):
                for declaration_kind, identifier_pattern in DECLARED_IDENTIFIER_PATTERNS:
                    identifier_match = identifier_pattern.search(line)
                    if identifier_match is None:
                        continue
                    identifier = identifier_match.group(1)
                    if identifier in GODOT_441_RESERVED_IDENTIFIERS:
                        fail(
                            f"Godot 4.4.1 reserved token {identifier!r} is used as a "
                            f"{declaration_kind} identifier at {path.relative_to(ROOT)}:{line_number}",
                            failures,
                        )
                if INFERRED_DECLARATION_RE.search(line):
                    fail(
                        f"inferred declaration is forbidden at {path.relative_to(ROOT)}:{line_number}",
                        failures,
                    )
                if UNTYPED_DECLARATION_RE.search(line):
                    fail(
                        f"untyped declaration is forbidden at {path.relative_to(ROOT)}:{line_number}",
                        failures,
                    )
                shadowed_match = SHADOWED_GLOBAL_DECLARATION_RE.search(line)
                if shadowed_match:
                    fail(
                        f"global identifier {shadowed_match.group(1)} is shadowed at "
                        f"{path.relative_to(ROOT)}:{line_number}",
                        failures,
                    )
                if line.lstrip().startswith("func "):
                    declaration = line.strip()
                    cursor = line_number
                    while not declaration.rstrip().endswith(":") and cursor < len(gd_lines):
                        declaration += " " + gd_lines[cursor].strip()
                        cursor += 1
                    if "->" not in declaration:
                        fail(
                            f"function return type is missing at {path.relative_to(ROOT)}:{line_number}",
                            failures,
                        )
                    opening = declaration.find("(")
                    closing = declaration.rfind(")")
                    if opening >= 0 and closing > opening:
                        for parameter in split_parameters(declaration[opening + 1 : closing]):
                            parameter_name = parameter.split(":", 1)[0].strip() if parameter else ""
                            if parameter_name in GODOT_441_RESERVED_IDENTIFIERS:
                                fail(
                                    f"Godot 4.4.1 reserved token {parameter_name!r} is used as a "
                                    f"function parameter at {path.relative_to(ROOT)}:{line_number}",
                                    failures,
                                )
                            if parameter and ":" not in parameter:
                                fail(
                                    f"function parameter type is missing at "
                                    f"{path.relative_to(ROOT)}:{line_number}: {parameter}",
                                    failures,
                                )

        if path.suffix in {".gd", ".tscn", ".godot"}:
            for resource in RESOURCE_RE.findall(text):
                normalized = resource.rstrip(".,;:")
                target = ROOT / normalized.removeprefix("res://")
                if not target.exists():
                    fail(
                        f"broken resource reference {normalized} in {path.relative_to(ROOT)}",
                        failures,
                    )

        if path.suffix == ".svg":
            try:
                ET.fromstring(text)
            except ET.ParseError as exc:
                fail(f"malformed SVG {path.relative_to(ROOT)}: {exc}", failures)

    missing_classes = sorted(REQUIRED_CLASSES.difference(global_classes))
    for class_name in missing_classes:
        fail(f"required runtime class is missing: {class_name}", failures)

    # Validate direct uppercase constant access on project-owned global classes.
    # The ordinary delimiter/type text checks cannot detect a typo like
    # BoardEntityTypes.NONE; Godot reports that only while parsing the dependent
    # script. Enumerated members are included because unnamed enums expose their
    # values as class constants.
    project_constant_members: dict[str, set[str]] = {}
    for class_name, class_path in global_classes.items():
        class_source = class_path.read_text(encoding="utf-8")
        members = set(re.findall(r"^const\s+([A-Z][A-Z0-9_]*)\b", class_source, re.MULTILINE))
        for enum_match in ENUM_BLOCK_RE.finditer(class_source):
            members.update(re.findall(r"\b([A-Z][A-Z0-9_]*)\b", enum_match.group(1)))
        project_constant_members[class_name] = members
    for gd_path in (path for path in files if path.suffix == ".gd"):
        gd_text = gd_path.read_text(encoding="utf-8")
        for match in PROJECT_CLASS_CONSTANT_USE_RE.finditer(gd_text):
            class_name, member_name = match.groups()
            if class_name not in project_constant_members:
                continue
            if member_name in project_constant_members[class_name]:
                continue
            line_number = gd_text[: match.start()].count("\n") + 1
            fail(
                f"undefined project-class constant {class_name}.{member_name} at "
                f"{gd_path.relative_to(ROOT)}:{line_number}",
                failures,
            )

    # Board entity type IDs are StringName constants, not an enum with an implicit
    # NONE member. This semantic check deliberately mirrors BoardEntityTypes so a
    # typo such as BoardEntityTypes.NONE cannot pass static validation and only
    # surface later as a Godot parser error. BoardModel.get_entity_type() likewise
    # returns StringName, so explicitly typed int assignments are always invalid.
    board_entity_types_path = ROOT / "scripts/core/board_entity_types.gd"
    if board_entity_types_path.is_file():
        board_entity_types_source = board_entity_types_path.read_text(encoding="utf-8")
        defined_entity_type_constants = set(BOARD_ENTITY_TYPE_CONST_RE.findall(board_entity_types_source))
        for gd_path in (path for path in files if path.suffix == ".gd"):
            gd_text = gd_path.read_text(encoding="utf-8")
            for match in BOARD_ENTITY_TYPE_USE_RE.finditer(gd_text):
                member_name = match.group(1)
                if member_name not in defined_entity_type_constants:
                    line_number = gd_text[: match.start()].count("\n") + 1
                    fail(
                        f"undefined BoardEntityTypes member {member_name} at "
                        f"{gd_path.relative_to(ROOT)}:{line_number}",
                        failures,
                    )
            for match in GET_ENTITY_TYPE_INT_ASSIGN_RE.finditer(gd_text):
                line_number = gd_text[: match.start()].count("\n") + 1
                fail(
                    f"BoardModel.get_entity_type() returns StringName, but "
                    f"{match.group(1)} is declared int at "
                    f"{gd_path.relative_to(ROOT)}:{line_number}",
                    failures,
                )

    runtime_files = [
        path
        for path in files
        if path.suffix == ".gd" and "features/nodes" not in path.as_posix()
    ]
    for path in runtime_files:
        text = path.read_text(encoding="utf-8")
        for term in FORBIDDEN_RUNTIME_TERMS:
            if term in text:
                fail(f"retired graph dependency {term} in {path.relative_to(ROOT)}", failures)

    schema_text = (ROOT / "scripts/core/board_document_schema.gd").read_text(encoding="utf-8")
    if "CURRENT_VERSION: int = 13" not in schema_text:
        fail("Notes-enabled document schema version is not 13", failures)

    repository_text = (ROOT / "scripts/data/board_repository.gd").read_text(encoding="utf-8")
    if STROKE_PAYLOAD_MISINDENT_RE.search(repository_text):
        fail(
            "BoardRepository stroke payload assignment escaped its if block before else; "
            "this is a GDScript parse error",
            failures,
        )
    if '\t\tstorage["stroke_payload"] = payload_filename\n\telse:' not in repository_text:
        fail("BoardRepository stroke payload branch is not structurally guarded", failures)

    drawing_palette_text = (ROOT / "scripts/ui/drawing_tool_palette.gd").read_text(encoding="utf-8")
    if "QUICK_COLOR_PRESET_DEFS: Array[Dictionary]" not in drawing_palette_text or "static func quick_color_presets() -> Array[Dictionary]:" not in drawing_palette_text:
        fail("DrawingToolPalette is missing localized typed Dictionary presets for BoardColorPopover", failures)

    board_screen_stage9_text = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    if STROKE_POPOVER_WRONG_PRESET_RE.search(board_screen_stage9_text):
        fail(
            "BoardScreen passes Array[Color] to BoardColorPopover.show_for(), which requires Array[Dictionary]",
            failures,
        )
    if board_screen_stage9_text.count("DrawingToolPalette.quick_color_presets()") < 2:
        fail("drawing/stroke color popovers do not use the localized typed quick-color preset bridge", failures)

    stroke_stress_text = (ROOT / "tools/stroke_store_stress_test.gd").read_text(encoding="utf-8")
    if "var before_bounds: Array[Rect2]" not in stroke_stress_text or "var after_bounds: Array[Rect2]" not in stroke_stress_text:
        fail("stroke stress test passes untyped array literals into TransformEntitiesCommand", failures)
    if "_migrate_v2_to_v3" not in schema_text:
        fail("document schema does not migrate Stage 3.2 text documents", failures)
    if "_migrate_v3_to_v4" not in schema_text:
        fail("Stage 5 schema does not migrate pre-image documents", failures)
    if "_migrate_v4_to_v5" not in schema_text:
        fail("Stage 6 schema does not migrate pre-video documents", failures)
    if "_migrate_v5_to_v6" not in schema_text or '"instance_title"' not in schema_text:
        fail("Stage 8 schema does not migrate image/video instance labels", failures)
    if "_migrate_v6_to_v7" not in schema_text or '"stroke_payload"' not in schema_text:
        fail("Stage 9 schema does not migrate/persist binary stroke sidecar metadata", failures)
    if "_migrate_v8_to_v9" not in schema_text or '"audios"' not in schema_text:
        fail("Stage 9.5 schema does not migrate/persist audio records", failures)
    if "static func is_supported" not in schema_text:
        fail("BoardDocumentSchema does not reject unsupported future schemas", failures)

    runtime_text = (ROOT / "scripts/core/board_runtime.gd").read_text(encoding="utf-8")
    if "deserialize_content" not in runtime_text or "serialize_content" not in runtime_text:
        fail("BoardRuntime does not roundtrip registered content stores", failures)

    board_view_text = (ROOT / "scripts/board/native_board_view.gd").read_text(encoding="utf-8")
    if "set_process(false)" not in board_view_text:
        fail("NativeBoardView does not suspend processing after camera settling", failures)

    grid_renderer_path = ROOT / "scripts/board/board_grid_renderer.gd"
    grid_shader_path = ROOT / "assets/shaders/dot_grid.gdshader"
    if not grid_renderer_path.is_file() or not grid_shader_path.is_file():
        fail("GPU grid renderer resources are missing", failures)

    settings_dialog_text = (ROOT / "scripts/ui/settings_dialog.gd").read_text(encoding="utf-8")
    if "extends Window" in settings_dialog_text:
        fail("SettingsDialog must remain an in-canvas modal, not a Window", failures)
    if "func _init() -> void:" not in settings_dialog_text or "visible = false" not in settings_dialog_text:
        fail("SettingsDialog is not hidden before entering the scene tree", failures)

    text_store_text = (ROOT / "scripts/core/text_block_store.gd").read_text(encoding="utf-8")
    required_packed_arrays = (
        "PackedInt64Array",
        "PackedStringArray",
        "PackedFloat32Array",
        "PackedInt32Array",
        "PackedColorArray",
    )
    for packed_type in required_packed_arrays:
        if packed_type not in text_store_text:
            fail(f"TextBlockStore does not use {packed_type}", failures)
    if "_index_by_id[moved_id] = index" not in text_store_text:
        fail("TextBlockStore does not maintain swap-remove lookup", failures)
    if "func create_render_snapshot" not in text_store_text:
        fail("TextBlockStore does not expose worker-safe snapshots", failures)

    for required_term in (
        "font_families: PackedStringArray",
        "base_style_flags: PackedInt32Array",
        "run_offsets: PackedInt32Array",
        "_run_starts: PackedInt32Array",
        "_run_flags: PackedInt32Array",
        "_run_colors: PackedColorArray",
        "paragraph_offsets: PackedInt32Array",
        "_paragraph_list_types: PackedInt32Array",
        "_paragraph_indents: PackedInt32Array",
        "func apply_style_range",
        "func apply_style_flag_range",
        "func apply_text_color_range",
        "func set_paragraph_list_type",
    ):
        if required_term not in text_store_text:
            fail(f"Stage 3.3 semantic text store contract is missing: {required_term}", failures)

    worker_text = (ROOT / "scripts/workers/text_block_render_worker.gd").read_text(encoding="utf-8")
    for required_term in ("Thread.new()", "Mutex.new()", "Semaphore.new()", "func submit", "func poll_result"):
        if required_term not in worker_text:
            fail(f"text worker contract is missing: {required_term}", failures)
    for forbidden_term in ("Node2D", "Control", "CanvasItem", "Texture2D"):
        if forbidden_term in worker_text:
            fail(f"text worker touches render/scene type {forbidden_term}", failures)

    text_renderer_text = (ROOT / "scripts/render/text_block_batch_renderer.gd").read_text(encoding="utf-8")
    if "MultiMeshInstance2D" not in text_renderer_text or "set_instance_transform_2d" not in text_renderer_text:
        fail("TextBlockBatchRenderer does not batch distant backgrounds", failures)

    board_view_text = (ROOT / "scripts/board/native_board_view.gd").read_text(encoding="utf-8")
    for required_term in (
        "MaterializedTextEditor",
        "ACTION_CREATE_TEXT",
        "ACTION_MARQUEE",
        "TextBlockRenderWorker",
        "max_visible_text_blocks",
        "text_editor_state_changed",
        "text_editor_format_changed",
        "apply_editor_font_family",
        "apply_editor_style_flag",
        "apply_editor_text_color",
        "apply_editor_list_type",
        "_detect_auto_list_prefix",
        "_apply_pending_typing_style",
    ):
        if required_term not in board_view_text:
            fail(f"NativeBoardView text UX contract is missing: {required_term}", failures)
    for forbidden_term in ("Line2D.new()", "Sprite2D.new()"):
        if forbidden_term in board_view_text:
            fail(f"per-object renderer leaked into NativeBoardView: {forbidden_term}", failures)

    for required_term in (
        "RichTextCaretBlinkTimer",
        "_draw_editor_caret_overlay",
        "_draw_editor_selection_overlay",
        "_visual_line_index_for_character_offset",
        "_build_rich_text_screen_layout",
        "_record_has_visible_list_marker",
        'add_theme_color_override("caret_color", Color.TRANSPARENT)',
    ):
        if required_term not in board_view_text:
            fail(f"Stage 3.3.1 rich-text caret contract is missing: {required_term}", failures)

    board_screen_text = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    if "TOOL_TEXT" not in board_screen_text or "TextContextToolbar" not in board_screen_text:
        fail("BoardScreen does not expose the text tool and contextual toolbar", failures)
    theme_text = (ROOT / "scripts/ui/notlight_theme.gd").read_text(encoding="utf-8")
    if "DangerIconButton" not in theme_text:
        fail("theme is missing the readable contextual delete state", failures)

    text_layout_text = (ROOT / "scripts/core/text_layout_utils.gd").read_text(encoding="utf-8")
    for required_term in ("wrap_text_rich", "list_marker", "paragraph_indices_for_character_range", "estimate_rich_range_width"):
        if required_term not in text_layout_text:
            fail(f"Stage 3.3 rich layout contract is missing: {required_term}", failures)

    font_registry_text = (ROOT / "scripts/core/text_font_registry.gd").read_text(encoding="utf-8")
    for required_term in ("SystemFont.new()", "OS.get_system_fonts()", "font_weight", "font_italic", "multichannel_signed_distance_field"):
        if required_term not in font_registry_text:
            fail(f"Stage 3.3 font registry contract is missing: {required_term}", failures)

    toolbar_text = (ROOT / "scripts/ui/text_context_toolbar.gd").read_text(encoding="utf-8")
    for required_term in (
        "font_family_requested",
        "font_style_requested",
        "list_type_requested",
        "text_color_requested",
        "background_color_requested",
        "text_color_picker_requested",
        "background_color_picker_requested",
        "TextFontRegistry.available_font_families()",
        "set_toolbar_anchor",
    ):
        if required_term not in toolbar_text:
            fail(f"Stage 3.3.1 text toolbar contract is missing: {required_term}", failures)
    if "ColorPickerButton.new()" in toolbar_text:
        fail("Stage 3.3.1 text toolbar must use the viewport-contained color popover", failures)
    color_popover_text = (ROOT / "scripts/ui/board_color_popover.gd").read_text(encoding="utf-8")
    for required_term in (
        "class_name BoardColorPopover",
        "ScrollContainer.new()",
        "_place_inside_viewport",
        "update_viewport",
    ):
        if required_term not in color_popover_text:
            fail(f"Stage 3.3.1 color popover contract is missing: {required_term}", failures)
    if "Стикер" in toolbar_text or "STYLE_STICKY" in toolbar_text or "Стикер" in board_screen_text:
        fail("Stage 3.3 active UI still exposes Sticky as a separate text object mode", failures)
    if "func set_anchor(" in toolbar_text:
        fail("custom text toolbar collides with Control.set_anchor", failures)
    if toolbar_text.count("row.add_child(_edit_button)") != 1:
        fail("text toolbar must add its edit button exactly once", failures)

    shader_path = ROOT / "assets/shaders/text_block_background.gdshader"
    if not shader_path.is_file():
        fail("text background shader is missing", failures)
    else:
        text_shader: str = shader_path.read_text(encoding="utf-8")
        if re.search(r"\bvec[234]\s+inner\b", text_shader):
            fail("text background shader uses reserved identifier 'inner'", failures)
        if "fwidth(" in text_shader:
            fail("text background shader reintroduced derivative-dependent edge smoothing on the GL Compatibility path", failures)
        for required_term in ("varying vec4 block_data", "INSTANCE_CUSTOM", "float inner_alpha"):
            if required_term not in text_shader:
                fail(f"Stage 7.2 text shader compatibility contract is missing: {required_term}", failures)

    for required_term in (
        "ACTION_CONNECT",
        "_hit_connection_handle",
        "_draw_dashed_rect",
        "copy_selection",
        "paste_clipboard",
        "duplicate_selection",
        "_fallback_scan_dense_objects",
    ):
        source_text = board_view_text if required_term != "_fallback_scan_dense_objects" else (ROOT / "scripts/core/board_hit_test_system.gd").read_text(encoding="utf-8")
        if required_term not in source_text:
            fail(f"Stage 3.2 interaction contract is missing: {required_term}", failures)

    connector_renderer_text = (ROOT / "scripts/render/connector_batch_renderer.gd").read_text(encoding="utf-8")
    if "draw_multiline" not in connector_renderer_text or "Line2D" in connector_renderer_text:
        fail("connector renderer must remain a batched CanvasItem renderer", failures)
    connector_store_text = (ROOT / "scripts/core/connector_store.gd").read_text(encoding="utf-8")
    for packed_type in ("PackedInt64Array", "PackedInt32Array", "PackedColorArray", "PackedFloat32Array"):
        if packed_type not in connector_store_text:
            fail(f"ConnectorStore does not use {packed_type}", failures)
    if '"connectors"' not in schema_text:
        fail("document schema does not reserve connector content", failures)

    if "LAYOUT_AUTO_WIDTH" not in text_store_text or "LAYOUT_FIXED_WIDTH" not in text_store_text:
        fail("TextBlockStore is missing adaptive layout modes", failures)
    if "router_point_offsets" not in connector_store_text or "_router_point_pool" not in connector_store_text:
        fail("ConnectorStore is missing the packed router point pool", failures)
    connector_geometry_text = (ROOT / "scripts/core/connector_geometry.gd").read_text(encoding="utf-8")
    for required_term in (
        "sample_routed_curve",
        "router_insertion_index",
        "MAX_SEGMENT_SAMPLES",
        "DIRECTION_NONE",
        "DIRECTION_FORWARD",
        "DIRECTION_REVERSE",
        "DIRECTION_BOTH",
        "direction_has_source_arrow",
        "direction_has_target_arrow",
    ):
        if required_term not in connector_geometry_text:
            fail(f"routed connector geometry contract is missing: {required_term}", failures)
    for required_term in ("directions: PackedInt32Array", "func get_direction", "func set_color", "func set_direction"):
        if required_term not in connector_store_text:
            fail(f"Stage 3.3.1 connector style contract is missing: {required_term}", failures)
    if "ConnectorStore.DIRECTION_" in connector_geometry_text:
        fail("ConnectorGeometry must not depend back on ConnectorStore direction constants", failures)
    connector_toolbar_text = (ROOT / "scripts/ui/connector_context_toolbar.gd").read_text(encoding="utf-8")
    for required_term in ("direction_requested", "color_picker_requested", "DIRECTION_BOTH", "set_toolbar_anchor"):
        if required_term not in connector_toolbar_text:
            fail(f"Stage 3.3.1 connector toolbar contract is missing: {required_term}", failures)
    clipboard_text = (ROOT / "scripts/core/board_clipboard_service.gd").read_text(encoding="utf-8")
    if "make_paste_command_at" not in clipboard_text or "_source_bounds.get_center()" not in clipboard_text:
        fail("clipboard is not cursor-positioned", failures)
    for required_term in (
        "ACTION_REWIRE_CONNECTOR",
        "ACTION_MOVE_ROUTER_POINT",
        "_start_connector_rewire",
        "_add_router_point",
        "_remove_router_point",
        "make_paste_command_at",
    ):
        if required_term not in board_view_text:
            fail(f"Stage 3.2 routed interaction contract is missing: {required_term}", failures)
    if ".set_anchor(" in board_screen_text or "func set_anchor(" in toolbar_text:
        fail("custom text toolbar still collides with Control.set_anchor", failures)
    if "set_toolbar_anchor" not in board_screen_text:
        fail("BoardScreen does not call the non-conflicting toolbar anchor API", failures)
    for required_term in ("KEY_ESCAPE", "_build_board_utilities", 'NotLightL10n.bind_tooltip(_settings_button, "hub.settings_tooltip")') :
        if required_term not in board_screen_text:
            fail(f"Stage 3.2 utility UI contract is missing: {required_term}", failures)

    # Stage 4 — global Asset Library core.
    asset_kinds_text = (ROOT / "scripts/assets/asset_kinds.gd").read_text(encoding="utf-8")
    for required_term in ("IMAGE", "VIDEO", "AUDIO", "PDF", "MODEL_3D", "FONT", "from_extension"):
        if required_term not in asset_kinds_text:
            fail(f"AssetKinds contract is missing: {required_term}", failures)

    asset_id_text = (ROOT / "scripts/assets/asset_id.gd").read_text(encoding="utf-8")
    for required_term in ("Crypto.new()", "generate_random_bytes(16)", "0x40", "0x80"):
        if required_term not in asset_id_text:
            fail(f"Asset UUID contract is missing: {required_term}", failures)

    asset_catalog_text = (ROOT / "scripts/assets/asset_catalog.gd").read_text(encoding="utf-8")
    for required_term in (
        'SCHEMA_ID: String = "notlight.asset_catalog"',
        "hash_sha256",
        "blob_relpath",
        "folder_id",
        "_write_json_atomic",
        "_blob_path_matches_hash",
        "_sanitize_folder_hierarchy",
        "list_assets_readonly",
    ):
        if required_term not in asset_catalog_text:
            fail(f"AssetCatalog durability contract is missing: {required_term}", failures)

    blob_store_text = (ROOT / "scripts/assets/asset_blob_store.gd").read_text(encoding="utf-8")
    for required_term in (
        'root_dir.path_join("blobs")',
        'root_dir.path_join("cache")',
        'root_dir.path_join("tmp")',
        'clean.begins_with("blobs/")',
        "commit_temp",
        "list_blob_entries",
        "clear_cache",
    ):
        if required_term not in blob_store_text:
            fail(f"content-addressed blob store contract is missing: {required_term}", failures)

    asset_kinds_text = (ROOT / "scripts/assets/asset_kinds.gd").read_text(encoding="utf-8")
    if "AssetImportCapabilities." in asset_kinds_text:
        fail("AssetKinds must not depend on AssetImportCapabilities; keep the import-registry dependency one-way", failures)

    import_capabilities_text = (ROOT / "scripts/assets/asset_import_capabilities.gd").read_text(encoding="utf-8")
    for required_term in (
        "IMAGE_EXTENSIONS",
        "VIDEO_EXTENSIONS",
        "AUDIO_EXTENSIONS",
        "PDF_EXTENSIONS",
        "IMPORTABLE_KINDS",
        "supported_extensions",
        "file_dialog_filters",
        "kind_for_extension",
        "validate_candidate",
        "AssetImportContentValidator.validate",
    ):
        if required_term not in import_capabilities_text:
            fail(f"AssetImportCapabilities safe-import contract is missing: {required_term}", failures)
    if "MODEL_3D" in import_capabilities_text or "FONT_EXTENSIONS" in import_capabilities_text:
        fail("new-import capability registry must not expose legacy 3D/font kinds", failures)
    if '",".join(patterns)' not in import_capabilities_text or '",".join(mimes)' not in import_capabilities_text:
        fail("native FileDialog filters must use the documented comma-separated extension/MIME form", failures)
    if "*.*" in import_capabilities_text:
        fail("safe-import capability registry must not expose an unrestricted All Files filter", failures)

    import_candidate_text = (ROOT / "scripts/assets/import_candidate_result.gd").read_text(encoding="utf-8")
    if "AssetImportCapabilities." in import_candidate_text:
        fail("ImportCandidateResult must not depend back on AssetImportCapabilities", failures)

    import_validator_text = (ROOT / "scripts/assets/asset_import_content_validator.gd").read_text(encoding="utf-8")
    for required_term in (
        '"%PDF-"',
        '"RIFF"',
        '"WEBP"',
        '"OggS"',
        '"fLaC"',
        '"ftyp"',
        "PopplerTools.pdfinfo_path",
        "FFmpegTools.ffprobe_path",
        "SidecarProcessRunner.new",
        "PROBE_TIMEOUT_MSEC",
        "PROBE_OUTPUT_LIMIT_BYTES",
        "REJECTION_UNSAFE_SVG",
        "REJECTION_SVG_TOO_LARGE",
        "MAX_SVG_BYTES",
        "stream_disposition=attached_pic",
        'stream.get("disposition", {})',
        'not attached_picture',
        "_svg_has_external_href",
        "_svg_has_external_url",
        "_svg_reference_is_local_and_safe",
        '"data:image/png;base64,"',
        '["m4a", "ogg", "opus", "mp3", "aac"].has(extension)',
    ):
        if required_term not in import_validator_text:
            fail(f"asset content-validation contract is missing: {required_term}", failures)
    if "OS.execute(" in import_validator_text:
        fail("safe import validator must not use blocking OS.execute()", failures)
    if "AssetImportCapabilities." in import_validator_text:
        fail("AssetImportContentValidator must not depend back on AssetImportCapabilities", failures)

    import_worker_text = (ROOT / "scripts/workers/asset_import_validation_worker.gd").read_text(encoding="utf-8")
    for required_term in (
        "Thread.new()",
        "Mutex.new()",
        "Semaphore.new()",
        "MAX_PENDING_BATCHES",
        "MAX_FILES_PER_BATCH",
        "HASH_CHUNK_BYTES",
        "HashingContext.HASH_SHA256",
        "AssetImportCapabilities.validate_candidate",
        "cancel_check",
        "_push_progress(job_key, index, total, source_path)",
    ):
        if required_term not in import_worker_text:
            fail(f"bounded import-validation worker contract is missing: {required_term}", failures)
    hash_call_index = import_worker_text.find("hash_result = _hash_file(job_key, source_path)")
    validate_call_index = import_worker_text.find("var validation: Dictionary = AssetImportCapabilities.validate_candidate")
    if hash_call_index < 0 or validate_call_index < 0 or hash_call_index > validate_call_index:
        fail("preflight worker must fingerprint a supported candidate before content validation for TOCTOU comparison", failures)

    preflight_service_text = (ROOT / "scripts/assets/asset_import_preflight_service.gd").read_text(encoding="utf-8")
    for required_term in (
        "MAX_FILES_PER_PREFLIGHT",
        "AssetImportValidationWorker.new",
        "request_batch(request_id, candidates, true)",
        "catalog.find_asset_by_hash",
        "duplicate_in_batch",
        "preflight_completed",
        "preflight_cancelled",
        "_worker_ready",
    ):
        if required_term not in preflight_service_text:
            fail(f"import preflight service contract is missing: {required_term}", failures)

    import_staging_worker_text = (ROOT / "scripts/workers/asset_import_staging_worker.gd").read_text(encoding="utf-8")
    for required_term in (
        "Thread.new()",
        "Mutex.new()",
        "Semaphore.new()",
        "MAX_PENDING_JOBS: int = 1",
        "COPY_CHUNK_BYTES",
        "HashingContext.HASH_SHA256",
        "store_buffer(chunk)",
        "_progress_by_key",
        "_should_cancel",
        "_pending_keys.size() + _results.size() >= MAX_PENDING_JOBS",
    ):
        if required_term not in import_staging_worker_text:
            fail(f"bounded import staging-worker contract is missing: {required_term}", failures)

    import_pipeline_text = (ROOT / "scripts/assets/asset_import_pipeline.gd").read_text(encoding="utf-8")
    for required_term in (
        "MAX_PENDING_JOBS",
        "catalog.find_asset_by_hash",
        "AssetImportStagingWorker.new",
        "AssetImportValidationWorker.new",
        "_staging_worker.request",
        "request_batch(job_id, [candidate], true)",
        'validation.get("hash_sha256", "")',
        'library.import.error.staging_changed',
        "expected_source_hash",
        "REJECTION_SOURCE_CHANGED",
        "blob_store.commit_preverified_temp",
    ):
        if required_term not in import_pipeline_text:
            fail(f"Asset import pipeline contract is missing: {required_term}", failures)
    for forbidden_term in ("HashingContext", "FileAccess.open(source_path, FileAccess.READ)", "store_buffer(chunk)"):
        if forbidden_term in import_pipeline_text:
            fail(f"Asset import pipeline moved heavy copy/hash work back to the main thread: {forbidden_term}", failures)
    if "blob_store.commit_temp(" in import_pipeline_text:
        fail("final user import must not re-hash staging synchronously through commit_temp()", failures)

    if "AssetImportCapabilities.kind_for_extension(extension)" not in asset_catalog_text or "AssetKinds.from_extension(extension)" not in asset_catalog_text:
        fail("catalog normalization must classify current formats through the import registry and preserve legacy kind fallback", failures)

    reference_index_text = (ROOT / "scripts/assets/asset_reference_index.gd").read_text(encoding="utf-8")
    for required_term in ("asset_refs", "usage_count", "board_names_for", "referenced_asset_ids", "set_board_metadata", "remove_board"):
        if required_term not in reference_index_text:
            fail(f"Asset reference index contract is missing: {required_term}", failures)

    asset_service_text = (ROOT / "scripts/assets/asset_library_service.gd").read_text(encoding="utf-8")
    for required_term in (
        'ROOT_DIR: String = "user://notlight/library"',
        "query_assets",
        "cleanup_unused",
        "get_integrity_report",
        "_orphan_blob_entries",
        "clear_derived_cache",
        "refresh_references",
        "resolve_asset_path",
        "_on_board_manifest_changed",
        "_on_board_deleted",
    ):
        if required_term not in asset_service_text:
            fail(f"AssetLibraryService contract is missing: {required_term}", failures)

    for required_term in (
        "request_import_preflight",
        "import_preflight_results",
        "cancel_import_preflight",
        "import_queue_changed",
    ):
        if required_term not in asset_service_text:
            fail(f"AssetLibraryService safe-import contract is missing: {required_term}", failures)

    import_dialog_text = (ROOT / "scripts/ui/asset_import_preflight_dialog.gd").read_text(encoding="utf-8")
    for required_term in (
        "class_name AssetImportPreflightDialog",
        "ScrollContainer",
        "import_requested",
        "cancel_requested",
        "duplicate_count",
        "rejected_count",
        "repair_count",
    ):
        if required_term not in import_dialog_text:
            fail(f"Import Preflight UI contract is missing: {required_term}", failures)

    repository_text = (ROOT / "scripts/data/board_repository.gd").read_text(encoding="utf-8")
    for required_term in (
        "MANIFEST_SCHEMA_VERSION: int = 4",
        "asset_refs",
        "BoardDocumentSchema.collect_asset_references",
        "Stage 4 moves original media into the global content-addressed Asset Library",
        "board_manifest_changed",
        "board_deleted",
        "_upsert_index_metadata",
    ):
        if required_term not in repository_text:
            fail(f"board asset-reference manifest contract is missing: {required_term}", failures)
    if "static func collect_asset_references" not in schema_text:
        fail("BoardDocumentSchema does not collect future asset_id references", failures)

    asset_view_text = (ROOT / "scripts/ui/asset_library_view.gd").read_text(encoding="utf-8")
    for required_term in (
        "FULL_PAGE_SIZE",
        "COMPACT_PAGE_SIZE",
        'NotLightL10n.bind_placeholder_text(search_edit, "library.search.help")',
        'NotLightL10n.text("library.usage.used")',
        'NotLightL10n.text("library.usage.unused")',
        'NotLightL10n.bind_text(cleanup, "library.cleanup_unused")',
        'NotLightL10n.bind_text(audit, "library.audit")',
        "FOLDER_DIALOG_CREATE",
        "FOLDER_DIALOG_RENAME",
        "AssetInspectorPanel.new()",
        "_refresh_tag_filter",
    ):
        if required_term not in asset_view_text:
            fail(f"Asset Library UX contract is missing: {required_term}", failures)

    hub_text = (ROOT / "scripts/ui/hub_screen.gd").read_text(encoding="utf-8")
    for required_term in ("SECTION_LIBRARY", "SECTION_MODULES", "HubSectionNav.new()", "AssetLibraryView.new()", "_build_modules_page", "SettingsDialog.new()", 'bind_placeholder_text(_search_edit, "hub.boards.search")'):
        if required_term not in hub_text:
            fail(f"Hub navigation/library contract is missing: {required_term}", failures)
    hub_nav_path = ROOT / "scripts/ui/hub_section_nav.gd"
    if not hub_nav_path.is_file():
        fail("Hub triangular section navigation is missing", failures)
    else:
        hub_nav_text = hub_nav_path.read_text(encoding="utf-8")
        for required_term in ('"hub.boards"', '"hub.library"', '"hub.modules"', "draw_line(top_bottom, left_top", "draw_line(top_bottom, right_top", "CONNECTOR_GAP"):
            if required_term not in hub_nav_text:
                fail(f"Hub triangular navigation contract is missing: {required_term}", failures)

    if "PerformanceMonitorStrip" in hub_text or "_monitor_strip" in hub_text:
        fail("Stage 8.2 performance monitors must not be materialized in the Hub", failures)
    if 'NotLightL10n.bind_text(_search_edit, "hub.boards.search")' in hub_text:
        fail("Hub search localization must target placeholder_text, not LineEdit.text; otherwise it filters all boards", failures)

    for required_term in (
        "AssetLibraryDrawer",
        "PRESET_RIGHT_WIDE",
        "_set_library_drawer_open",
        "KEY_L",
        "_save_button",
        "_update_title_save_marker",
        'NotLightL10n.text("ui.format.unsaved_title") % _board_display_name',
        "_layout_left_controls",
    ):
        if required_term not in board_screen_text:
            fail(f"Board Stage 4 shell contract is missing: {required_term}", failures)
    if 'placeholder_text = "Введите' in board_view_text:
        fail("materialized rich-text editor still exposes the placeholder/list ghost", failures)
    if 'stage_label.text' in board_screen_text:
        fail("development stage label leaked into the board UI", failures)

    # Guard a concrete API regression caught during Stage 5 integration:
    # ImageStore implements BoardDataStore.remove(), not remove_entity().
    for gd_path in ROOT.rglob("*.gd"):
        gd_text = gd_path.read_text(encoding="utf-8")
        if ".images.remove_entity(" in gd_text:
            fail(f"Invalid ImageStore API call in {gd_path.relative_to(ROOT)}: use images.remove(...) instead of images.remove_entity(...)", failures)

    # Stage 5 — DOD image objects backed by the global Asset Library.
    image_store_text = (ROOT / "scripts/core/image_store.gd").read_text(encoding="utf-8")
    for required_term in (
        'STORE_ID: StringName = &"images"',
        "entity_ids: PackedInt64Array",
        "asset_ids: PackedStringArray",
        "pixel_widths: PackedInt32Array",
        "pixel_heights: PackedInt32Array",
        "_index_by_id[int(entity_ids[index])] = index",
        "func get_aspect_ratio",
        "func remap_record",
    ):
        if required_term not in image_store_text:
            fail(f"ImageStore DOD contract is missing: {required_term}", failures)

    board_model_text = (ROOT / "scripts/core/board_model.gd").read_text(encoding="utf-8")
    for required_term in (
        "images: ImageStore = ImageStore.new()",
        "stores.register_store(images)",
        "image_revision",
        "_on_image_data_changed",
    ):
        if required_term not in board_model_text:
            fail(f"BoardModel image-store contract is missing: {required_term}", failures)

    image_worker_text = (ROOT / "scripts/workers/image_decode_worker.gd").read_text(encoding="utf-8")
    for required_term in (
        "Thread.new()",
        "Mutex.new()",
        "Semaphore.new()",
        "Image.load_from_file",
        "pending_work_count",
        "INTERPOLATE_LANCZOS",
    ):
        if required_term not in image_worker_text:
            fail(f"image decode worker contract is missing: {required_term}", failures)
    for forbidden_term in ("ImageTexture", "Texture2D", "Node2D", "Control", "CanvasItem"):
        if forbidden_term in image_worker_text:
            fail(f"image decode worker touches render/scene type {forbidden_term}", failures)

    image_cache_text = (ROOT / "scripts/assets/image_asset_cache.gd").read_text(encoding="utf-8")
    for required_term in (
        "ImageTexture.create_from_image",
        "MAX_PENDING_DECODE_REQUESTS",
        "max_uploads_per_frame",
        "memory_limit_bytes",
        "tier_for_extent",
        "_best_cached_texture",
        "_evict_if_needed",
        "set_process(false)",
        "pending_work_count",
    ):
        if required_term not in image_cache_text:
            fail(f"ImageAssetCache performance contract is missing: {required_term}", failures)

    image_renderer_text = (ROOT / "scripts/render/image_batch_renderer.gd").read_text(encoding="utf-8")
    for required_term in (
        "candidate_ids: PackedInt64Array",
        "BoardEntityTypes.IMAGE",
        "maximum_images",
        "request_texture",
        "draw_texture_rect",
        "_draw_placeholder",
    ):
        if required_term not in image_renderer_text:
            fail(f"ImageBatchRenderer contract is missing: {required_term}", failures)
    for forbidden_term in ("Sprite2D", "TextureRect.new()"):
        if forbidden_term in image_renderer_text:
            fail(f"per-image SceneTree renderer leaked into ImageBatchRenderer: {forbidden_term}", failures)

    image_command_text = (ROOT / "scripts/core/create_image_command.gd").read_text(encoding="utf-8")
    for required_term in ("BoardEntityTypes.IMAGE", "model.images.add_image", "func undo"):
        if required_term not in image_command_text:
            fail(f"CreateImageCommand contract is missing: {required_term}", failures)

    image_toolbar_text = (ROOT / "scripts/ui/image_context_toolbar.gd").read_text(encoding="utf-8")
    for required_term in ("rename_requested", "duplicate_requested", "delete_requested", "set_toolbar_anchor"):
        if required_term not in image_toolbar_text:
            fail(f"ImageContextToolbar contract is missing: {required_term}", failures)
    if "func set_anchor(" in image_toolbar_text:
        fail("ImageContextToolbar collides with Control.set_anchor", failures)

    for required_term in (
        "configure_image_cache",
        "create_image_from_asset",
        "paste_external_text",
        "INTERNAL_CLIPBOARD_MARKER",
        "BoardEntityTypes.IMAGE",
        "_apply_media_resize_preview",
        "_draw_transient_image",
        "max_visible_images",
        "model.image_revision",
    ):
        if required_term not in board_view_text:
            fail(f"NativeBoardView Stage 5 image contract is missing: {required_term}", failures)

    for required_term in (
        "DisplayServer.clipboard_has_image",
        "DisplayServer.clipboard_get_image",
        "_paste_from_system_clipboard",
        "_open_image_import_dialog",
        "_queue_image_files",
        "_place_library_asset",
        "get_view_center_world_position",
        "FileAccess.file_exists",
        "asset_insert_requested",
    ):
        if required_term not in board_screen_text:
            fail(f"BoardScreen Stage 5 import/clipboard contract is missing: {required_term}", failures)
    if board_screen_text.count("background_color_picker_requested.connect(_open_background_color_popover)") != 1:
        fail("background color popover signal must be connected exactly once", failures)

    for required_term in (
        "AssetImportCapabilities.file_dialog_filters()",
        "FileDialog.FILE_MODE_OPEN_FILES",
        "use_native_dialog = true",
        "AssetImportPreflightDialog.new()",
        "request_import_preflight",
        "_on_library_files_dropped",
        "window.files_dropped.connect(_on_library_files_dropped)",
        "mode_overrides_title = false",
    ):
        if required_term not in asset_view_text:
            fail(f"Resource Library safe import UI contract is missing: {required_term}", failures)
    for required_term in (
        "AssetImportCapabilities.file_dialog_filters(AssetKinds.IMAGE)",
        "AssetImportCapabilities.file_dialog_filters(AssetKinds.PDF)",
        "AssetImportCapabilities.file_dialog_filters(AssetKinds.VIDEO)",
        "AssetImportCapabilities.file_dialog_filters(AssetKinds.AUDIO)",
        "AssetImportCapabilities.kind_for_path(path)",
        "mode_overrides_title = false",
    ):
        if required_term not in board_screen_text:
            fail(f"Board import filter is not registry-driven: {required_term}", failures)
    if "if not is_visible_in_tree() or _board_view == null or paths.is_empty():" not in board_screen_text:
        fail("BoardScreen must ignore global file drops while the board screen is hidden", failures)
    for forbidden_pattern in ("*.png,", "*.mp4,", "*.mp3,", 'PackedStringArray(["*.pdf'):
        if forbidden_pattern in board_screen_text:
            fail(f"BoardScreen duplicates safe-import extension filters: {forbidden_pattern}", failures)

    if "asset_insert_requested" not in asset_view_text or "notes.place_on_board" not in (ROOT / "scripts/ui/asset_library_card.gd").read_text(encoding="utf-8"):
        fail("Board Asset Library placement action is missing", failures)
    asset_card_text = (ROOT / "scripts/ui/asset_library_card.gd").read_text(encoding="utf-8")
    for required_term in ("ImageAssetCache", "request_texture", "texture_ready"):
        if required_term not in asset_card_text:
            fail(f"Asset Library image thumbnail contract is missing: {required_term}", failures)

    for required_term in (
        "import_job_finished",
        "import_job_failed",
        "func import_image",
        '"clipboard.png"',
    ):
        if required_term not in asset_service_text:
            fail(f"AssetLibraryService Stage 5 image import contract is missing: {required_term}", failures)
    for required_term in ("func enqueue_file", "cleanup_source", "display_name_override", "original_filename_override"):
        if required_term not in import_pipeline_text:
            fail(f"AssetImportPipeline Stage 5 contract is missing: {required_term}", failures)
    if "clipboard_image_" not in blob_store_text:
        fail("blob store does not clean interrupted clipboard-image temporaries", failures)

    for required_term in ("color_picker.show_values", "_set_advanced_controls", "NotLightColorPickerStyle.configure_picker"):
        if required_term not in color_popover_text:
            fail(f"Stage 5/9.2 advanced color UI contract is missing: {required_term}", failures)

    if '"images"' not in schema_text or "_migrate_v3_to_v4" not in schema_text:
        fail("Stage 5 document schema does not persist/migrate image rows", failures)

    # Stage 7 — DOD video cards + bounded inline playback + durable video variants.
    video_store_text = (ROOT / "scripts/core/video_store.gd").read_text(encoding="utf-8")
    for required_term in (
        'STORE_ID: StringName = &"videos"',
        "entity_ids: PackedInt64Array",
        "asset_ids: PackedStringArray",
        "pixel_widths: PackedInt32Array",
        "pixel_heights: PackedInt32Array",
        "duration_msec: PackedInt64Array",
        "_index_by_id[int(entity_ids[index])] = index",
        "func get_aspect_ratio",
    ):
        if required_term not in video_store_text:
            fail(f"VideoStore DOD contract is missing: {required_term}", failures)

    video_command_text = (ROOT / "scripts/core/create_video_command.gd").read_text(encoding="utf-8")
    for required_term in ("BoardEntityTypes.VIDEO", "model.videos.add_video", "func undo"):
        if required_term not in video_command_text:
            fail(f"CreateVideoCommand contract is missing: {required_term}", failures)

    video_renderer_text = (ROOT / "scripts/render/video_batch_renderer.gd").read_text(encoding="utf-8")
    for required_term in ("candidate_ids: PackedInt64Array", "model.videos.contains", "max_visible", "draw_texture_rect", "_draw_video_card"):
        if required_term not in video_renderer_text:
            fail(f"VideoBatchRenderer contract is missing: {required_term}", failures)
    for forbidden_term in ("VideoStreamPlayer.new()", "TextureRect.new()"):
        if forbidden_term in video_renderer_text:
            fail(f"per-video SceneTree playback leaked into VideoBatchRenderer: {forbidden_term}", failures)

    video_service_text = (ROOT / "scripts/media/video_media_service.gd").read_text(encoding="utf-8")
    for required_term in (
        "FFmpegTools.probe",
        "OS.create_process",
        "output_size >= input_size",
        "func cancel_active",
        "VARIANT_ORIGINAL",
        "VARIANT_OPTIMIZED",
        "func set_preferred_variant",
        "func delete_original_variant",
        "libx264",
        "OS.get_processor_count",
    ):
        if required_term not in video_service_text:
            fail(f"VideoMediaService Stage 7 contract is missing: {required_term}", failures)

    ffmpeg_tools_text = (ROOT / "scripts/media/ffmpeg_tools.gd").read_text(encoding="utf-8")
    for required_term in ('tool + (".exe" if OS.has_feature("windows") else "")', "OS.get_executable_path", "func ffmpeg_path", "func ffprobe_path", "func probe"):
        if required_term not in ffmpeg_tools_text:
            fail(f"FFmpegTools sidecar/probe contract is missing: {required_term}", failures)
    ffmpeg_availability_section = ffmpeg_tools_text.split("static func _can_run", 1)[1].split("static func _native_path", 1)[0] if "static func _can_run" in ffmpeg_tools_text else ""
    if "OS.execute" in ffmpeg_availability_section or "_find_on_path" not in ffmpeg_availability_section:
        fail("FFmpegTools availability checks must not synchronously launch sidecars from UI/selection hot paths", failures)

    video_player_text = (ROOT / "scripts/ui/video_board_player.gd").read_text(encoding="utf-8")
    for required_term in (
        "FFmpegVideoStream",
        "set_file",
        "stream_position",
        "get_stream_length",
        "set_preferred_variant",
        "delete_original_variant",
        "AspectRatioContainer.new()",
        "AspectRatioContainer.STRETCH_FIT",
        "func video_aspect_ratio",
        "func set_display_name",
    ):
        if required_term not in video_player_text:
            fail(f"VideoBoardPlayer contract is missing: {required_term}", failures)

    video_pool_text = (ROOT / "scripts/ui/video_player_pool.gd").read_text(encoding="utf-8")
    for required_term in (
        "DEFAULT_MAX_ACTIVE_PLAYERS: int = 10",
        "active_player_budget",
        "max_active_players",
        "VideoBoardPlayer",
        "z_index = 100",
        "func activate",
        "func deactivate",
        "func toggle_expanded",
        "func _fit_aspect_inside",
        "BoardLiveSurfaceProjection.projected_rect",
    ):
        if required_term not in video_pool_text:
            fail(f"VideoPlayerPool contract is missing: {required_term}", failures)

    for required_term in ("video_open_requested", "create_video_from_asset", "VideoBatchRenderer", "BoardEntityTypes.VIDEO"):
        if required_term not in board_view_text:
            fail(f"NativeBoardView Stage 7 video contract is missing: {required_term}", failures)
    for required_term in (
        "VideoPlayerPool",
        "VideoContextToolbar",
        "_queue_video_placement",
        "video_open_requested",
        "AssetKinds.VIDEO",
        "add_child(_video_player_pool)",
        "_open_selected_video_rename_dialog",
        "_optimize_selected_video",
        "_layout_left_controls",
        "vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER",
    ):
        if required_term not in board_screen_text:
            fail(f"BoardScreen Stage 7.2 video/UI contract is missing: {required_term}", failures)
    if "_board_view.add_child(_video_player_pool)" in board_screen_text:
        fail("VideoPlayerPool must be a BoardScreen sibling so board UI can stay above playback", failures)
    if '"videos"' not in schema_text or "_migrate_v4_to_v5" not in schema_text:
        fail("Stage 7 document schema does not persist/migrate video rows", failures)

    settings_text = (ROOT / "scripts/settings/app_settings_store.gd").read_text(encoding="utf-8")
    grid_renderer_text = (ROOT / "scripts/board/board_grid_renderer.gd").read_text(encoding="utf-8")
    grid_shader_text = (ROOT / "assets/shaders/dot_grid.gdshader").read_text(encoding="utf-8")
    for required_term in ("GridIntensity", '"grid_intensity": int(grid_intensity)', "func set_grid_intensity(value: int) -> void"):
        if required_term not in settings_text:
            fail(f"board grid intensity settings contract is missing: {required_term}", failures)
    for required_term in ("func set_intensity(value: int) -> void", "GridIntensity.EXPRESSIVE", 'set_shader_parameter("dot_scale", dot_scale)', "minor_alpha = 0.72", "dot_scale = 1.42"):
        if required_term not in grid_renderer_text:
            fail(f"board grid renderer intensity contract is missing: {required_term}", failures)
    grid_preview_path = ROOT / "scripts/ui/grid_intensity_preview.gd"
    if not grid_preview_path.is_file():
        fail("grid intensity live preview is missing", failures)
    else:
        grid_preview_text = grid_preview_path.read_text(encoding="utf-8")
        for required_term in ("class_name GridIntensityPreview", "func set_intensity(value: int) -> void", "GridIntensity.EXPRESSIVE", "draw_circle"):
            if required_term not in grid_preview_text:
                fail(f"grid intensity preview contract is missing: {required_term}", failures)
    if "uniform float dot_scale" not in grid_shader_text:
        fail("board grid shader does not support intensity-dependent dot sizing", failures)
    for required_term in ("library_root", "CompressionCpuMode", "set_library_root", "set_compression_cpu_mode", "auto_optimize_video"):
        if required_term not in settings_text:
            fail(f"Stage 7 settings contract is missing: {required_term}", failures)
    library_service_text = (ROOT / "scripts/assets/asset_library_service.gd").read_text(encoding="utf-8")
    for required_term in (
        "prepare_external_library",
        "replace_asset_primary_blob",
        "delete_blob_if_unreferenced_path",
        "_asset_blob_relpaths",
        '"blob_bytes"',
        '"active_blob_bytes"',
        "_add_path_size",
    ):
        if required_term not in library_service_text:
            fail(f"Stage 7.2 external-library/variant accounting contract is missing: {required_term}", failures)
    settings_dialog_text = (ROOT / "scripts/ui/settings_dialog.gd").read_text(encoding="utf-8")
    for required_term in ("PAGE_STORAGE", 'NotLightL10n.text("settings.storage.choose")', "prepare_external_library", "compression_cpu_mode"):
        if required_term not in settings_dialog_text:
            fail(f"Stage 7 storage UI contract is missing: {required_term}", failures)

    app_root_text = (ROOT / "scripts/app/app_root.gd").read_text(encoding="utf-8")
    for required_term in (
        "CONTENT_SCALE_MODE_DISABLED",
        "CONTENT_SCALE_ASPECT_IGNORE",
        "content_scale_size = Vector2i.ZERO",
    ):
        if required_term not in app_root_text:
            fail(f"Stage 7.2 responsive desktop content scaling contract is missing: {required_term}", failures)

    video_toolbar_text = (ROOT / "scripts/ui/video_context_toolbar.gd").read_text(encoding="utf-8")
    for required_term in ("rename_requested", "optimize_requested", "duplicate_requested", "set_toolbar_anchor"):
        if required_term not in video_toolbar_text:
            fail(f"VideoContextToolbar contract is missing: {required_term}", failures)

    required_public_methods: dict[str, tuple[str, ...]] = {
        "TextContextToolbar": ("update_context", "set_toolbar_anchor"),
        "NativeBoardView": (
            "get_editor_format_context",
            "apply_editor_font_size",
            "apply_editor_font_family",
            "apply_editor_alignment",
            "apply_editor_style_flag",
            "apply_editor_text_color",
            "apply_editor_background_color",
            "apply_editor_background_opacity",
            "apply_editor_list_type",
            "adjust_editor_list_indent",
        ),
        "TextBlockStore": (
            "get_record",
            "apply_record",
            "apply_style_range",
            "apply_style_flag_range",
            "apply_text_color_range",
            "set_paragraph_list_type",
            "adjust_paragraph_indent",
            "create_render_snapshot",
        ),
        "ImageStore": (
            "get_asset_id",
            "get_pixel_size",
            "get_aspect_ratio",
            "capture_record",
            "restore_record",
            "remap_record",
        ),
        "ImageAssetCache": (
            "configure",
            "set_upload_budget",
            "set_memory_limit_megabytes",
            "request_texture",
            "request_metadata",
            "get_intrinsic_size",
        ),
        "ImageContextToolbar": ("configure", "set_toolbar_anchor"),
        "AssetLibraryView": ("configure", "set_compact_mode"),
        "VideoBoardPlayer": ("configure", "set_display_name", "video_aspect_ratio", "set_expanded", "shutdown"),
        "VideoPlayerPool": ("configure", "activate", "deactivate", "deactivate_all", "toggle_expanded", "active_count", "refresh_player_names"),
        "VideoContextToolbar": ("configure", "set_toolbar_anchor"),
        "AssetInspectorPanel": ("configure", "show_asset", "clear_asset", "flush_pending"),
        "AssetLibraryService": ("import_image", "import_files", "get_asset", "resolve_asset_path", "rename_asset", "update_asset_details", "list_tags"),
    }
    asset_view_text = (ROOT / "scripts/ui/asset_library_view.gd").read_text(encoding="utf-8")
    for required_term in ("FULL_PAGE_SIZE: int = 120", "ScrollContainer.new()", 'stats.get("active_blob_bytes"', 'NotLightL10n.text("common.show_more_remaining"'):
        if required_term not in asset_view_text:
            fail(f"Stage 7.2 scalable Asset Library UI contract is missing: {required_term}", failures)

    hub_text = (ROOT / "scripts/ui/hub_screen.gd").read_text(encoding="utf-8")
    for required_term in ("BOARD_PAGE_SIZE: int = 120", "_boards_load_more_button", "_load_more_boards", "ScrollContainer.new()"):
        if required_term not in hub_text:
            fail(f"Stage 7.2 scalable board-list UI contract is missing: {required_term}", failures)

    # Stage 8 — centralized UX foundations and resource metadata.
    localization_text = (ROOT / "scripts/localization/localization_service.gd").read_text(encoding="utf-8")
    localization_facade_text = (ROOT / "scripts/localization/notlight_l10n.gd").read_text(encoding="utf-8")
    for required_term in (
        "CORE_LOCALIZATION_DIR",
        "register_module_localization",
        "scan_external_modules",
        "module_text",
        "_path_is_within",
        "not _module_paths.has(module_id)",
        "bind_text",
        "refresh_tree",
    ):
        if required_term not in localization_text:
            fail(f"Stage 8 localization/module contract is missing: {required_term}", failures)
    if '[autoload]' not in project_text or 'LocalizationRuntime="*res://scripts/localization/localization_service.gd"' not in project_text:
        fail("Stage 8 LocalizationRuntime autoload is missing", failures)
    for required_term in (
        "class_name NotLightL10n",
        "static func runtime() -> LocalizationRuntimeService",
        "connect_locale_changed",
        "bind_placeholder_text",
        "register_module_localization",
        "NotLightCoreRuFallback.strings()",
        "static var _core_bundles: Dictionary",
        'RUNTIME_NODE_NAME: StringName = &"LocalizationRuntime"',
        'OS.get_thread_caller_id() != OS.get_main_thread_id()',
    ):
        if required_term not in localization_facade_text:
            fail(f"Stage 8 parser-safe localization facade is missing: {required_term}", failures)
    facade_methods = set(
        re.findall(r"^static func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", localization_facade_text, re.MULTILINE)
    )
    for gd_path in ROOT.rglob("*.gd"):
        gd_text = gd_path.read_text(encoding="utf-8")
        for call_name in re.findall(r"\bNotLightL10n\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", gd_text):
            if call_name not in facade_methods:
                fail(
                    f"unknown NotLightL10n API call {call_name} in {gd_path.relative_to(ROOT)}",
                    failures,
                )
    if "class_name LocalizationRuntimeService" not in localization_text:
        fail("Stage 8 localization runtime lacks a globally typed service class", failures)
    for gd_path in ROOT.rglob("*.gd"):
        gd_text = gd_path.read_text(encoding="utf-8")
        if gd_path.name != "localization_service.gd" and re.search(r"\bLocalization\.", gd_text):
            fail(
                f"parser-unsafe bare Localization autoload reference remains in {gd_path.relative_to(ROOT)}",
                failures,
            )
    for locale_name in ("ru",):
        if not (ROOT / f"localization/core/{locale_name}.json").is_file():
            fail(f"Stage 8 Russian core localization bundle is missing: {locale_name}.json", failures)

    fallback_text = (ROOT / "scripts/localization/core_ru_fallback.gd").read_text(encoding="utf-8")
    for required_term in ("class_name NotLightCoreRuFallback", "SOURCE_SHA256", "static func strings() -> Dictionary"):
        if required_term not in fallback_text:
            fail(f"Stage 8.2 Russian bootstrap localization fallback is missing: {required_term}", failures)
    export_preset_text = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    if "localization/core/*.json" not in export_preset_text:
        fail("Stage 8.2 export does not explicitly retain core localization JSON files", failures)

    palette_text = (ROOT / "scripts/theme/notlight_palette.gd").read_text(encoding="utf-8")
    for required_term in ("SEMANTIC_KEYS", "PRESET_HIGH_CONTRAST", "PRESET_CUSTOM", "text_on_accent"):
        if required_term not in palette_text:
            fail(f"Stage 8 semantic palette contract is missing: {required_term}", failures)

    settings_text = (ROOT / "scripts/settings/app_settings_store.gd").read_text(encoding="utf-8")
    for required_term in (
        "SETTINGS_SCHEMA_VERSION: int = 19",
        "WindowModePreference",
        "PerformanceProfile",
        "get_performance_budget",
        "apply_render_policy",
        "custom_active_video_players",
        "custom_active_note_workspace_surfaces",
        "prefer_maximum_fps",
        "monitor_interval_seconds",
        "palette_id",
        "locale",
    ):
        if required_term not in settings_text:
            fail(f"Stage 8 centralized settings contract is missing: {required_term}", failures)
    for required_term in ("allow_performance_edit", "settings.performance.locked", "SpinBox", "ColorPickerButton"):
        if required_term not in settings_dialog_text:
            fail(f"Stage 8 settings UX contract is missing: {required_term}", failures)
    if "PRESET_DARK" in palette_text or "settings.palette.dark" in settings_dialog_text:
        fail("Stage 8.3 dark palette must not be exposed by the application", failures)
    for required_term in ("user_palette_presets", "save_user_palette_preset", "delete_user_palette_preset", "MAX_USER_PALETTE_PRESETS"):
        if required_term not in settings_text:
            fail(f"Stage 8.3 saved palette preset contract is missing: {required_term}", failures)
    for required_term in ("settings.palette.save_preset", "_rebuild_palette_options", "_on_save_palette_preset_pressed"):
        if required_term not in settings_dialog_text:
            fail(f"Stage 8.3 saved palette UX contract is missing: {required_term}", failures)

    telemetry_text = (ROOT / "scripts/performance/performance_telemetry_service.gd").read_text(encoding="utf-8")
    for required_term in ("Performance.TIME_FPS", "Performance.RENDER_VIDEO_MEM_USED", "OS.create_process", "WINDOWS_PROBE_MIN_INTERVAL", "set_monitoring_active", "_monitoring_active"):
        if required_term not in telemetry_text:
            fail(f"Stage 8 performance telemetry contract is missing: {required_term}", failures)

    catalog_text = (ROOT / "scripts/assets/asset_catalog.gd").read_text(encoding="utf-8")
    for required_term in ("SCHEMA_VERSION: int = 2", '"description"', '"tags"', "_sanitize_tags"):
        if required_term not in catalog_text:
            fail(f"Stage 8 Asset Catalog metadata contract is missing: {required_term}", failures)
    for required_term in ("update_asset_details", "list_tags", "_asset_matches_tokens", 'needle.begins_with("tag:")'):
        if required_term not in library_service_text:
            fail(f"Stage 8 searchable resource metadata contract is missing: {required_term}", failures)
    inspector_text = (ROOT / "scripts/ui/asset_inspector_panel.gd").read_text(encoding="utf-8")
    for required_term in (
        "AssetInspectorPanel", "DESCRIPTION_SAVE_DELAY", "ScrollContainer.new()",
        "HFlowContainer.new()", "follow_focus = true", "text_overrun_behavior",
        "_pdf_cancel_button.visible = optimizing", "update_asset_details", "used_on_boards",
    ):
        if required_term not in inspector_text:
            fail(f"Stage 8 Resource Inspector contract is missing: {required_term}", failures)

    image_store_text = (ROOT / "scripts/core/image_store.gd").read_text(encoding="utf-8")
    video_store_text = (ROOT / "scripts/core/video_store.gd").read_text(encoding="utf-8")
    for label, store_text in (("ImageStore", image_store_text), ("VideoStore", video_store_text)):
        for required_term in ("instance_titles: PackedStringArray", "get_instance_title", "set_instance_title", '"instance_title"'):
            if required_term not in store_text:
                fail(f"Stage 8 {label} instance-metadata contract is missing: {required_term}", failures)
    if "UpdateAssetInstanceTitleCommand" not in board_screen_text:
        fail("Stage 8 board-local asset title command is not integrated into BoardScreen", failures)

    if "PerformanceMonitorStrip.new()" not in board_screen_text:
        fail("Stage 8.2 board performance monitor strip is missing", failures)

    app_root_text = (ROOT / "scripts/app/app_root.gd").read_text(encoding="utf-8")
    for required_term in ("telemetry.set_monitoring_active(false)", "telemetry.set_monitoring_active(true)"):
        if required_term not in app_root_text:
            fail(f"Stage 8.2 Hub/board telemetry lifecycle is missing: {required_term}", failures)

    repository_text = (ROOT / "scripts/data/board_repository.gd").read_text(encoding="utf-8")
    for required_term in ("_read_best_manifest", "Hub discovery is intentionally manifest-first", "repair the", "_rebuild_index_from_manifests"):
        if required_term not in repository_text:
            fail(f"Stage 8.2 board recovery contract is missing: {required_term}", failures)

    if "InspectorTextEdit" not in inspector_text or "InspectorTextEdit" not in theme_text:
        fail("Stage 8.2 Resource Inspector description field is not using the NotLight theme", failures)
    for required_term in ("compact_row.clip_contents = true", "_search_edit.custom_minimum_size = Vector2(0.0, 42.0)", "_tag_filter.custom_minimum_size = Vector2(0.0, 42.0)"):
        if required_term not in asset_view_text:
            fail(f"Stage 8.2 compact Resource Library overflow guard is missing: {required_term}", failures)

    for class_name, method_names in required_public_methods.items():
        class_path = global_classes.get(class_name)
        if class_path is None:
            continue
        class_text = class_path.read_text(encoding="utf-8")
        for method_name in method_names:
            if re.search(rf"^func\s+{re.escape(method_name)}\s*\(", class_text, re.MULTILINE) is None:
                fail(f"public API mismatch: {class_name}.{method_name} is missing", failures)

    # Require current canonical architecture/release documentation rather than
    # historical milestone notes that are not part of the maintained tree.
    for required_doc in (
        "README.md",
        "docs/AUDIO_MASTER_AND_BACKGROUND_MUSIC.md",
        "docs/PDF_SUPPORT.md",
        "docs/MODULE_API_V1.md",
        "docs/MANUAL_TEST_CHECKLIST.md",
        "RELEASE_COMPLIANCE.md",
        "CORRESPONDING_SOURCE.md",
    ):
        if not (ROOT / required_doc).is_file():
            fail(f"project documentation is missing: {required_doc}", failures)

    # Stage 9 — DOD drawing, binary stroke points, compact adaptive board UI.
    stroke_store_text = (ROOT / "scripts/core/stroke_store.gd").read_text(encoding="utf-8")
    for required_term in (
        "PackedVector2Array",
        "point_offsets",
        "point_counts",
        "encode_binary_payload",
        "apply_binary_payload",
        "var_to_bytes",
        "bytes_to_var",
        "style_width_multiplier",
        "visual_padding_for",
        "recommended_bounds_for_world_points",
        "apply_style_with_world_geometry",
        "spray_spreads",
        "spray_spread",
        "editor_max_width_for_style",
        "get_point_count",
    ):
        if required_term not in stroke_store_text:
            fail(f"Stage 9 StrokeStore DOD/binary contract is missing: {required_term}", failures)
    if re.search(r'"points"\s*:', stroke_store_text[stroke_store_text.find("func serialize"):stroke_store_text.find("func deserialize")]):
        fail("Stage 9 StrokeStore serialize() must keep point arrays out of board JSON", failures)
    if re.search(r"(?:var_to_bytes|bytes_to_var)\([^\n]*,\s*false\)", stroke_store_text):
        fail("Stage 9 uses an invalid Godot 4.4 Variant serialization call signature", failures)

    stroke_renderer_text = (ROOT / "scripts/render/stroke_batch_renderer.gd").read_text(encoding="utf-8")
    for required_term in ("class_name StrokeBatchRenderer", "max_visible_stroke_segments", "draw_polyline", "STYLE_HIGHLIGHTER", "STYLE_PENCIL", "STYLE_SPRAY", "MultiMesh", "draw_multimesh", "Geometry2D.offset_polyline", "max_spray_particles_per_stroke"):
        if required_term not in stroke_renderer_text:
            fail(f"Stage 9 stroke batch renderer contract is missing: {required_term}", failures)
    if "var record: Dictionary = _spray_cache_record(entity_id)" in stroke_renderer_text[stroke_renderer_text.find("func _estimated_spray_cost"):stroke_renderer_text.find("func _prune_spray_cache")]:
        fail("Stage 9.2 spray budget estimation must not build a MultiMesh before deciding whether a stroke fits the frame budget", failures)
    if "Line2D.new()" in stroke_renderer_text or "Node2D.new()" in stroke_store_text:
        fail("Stage 9 strokes must not materialize one SceneTree node per stroke", failures)

    drawing_palette_text = (ROOT / "scripts/ui/drawing_tool_palette.gd").read_text(encoding="utf-8")
    stroke_toolbar_text = (ROOT / "scripts/ui/stroke_context_toolbar.gd").read_text(encoding="utf-8")
    for required_term in ("TOOL_DRAW", "ACTION_DRAW_STROKE", "ACTION_ERASE_STROKES", "CreateStrokeCommand", "hit_test_segment", "BoardEntityTypes.STROKE"):
        if required_term not in board_view_text:
            fail(f"Stage 9 NativeBoardView drawing contract is missing: {required_term}", failures)
    for required_term in ("DrawingToolPalette", "StrokeContextToolbar", "_layout_status_controls", "set_maximum_width"):
        if required_term not in board_screen_text:
            fail(f"Stage 9 BoardScreen drawing/adaptive UI contract is missing: {required_term}", failures)
    for required_term in ("drawing.presets", "save_user_drawing_preset", "eraser_radius"):
        if required_term not in drawing_palette_text and required_term not in settings_text:
            fail(f"Stage 9 drawing preset UX contract is missing: {required_term}", failures)
    for required_term in ("HFlowContainer", "width_requested", "spray_spread_requested", "color_picker_requested"):
        if required_term not in stroke_toolbar_text:
            fail(f"Stage 9.2 stroke context toolbar contract is missing: {required_term}", failures)
    if "style_requested" in stroke_toolbar_text:
        fail("Stage 9.2 selected strokes must not expose tool-style conversion in the context toolbar", failures)

    repository_text = (ROOT / "scripts/data/board_repository.gd").read_text(encoding="utf-8")
    for required_term in ("STROKE_PAYLOAD_PREFIX", "_write_binary_atomic", "_read_stroke_payload", "_cleanup_stale_stroke_payloads", "_materialize_board_pair", "store_buffer", "get_buffer"):
        if required_term not in repository_text:
            fail(f"Stage 9 board binary-sidecar durability contract is missing: {required_term}", failures)
    if '"storage_version": 5' not in repository_text:
        fail("Stage 9 board manifest storage version is not 5", failures)

    performance_strip_text = (ROOT / "scripts/ui/performance_monitor_strip.gd").read_text(encoding="utf-8")
    for required_term in ("set_maximum_width", "removal_order", "visibility_layout_changed"):
        if required_term not in performance_strip_text:
            fail(f"Stage 9 adaptive performance monitor contract is missing: {required_term}", failures)
    color_picker_style_text = (ROOT / "scripts/ui/notlight_color_picker_style.gd").read_text(encoding="utf-8")
    for required_term in ("presets_visible = false", "sliders_visible = advanced", 'add_theme_constant_override("sv_height"', "popup.max_size"):
        if required_term not in color_picker_style_text:
            fail(f"Stage 9.2 centralized ColorPicker contract is missing: {required_term}", failures)
    telemetry_text = (ROOT / "scripts/performance/performance_telemetry_service.gd").read_text(encoding="utf-8")
    for required_term in ("FPS_SAMPLE_INTERVAL", "_fps_timer", "_system_timer", "_sample_fps", "_sample_system"):
        if required_term not in telemetry_text:
            fail(f"Stage 9.2 split telemetry timing contract is missing: {required_term}", failures)
    for required_term in ("developer_diagnostics_enabled", "record_developer_counter", "record_developer_timing_usec", "set_developer_gauge"):
        if required_term not in telemetry_text:
            fail(f"Stage 9.3 developer diagnostics contract is missing: {required_term}", failures)

    for required_term in (
        "save_developer_report",
        "start_developer_recording",
        "stop_developer_recording",
        "reset_developer_session",
        "DIAGNOSTICS_TRACE_SCHEMA",
        "DIAGNOSTICS_REPORT_SCHEMA",
        "hitch_33ms",
        "hitch_50ms",
        "hitch_100ms",
        "dev_session_frame_delta_max_ms",
    ):
        if required_term not in telemetry_text:
            fail(f"Stage 9.4 diagnostics capture contract is missing: {required_term}", failures)

    if "var developer_diagnostics_enabled: bool = false" not in settings_text:
        fail("Stage 9.3 developer diagnostics must remain opt-in by default", failures)
    for required_term in ("PAGE_DEVELOPER", "settings.nav.developer", "_build_developer_page", "_on_developer_diagnostics_toggled"):
        if required_term not in settings_dialog_text:
            fail(f"Stage 9.3 developer settings UX contract is missing: {required_term}", failures)

    developer_panel_path = ROOT / "scripts/ui/developer_diagnostics_panel.gd"
    if not developer_panel_path.is_file():
        fail("Stage 9.3 developer diagnostics panel is missing", failures)
    else:
        developer_panel_text = developer_panel_path.read_text(encoding="utf-8")
        for required_term in (
            "developer.diagnostics.frame_line_v4",
            "developer.diagnostics.engine_line",
            "developer.diagnostics.objects_line",
            "developer.diagnostics.visibility_line_v2",
            "developer.diagnostics.stroke_prepare_line",
            "developer.diagnostics.context_line_v2",
            "dev_visible_candidates_total",
            "dev_session_frame_delta_max_ms",
            "dev_stroke_effective_lod",
            "dev_stroke_simplify_cache_misses_per_second",
            "dev_candidate_filter_max_ms",
            "dev_spatial_index_size",
            "dev_context_anchor_dirty",
            "save_developer_report",
            "start_developer_recording",
            "stop_developer_recording",
            "TextServer.AUTOWRAP_WORD_SMART",
            "OS.shell_show_in_file_manager",
        ):
            if required_term not in developer_panel_text:
                fail(f"Stage 9.4 developer diagnostics UI contract is missing: {required_term}", failures)
        if "OVERRUN_TRIM_ELLIPSIS" in developer_panel_text:
            fail("Stage 9.4 developer diagnostics must wrap instead of truncating metric lines", failures)

    hub_screen_text = (ROOT / "scripts/ui/hub_screen.gd").read_text(encoding="utf-8")
    app_root_text = (ROOT / "scripts/app/app_root.gd").read_text(encoding="utf-8")
    for required_term in ("signal exit_requested", "hub.exit_tooltip", "exit_requested.emit"):
        if required_term not in hub_screen_text:
            fail(f"Stage 9.4 hub exit UX contract is missing: {required_term}", failures)
    for required_term in ("hub.exit_requested.connect(_request_application_exit)", "func _request_application_exit()"):
        if required_term not in app_root_text:
            fail(f"Stage 9.4 application-exit contract is missing: {required_term}", failures)

    for renderer_path in (
        ROOT / "scripts/render/image_batch_renderer.gd",
        ROOT / "scripts/render/video_batch_renderer.gd",
        ROOT / "scripts/render/audio_batch_renderer.gd",
        ROOT / "scripts/render/stroke_batch_renderer.gd",
        ROOT / "scripts/render/connector_batch_renderer.gd",
    ):
        renderer_text = renderer_path.read_text(encoding="utf-8")
        if "candidate_ids: PackedInt64Array" not in renderer_text:
            fail(f"Stage 9.3 shared visibility candidate contract is missing in {renderer_path.name}", failures)
        if "spatial_index.query_rect" in renderer_text:
            fail(f"Stage 9.3 renderer bypasses shared visibility in {renderer_path.name}", failures)

    for required_term in (
        "_flush_render_refresh_queue",
        "_ensure_shared_visibility",
        "MAX_RENDER_REBUILDS_WHILE_MOVING",
        "_zoom_bucket_with_hysteresis",
        "_stroke_render_lod",
        "_connector_render_lod",
        "_context_anchor_dirty",
        "_publish_context_anchor",
        "_recover_pointer_pan_release",
        "_pointer_pan_input_held",
        "_schedule_deferred_view_refresh_if_ready",
        "VIEW_RENDER_DEBOUNCE_SECONDS",
        "COVERAGE_RETENTION_AREA_RATIO",
        "_coverage_is_reusable",
        "_current_stroke_lod_level",
        "STROKE_FULL_ENTER_ZOOM",
        "_target_visible_world_rect",
        "get_developer_diagnostics_snapshot",
        "candidate_filter",
        ".intersects(requested_coverage, true)",
        "Returning that whole set to every renderer",
        "Context UI follows perceived input idle",
    ):
        if required_term not in board_view_text:
            fail(f"Stage 9.4 NativeBoardView optimization contract is missing: {required_term}", failures)

    text_refresh_match = re.search(
        r"func _perform_text_refresh\(force: bool\) -> bool:(.*?)(?=\nfunc )",
        board_view_text,
        re.DOTALL,
    )
    stroke_refresh_match = re.search(
        r"func _perform_stroke_refresh\(force: bool\) -> bool:(.*?)(?=\nfunc )",
        board_view_text,
        re.DOTALL,
    )
    if text_refresh_match is None or "_current_lod_level(render_zoom)" not in text_refresh_match.group(1):
        fail("Stage 9.4 text refresh must use the board LOD, not the stroke-specific LOD", failures)
    if stroke_refresh_match is None or "_current_stroke_lod_level(render_zoom)" not in stroke_refresh_match.group(1):
        fail("Stage 9.4 stroke refresh must use the stroke-specific retained-geometry LOD", failures)

    for required_term in (
        "if should_show and not was_requested",
        "_reposition_context_toolbars",
        "context_refreshes",
        "context_repositions",
    ):
        if required_term not in board_screen_text:
            fail(f"Stage 9.4 BoardScreen contextual-HUD contract is missing: {required_term}", failures)

    stroke_geometry_text = (ROOT / "scripts/core/stroke_geometry.gd").read_text(encoding="utf-8")
    for required_term in (
        "_draw_far_lod_stroke",
        "_estimated_render_cost_for_lod",
        "_estimated_full_source_cost",
        "TARGET_RETAINED_STROKE_SEGMENTS_FULL",
        "TARGET_RETAINED_STROKE_SEGMENTS_MEDIUM",
        "TARGET_RETAINED_STROKE_SEGMENTS_LOW",
        "TARGET_RETAINED_STROKE_SEGMENTS_PLACEHOLDER",
        "_configure_adaptive_lod",
        "_effective_segment_budget",
        "stroke_simplify_cache_hits",
        "stroke_simplify",
    ):
        if required_term not in stroke_renderer_text:
            fail(f"Stage 9.4 bounded stroke render path is missing: {required_term}", failures)
    adaptive_lod_match = re.search(
        r"func _configure_adaptive_lod\(\) -> void:(.*?)(?=\nfunc )",
        stroke_renderer_text,
        re.DOTALL,
    )
    if adaptive_lod_match is None:
        fail("Stage 9.4 adaptive stroke LOD function cannot be inspected", failures)
    else:
        adaptive_body = adaptive_lod_match.group(1)
        budget_assignment = adaptive_body.find("_effective_segment_budget = target_segments")
        full_return_guard = adaptive_body.find("if lod_cap <= 0:")
        if budget_assignment < 0 or full_return_guard < 0 or budget_assignment > full_return_guard:
            fail(
                "Stage 9.4 FULL stroke path must apply its retained-segment target before the FULL LOD early return",
                failures,
            )
        if "estimated_full_cost > target_segments" not in adaptive_body:
            fail("Stage 9.4 dense FULL stroke fallback must use weighted retained-cost estimation", failures)
    if '"user_data_dir"' in telemetry_text:
        fail("Developer diagnostics reports must not expose the local user-data directory", failures)
    if "settings.developer_diagnostics_enabled" not in telemetry_text or "show_system = (" not in telemetry_text:
        fail("Developer diagnostics must keep system telemetry sampling active even when ordinary HUD counters are hidden", failures)
    if 'var uses_windows_process_probe: bool = (' not in telemetry_text or 'if not uses_windows_process_probe or not _last_sample.has("ram_bytes"):' not in telemetry_text:
        fail("Windows process RAM telemetry must preserve the last WorkingSet64 sample instead of oscillating with allocator-only static memory", failures)
    if "if not settings.developer_diagnostics_enabled and not settings.show_cpu and not settings.show_ram:" not in telemetry_text:
        fail("Developer diagnostics must keep the Windows CPU/RAM probe available even when ordinary HUD counters are hidden", failures)
    if "clampi(max_particles, 8, 6000)" not in stroke_renderer_text:
        fail("Stage 9.4 spray MultiMesh minimum must match the adaptive retained-particle minimum", failures)

    # Stage 9.5 — audio assets, voice notes, local media naming and search foundation.
    audio_store_path = ROOT / "scripts/core/audio_store.gd"
    audio_media_path = ROOT / "scripts/media/audio_media_service.gd"
    voice_recording_path = ROOT / "scripts/media/voice_recording_service.gd"
    audio_renderer_path = ROOT / "scripts/render/audio_batch_renderer.gd"
    audio_player_path = ROOT / "scripts/ui/audio_board_player.gd"
    audio_pool_path = ROOT / "scripts/ui/audio_player_pool.gd"
    audio_toolbar_path = ROOT / "scripts/ui/audio_context_toolbar.gd"
    search_snapshot_path = ROOT / "scripts/search/board_search_snapshot.gd"
    credits_dialog_path = ROOT / "scripts/ui/credits_dialog.gd"
    stage95_paths = (
        audio_store_path, audio_media_path, voice_recording_path, audio_renderer_path,
        audio_player_path, audio_pool_path, audio_toolbar_path, search_snapshot_path, credits_dialog_path,
    )
    for stage95_path in stage95_paths:
        if not stage95_path.is_file():
            fail(f"Stage 9.5 runtime file is missing: {stage95_path.relative_to(ROOT)}", failures)

    if audio_store_path.is_file():
        audio_store_text = audio_store_path.read_text(encoding="utf-8")
        for required_term in (
            "PackedInt64Array", "PackedStringArray", "PackedInt32Array",
            "instance_titles", "duration_msec", "playback_flags",
            "_index_by_id", "func serialize() -> Array[Dictionary]", "func deserialize(records: Array) -> void",
        ):
            if required_term not in audio_store_text:
                fail(f"Stage 9.5 AudioStore DOD contract is missing: {required_term}", failures)

    entity_types_text = (ROOT / "scripts/core/board_entity_types.gd").read_text(encoding="utf-8")
    if 'const AUDIO: StringName = &"audio"' not in entity_types_text or "AUDIO," not in entity_types_text:
        fail("Stage 9.5 audio entity type is not registered as a built-in board type", failures)
    board_model_text = (ROOT / "scripts/core/board_model.gd").read_text(encoding="utf-8")
    for required_term in ("var audios: AudioStore", "audio_revision", "stores.register_store(audios)"):
        if required_term not in board_model_text:
            fail(f"Stage 9.5 BoardModel audio contract is missing: {required_term}", failures)
    for function_name in ("set_entity_transform", "set_entity_z_order", "set_entity_flags"):
        match = re.search(rf"func {function_name}\(.*?(?=\nfunc )", board_model_text, re.DOTALL)
        if match is None or "_increment_type_revision(type_id)" not in match.group(0):
            fail(f"Stage 9.5 {function_name} must invalidate its category retained renderer", failures)
    revision_helper_match = re.search(
        r"func _increment_type_revision\(type_id: StringName\) -> void:(.*?)(?=\nfunc |\Z)",
        board_model_text,
        re.DOTALL,
    )
    if revision_helper_match is None or "BoardEntityTypes.AUDIO" not in revision_helper_match.group(1) or "audio_revision += 1" not in revision_helper_match.group(1):
        fail("Stage 9.5 category revision helper must invalidate retained audio", failures)

    if audio_media_path.is_file():
        audio_media_text = audio_media_path.read_text(encoding="utf-8")
        for required_term in (
            "AudioStreamWAV.load_from_file", "AudioStreamMP3.load_from_file",
            "AudioStreamOggVorbis.load_from_file", "request_prepare", "showwavespic",
            "OS.create_process", "PLAYBACK_FILE", "WAVEFORM_FILE",
            "REQUEST_PLAYBACK", "REQUEST_WAVEFORM", "_queued_request_flags",
            "_active_request_flags", "_failed_request_flags",
            "request_prepare(asset_id, false, true)", "request_prepare(asset_id, true, false)",
        ):
            if required_term not in audio_media_text:
                fail(f"Stage 9.5 AudioMediaService contract is missing: {required_term}", failures)
        ensure_match = re.search(
            r"func ensure_asset\(asset_id: String\) -> Dictionary:(.*?)(?=\nfunc )",
            audio_media_text,
            re.DOTALL,
        )
        if ensure_match is None or "request_prepare(asset_id, false, true)" not in ensure_match.group(1):
            fail("Stage 9.5 board placement must prepare waveform without eagerly transcoding playback", failures)
        waveform_match = re.search(
            r"func get_waveform\(asset_id: String, request_if_missing: bool = true\) -> Texture2D:(.*?)(?=\nfunc )",
            audio_media_text,
            re.DOTALL,
        )
        if waveform_match is None or "_enqueue_request_flags(clean_id, REQUEST_WAVEFORM)" not in waveform_match.group(1):
            fail("Stage 9.5 retained audio cards must enqueue waveform-only preparation", failures)
        if waveform_match is not None and ("FileAccess" in waveform_match.group(1) or "resolve_asset_path" in waveform_match.group(1)):
            fail("Stage 9.5 retained audio waveform requests must stay disk-free inside the draw path", failures)
        playback_match = re.search(
            r"func resolve_playback_path\(asset_id: String, request_if_missing: bool = true\) -> String:(.*?)(?=\nfunc )",
            audio_media_text,
            re.DOTALL,
        )
        if playback_match is None or "request_prepare(asset_id, true, false)" not in playback_match.group(1):
            fail("Stage 9.5 playback must request transcode independently from waveform preparation", failures)
        if playback_match is None or 'return ""' not in playback_match.group(1) or "_requires_compatibility_playback" not in playback_match.group(1):
            fail("Stage 9.5 non-Vorbis OGG playback must wait for a derived Vorbis stream", failures)
        metadata_match = re.search(
            r"func get_metadata\(asset_id: String, force_refresh: bool = false\) -> Dictionary:(.*?)(?=\nfunc )",
            audio_media_text,
            re.DOTALL,
        )
        if metadata_match is None or metadata_match.group(1).find("_metadata_cache[clean_id]") > metadata_match.group(1).find('metadata["playback_path"]'):
            fail("Stage 9.5 codec metadata must be cached before OGG playback-path resolution", failures)
        for required_term in (
            "PLAYBACK_TEMP_FILE", "WAVEFORM_TEMP_FILE", "func _exit_tree() -> void",
            "OS.kill(_active_pid)", "_promote_stage_output", "DirAccess.rename_absolute",
            "_remove_partial_stage_output", "_is_nonempty_file",
        ):
            if required_term not in audio_media_text:
                fail(f"Stage 9.5 atomic audio-derivation cleanup contract is missing: {required_term}", failures)
        if 'ProjectSettings.globalize_path(output_path)' not in audio_media_text:
            fail("Stage 9.5 FFmpeg audio derivation must target staging files, not stable cache names", failures)
        for required_term in (
            "if _is_nonempty_file(derived):",
            "if path == derived_path:",
            "_clear_failed_flag(clean_id, REQUEST_PLAYBACK)",
            'metadata["audio_codec"] = "runtime_loader_failed"',
        ):
            if required_term not in audio_media_text:
                fail(f"Stage 9.5 audio decoder/cache recovery contract is missing: {required_term}", failures)

    if voice_recording_path.is_file():
        voice_text = voice_recording_path.read_text(encoding="utf-8")
        for required_term in (
            "AudioEffectRecord", "AudioStreamMicrophone", "RECORD_BUS_NAME",
            "set_recording_active(true)", "save_to_wav", "library.import_files",
            'ProjectSettings.get_setting_with_override(&"audio/driver/enable_input"',
        ):
            if required_term not in voice_text:
                fail(f"Stage 9.5 voice recording contract is missing: {required_term}", failures)
    if 'driver/enable_input=true' not in project_text:
        fail("Stage 9.5 microphone input is not enabled in project.godot", failures)

    if audio_renderer_path.is_file():
        audio_renderer_text = audio_renderer_path.read_text(encoding="utf-8")
        for required_term in (
            "candidate_ids: PackedInt64Array", "max_visible", "get_waveform",
            "_draw_waveform_placeholder", "var request_waveform: bool = not compact",
            "get_waveform(asset_id, request_waveform)",
        ):
            if required_term not in audio_renderer_text:
                fail(f"Stage 9.5 audio retained-render contract is missing: {required_term}", failures)
        if "spatial_index.query_rect" in audio_renderer_text:
            fail("Stage 9.5 audio renderer bypasses shared visibility", failures)

    for required_term in (
        "RENDER_REFRESH_AUDIO", "_perform_audio_refresh", "_shared_audio_candidates",
        "create_audio_from_asset", "audio_open_requested", "focus_single_selection",
        "DEFAULT_AUDIO_SIZE",
    ):
        if required_term not in board_view_text:
            fail(f"Stage 9.5 NativeBoardView audio/focus contract is missing: {required_term}", failures)
    for required_term in (
        "_build_audio_player", "_build_audio_import_dialog", "_queue_audio_placement",
        "_toggle_voice_recording", "_open_selected_audio_rename_dialog", "KEY_F",
        "objects_audios", "AudioContextToolbar",
        "var audio_source_path: String = asset_library.resolve_asset_path(audio_asset_id)",
    ):
        if required_term not in board_screen_text:
            fail(f"Stage 9.5 BoardScreen audio/voice UX contract is missing: {required_term}", failures)
    asset_card_text = (ROOT / "scripts/ui/asset_library_card.gd").read_text(encoding="utf-8")
    if "_kind == AssetKinds.AUDIO" not in asset_card_text:
        fail("Stage 9.5 Resource Library audio cards must expose the board-insert action", failures)
    for required_term in (
        "var _audio_media: AudioMediaService",
        "_audio_media.get_waveform(asset_id)",
        "_on_audio_waveform_ready",
    ):
        if required_term not in asset_card_text:
            fail(f"Stage 9.5 Resource Library audio-preview contract is missing: {required_term}", failures)
    asset_view_text = (ROOT / "scripts/ui/asset_library_view.gd").read_text(encoding="utf-8")
    if "audio_service: AudioMediaService = null" not in asset_view_text or "video_media, audio_media" not in asset_view_text:
        fail("Stage 9.5 Resource Library must pass the bounded AudioMediaService into visible audio cards", failures)
    hit_test_text = (ROOT / "scripts/core/board_hit_test_system.gd").read_text(encoding="utf-8")
    fallback_hit_match = re.search(
        r"func _fallback_scan_dense_objects\(world_position: Vector2, tolerance: float\) -> int:(.*?)(?=\nfunc )",
        hit_test_text,
        re.DOTALL,
    )
    if fallback_hit_match is None or "model.audios.entity_ids" not in fallback_hit_match.group(1):
        fail("Stage 9.5 dense-object hit-test fallback must include audio entities", failures)
    name_dialog_text = (ROOT / "scripts/ui/name_dialog.gd").read_text(encoding="utf-8")
    if "allow_empty: bool = false" not in name_dialog_text or "not _allow_empty_submission" not in name_dialog_text:
        fail("Stage 9.5 board-local media rename must support clearing an override without weakening other name dialogs", failures)
    instance_rename_match = re.search(
        r"func _open_instance_rename_dialog\(entity_id: int, type_id: StringName\) -> void:(.*?)(?=\nfunc )",
        board_screen_text,
        re.DOTALL,
    )
    if instance_rename_match is None or '{"name": global_name}' not in instance_rename_match.group(1) or "instance_title," not in instance_rename_match.group(1):
        fail("Stage 9.5 board-local rename dialog must distinguish a blank local override from the global Library name", failures)
    rename_apply_match = re.search(
        r"func _rename_selected_asset\(new_name: String\) -> void:(.*?)(?=\nfunc )",
        board_screen_text,
        re.DOTALL,
    )
    if rename_apply_match is None or "if after.is_empty()" in rename_apply_match.group(1):
        fail("Stage 9.5 clearing a board-local media title must restore Library-name inheritance", failures)
    audio_context_match = re.search(
        r"if _audio_toolbar != null:(.*?)(?=\n\tif _stroke_toolbar != null:)",
        board_screen_text,
        re.DOTALL,
    )
    if audio_context_match is None:
        fail("Stage 9.5 audio context-toolbar refresh block is missing", failures)
    elif "audio_media.resolve_playback_path" in audio_context_match.group(1):
        fail("Stage 9.5 merely selecting audio must not trigger playback transcoding", failures)

    if audio_pool_path.is_file():
        audio_pool_text = audio_pool_path.read_text(encoding="utf-8")
        if "BoardLiveSurfaceProjection.projected_rect" not in audio_pool_text or "set_inline_screen_size" not in audio_pool_text:
            fail("Stage 11.6 active audio projection contract is missing", failures)
        if "large_enough_for_controls" in audio_pool_text:
            fail("Stage 9.5.2 active audio must not disappear behind a minimum projected-size threshold", failures)
    video_pool_text = (ROOT / "scripts/ui/video_player_pool.gd").read_text(encoding="utf-8")
    if "BoardLiveSurfaceProjection.projected_rect" not in video_pool_text or "set_inline_screen_size" not in video_pool_text:
        fail("Stage 11.6 active video projection contract is missing", failures)
    if "large_enough_for_live_surface" in video_pool_text:
        fail("Stage 9.5.2 active video must not disappear behind a minimum projected-size threshold", failures)

    if search_snapshot_path.is_file():
        search_snapshot_text = search_snapshot_path.read_text(encoding="utf-8")
        for required_term in ("class_name BoardSearchSnapshot", "search_texts", "BoardEntityTypes.AUDIO", "instance_title"):
            if required_term not in search_snapshot_text:
                fail(f"Stage 9.5 board-search snapshot contract is missing: {required_term}", failures)

    if credits_dialog_path.is_file():
        credits_text = credits_dialog_path.read_text(encoding="utf-8")
        for required_term in ("credits.title", "credits.subtitle", "credits.body", "credits.license_note"):
            if required_term not in credits_text:
                fail(f"Stage 9.5 Credits localization contract is missing: {required_term}", failures)
    for required_term in ("CreditsDialog", "hub.credits_tooltip"):
        if required_term not in hub_screen_text:
            fail(f"Stage 9.5 Hub Credits contract is missing: {required_term}", failures)
    spray_estimate_match = re.search(
        r"func _estimated_spray_cost\(entity_id: int\) -> int:(.*?)(?=\nfunc )",
        stroke_renderer_text,
        re.S,
    )
    if spray_estimate_match is None or "return particle_limit" not in spray_estimate_match.group(1):
        fail("Stage 9.4 uncached spray cost must conservatively respect the retained-particle cap", failures)
    flush_match = re.search(r"DIAGNOSTICS_FLUSH_INTERVAL_MSEC: int = (\d+)", telemetry_text)
    if flush_match is None or int(flush_match.group(1)) < 2000:
        fail("Diagnostics trace flushing must be infrequent enough not to distort performance captures", failures)
    if '"board_name"' in board_screen_text or '"board_id"' in board_screen_text:
        fail("Shareable developer diagnostics context must not expose board names or board IDs", failures)
    for required_term in ("simplify_polyline", "simplify_polyline_fast", "_decimate_to_maximum"):
        if required_term not in stroke_geometry_text:
            fail(f"Stage 9.4 far-zoom stroke geometry contract is missing: {required_term}", failures)
    stroke_store_text = (ROOT / "scripts/core/stroke_store.gd").read_text(encoding="utf-8")
    if "get_local_points_decimated" not in stroke_store_text:
        fail("Stage 9.4 StrokeStore is missing bounded arena reads for render LOD", failures)
    connector_renderer_text = (ROOT / "scripts/render/connector_batch_renderer.gd").read_text(encoding="utf-8")
    for required_term in ("BoardRenderPolicy.LodLevel.PLACEHOLDER", "BoardRenderPolicy.LodLevel.LOW", "get_last_segment_count"):
        if required_term not in connector_renderer_text:
            fail(f"Stage 9.3 connector LOD contract is missing: {required_term}", failures)
    for required_term in ("spray_preview_particles", "stroke_smoothing_steps", "stroke_input_spacing_scale"):
        if required_term not in (ROOT / "scripts/core/board_render_policy.gd").read_text(encoding="utf-8"):
            fail(f"Stage 9.2 drawing quality policy is missing: {required_term}", failures)
    for required_term in ("_tool_group", "_spread_slider", "ScrollContainer", "editor_max_width_for_style"):
        if required_term not in drawing_palette_text:
            fail(f"Stage 9.2 drawing palette UX contract is missing: {required_term}", failures)

    theme_text = (ROOT / "scripts/ui/notlight_theme.gd").read_text(encoding="utf-8")
    if 'LibraryDrawerPanel' not in theme_text or 'library_drawer.shadow_size = 11' not in theme_text:
        fail("Stage 9 Resource Library drawer shadow contract is missing", failures)
    for required_term in ("SLIDER_GRABBER", 'set_icon("grabber", "HSlider"', 'semantic_color("accent")'):
        if required_term not in theme_text:
            fail(f"Stage 9.2 unified slider theme contract is missing: {required_term}", failures)

    # Stage 9.5.1 — parser regression guard and post-edit visual continuity.
    if '"build": NotLightL10n.text("developer.diagnostics.build_name")' not in telemetry_text:
        fail("Stage 9.7.4 developer diagnostics build metadata is stale", failures)

    board_model_text = (ROOT / "scripts/core/board_model.gd").read_text(encoding="utf-8")
    for required_term in (
        "var text_revision: int = 0",
        "var connector_revision: int = 0",
        "func _increment_type_revision(type_id: StringName) -> void",
    ):
        if required_term not in board_model_text:
            fail(f"Stage 9.5.1 category-revision contract is missing: {required_term}", failures)
    for required_term in (
        "var _text_commit_handoff_ids: Dictionary = {}",
        "var _stroke_commit_handoff_ids: Dictionary = {}",
        "func _sync_text_renderer_hidden_ids() -> void",
        "func _prune_commit_handoff_ids() -> void",
        "func _begin_content_handoff_quiet_window() -> void",
        "plan_matches_current_text_state",
        "_stroke_commit_handoff_ids[command.created_entity_id] = true",
        "_text_commit_handoff_ids[entity_id] = true",
        "_queue_all_render_refreshes(false)",
        "var revision: int = _runtime.model.text_revision",
        "var revision: int = _runtime.model.connector_revision",
    ):
        if required_term not in board_view_text:
            fail(f"Stage 9.5.1 edit-handoff/render-invalidation contract is missing: {required_term}", failures)
    if "canonical_smoothing_spacing" not in board_view_text:
        fail("Stage 9.5.1 live stroke preview must use the canonical commit smoothing spacing", failures)
    create_stroke_text = (ROOT / "scripts/core/create_stroke_command.gd").read_text(encoding="utf-8")
    if "runtime.begin_change_batch()" not in create_stroke_text or create_stroke_text.count("runtime.end_change_batch()") < 4:
        fail("Stage 9.5.1 stroke creation must batch model/store notifications before the retained handoff", failures)

    if "signal handoff_entities_ready(entity_ids: PackedInt64Array)" not in stroke_renderer_text:
        fail("Stage 9.5.1 retained stroke handoff signal is missing", failures)
    if audio_media_path.is_file():
        audio_media_text = audio_media_path.read_text(encoding="utf-8")
        if "_waveform_cache_order.erase(" in audio_media_text:
            fail("Stage 9.5.1 reintroduced PackedStringArray.erase() in AudioMediaService", failures)
        if "func _remove_waveform_cache_order_entry(asset_id: String) -> void" not in audio_media_text:
            fail("Stage 9.5.1 waveform-cache LRU removal helper is missing", failures)

    # Stage 9.5.2 — media UX, first-use microphone consent and handoff continuity.
    microphone_dialog_path = ROOT / "scripts/ui/microphone_permission_dialog.gd"
    waveform_view_path = ROOT / "scripts/ui/audio_waveform_view.gd"
    if not microphone_dialog_path.is_file():
        fail("Stage 9.5.2 microphone permission dialog is missing", failures)
    else:
        microphone_dialog_text = microphone_dialog_path.read_text(encoding="utf-8")
        for required_term in ("allow_requested", "decline_requested", "system_settings_requested", "voice.permission.privacy_note"):
            if required_term not in microphone_dialog_text:
                fail(f"Stage 9.5.2 microphone consent UI contract is missing: {required_term}", failures)
    if waveform_view_path.is_file():
        waveform_view_text = waveform_view_path.read_text(encoding="utf-8")
        for required_term in ("draw_texture_rect_region", "set_playback_progress", "played_background"):
            if required_term not in waveform_view_text:
                fail(f"Stage 9.5.2 active audio waveform-progress contract is missing: {required_term}", failures)
    for required_term in (
        "MICROPHONE_CONSENT_UNKNOWN", "MICROPHONE_CONSENT_ALLOWED",
        "MICROPHONE_CONSENT_DECLINED", "microphone_consent_state",
    ):
        if required_term not in settings_text:
            fail(f"Stage 9.5.2 persisted microphone-consent contract is missing: {required_term}", failures)
    if "driver/enable_input=true" not in (ROOT / "project.godot").read_text(encoding="utf-8"):
        fail("Stage 9.5.2 project must keep microphone audio input enabled", failures)
    if voice_recording_path.is_file():
        voice_recording_text = voice_recording_path.read_text(encoding="utf-8")
        for required_term in (
            "ProjectSettings.get_setting_with_override(&\"audio/driver/enable_input\")",
            "ms-settings:privacy-microphone", "voice.error.no_signal", "decode_s16",
        ):
            if required_term not in voice_recording_text:
                fail(f"Stage 9.5.2 voice input/privacy contract is missing: {required_term}", failures)
    if "Control.PRESET_TOP_LEFT" not in board_screen_text or "var box: VBoxContainer" not in board_screen_text:
        fail("Stage 9.5.2 lower-left board utility rail regression was reintroduced", failures)
    handoff_signal_match = re.search(
        r"func _on_stroke_renderer_handoff_ready\(ready_entity_ids: PackedInt64Array\) -> void:(.*?)(?=\nfunc )",
        board_view_text,
        re.DOTALL,
    )
    handoff_finalize_match = re.search(
        r"func _finalize_stroke_renderer_handoff\(ready_entity_ids: PackedInt64Array\) -> void:(.*?)(?=\nfunc )",
        board_view_text,
        re.DOTALL,
    )
    if handoff_signal_match is None or 'call_deferred("_finalize_stroke_renderer_handoff"' not in handoff_signal_match.group(1):
        fail("Stage 9.5.2 stroke handoff must defer ownership transfer until the active draw pass is finished", failures)
    if handoff_finalize_match is None or "_stroke_renderer.queue_redraw()" not in handoff_finalize_match.group(1):
        fail("Stage 9.5.2 stroke transient-to-retained handoff must redraw the retained layer immediately after deferred transfer", failures)
    name_dialog_text = (ROOT / "scripts/ui/name_dialog.gd").read_text(encoding="utf-8")
    for required_term in (
        "DEFAULT_DIALOG_SIZE: Vector2i = Vector2i(580, 390)",
        "popup_centered_clamped",
        "ScrollContainer.SCROLL_MODE_AUTO",
        "common.cancel",
        "KEY_ESCAPE",
        "close_button",
    ):
        if required_term not in name_dialog_text:
            fail(f"Stage 9.5.2 rename-dialog adaptive escape/action contract is missing: {required_term}", failures)

    # Stage 9.5.3 — reliable audio transport, scalable Library layout, board search and durable audio variants.
    board_search_panel_path = ROOT / "scripts/ui/board_search_panel.gd"
    if not board_search_panel_path.is_file():
        fail("Stage 9.5.3 board search panel is missing", failures)
    else:
        board_search_panel_text = board_search_panel_path.read_text(encoding="utf-8")
        for required_term in (
            "class_name BoardSearchPanel", "HFlowContainer", "MAX_VISIBLE_RESULTS",
            "PANEL_LEFT: float = 92.0", "func _filtered_results(query: String) -> Array[Dictionary]",
            "entity_requested.emit(entity_id)", "text_submitted.connect(_on_search_submitted)",
        ):
            if required_term not in board_search_panel_text:
                fail(f"Stage 9.5.3 board-search drawer contract is missing: {required_term}", failures)
        if "func _process(" in board_search_panel_text:
            fail("Stage 9.5.3 search panel must not add a permanent per-frame search loop", failures)

    for required_term in (
        "func _input(event: InputEvent) -> void", "KEY_F", "_toggle_board_search()",
        "_board_search_panel.close_panel()",
        "BoardSearchSnapshot.build(session.runtime.model, asset_library, note_repository)",
        "_board_view.focus_entity(entity_id, true)",
    ):
        if required_term not in board_screen_text:
            fail(f"Stage 9.5.3 BoardScreen search shortcut/focus contract is missing: {required_term}", failures)
    if "func focus_entity(entity_id: int, select_entity: bool = true) -> bool" not in board_view_text:
        fail("Stage 9.5.3 NativeBoardView public focus_entity API is missing", failures)

    if audio_player_path.is_file():
        audio_player_text = audio_player_path.read_text(encoding="utf-8")
        for required_term in (
            "has_stream_playback()", "_paused_position", "_pending_seek_position",
            "set_value_no_signal", "func _apply_seek_target(target: float, resume_after: bool) -> void",
            "func _on_seek_changed(value: float) -> void", "playback_variant_changed",
        ):
            if required_term not in audio_player_text:
                fail(f"Stage 9.5.3 audio transport contract is missing: {required_term}", failures)
        if "_player.play()\n\t\t_player.stream_paused = false" in audio_player_text:
            fail("Stage 9.5.3 audio resume path regressed to restarting playback from zero", failures)

    if audio_media_path.is_file():
        audio_media_text = audio_media_path.read_text(encoding="utf-8")
        for required_term in (
            "REQUEST_OPTIMIZE", "STAGE_OPTIMIZE", "libvorbis", "library.blobs.commit_temp",
            "func delete_original_variant(asset_id: String) -> bool",
            "func delete_optimized_variant(asset_id: String) -> bool",
            "replace_asset_primary_blob", "audio.optimize.original_required",
        ):
            if required_term not in audio_media_text:
                fail(f"Stage 9.5.3 durable audio-variant contract is missing: {required_term}", failures)
        if "if _variant_path(state, VARIANT_ORIGINAL).is_empty():\n\t\treturn false" not in audio_media_text:
            fail("Stage 9.5.3 must refuse lossy re-compression after the audio original was discarded", failures)

    durable_variants_path = ROOT / "scripts/assets/asset_durable_variants.gd"
    if not durable_variants_path.is_file():
        fail("Stage 9.6 durable-variant registry is missing", failures)
    else:
        durable_variants_text = durable_variants_path.read_text(encoding="utf-8")
        for required_term in (
            "class_name AssetDurableVariants",
            'const SUPPORTED_NAMESPACES: PackedStringArray = ["video", "audio", "pdf"]',
            "AssetKinds.VIDEO",
            "AssetKinds.AUDIO",
            "AssetKinds.PDF",
            "static func blob_relpaths(asset: Dictionary) -> PackedStringArray",
        ):
            if required_term not in durable_variants_text:
                fail(f"Stage 9.6 durable-variant registry contract is missing: {required_term}", failures)
    for required_term in (
        "AssetDurableVariants.blob_relpaths(asset)",
        "AssetDurableVariants.state_from_asset(asset)",
    ):
        if required_term not in asset_service_text:
            fail(f"Stage 9.6 Library durable-blob accounting is missing: {required_term}", failures)

    for required_term in (
        "FULL_FOLDER_WIDTH: float = 216.0", "FULL_INSPECTOR_WIDTH: float = 348.0",
        "FULL_GRID_CONTENT_GUTTER: float = 28.0",
        "FULL_MIN_COLUMNS_WITH_INSPECTOR: int = 2",
        "FULL_MIN_COLUMNS_WITH_FOLDER_AND_INSPECTOR: int = 3",
        "var _asset_host: Control", "var _inspector_host: Control",
        "_folder_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN",
        "_asset_host.resized.connect(_update_grid_columns)",
        "_inspector_host.size_flags_horizontal = Control.SIZE_SHRINK_END",
        "var available: float = maxf(FULL_CARD_WIDTH, _asset_host.size.x - FULL_GRID_CONTENT_GUTTER)",
        "var view_width: float = _body.size.x",
        "func _required_grid_host_width(column_count: int) -> float",
        "_inspector_host.custom_minimum_size",
        "inspector_replaces_asset_area",
    ):
        if required_term not in asset_view_text:
            fail(f"Stage 9.5.3 responsive Resource Library layout contract is missing: {required_term}", failures)
    if "_asset_area.size.x if _asset_area != null" in asset_view_text:
        fail("Stage 9.5.3 Resource Library reintroduced the GridContainer minimum-width feedback loop", failures)
    if "func _effective_layout_width() -> float" in asset_view_text:
        fail("Stage 9.5.3 Resource Library must size from its assigned body/asset slots, not ancestor widths", failures)
    for required_term in (
        "_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS",
        "_usage_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS",
        "func _set_meta_text(value: String) -> void",
    ):
        if required_term not in asset_card_text:
            fail(f"Stage 9.5.3 Resource Library card width-bounding contract is missing: {required_term}", failures)

    for required_term in (
        "func _refresh_connectors_immediately() -> void",
        "_perform_connector_refresh(true)",
        "Materialize the new arrow immediately",
        "Complete the retained/transient handoff synchronously",
    ):
        if required_term not in board_view_text:
            fail(f"Stage 9.5.3 connector continuity contract is missing: {required_term}", failures)

    for required_term in (
        "MENU_AUDIO_OPTIMIZE", "MENU_AUDIO_DELETE_ORIGINAL", "MENU_AUDIO_DELETE_OPTIMIZED",
        "_audio_media.is_optimizing(asset_id)", "audio.menu.delete_original",
    ):
        if required_term not in asset_card_text:
            fail(f"Stage 9.5.3 audio compression card UX contract is missing: {required_term}", failures)

    stroke_stress_path = ROOT / "tools/stroke_store_stress_test.gd"
    if not stroke_stress_path.is_file():
        fail("Stage 9 stroke DOD/binary stress test is missing", failures)
    else:
        stroke_stress_text = stroke_stress_path.read_text(encoding="utf-8")
        for required_term in ("STORE_ENTITY_COUNT", "encode_binary_payload", "apply_binary_payload", "CreateStrokeCommand", "UpdateStrokeStyleCommand", "style change moved stroke geometry", "CreateConnectorCommand", "DeleteEntitiesCommand", "_test_far_zoom_simplification", "simplify_polyline_fast", "get_local_points_decimated"):
            if required_term not in stroke_stress_text:
                fail(f"Stage 9 stroke stress test contract is missing: {required_term}", failures)

    core_smoke_text = (ROOT / "tools/core_smoke_test.gd").read_text(encoding="utf-8")
    if "CURRENT_VERSION + 1" not in core_smoke_text:
        fail("core smoke test does not cover unsupported future schemas", failures)
    if "_test_render_policy_hysteresis" not in core_smoke_text:
        fail("Stage 9.3 core smoke test does not cover render-policy hysteresis", failures)
    image_smoke_path = ROOT / "tools/image_store_stress_test.gd"
    if not image_smoke_path.is_file():
        fail("Stage 5 image store stress test is missing", failures)
    else:
        image_smoke_text = image_smoke_path.read_text(encoding="utf-8")
        for required_term in ("STORE_ENTITY_COUNT", "CreateImageCommand", "SHARED_ASSET_ID", "collect_asset_references", "make_paste_command_at"):
            if required_term not in image_smoke_text:
                fail(f"Stage 5 image stress test contract is missing: {required_term}", failures)

    video_smoke_path = ROOT / "tools/video_store_stress_test.gd"
    if not video_smoke_path.is_file():
        fail("Stage 7 video store stress test is missing", failures)
    else:
        video_smoke_text = video_smoke_path.read_text(encoding="utf-8")
        for required_term in ("STORE_ENTITY_COUNT", "CreateVideoCommand", "SHARED_ASSET_ID", "BoardEntityTypes.VIDEO", "collect_asset_references"):
            if required_term not in video_smoke_text:
                fail(f"Stage 7 video stress test contract is missing: {required_term}", failures)

    audio_smoke_path = ROOT / "tools/audio_store_stress_test.gd"
    if not audio_smoke_path.is_file():
        fail("Stage 9.5 audio DOD/schema/search stress test is missing", failures)
    else:
        audio_smoke_text = audio_smoke_path.read_text(encoding="utf-8")
        for required_term in (
            "STORE_ENTITY_COUNT", "AudioStore", "CreateAudioCommand",
            "UpdateAssetInstanceTitleCommand", "BoardEntityTypes.AUDIO",
            "BoardSearchSnapshot", "BoardDocumentSchema.CURRENT_VERSION",
            "make_paste_command_at", "audio_revision",
        ):
            if required_term not in audio_smoke_text:
                fail(f"Stage 9.5 audio stress test contract is missing: {required_term}", failures)

    asset_smoke_path = ROOT / "tools/asset_library_smoke_test.gd"
    if not asset_smoke_path.is_file():
        fail("Stage 4 Asset Library smoke test is missing", failures)
    else:
        asset_smoke_text = asset_smoke_path.read_text(encoding="utf-8")
        for required_term in ("HASH_SHA256", "commit_temp", "find_asset_by_hash", "collect_asset_references"):
            if required_term not in asset_smoke_text:
                fail(f"Asset Library smoke test contract is missing: {required_term}", failures)

    import_smoke_path = ROOT / "tools/asset_import_smoke_test.gd"
    if not import_smoke_path.is_file():
        fail("Stage 9.6.2 safe-import smoke test is missing", failures)
    else:
        import_smoke_text = import_smoke_path.read_text(encoding="utf-8")
        for required_term in (
            "AssetImportCapabilities",
            "AssetImportValidationWorker",
            "AssetImportStagingWorker",
            "MAX_FILES_PER_BATCH",
            "REJECTION_INVALID_CONTENT",
            "REJECTION_UNSAFE_SVG",
            "late-unsafe.svg",
            "relative-link.svg",
            "unsafe-data.svg",
            "HASH_SHA256",
        ):
            if required_term not in import_smoke_text:
                fail(f"Stage 9.6.2 safe-import smoke contract is missing: {required_term}", failures)

    runtime_regression_smoke_path = ROOT / "tools/runtime_regression_smoke_test.gd"
    if not runtime_regression_smoke_path.is_file():
        fail("Stage 9.7.4 runtime regression smoke test is missing", failures)
    else:
        runtime_regression_smoke_text = runtime_regression_smoke_path.read_text(encoding="utf-8")
        for required_term in (
            "FormulaEditorPanel.new()", 'panel.get("_apply_button") is Button',
            "AssetPreviewOverlay.new()", 'overlay.get("_seek") is HSlider', "not seek.editable",
            'runner.call("_decode_text_capture", utf16)', "to_utf16_buffer",
            "_test_sidecar_nul_padded_utf8_decode", 'runner.call("_decode_text_capture", padded)',
            "text_block_background.gdshader", "vec4 block_color = COLOR;",
        ):
            if required_term not in runtime_regression_smoke_text:
                fail(f"Stage 9.7.4 runtime regression smoke contract is missing: {required_term}", failures)

    formula_smoke_path = ROOT / "tools/formula_smoke_test.gd"
    if not formula_smoke_path.is_file():
        fail("Stage 9.7.1 FormulaObject smoke test is missing", failures)
    else:
        formula_smoke_text = formula_smoke_path.read_text(encoding="utf-8")
        for required_term in (
            "FormulaStore", "CreateFormulaCommand", "UpdateFormulaCommand",
            "BoardEntityTypes.FORMULA", "BoardSearchSnapshot",
            'TypstMiTexTools.BUNDLED_TYPST_VERSION == "0.15.1"',
            'TypstMiTexTools.MITEX_VERSION == "0.2.7"',
            '"@local/mitex:0.2.7"', "--package-path", "--ignore-system-fonts",
            "BoardDocumentSchema.CURRENT_VERSION",
        ):
            if required_term not in formula_smoke_text:
                fail(f"Stage 9.7.1 formula smoke contract is missing: {required_term}", failures)

    formula_service_path = ROOT / "scripts/media/formula_render_service.gd"
    typst_tools_path = ROOT / "scripts/media/typst_mitex_tools.gd"
    formula_worker_path = ROOT / "scripts/workers/formula_image_load_worker.gd"
    formula_cache_worker_path = ROOT / "scripts/workers/formula_cache_scan_worker.gd"
    for required_path, label in (
        (formula_service_path, "FormulaRenderService"),
        (typst_tools_path, "TypstMiTexTools"),
        (formula_worker_path, "FormulaImageLoadWorker"),
        (formula_cache_worker_path, "FormulaCacheScanWorker"),
    ):
        if not required_path.is_file():
            fail(f"Stage 9.7.1 {label} is missing", failures)

    formula_service_text = formula_service_path.read_text(encoding="utf-8") if formula_service_path.is_file() else ""
    formula_editor_text = (ROOT / "scripts/ui/formula_editor_panel.gd").read_text(encoding="utf-8")
    typst_tools_text = typst_tools_path.read_text(encoding="utf-8") if typst_tools_path.is_file() else ""
    formula_worker_text = formula_worker_path.read_text(encoding="utf-8") if formula_worker_path.is_file() else ""
    formula_cache_worker_text = formula_cache_worker_path.read_text(encoding="utf-8") if formula_cache_worker_path.is_file() else ""
    formula_store_text = (ROOT / "scripts/core/formula_store.gd").read_text(encoding="utf-8")
    cursor_text = (ROOT / "scripts/ui/cursor_theme_service.gd").read_text(encoding="utf-8")
    power_text = (ROOT / "scripts/platform/power_status_service.gd").read_text(encoding="utf-8")
    windows_power_text = (ROOT / "scripts/platform/windows_power_status_provider.gd").read_text(encoding="utf-8")
    grid_preview_text = (ROOT / "scripts/ui/grid_intensity_preview.gd").read_text(encoding="utf-8")

    for required_term in (
        "class_name FormulaStore", "MAX_SOURCE_LENGTH: int = 8192",
        "source_latex", "display_modes", "font_scales", "foregrounds",
    ):
        if required_term not in formula_store_text:
            fail(f"Stage 9.7.1 formula DOD contract is missing: {required_term}", failures)

    for required_term in (
        'BUNDLED_TYPST_VERSION: String = "0.15.1"',
        'MITEX_VERSION: String = "0.2.7"',
        'PACKAGE_NAMESPACE: String = "local"',
        'PACKAGE_NAME: String = "mitex"',
        '"--format", "svg"', '"--root"', '"--package-path"',
        '"--package-cache-path"', '"--ignore-system-fonts"',
        '"--creation-timestamp", "0"', '"--jobs", "1"',
        'return "@%s/%s:%s"', "PACKAGE_METADATA_NAME",
    ):
        if required_term not in typst_tools_text:
            fail(f"Stage 9.7.1 Typst/MiTeX pin/local-runtime contract is missing: {required_term}", failures)

    for required_term in (
        "MAX_PENDING_JOBS: int = 8", "MAX_WAITING_REQUESTS: int = 64",
        "MAX_MEMORY_CACHE_BYTES", "MAX_DISK_CACHE_BYTES", "MAX_FAILURE_RECORDS: int = 2048",
        "DISK_DELETIONS_PER_FRAME: int = 4", "MAX_SVG_BYTES", "FormulaImageLoadWorker",
        "FormulaCacheScanWorker", 'path_join("package-cache")',
        "request_preview_texture", "_cancel_stale_preview_work", "WRAPPER_VERSION",
        'VECTOR_CONTRACT_VERSION: String = "typst-svg-white-mask-godot-tint-v2"',
        'path_join("formula.svg")', "_queued_documents", "_document_key",
        'read(\\"formula.txt\\")', 'expected_local_import()',
        "_failures.has(key)", "_remove_file_if_exists(loading_path)",
        "_disk_cache_protected_paths", "_request_disk_cache_scan()", "_drain_disk_delete_queue", '"\\\\iftypst"',
    ):
        if required_term not in formula_service_text:
            fail(f"Stage 9.7.1 bounded/local formula-render contract is missing: {required_term}", failures)
    if "@preview/" in formula_service_text:
        fail("Stage 9.7.1 formula wrapper must never generate a remote @preview package import", failures)
    if "TectonicTools" in formula_service_text or "PopplerTools" in formula_service_text or "formula.pdf" in formula_service_text:
        fail("Stage 9.7.1 primary formula renderer still depends on the old Tectonic/Poppler pipeline", failures)
    if "OS.execute(" in formula_service_text or "OS.execute(" in typst_tools_text:
        fail("Stage 9.7.1 formula/Typst path reintroduced blocking OS.execute()", failures)
    if '"source_latex"' in formula_service_text.split("func _build_typst_document", 1)[1].split("func _validate_source", 1)[0]:
        fail("Stage 9.7.1 Typst wrapper appears to interpolate FormulaObject source instead of reading formula.txt as data", failures)

    for required_term in (
        "MAX_PENDING_JOBS: int = 4", "MAX_IMAGE_PIXELS", "MAX_SVG_BYTES",
        "load_svg_from_buffer", "target_extent", "is_finite",
    ):
        if required_term not in formula_worker_text:
            fail(f"Stage 9.7.1 bounded SVG raster worker contract is missing: {required_term}", failures)

    for required_term in (
        "class_name FormulaCacheScanWorker", "Thread.new()", "MAX_SCAN_FILES_HARD_LIMIT: int = 4096",
        "FileAccess.get_modified_time", 'entry == "formula.svg" or entry == "formula.svg.part"', 'entry != ".jobs"',
        "MAX_SCAN_DIRECTORIES_HARD_LIMIT: int = 8192", "has_pending_work",
    ):
        if required_term not in formula_cache_worker_text:
            fail(f"Stage 9.7.1 off-main formula cache-scan contract is missing: {required_term}", failures)

    for required_term in ("ScrollContainer", "SCROLL_MODE_RESERVE", "follow_focus = true"):
        if required_term not in formula_editor_text:
            fail(f"Stage 9.7 FormulaObject editor overflow protection is missing: {required_term}", failures)
    if ".selectable =" in formula_editor_text:
        fail("Stage 9.7.2 FormulaEditorPanel assigns unsupported Label.selectable on Godot 4.4.1", failures)

    # Runtime regressions found on the real Godot 4.4.1 Windows build: shader
    # identifiers must not collide with shading-language hint keywords, and
    # Windows UTF-16 pipe output must be decoded before UTF-8 conversion.
    text_background_shader_path = ROOT / "assets/shaders/text_block_background.gdshader"
    text_background_shader_text = text_background_shader_path.read_text(encoding="utf-8") if text_background_shader_path.is_file() else ""
    if re.search(r"\bvec4\s+source_color\b", text_background_shader_text):
        fail("Stage 9.7.2 text-block shader reuses reserved Godot shader token source_color", failures)
    if "vec4 block_color = COLOR;" not in text_background_shader_text:
        fail("Stage 9.7.2 text-block background shader runtime fix is missing", failures)

    sidecar_runtime_path = ROOT / "scripts/media/sidecar_process_runner.gd"
    sidecar_runtime_text = sidecar_runtime_path.read_text(encoding="utf-8") if sidecar_runtime_path.is_file() else ""
    for required_term in (
        "_decode_text_capture", "_looks_like_utf16", "get_string_from_utf16",
        "_without_nul_bytes", "pipe.get_buffer(read_size)",
    ):
        if required_term not in sidecar_runtime_text:
            fail(f"Stage 9.7.4 sidecar Unicode/pipe hardening contract is missing: {required_term}", failures)
    if "OutputEncoding=[System.Text.UTF8Encoding]::new($false)" not in windows_power_text:
        fail("Stage 9.7.2 Windows battery query must force UTF-8 pipe output", failures)

    queue_guard = formula_service_text.split("if _queue.size() >= MAX_PENDING_JOBS:", 1)[1].split("DirAccess.make_dir_recursive_absolute", 1)[0] if "if _queue.size() >= MAX_PENDING_JOBS:" in formula_service_text else ""
    if "_register_failure" in queue_guard:
        fail("Stage 9.7.1 formula queue saturation must remain backpressure, not a sticky FormulaObject failure", failures)
    if "_cancel_stale_preview_work" not in formula_service_text or "_runner.cancel()" not in formula_service_text or "preserve_document_key" not in formula_service_text:
        fail("Stage 9.7.3 stale formula preview cancellation/fan-out contract is missing", failures)
    ready_section = formula_service_text.split("func _ready() -> void:", 1)[1].split("func _exit_tree() -> void:", 1)[0] if "func _ready() -> void:" in formula_service_text else ""
    if "_request_disk_cache_scan()" not in ready_section or "_cache_scan_worker.start()" not in ready_section:
        fail("Stage 9.7.1 formula disk cache must schedule its startup scan off the main thread", failures)
    if "_collect_cache_files" in formula_service_text or "FileAccess.get_modified_time" in formula_service_text:
        fail("Stage 9.7.1 formula disk-cache metadata traversal regressed onto FormulaRenderService/main thread", failures)
    if "HashingContext" in formula_service_text and "func _small_sha256" not in formula_service_text:
        fail("Stage 9.7.1 formula renderer has unexpected direct heavy hashing", failures)

    for required_term in ("Input.set_custom_mouse_cursor", "assets/cursors", "Input.CURSOR_HELP"):
        if required_term not in cursor_text:
            fail(f"Stage 9.7 centralized custom-cursor contract is missing: {required_term}", failures)
    for required_term in ("POLL_INTERVAL_SECONDS: float = 30.0", "SidecarProcessRunner", "show_battery"):
        if required_term not in power_text:
            fail(f"Stage 9.7 bounded battery-monitor contract is missing: {required_term}", failures)
    if "Get-CimInstance -ClassName Win32_Battery" not in windows_power_text:
        fail("Stage 9.7 Windows battery provider is missing its fixed system query", failures)
    if "clip_contents = true" not in grid_preview_text:
        fail("Stage 9.7 grid preview no longer clips its drawing area", failures)
    if "window_mode: WindowModePreference = WindowModePreference.MAXIMIZED" not in settings_text:
        fail("Stage 9.7 fresh settings no longer default to a maximized window", failures)

    # Stage 9.7.3 formula UX/performance pass: formulas render transparently,
    # formula editing uses the shared bounded color popover, preview consumers fan
    # out from one vector compile, mixed selections suppress entity toolbars, and
    # the board text-placement cursor no longer replaces the native editor I-beam.
    formula_renderer_text = (ROOT / "scripts/render/formula_batch_renderer.gd").read_text(encoding="utf-8")
    formula_toolbar_path = ROOT / "scripts/ui/formula_context_toolbar.gd"
    formula_toolbar_text = formula_toolbar_path.read_text(encoding="utf-8") if formula_toolbar_path.is_file() else ""
    board_color_popover_text = (ROOT / "scripts/ui/board_color_popover.gd").read_text(encoding="utf-8")
    native_board_text = (ROOT / "scripts/board/native_board_view.gd").read_text(encoding="utf-8")
    if 'draw_rect(bounds, paper, true)' in formula_renderer_text or 'Color("#fffdf7")' in formula_renderer_text:
        fail("Stage 9.7.3 FormulaObject renderer regressed to an opaque paper background", failures)
    if 'WRAPPER_VERSION: String = "notlight-formula-mitex-wrapper-v4-vector-guard-band"' not in formula_service_text:
        fail("Stage 9.7.3 formula wrapper must use the current neutral white-mask/vector-guard render contract", failures)
    record_key_section = formula_service_text.split("func _record_key_data", 1)[1].split("func _build_typst_document", 1)[0] if "func _record_key_data" in formula_service_text else ""
    if '"foreground"' in record_key_section:
        fail("Stage 9.7.3 formula foreground must not participate in the Typst/vector cache key", failures)
    wrapper_section = formula_service_text.split("func _build_typst_document", 1)[1].split("func _validate_source", 1)[0] if "func _build_typst_document" in formula_service_text else ""
    if '#FFFFFF' not in wrapper_section or 'record.get("foreground"' in wrapper_section:
        fail("Stage 9.7.3 Typst wrapper must render a fixed white alpha mask independent of FormulaObject color", failures)
    if 'draw_texture_rect(texture, fitted, false, foreground)' not in formula_renderer_text:
        fail("Stage 9.7.3 FormulaObject foreground must be applied as a cheap Godot draw-time tint", failures)
    if 'model.formulas.get_foreground(entity_id)' not in formula_renderer_text:
        fail("Stage 9.7.4 FormulaObject renderer must read the typed canonical foreground instead of the serialized record string", failures)
    transient_formula_section = native_board_text.split("func _draw_transient_formula", 1)[1].split("func _draw_transient_audio", 1)[0] if "func _draw_transient_formula" in native_board_text else ""
    if 'Color("#fffdf7")' in transient_formula_section or 'get_foreground(entity_id)' not in transient_formula_section:
        fail("Stage 9.7.4 transient FormulaObject drawing must stay transparent and use the canonical foreground tint", failures)
    for required_term in ("_document_waiters", "_queue_raster_request", "_drain_raster_queue", "MAX_PENDING_RASTER_REQUESTS", "_typst_executable"):
        if required_term not in formula_service_text:
            fail(f"Stage 9.7.3 formula preview fan-out/performance contract is missing: {required_term}", failures)
    if "ColorPickerButton" in formula_editor_text:
        fail("Stage 9.7.3 FormulaEditorPanel must use the shared bounded color popover instead of ColorPickerButton", failures)
    color_apply_section = formula_editor_text.split("func apply_color_from_popover", 1)[1].split("func _update_color_button", 1)[0] if "func apply_color_from_popover" in formula_editor_text else ""
    if "_schedule_preview" in color_apply_section or "_update_preview_tint" not in color_apply_section:
        fail("Stage 9.7.3 formula color edits must tint the cached mask without recompiling Typst", failures)
    for required_term in ("FormulaSourceEdit", "color_picker_requested", "editor_visibility_changed"):
        if required_term not in formula_editor_text:
            fail(f"Stage 9.7.3 FormulaEditorPanel UX contract is missing: {required_term}", failures)
    for required_term in ("class_name FormulaContextToolbar", "display_mode_requested", "copy_latex_requested", "color_picker_requested"):
        if required_term not in formula_toolbar_text:
            fail(f"Stage 9.7.3 FormulaObject context toolbar contract is missing: {required_term}", failures)
    for required_term in ("deferred_mode = true", "SCROLL_MODE_RESERVE", "follow_focus = true"):
        if required_term not in board_color_popover_text and required_term != "deferred_mode = true":
            fail(f"Stage 9.7.3 bounded color-popover viewport contract is missing: {required_term}", failures)
    color_style_text = (ROOT / "scripts/ui/notlight_color_picker_style.gd").read_text(encoding="utf-8")
    if "deferred_mode = true" not in color_style_text:
        fail("Stage 9.7.3 shared color picker must remain deferred to avoid high-frequency style/render updates", failures)
    if "move_to_front()" not in board_color_popover_text:
        fail("Stage 9.7.4 shared color popover must move to the front of sibling GUI input order when opened", failures)
    for required_term in ("show_tool_hints", "set_show_tool_hints", "_migrate_settings_dictionary"):
        if required_term not in settings_text:
            fail(f"Stage 9.7.3 tool-hint settings contract is missing: {required_term}", failures)
    for required_term in ("_hint_label.max_lines_visible = 2", "_hint_label.clip_text = true", 'semantic_color("text")'):
        if required_term not in board_screen_text:
            fail(f"Stage 9.7.4 board tool-hint readability contract is missing: {required_term}", failures)
    if 'Input.CURSOR_IBEAM' in cursor_text:
        fail("Stage 9.7.3 custom cursor service must not replace the native I-beam used by text-entry controls", failures)
    if 'Input.CURSOR_VSPLIT' not in cursor_text:
        fail("Stage 9.7.3 dedicated board text-placement hardware cursor is missing", failures)

    for ignored_runtime_dir in (
        ROOT / "tools/typst/packages",
        ROOT / "tools/typst/windows",
    ):
        if not (ignored_runtime_dir / ".gdignore").is_file():
            fail(f"Stage 9.7.1 external Typst payload directory must contain .gdignore: {ignored_runtime_dir.relative_to(ROOT)}", failures)

    prepare_package_path = ROOT / "tools/prepare_mitex_windows.ps1"
    checker_path = ROOT / "tools/check_formula_runtime_windows.ps1"
    if not prepare_package_path.is_file():
        fail("Stage 9.7.1 safe MiTeX package preparation helper is missing", failures)
    else:
        prepare_text = prepare_package_path.read_text(encoding="utf-8")
        for required_term in (
            "mitex-0.2.7.tar.gz", "tar.exe", "ReparsePoint",
            "notlight.mitex-package-provenance", "content_digest_sha256",
            "@(?:preview|packages)/", "maxExtractedBytes", ".prepare-mitex-",
            "WebAssembly header", "Write-Utf8NoBom", "-tvzf",
            "Only regular files/directories are accepted", ".backup-mitex-",
        ):
            if required_term not in prepare_text:
                fail(f"Stage 9.7.1 MiTeX preparation safety contract is missing: {required_term}", failures)
    if not checker_path.is_file():
        fail("Stage 9.7.1 Typst/MiTeX runtime checker is missing", failures)
    else:
        checker_text = checker_path.read_text(encoding="utf-8")
        for required_term in (
            'expectedTypstVersion = "0.15.1"', '#import "@local/mitex:0.2.7": mi, mitex',
            "--package-path", "--package-cache-path", "--ignore-system-fonts",
            "--creation-timestamp", '"--jobs", "1"', "formula.svg",
            "content_digest_sha256", "Write-Utf8NoBom",
        ):
            if required_term not in checker_text:
                fail(f"Stage 9.7.1 Typst/MiTeX offline smoke contract is missing: {required_term}", failures)

    # Stage 9.7.1 must not regress to shipping the multi-gigabyte TeX/Tectonic
    # runtime. Keeping old archives outside the project is fine; active project
    # files must not depend on the old backend.
    forbidden_active_paths = (
        ROOT / "scripts/media/tectonic_tools.gd",
        ROOT / "tools/check_tectonic_windows.ps1",
        ROOT / "tools/prepare_tectonic_bundle_windows.ps1",
    )
    for forbidden_path in forbidden_active_paths:
        if forbidden_path.exists():
            fail(f"Stage 9.7.1 still contains an active legacy Tectonic integration file: {forbidden_path.relative_to(ROOT)}", failures)

    return failures


def main() -> int:
    failures = validate()
    portable_smoke_path = ROOT / "tools/portable_package_smoke_test.gd"
    if not portable_smoke_path.is_file():
        fail("Portable package smoke test is missing", failures)
    else:
        portable_smoke_text = portable_smoke_path.read_text(encoding="utf-8")
        for required_term in ("write_package", "materialize_payloads", "manifest_corrupted", "truncated", "corrupted", "repaired"):
            if required_term not in portable_smoke_text:
                fail(f"Portable package smoke test contract is missing: {required_term}", failures)

    portable_format_path = ROOT / "scripts/portable/notlight_portable_package_format.gd"
    portable_service_path = ROOT / "scripts/portable/notlight_portable_package_service.gd"
    ambient_layer_path = ROOT / "scripts/ui/hub_ambient_phrase_layer.gd"
    if not portable_format_path.is_file() or not portable_service_path.is_file():
        fail("Portable board/library exchange foundation is missing", failures)
    else:
        portable_format_text = portable_format_path.read_text(encoding="utf-8")
        portable_service_text = portable_service_path.read_text(encoding="utf-8")
        for required_term in (
            'const MAGIC_TEXT: String = "NLTPKG01"',
            "HashingContext.HASH_SHA256",
            "MAX_MANIFEST_BYTES",
            "materialize_payloads",
            "MAX_PAYLOAD_KEY_LENGTH",
            "_same_file_path",
            "output.get_error()",
            "_make_unused_sibling_path",
            "_commit_atomic_file",
            "directory.is_link",
        ):
            if required_term not in portable_format_text:
                fail(f"Portable package integrity contract is missing: {required_term}", failures)
        for required_term in (
            "func export_board(",
            "func import_board(",
            "func export_library(",
            "func import_library(",
            "make_catalog_snapshot",
            "restore_catalog_snapshot",
            "BoardDocumentSchema.collect_asset_references",
            "_validate_board_folder_manifest",
            "_validate_board_asset_manifest",
            "_prune_unused_board_folders",
            "_validate_library_manifest",
            "_validate_export_destination",
            "_validate_local_asset_references",
            "_rollback_and_fail",
            "_blob_path_matches_hash_and_extension",
            '_staging_root = library_root.path_join("package_staging")',
        ):
            if required_term not in portable_service_text:
                fail(f"Portable exchange service contract is missing: {required_term}", failures)
        if "get_var(" in portable_format_text or "bytes_to_var(" in portable_format_text:
            fail("Portable package parser must not deserialize executable Variant objects", failures)
        blob_store_text = (ROOT / "scripts/assets/asset_blob_store.gd").read_text(encoding="utf-8")
        for required_term in ("FileAccess.get_sha256(temp_path)", '"repaired": true', '"repaired": false'):
            if required_term not in blob_store_text:
                fail(f"Asset blob integrity repair contract is missing: {required_term}", failures)
    if not ambient_layer_path.is_file():
        fail("Hub ambient phrase layer is missing", failures)
    else:
        ambient_text = ambient_layer_path.read_text(encoding="utf-8")
        for required_term in (
            "MOUSE_FILTER_IGNORE", "PHRASE_KEYS", "NotLightL10n.text(key)",
            "_build_spread_slots", "SPREAD_CANDIDATE_MULTIPLIER",
            "min_distance_squared", "_phrase_colors",
        ):
            if required_term not in ambient_text:
                fail(f"Hub ambient phrase centralized-localization contract is missing: {required_term}", failures)
        ru_bundle = json.loads((ROOT / "localization/core/ru.json").read_text(encoding="utf-8"))
        ru_strings = ru_bundle.get("strings", {}) if isinstance(ru_bundle, dict) else {}
        ambient_keys = [key for key in ru_strings if str(key).startswith("ambient.phrase.")]
        if len(ambient_keys) < 40:
            fail("Russian Hub ambient phrases must live in the centralized core catalog", failures)


    pdf_paths = (
        ROOT / "scripts/core/pdf_store.gd",
        ROOT / "scripts/core/create_pdf_command.gd",
        ROOT / "scripts/core/update_pdf_page_command.gd",
        ROOT / "scripts/media/pdf_media_service.gd",
        ROOT / "scripts/media/poppler_tools.gd",
        ROOT / "scripts/workers/pdf_render_worker.gd",
        ROOT / "scripts/render/pdf_batch_renderer.gd",
        ROOT / "scripts/ui/pdf_context_toolbar.gd",
        ROOT / "tools/pdf_store_stress_test.gd",
    )
    for pdf_path in pdf_paths:
        if not pdf_path.is_file():
            fail(f"PDF foundation file is missing: {pdf_path.relative_to(ROOT)}", failures)

    pdf_store_path = ROOT / "scripts/core/pdf_store.gd"
    if pdf_store_path.is_file():
        pdf_store_text = pdf_store_path.read_text(encoding="utf-8")
        for required_term in (
            'const STORE_ID: StringName = &"pdf_blocks"', "PackedInt64Array",
            "PackedStringArray", "PackedInt32Array", "page_indices", "page_counts",
            "page_widths", "page_heights", "func serialize() -> Array[Dictionary]",
            "func deserialize(records: Array) -> void",
        ):
            if required_term not in pdf_store_text:
                fail(f"PDF DOD store contract is missing: {required_term}", failures)

    schema_text = (ROOT / "scripts/core/board_document_schema.gd").read_text(encoding="utf-8")
    entity_types_text = (ROOT / "scripts/core/board_entity_types.gd").read_text(encoding="utf-8")
    if 'const PDF: StringName = &"pdf"' not in entity_types_text or "PDF," not in entity_types_text:
        fail("PDF entity type is not registered as a built-in board type", failures)
    board_model_text = (ROOT / "scripts/core/board_model.gd").read_text(encoding="utf-8")
    for required_term in ("var pdfs: PdfStore", "pdf_revision", "stores.register_store(pdfs)"):
        if required_term not in board_model_text:
            fail(f"BoardModel PDF contract is missing: {required_term}", failures)
    if "_migrate_v9_to_v10" not in schema_text or '"pdf_blocks"' not in schema_text:
        fail("Document schema does not migrate/persist PDF records", failures)

    pdf_media_path = ROOT / "scripts/media/pdf_media_service.gd"
    if pdf_media_path.is_file():
        pdf_media_text = pdf_media_path.read_text(encoding="utf-8")
        for required_term in (
            "PdfRenderWorker", "request_page", "request_thumbnail", "tier_for_extent",
            "MAX_PENDING_JOBS", "memory_limit_bytes", "hash_sha256",
            "_worker_started", "pdf.error.worker_unavailable",
        ):
            # Hash is intentionally satisfied by hash_sha256 in the content-addressed cache key.
            if required_term not in pdf_media_text:
                fail(f"PdfMediaService retained/cache contract is missing: {required_term}", failures)
        for required_term in ("_failed_page_keys", "_failed_probe_assets", "pdf.error.encrypted_unsupported"):
            if required_term not in pdf_media_text:
                fail(f"PdfMediaService edge-case guard is missing: {required_term}", failures)
    pdf_worker_path = ROOT / "scripts/workers/pdf_render_worker.gd"
    if pdf_worker_path.is_file():
        pdf_worker_text = pdf_worker_path.read_text(encoding="utf-8")
        for required_term in (
            "Thread.new()", "Mutex.new()", "Semaphore.new()", "PopplerTools.pdfinfo_path()",
            "PopplerTools.pdftoppm_path()", '"-singlefile"', '"-scale-to"',
            "ProjectSettings.globalize_path", "func start() -> bool", "var start_error: Error",
        ):
            if required_term not in pdf_worker_text:
                fail(f"PDF worker contract is missing: {required_term}", failures)
        if "OS.execute" not in pdf_worker_text:
            fail("PDF worker must invoke Poppler outside the retained draw path", failures)
        for required_term in ('"error_kind": error_kind', '"tool_missing"', '"encrypted"', "_remove_partial_output"):
            if required_term not in pdf_worker_text:
                fail(f"PDF worker failure classification is missing: {required_term}", failures)
        if "OS.execute" in pdf_media_text:
            fail("PdfMediaService must not execute Poppler on the UI/main thread", failures)
    board_view_text = (ROOT / "scripts/board/native_board_view.gd").read_text(encoding="utf-8")
    for required_term in (
        "PdfBatchRenderer", "create_pdf_from_asset", "set_pdf_page",
        "BoardEntityTypes.PDF", "RENDER_REFRESH_PDF",
    ):
        if required_term not in board_view_text:
            fail(f"Board PDF interaction/render contract is missing: {required_term}", failures)
    search_snapshot_path = ROOT / "scripts/search/board_search_snapshot.gd"
    if search_snapshot_path.is_file() and "model.pdfs.entity_ids" not in search_snapshot_path.read_text(encoding="utf-8"):
        fail("Board search snapshot does not include PDF objects", failures)
    asset_view_text = (ROOT / "scripts/ui/asset_library_view.gd").read_text(encoding="utf-8")
    asset_card_text = (ROOT / "scripts/ui/asset_library_card.gd").read_text(encoding="utf-8")
    if "AssetKinds.PDF" not in asset_view_text or "request_thumbnail(asset_id)" not in asset_card_text:
        fail("Resource Library PDF filter/preview integration is incomplete", failures)
    app_root_text = (ROOT / "scripts/app/app_root.gd").read_text(encoding="utf-8")
    if "var pdf_media: PdfMediaService" not in app_root_text or "pdf_media.configure(asset_library)" not in app_root_text:
        fail("AppRoot does not own/configure the centralized PdfMediaService", failures)
    poppler_root = ROOT / "tools/poppler/windows"
    poppler_setup = ROOT / "tools/setup_windows_dependencies.ps1"
    required_poppler_runtime = (
        "Library/bin/pdfinfo.exe", "Library/bin/pdftoppm.exe",
        "share/poppler/COPYING",
    )
    missing_poppler_runtime = [relative for relative in required_poppler_runtime if not (poppler_root / relative).is_file()]
    if missing_poppler_runtime and not poppler_setup.is_file():
        for relative in missing_poppler_runtime:
            fail(f"Pinned Poppler runtime file is missing and no source-checkout setup script is available: tools/poppler/windows/{relative}", failures)
    poppler_tools_text = (ROOT / "scripts/media/poppler_tools.gd").read_text(encoding="utf-8")
    if "OS.execute" in poppler_tools_text:
        fail("Poppler availability probing must not block the UI thread", failures)
    pdf_architecture_path = ROOT / "docs/PDF_SUPPORT.md"
    if not pdf_architecture_path.is_file():
        fail("PDF architecture documentation is missing", failures)
    export_preset_text = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    for required_term in ("tools/poppler/windows/Library/bin/*", "tools/poppler/windows/share/poppler/*"):
        if required_term not in export_preset_text:
            fail(f"Poppler sidecar is not explicitly excluded from the PCK: {required_term}", failures)
    notices_text = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
    if "Poppler PDF tools" not in notices_text or "tools/poppler/SOURCE_INFO.md" not in notices_text:
        fail("Poppler third-party notice/provenance documentation is incomplete", failures)

    # Stage 9.6 — qpdf remains an optional sidecar, but its integration contract
    # is strict: fixed arguments, bounded/cancellable execution, staging
    # validation, durable variants, and no API that can delete the PDF original.
    qpdf_tools_path = ROOT / "scripts/media/qpdf_tools.gd"
    sidecar_runner_path = ROOT / "scripts/media/sidecar_process_runner.gd"
    pdf_optimizer_path = ROOT / "scripts/media/pdf_optimization_service.gd"
    pdf_probe_path = ROOT / "scripts/media/pdf_document_probe.gd"
    file_hash_worker_path = ROOT / "scripts/workers/file_hash_worker.gd"
    for required_path, label in (
        (qpdf_tools_path, "QpdfTools"),
        (sidecar_runner_path, "SidecarProcessRunner"),
        (pdf_optimizer_path, "PdfOptimizationService"),
        (pdf_probe_path, "PdfDocumentProbe"),
        (file_hash_worker_path, "FileHashWorker"),
    ):
        if not required_path.is_file():
            fail(f"Stage 9.6 {label} implementation is missing", failures)

    if qpdf_tools_path.is_file():
        qpdf_tools_text = qpdf_tools_path.read_text(encoding="utf-8")
        for required_term in (
            'BUNDLED_VERSION: String = "12.4.0"',
            'EXPECTED_ARCHIVE_NAME: String = "qpdf-12.4.0-msvc64.zip"',
            'EXPECTED_ARCHIVE_SHA256: String = "5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72"',
            '"--compress-streams=y"',
            '"--decode-level=generalized"',
            '"--recompress-flate"',
            '"--compression-level=9"',
            '"--object-streams=generate"',
            '"--optimize-images"',
            '"--jpeg-quality=90"',
            "MAX_SEARCH_DEPTH",
            "parse_version_value",
            "bundled_version_matches",
        ):
            if required_term not in qpdf_tools_text:
                fail(f"Stage 9.6 qpdf pin/preset contract is missing: {required_term}", failures)

    if sidecar_runner_path.is_file():
        sidecar_runner_text = sidecar_runner_path.read_text(encoding="utf-8")
        for required_term in (
            "OS.execute_with_pipe",
            "OS.is_process_running",
            "OS.get_process_exit_code",
            "OS.kill",
            "DEFAULT_OUTPUT_LIMIT_BYTES",
            "MAX_DRAIN_BYTES_PER_POLL",
            "_timeout_msec",
            "_cancel_requested",
        ):
            if required_term not in sidecar_runner_text:
                fail(f"Stage 9.6 bounded sidecar-process contract is missing: {required_term}", failures)
        if "OS.execute(" in sidecar_runner_text:
            fail("Stage 9.6 sidecar runner regressed to blocking OS.execute", failures)

    if file_hash_worker_path.is_file():
        file_hash_worker_text = file_hash_worker_path.read_text(encoding="utf-8")
        for required_term in (
            "class_name FileHashWorker",
            "Thread.new()",
            "MAX_PENDING_JOBS: int = 4",
            "HASH_CHUNK_BYTES: int = 4 * 1024 * 1024",
            "HashingContext.HASH_SHA256",
            "func cancel(job_key: String) -> bool",
            "func poll_results(maximum_count: int = 1) -> Array[Dictionary]",
        ):
            if required_term not in file_hash_worker_text:
                fail(f"Stage 9.6 background SHA-256 worker contract is missing: {required_term}", failures)

    if pdf_optimizer_path.is_file():
        pdf_optimizer_text = pdf_optimizer_path.read_text(encoding="utf-8")
        for required_term in (
            "MAX_PENDING_JOBS: int = 4",
            "FileHashWorker.new()",
            "STAGE_SOURCE_HASH",
            "STAGE_RESULT_HASH",
            "source_hash_mismatch",
            "result_changed",
            "MIN_SAVING_RATIO",
            "QpdfTools.check_arguments",
            "QpdfTools.optimize_arguments",
            "PdfDocumentProbe.parse_pdfinfo",
            "PopplerTools.pdftoppm_path()",
            "STAGE_RENDER_FIRST",
            "STAGE_RENDER_LAST",
            "_hash_worker.request",
            "_hash_worker.poll_results",
            "_hash_worker.cancel",
            "commit_preverified_temp",
            "register_optimized_variant",
            "exit_code == 3",
            'OS.has_feature("windows") and detected_version != QpdfTools.BUNDLED_VERSION',
            "_qpdf_version_verified",
            '"backend_version": _qpdf_version',
        ):
            if required_term not in pdf_optimizer_text:
                fail(f"Stage 9.6 transactional PDF optimization contract is missing: {required_term}", failures)
        if "OS.execute(" in pdf_optimizer_text:
            fail("Stage 9.6 PDF optimization must not block the main thread with OS.execute", failures)
        if "HashingContext" in pdf_optimizer_text:
            fail("Stage 9.6 PDF optimization must hash large files in FileHashWorker, not on the main thread", failures)

    asset_blob_store_stage96 = (ROOT / "scripts/assets/asset_blob_store.gd").read_text(encoding="utf-8")
    for required_term in (
        "commit_preverified_temp",
        "_is_managed_preverified_temp_path",
        'temp_path.get_file().ends_with(".part")',
    ):
        if required_term not in asset_blob_store_stage96:
            fail(f"Stage 9.6 preverified blob-commit boundary is missing: {required_term}", failures)

    if pdf_media_path.is_file():
        for required_term in (
            'VARIANT_ORIGINAL: String = "original"',
            'VARIANT_OPTIMIZED: String = "optimized"',
            "source_hash_sha256",
            "set_preferred_variant",
            "register_optimized_variant",
            "delete_optimized_variant",
            "display_blob_hash",
            "resolve_display_path",
        ):
            if required_term not in pdf_media_text:
                fail(f"Stage 9.6 PDF durable-variant contract is missing: {required_term}", failures)
        if "delete_original_variant" in pdf_media_text:
            fail("Stage 9.6 must not expose a PDF-original deletion API", failures)

    portable_service_stage96 = (ROOT / "scripts/portable/notlight_portable_package_service.gd").read_text(encoding="utf-8")
    if portable_service_stage96.count("AssetDurableVariants.SUPPORTED_NAMESPACES") < 3:
        fail("Stage 9.6 portable exchange must enumerate durable variants from the central registry", failures)

    qpdf_source_info = ROOT / "tools/qpdf/SOURCE_INFO.md"
    qpdf_placeholder = ROOT / "tools/qpdf/windows/PLACE_QPDF_HERE.md"
    qpdf_runtime_check = ROOT / "tools/check_qpdf_windows.ps1"
    qpdf_smoke_test = ROOT / "tools/pdf_optimization_smoke_test.gd"
    if not qpdf_source_info.is_file() or not qpdf_placeholder.is_file():
        fail("Stage 9.6 qpdf provenance/extraction instructions are missing", failures)
    else:
        qpdf_source_text = qpdf_source_info.read_text(encoding="utf-8")
        for required_term in (
            "qpdf-12.4.0-msvc64.zip",
            "5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72",
            "Apache-2.0",
            "tools/qpdf/windows",
        ):
            if required_term not in qpdf_source_text:
                fail(f"Stage 9.6 qpdf provenance pin is incomplete: {required_term}", failures)
    if "qpdf 12.4.0 PDF optimization backend" not in notices_text or "tools/qpdf/SOURCE_INFO.md" not in notices_text:
        fail("Stage 9.6 qpdf third-party notice is missing", failures)

    if not qpdf_runtime_check.is_file():
        fail("Stage 9.6 qpdf Windows runtime/version checker is missing", failures)
    else:
        qpdf_runtime_check_text = qpdf_runtime_check.read_text(encoding="utf-8")
        for required_term in (
            'expectedVersion = "12.4.0"',
            'expectedArchiveName = "qpdf-12.4.0-msvc64.zip"',
            'expectedArchiveSha256 = "5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72"',
            "Get-FileHash",
            "--version",
        ):
            if required_term not in qpdf_runtime_check_text:
                fail(f"Stage 9.6 qpdf runtime checker pin is incomplete: {required_term}", failures)
    if not qpdf_smoke_test.is_file():
        fail("Stage 9.6 PDF optimization Godot smoke test is missing", failures)
    else:
        qpdf_smoke_text = qpdf_smoke_test.read_text(encoding="utf-8")
        for required_term in (
            "QpdfTools.parse_version_value",
            "QpdfTools.optimize_arguments",
            "FileHashWorker.MAX_PENDING_JOBS",
            "FileHashWorker.HASH_CHUNK_BYTES",
            "PdfDocumentProbe.parse_pdfinfo",
            "AssetDurableVariants.blob_relpaths",
        ):
            if required_term not in qpdf_smoke_text:
                fail(f"Stage 9.6 PDF optimization smoke test is incomplete: {required_term}", failures)

    build_windows_text = (ROOT / "tools/build_windows.ps1").read_text(encoding="utf-8")
    for required_term in (r"tools\qpdf\windows", "qpdf.exe", "QPDF_SOURCE_INFO.md", "check_qpdf_windows.ps1"):
        if required_term not in build_windows_text:
            fail(f"Stage 9.6 Windows packaging contract is missing: {required_term}", failures)
    if "tools/qpdf/windows/*" not in export_preset_text:
        fail("Stage 9.6 qpdf sidecar must stay outside the Godot PCK", failures)
    if not (ROOT / "tools/qpdf/windows/.gdignore").is_file():
        fail("Stage 9.7.4 qpdf runtime directory must stay outside Godot indexing via .gdignore", failures)

    for required_term in (
        "var pdf_optimizer: PdfOptimizationService",
        "pdf_optimizer.configure(asset_library, pdf_media)",
    ):
        if required_term not in app_root_text:
            fail(f"Stage 9.6 AppRoot qpdf service wiring is missing: {required_term}", failures)

    asset_inspector_stage96 = (ROOT / "scripts/ui/asset_inspector_panel.gd").read_text(encoding="utf-8")
    for required_term in (
        "pdf_optimization_service",
        "library.inspector.pdf_optimization",
        "pdf.inspector.optimize_lossless",
        "pdf.inspector.optimize_balanced",
        "set_preferred_variant",
        "delete_optimized_variant",
        "cancel_optimization",
    ):
        if required_term not in asset_inspector_stage96:
            fail(f"Stage 9.6 Resource Library inspector PDF controls are missing: {required_term}", failures)
    for required_term in (
        "MENU_PDF_OPTIMIZE_LOSSLESS",
        "MENU_PDF_OPTIMIZE_BALANCED",
        "MENU_PDF_CANCEL_OPTIMIZATION",
        "MENU_PDF_USE_ORIGINAL",
        "MENU_PDF_USE_OPTIMIZED",
        "MENU_PDF_DELETE_OPTIMIZED",
    ):
        if required_term not in asset_card_text:
            fail(f"Stage 9.6 Resource Library PDF optimization UX is missing: {required_term}", failures)

    # Drawing UX/performance regression guards. A dirty board must not autosave
    # its complete binary stroke payload while the user is still panning/zooming.
    session_text = (ROOT / "scripts/data/board_session.gd").read_text(encoding="utf-8")
    board_screen_text_for_drawing = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    for required_term in (
        "func notify_user_activity() -> void",
        "_idle_seconds = 0.0",
        "request_save(true)",
        "var _save_requires_idle: bool = false",
        "if require_idle and _idle_seconds < AUTOSAVE_IDLE_SECONDS",
    ):
        if required_term not in session_text:
            fail(f"interaction-aware autosave contract is missing: {required_term}", failures)
    for required_term in (
        "signal interaction_activity",
        "interaction_activity.emit()",
        "_schedule_deferred_view_refresh_if_ready()",
        "var _render_model_pending_mask: int = 0",
        "func _queue_changed_model_refreshes() -> void",
        "var durable_mask: int = _render_force_mask | _render_model_pending_mask",
    ):
        if required_term not in board_view_text:
            fail(f"post-stroke/retained-render reliability contract is missing: {required_term}", failures)
    if "render_interaction_active = render_interaction_active or view_moving" in board_view_text:
        fail("eased camera motion must not globally block retained renderer refreshes", failures)
    if "_schedule_deferred_view_refresh_if_ready(fully_settled)" in board_view_text:
        fail("view refresh must not wait for the sub-pixel camera easing tail", failures)
    for required_term in (
        "_board_view.interaction_activity.connect(_on_board_interaction_activity)",
        "func _on_board_interaction_activity() -> void",
        "session.notify_user_activity()",
    ):
        if required_term not in board_screen_text_for_drawing:
            fail(f"BoardScreen interaction/autosave bridge is missing: {required_term}", failures)

    # Drawing UX/performance regression guards. Freshly committed strokes must stay
    # in retained world space during the post-commit quiet window; otherwise an
    # immediate pan/zoom rebuilds the whole transient stroke every camera frame.
    stroke_handoff_path = ROOT / "scripts/render/stroke_handoff_renderer.gd"
    if not stroke_handoff_path.is_file():
        fail("retained stroke handoff renderer is missing", failures)
    else:
        stroke_handoff_text = stroke_handoff_path.read_text(encoding="utf-8")
        for required_term in (
            "class_name StrokeHandoffRenderer",
            "extends Node2D",
            "func set_state(entity_ids: Dictionary, hidden_entity_ids: Dictionary) -> void",
            "StrokeBatchRenderer.draw_stroke(",
        ):
            if required_term not in stroke_handoff_text:
                fail(f"retained stroke handoff contract is missing: {required_term}", failures)
    for required_term in (
        "var _stroke_handoff_renderer: StrokeHandoffRenderer",
        "_world_root.add_child(_stroke_handoff_renderer)",
        "_stroke_handoff_renderer.set_state(_stroke_commit_handoff_ids, _hidden_render_ids)",
    ):
        if required_term not in board_view_text:
            fail(f"post-stroke pan/zoom performance contract is missing: {required_term}", failures)
    for required_term in (
        "_render_model_pending_mask &= ~refresh_kind",
        "if not _text_worker.submit(snapshot, signature):",
        "_queue_changed_model_refreshes()",
    ):
        if required_term not in board_view_text:
            fail(f"retained renderer retry/model-dirty contract is missing: {required_term}", failures)
    needs_overlay_match = re.search(r"func _needs_overlay_redraw\(\) -> bool:\n(?P<body>(?:\t.*\n)+)", board_view_text)
    if needs_overlay_match is not None and "_stroke_commit_handoff_ids" in needs_overlay_match.group("body"):
        fail("screen-space overlay redraw still depends on committed stroke handoff IDs", failures)
    if "or _has_inactive_module_cards()" not in board_view_text or "func _has_inactive_module_cards() -> bool:" not in board_view_text:
        fail("Inactive screen-space ModuleObject cards must invalidate custom drawing during camera motion", failures)

    stroke_renderer_text = (ROOT / "scripts/render/stroke_batch_renderer.gd").read_text(encoding="utf-8")
    highlighter_match = re.search(
        r"static func _draw_highlighter\([^\n]+\n(?P<body>.*?)(?=\n\nstatic func )",
        stroke_renderer_text,
        re.DOTALL,
    )
    if highlighter_match is None:
        fail("highlighter draw implementation is missing", failures)
    else:
        highlighter_body = highlighter_match.group("body")
        if re.search(r"^[ \t]*(?:var\s+[^=]+?=\s*)?Geometry2D\.offset_polyline\(", highlighter_body, re.MULTILINE) \
                or re.search(r"^[ \t]*[^#\n]*\.draw_colored_polygon\(", highlighter_body, re.MULTILINE):
            fail("highlighter still uses a filled polygon path that can fill closed loops", failures)
        if "_draw_round_polyline" not in highlighter_body:
            fail("highlighter is not rendered as an open stroke-only polyline", failures)

    theme_text = (ROOT / "scripts/ui/notlight_theme.gd").read_text(encoding="utf-8")
    if 'theme_type_variation = "CompactRailTextButton"' not in board_screen_text_for_drawing:
        fail("PDF rail button can still expand the fixed-width tool rail", failures)
    for required_term in ('&"CompactRailTextButton"', 'theme.set_font_size("font_size", "CompactRailTextButton", 13)'):
        if required_term not in theme_text:
            fail(f"compact PDF rail theme contract is missing: {required_term}", failures)

    # Stage 9.7.5-9.7.7 Resource Library UX and economical portable exchange.
    # Preview must stay on existing bounded media services and never spawn a
    # synchronous sidecar from the modal/UI path. Bulk catalog mutations are
    # service-level batches, while thin board packages resolve omitted assets
    # only through an exact local canonical SHA-256 before commit.
    asset_preview_path = ROOT / "scripts/ui/asset_preview_overlay.gd"
    board_export_options_path = ROOT / "scripts/ui/board_export_options_dialog.gd"
    if not asset_preview_path.is_file():
        fail("Stage 9.7.5 Resource Library preview overlay is missing", failures)
    else:
        asset_preview_text = asset_preview_path.read_text(encoding="utf-8")
        for required_term in (
            "class_name AssetPreviewOverlay",
            "image_cache.request_texture(asset_id, PREVIEW_EXTENT)",
            "pdf_media.request_page(asset_id, _page_index, PREVIEW_EXTENT, PDF_PRIORITY_CURRENT)",
            "audio_media.load_stream(asset_id)",
            'ClassDB.class_exists("FFmpegVideoStream")',
            "func close_preview() -> void",
            "move_to_front()",
            "grab_focus()",
            "_stop_media()",
        ):
            if required_term not in asset_preview_text:
                fail(f"Stage 9.7.5 preview contract is missing: {required_term}", failures)
        if "OS.execute(" in asset_preview_text or "OS.create_process(" in asset_preview_text:
            fail("Stage 9.7.5 preview UI must not launch sidecar processes directly", failures)
        if re.search(r"\b_seek\.disabled\s*=", asset_preview_text):
            fail("Stage 9.7.5 preview seek slider must use Slider.editable, not unsupported disabled", failures)
        if "_seek.editable = false" not in asset_preview_text:
            fail("Stage 9.7.5 preview seek slider missing non-editable reset state", failures)
        for required_term in (
            "const PDF_PRIORITY_CURRENT: int = 100",
            "const PDF_PRIORITY_PREFETCH: int = 20",
            "func _prefetch_pdf_neighbors() -> void",
            "_video_player.play()",
            "_set_audio_stream(stream, true)",
        ):
            if required_term not in asset_preview_text:
                fail(f"Stage 9.7.8 preview responsiveness/autoplay contract is missing: {required_term}", failures)

        pdf_service_text = (ROOT / "scripts/media/pdf_media_service.gd").read_text(encoding="utf-8")
        pdf_worker_text = (ROOT / "scripts/workers/pdf_render_worker.gd").read_text(encoding="utf-8")
        for required_term in (
            "MAX_BACKGROUND_PENDING_JOBS: int = 28",
            "func ensure_document(asset_id: String, priority: int = 0) -> Dictionary:",
            "ensure_document(clean_id, priority)",
            "_worker.promote_pending(key, priority)",
        ):
            if required_term not in pdf_service_text:
                fail(f"Stage 9.7.8 PDF interactive queue contract is missing: {required_term}", failures)
        for required_term in (
            "func request_probe(cache_key: String, asset_id: String, source_path: String, priority: int = 0) -> bool:",
            "func promote_pending(cache_key: String, priority: int) -> void",
            "func _insert_by_priority(job: Dictionary) -> void",
        ):
            if required_term not in pdf_worker_text:
                fail(f"Stage 9.7.8 PDF worker priority contract is missing: {required_term}", failures)

    board_screen_stage975 = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    hub_screen_stage975 = (ROOT / "scripts/ui/hub_screen.gd").read_text(encoding="utf-8")
    for required_term in (
        "_asset_preview.closed.connect(_on_asset_preview_closed)",
        "_board_view.set_process_unhandled_key_input(false)",
        "if _asset_preview != null and _asset_preview.visible:",
    ):
        if required_term not in board_screen_stage975:
            fail(f"Stage 9.7.5 board modal-input shield is missing: {required_term}", failures)
    if "_board_export_options_dialog != null and _board_export_options_dialog.visible" not in hub_screen_stage975:
        fail("Stage 9.7.5-9.7.7 Hub modal-input shield is missing", failures)

    asset_library_view_stage975 = (ROOT / "scripts/ui/asset_library_view.gd").read_text(encoding="utf-8")
    for required_term in (
        "signal asset_preview_requested(asset_id: String)",
        "func _on_bulk_select_requested(",
        "library.move_assets(selected_ids, folder_id)",
        "library.delete_assets(selected_ids, false)",
        "portable_packages.export_library_selection(destination, _export_selected_asset_ids)",
    ):
        if required_term not in asset_library_view_stage975:
            fail(f"Stage 9.7.6 Resource Library bulk UX contract is missing: {required_term}", failures)

    asset_catalog_stage976 = (ROOT / "scripts/assets/asset_catalog.gd").read_text(encoding="utf-8")
    asset_service_stage976 = (ROOT / "scripts/assets/asset_library_service.gd").read_text(encoding="utf-8")
    for required_term in (
        "func move_assets(asset_ids: PackedStringArray, folder_id: String) -> bool:",
        "func remove_assets(asset_ids: PackedStringArray) -> bool:",
    ):
        if required_term not in asset_catalog_stage976:
            fail(f"Stage 9.7.6 batch catalog contract is missing: {required_term}", failures)
    for required_term in (
        "func move_assets(asset_ids: PackedStringArray, folder_id: String) -> bool:",
        "func delete_assets(asset_ids: PackedStringArray, allow_used: bool = false) -> Dictionary:",
    ):
        if required_term not in asset_service_stage976:
            fail(f"Stage 9.7.6 batch library service contract is missing: {required_term}", failures)

    portable_format_stage977 = (ROOT / "scripts/portable/notlight_portable_package_format.gd").read_text(encoding="utf-8")
    portable_service_stage977 = (ROOT / "scripts/portable/notlight_portable_package_service.gd").read_text(encoding="utf-8")
    if "const MANIFEST_SCHEMA_VERSION: int = 2" not in portable_format_stage977:
        fail("Stage 9.7.7 portable package manifest schema must be v2", failures)
    for required_term in (
        "func export_library_selection(destination_path: String, asset_ids: PackedStringArray) -> Dictionary:",
        "var clean_asset_ids: PackedStringArray = PackedStringArray()",
        "func get_board_export_plan(board_id: String) -> Dictionary:",
        "func export_board_profile(board_id: String, destination_path: String, options: Dictionary) -> Dictionary:",
        '"resource_policy": {',
        '"embedded": false',
        '"mode": "reuse_external"',
        "FileAccess.get_sha256(external_path).to_lower() != hash_sha256",
        "func _validate_board_resource_policy(manifest: Dictionary) -> String:",
    ):
        if required_term not in portable_service_stage977:
            fail(f"Stage 9.7.7 economical portable exchange contract is missing: {required_term}", failures)
    if not board_export_options_path.is_file():
        fail("Stage 9.7.7 board export options dialog is missing", failures)
    else:
        board_export_options_text = board_export_options_path.read_text(encoding="utf-8")
        for required_term in (
            'set_item_metadata(0, "all")',
            'set_item_metadata(1, "none")',
            'set_item_metadata(2, "custom")',
            '"include_derived_variants": _derived.button_pressed',
        ):
            if required_term not in board_export_options_text:
                fail(f"Stage 9.7.7 board export UX contract is missing: {required_term}", failures)

    sidecar_runner_text = (ROOT / "scripts/media/sidecar_process_runner.gd").read_text(encoding="utf-8")
    for required_term in (
        "func _drain_after_exit() -> void",
        "func _drain_pipe_after_exit(",
        "_drain_after_exit()",
    ):
        if required_term not in sidecar_runner_text:
            fail(f"Stage 9.7.8 Windows sidecar pipe hardening is missing: {required_term}", failures)
    if "pipe.get_length()" in sidecar_runner_text:
        fail("Sidecar runner still uses PeekNamedPipe-backed get_length() on Windows pipes", failures)
    if "pipe.get_buffer(read_size)" not in sidecar_runner_text:
        fail("Sidecar runner is missing bounded direct pipe reads", failures)

    board_repository_text = (ROOT / "scripts/data/board_repository.gd").read_text(encoding="utf-8")
    asset_catalog_text = (ROOT / "scripts/assets/asset_catalog.gd").read_text(encoding="utf-8")
    for required_term in ("var write_ok: bool = file.store_string", "var write_error: Error = file.get_error()"):
        if required_term not in board_repository_text:
            fail(f"BoardRepository canonical write verification is missing: {required_term}", failures)
        if required_term not in asset_catalog_text:
            fail(f"AssetCatalog canonical write verification is missing: {required_term}", failures)
    if "var write_ok: bool = file.store_buffer(bytes)" not in board_repository_text:
        fail("BoardRepository binary payload write verification is missing", failures)
    settings_store_text = (ROOT / "scripts/settings/app_settings_store.gd").read_text(encoding="utf-8")
    for required_term in ("var write_ok: bool = file.store_string", "var write_error: Error = file.get_error()"):
        if required_term not in settings_store_text:
            fail(f"AppSettingsStore atomic write verification is missing: {required_term}", failures)


    # Stage 10 — first-party Module API v1 foundation. Code modules are trusted
    # executable extensions, but their install/state/portable boundaries remain
    # Local-First, bounded, hash-verified and core-owned.
    module_contract_paths = (
        "scripts/modules/module_manifest.gd",
        "scripts/modules/module_registry.gd",
        "scripts/modules/module_package_service.gd",
        "scripts/modules/module_localization_bundle.gd",
        "scripts/modules/module_instance_context.gd",
        "scripts/modules/module_surface_pool.gd",
        "scripts/core/module_store.gd",
        "scripts/core/create_module_command.gd",
        "scripts/core/update_module_state_command.gd",
        "scripts/ui/module_library_view.gd",
        "scripts/ui/module_picker_panel.gd",
        "sdk/notlight_module_api_v1.json",
        "docs/MODULE_API_V1.md",
    )
    for relative in module_contract_paths:
        if not (ROOT / relative).is_file():
            fail(f"Stage 10 Module API artifact is missing: {relative}", failures)

    module_manifest_text = (ROOT / "scripts/modules/module_manifest.gd").read_text(encoding="utf-8")
    for required_term in (
        'const MODULE_API_VERSION: int = 1',
        'const GODOT_RUNTIME_VERSION: String = "4.4.1"',
        '"board.instance_state"',
        '"localization.read"',
        '"theme.read"',
        'dependencies_value is not Array',
        'res:/" + "/modules/%s/"',
    ):
        if required_term not in module_manifest_text:
            fail(f"Stage 10 module manifest contract is missing: {required_term}", failures)

    module_store_text = (ROOT / "scripts/core/module_store.gd").read_text(encoding="utf-8")
    for required_term in (
        'const MAX_STATE_BYTES: int = 524288',
        'static func normalize_state(source: Dictionary) -> Dictionary:',
        'static func _normalize_variant(',
        '"instance_state"',
        '"state_schema_version"',
    ):
        if required_term not in module_store_text:
            fail(f"Stage 10 bounded ModuleStore contract is missing: {required_term}", failures)

    module_registry_text = (ROOT / "scripts/modules/module_registry.gd").read_text(encoding="utf-8")
    for required_term in (
        'ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(payload_path), false)',
        'FileAccess.get_sha256(payload_path).to_lower()',
        'module_manifest_sha256',
        'package_payloads',
        'var _localization_bundles: Dictionary = {}',
        'var _catalog_localization_bundles: Dictionary = {}',
        'func module_text(module_id: String, key: String, locale: String, values: Dictionary = {}) -> String:',
        'func _read_version_localizations(module_id: String, version_dir: String, manifest: Dictionary) -> Dictionary:',
        'func _catalog_localizations(',
        'ModuleLocalizationBundle.resolve_manifest_text(manifest, catalog_bundles, "description", locale)',
        'ModuleLocalizationBundle.read_file(path, module_id, locale, locale == "ru")',
        'if not pending_key.is_empty() and not active_key.is_empty():',
        'func _recover_legacy_first_install_retry_state() -> void:',
        'LEGACY_LOCALIZATION_ACTIVATION_ERROR',
        'func normalize_state(module_id: String, source: Dictionary) -> Dictionary:',
        '"preview_path": preview_path',
        'func _installed_artwork_path(version_dir: String, package_key: String, stem: String) -> String:',
    ):
        if required_term not in module_registry_text:
            fail(f"Stage 10 module activation/integrity contract is missing: {required_term}", failures)
    if 'NotLightL10n.register_module_localization' in module_registry_text:
        fail("Stage 10 ModuleRegistry must own active module localization instead of depending on the global localization autoload", failures)

    module_localization_text = (ROOT / "scripts/modules/module_localization_bundle.gd").read_text(encoding="utf-8")
    for required_term in (
        'class_name ModuleLocalizationBundle',
        'const MAX_STRINGS: int = 5000',
        'const MANIFEST_NAME_KEY: String = "module.name"',
        'const MANIFEST_DESCRIPTION_KEY: String = "module.description"',
        'static func read_file(',
        'static func validate_source(',
        'static func resolve_manifest_text(',
        'source.get("_meta", {})',
        'source.get("strings", {})',
        'NotLightL10n.text("runtime.modules.module_localization_bundle.e295e66e0c")',
    ):
        if required_term not in module_localization_text:
            fail(f"Stage 10 canonical module localization contract is missing: {required_term}", failures)

    module_package_text = (ROOT / "scripts/modules/module_package_service.gd").read_text(encoding="utf-8")
    for required_term in (
        'const STAGING_ROOT: String = "user://notlight/module_staging"',
        'NotLightPortablePackageFormat.materialize_payloads(',
        'func _validate_localization_file(',
        'ModuleLocalizationBundle.read_file(path, module_id, locale, require_nonempty)',
        'func _verify_staged_payload(',
        'registry.write_install_state(module_id, state)',
        'package_payloads',
        'module_manifest_sha256',
        'const MAX_PREVIEW_BYTES: int = 8 * 1024 * 1024',
        'var preview_key: String = str(manifest.get("preview_key", ""))',
        'preview_destination',
    ):
        if required_term not in module_package_text:
            fail(f"Stage 10 transactional module install contract is missing: {required_term}", failures)

    module_manifest_stage102 = (ROOT / "scripts/modules/module_manifest.gd").read_text(encoding="utf-8")
    for required_term in (
        'var preview_key: String = str(source.get("preview_key", ""))',
        'func _validate_unique_payload_keys(',
        'NotLightL10n.text("runtime.modules.module_manifest.a794e1f7af")',
        '"preview_key": preview_key',
    ):
        if required_term not in module_manifest_stage102:
            fail(f"Stage 10.2 module artwork/manifest contract is missing: {required_term}", failures)

    module_artwork_stage102 = (ROOT / "scripts/modules/module_artwork_loader.gd").read_text(encoding="utf-8")
    for required_term in (
        'class_name ModuleArtworkLoader',
        'const MAX_SOURCE_BYTES: int = 8 * 1024 * 1024',
        'image.load_png_from_buffer(bytes)',
        'image.load_svg_from_buffer(bytes, 1.0)',
        'ImageTexture.create_from_image(image)',
    ):
        if required_term not in module_artwork_stage102:
            fail(f"Stage 10.2 bounded module artwork loading contract is missing: {required_term}", failures)

    l10n_facade_text = (ROOT / "scripts/localization/notlight_l10n.gd").read_text(encoding="utf-8")
    l10n_runtime_text = (ROOT / "scripts/localization/localization_service.gd").read_text(encoding="utf-8")
    module_manifest_locale_text = (ROOT / "scripts/modules/module_manifest.gd").read_text(encoding="utf-8")
    expected_core_locales = '["ru", "be", "en", "uk"]'
    if f'const FALLBACK_LOCALES: Array[String] = {expected_core_locales}' not in l10n_facade_text:
        fail("Localization facade must retain the shipped ru/be/en/uk locale set", failures)
    if f'const SUPPORTED_LOCALES: Array[String] = {expected_core_locales}' not in l10n_runtime_text:
        fail("Localization runtime must retain the shipped ru/be/en/uk locale set", failures)
    if f'const SUPPORTED_LOCALES: Array[String] = {expected_core_locales}' not in module_manifest_locale_text:
        fail("Module API locale allowlist must retain ru/be/en/uk", failures)
    for retained_locale in ("ru", "be", "en", "uk"):
        if not (ROOT / f"localization/core/{retained_locale}.json").exists():
            fail(f"Expected retained localization bundle is missing: {retained_locale}.json", failures)


    module_context_text = (ROOT / "scripts/modules/module_instance_context.gd").read_text(encoding="utf-8")
    for required_term in (
        'func get_module_id() -> String:',
        'func get_module_instance_id() -> String:',
        'func get_locale() -> String:',
        'func text(key: String, values: Dictionary = {}) -> String:',
        'func get_theme_snapshot() -> Dictionary:',
        'func get_capabilities() -> Array:',
        'func commit_state(next_state: Dictionary, action_name: String = "") -> bool:',
    ):
        if required_term not in module_context_text:
            fail(f"Stage 10 ModuleContext bridge contract is missing: {required_term}", failures)

    if 'registry.module_text(module_id, key, get_locale(), values)' not in module_context_text:
        fail("Stage 10 ModuleContext localization must route through the active ModuleRegistry bundle", failures)

    module_context_funcs = set(re.findall(r"^\s*func\s+([A-Za-z_]\w*)\s*\(", module_context_text, re.MULTILINE))
    if "get_instance_id" in module_context_funcs:
        fail("Stage 10 ModuleContext must not shadow native Object.get_instance_id(); use get_module_instance_id()", failures)

    module_surface_text = (ROOT / "scripts/modules/module_surface_pool.gd").read_text(encoding="utf-8")
    module_surface_host_text = (ROOT / "scripts/modules/module_surface_host.gd").read_text(encoding="utf-8")
    board_module_state_host_text = (ROOT / "scripts/modules/board_module_instance_state_host.gd").read_text(encoding="utf-8")
    native_board_module_text = (ROOT / "scripts/board/native_board_view.gd").read_text(encoding="utf-8")
    for required_term in (
        'const DEFAULT_MAX_ACTIVE_SURFACES: int = 3',
        'func set_active_surface_budget(value: int) -> void:',
        'AppSettingsStore.MAX_MODULE_SURFACES',
        'ModuleSurfaceHost.new()',
        'BoardModuleInstanceStateHost.new()',
        '_surface_host.materialize(content, module_id, state_host, registry)',
        'var host: Control = Control.new()',
        'board_view.set_module_surface_active(entity_id, true)',
        'board_view.set_module_surface_active(entity_id, false)',
        'viewport_rect.intersects(projected_host_rect)',
        'const DRAG_BORDER_PX: float = 16.0',
        'BoardLiveSurfaceProjection.layout_zoom_for(view_zoom)',
        'host.scale = Vector2.ONE * transform_scale',
        'board_view.item_rect_changed.connect(_on_board_view_rect_changed)',
        'func _sync_all_host_geometry() -> void:',
        'func _push_presentation_if_changed(record: Dictionary, screen_size: Vector2) -> void:',
        'surface.call("notlight_set_host_presentation"',
    ):
        if required_term not in module_surface_text:
            fail(f"Stage 10 live-module surface lifecycle contract is missing: {required_term}", failures)
    for required_term in (
        'registry.normalize_state(clean_module_id, current_state)',
        'state_host.persist_normalized_state(normalized_state, target_schema)',
        'surface.call("notlight_attach_context", context, normalized_state.duplicate(true))',
    ):
        if required_term not in module_surface_host_text:
            fail(f"Stage 11.9 shared module-surface host contract is missing: {required_term}", failures)
    for required_term in (
        'extends ModuleInstanceStateHost',
        'UpdateModuleStateCommand.new(',
        'record["state_schema_version"] = state_schema_version',
    ):
        if required_term not in board_module_state_host_text:
            fail(f"Stage 11.9 board module-state host contract is missing: {required_term}", failures)

    if 'MIN_LIVE_PIXEL_EXTENT' in module_surface_text:
        fail("Active ModuleObject surfaces must stay live at far zoom instead of falling back to retained cards", failures)
    board_screen_module_text = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    if '_board_view.add_child(_module_surface_pool)' not in board_screen_module_text:
        fail("Stage 10.3 live ModuleSurfacePool must be parented to NativeBoardView to share one viewport-space origin", failures)
    if 'add_child(_module_surface_pool)' in board_screen_module_text.replace('_board_view.add_child(_module_surface_pool)', ''):
        fail("Stage 10.3 live ModuleSurfacePool must not return to a BoardScreen sibling overlay", failures)
    if 'SurfaceBackground' in module_surface_text:
        fail("Stage 10.3 module host must not paint an opaque backing surface behind module-owned presentation", failures)
    for forbidden_term in ('style.shadow_size = 4', 'style.shadow_color = Color(0.0, 0.0, 0.0, 0.13)'):
        if forbidden_term in module_surface_text:
            fail("Module host interaction frame must not shadow/tint module-owned pixels", failures)
    if 'style.draw_center = false' not in module_surface_text or 'style.shadow_size = 0' not in module_surface_text:
        fail("Module host interaction frame must be border-only with no center/shadow tint", failures)
    for required_term in (
        'var _live_module_surface_ids: Dictionary = {}',
        'func set_module_surface_active(entity_id: int, active: bool) -> void:',
        'if _live_module_surface_ids.has(entity_id):',
        'queue_redraw()',
    ):
        if required_term not in native_board_module_text:
            fail(f"Stage 10 retained/live ModuleObject handoff contract is missing: {required_term}", failures)

    settings_stage10_text = (ROOT / "scripts/settings/app_settings_store.gd").read_text(encoding="utf-8")
    settings_dialog_stage10_text = (ROOT / "scripts/ui/settings_dialog.gd").read_text(encoding="utf-8")
    for required_term in (
        'const MIN_MODULE_SURFACES: int = 1',
        'const MAX_MODULE_SURFACES: int = 32',
        'custom_active_module_surfaces',
        '"active_module_surfaces"',
        'func set_custom_active_module_surfaces(value: int) -> void:',
        'const MIN_NOTE_WORKSPACE_SURFACES: int = 1',
        'const MAX_NOTE_WORKSPACE_SURFACES: int = 32',
        'const DEFAULT_NOTE_WORKSPACE_SURFACES: int = 3',
        'custom_active_note_workspace_surfaces',
        '"active_note_workspace_surfaces"',
        'func set_custom_active_note_workspace_surfaces(value: int) -> void:',
    ):
        if required_term not in settings_stage10_text:
            fail(f"Stage 10 configurable module surface budget is missing: {required_term}", failures)
    for required_term in (
        'settings.performance.module_surfaces',
        'AppSettingsStore.MIN_MODULE_SURFACES',
        '_on_module_budget_changed',
        'settings.performance.note_workspace_surfaces',
        'AppSettingsStore.MIN_NOTE_WORKSPACE_SURFACES',
        '_on_note_workspace_budget_changed',
        'settings.performance.prefer_maximum_fps',
        '_on_prefer_maximum_fps_toggled',
    ):
        if required_term not in settings_dialog_stage10_text:
            fail(f"Stage 10/11 performance budget settings UX is missing: {required_term}", failures)

    app_root_frame_policy_text = (ROOT / "scripts/app/app_root.gd").read_text(encoding="utf-8")
    for required_term in (
        'func _apply_frame_rate_policy(prefer_maximum: bool) -> void:',
        'Engine.max_fps = 0',
        'DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)',
        'DisplayServer.window_get_vsync_mode()',
    ):
        if required_term not in app_root_frame_policy_text:
            fail(f"Stage 11.3 frame-rate preference contract is missing: {required_term}", failures)

    module_library_card_text = (ROOT / "scripts/ui/module_library_card.gd").read_text(encoding="utf-8")
    for required_term in (
        'class_name ModuleLibraryCard',
        'const CARD_WIDTH: float = 236.0',
        'TextureRect.STRETCH_KEEP_ASPECT_COVERED',
        'modules.library.card_meta_compact',
        'signal inspect_requested(module_id: String)',
        'func set_selected(selected: bool) -> void:',
    ):
        if required_term not in module_library_card_text:
            fail(f"Stage 10.2 Module Library card/grid contract is missing: {required_term}", failures)

    module_library_text = (ROOT / "scripts/ui/module_library_view.gd").read_text(encoding="utf-8")
    for required_term in (
        'class_name ModuleLibraryView',
        'FileDialog.FILE_MODE_OPEN_FILES',
        'func handle_external_files(files: PackedStringArray) -> bool:',
        'modules.library.trust_body',
        'byte_size',
        'modules.library.search',
        'func _matches_status_filter(info: Dictionary, filter_id: int) -> bool:',
        'GridContainer.new()',
        'ModuleLibraryCard.new()',
        'ModuleArtworkLoader.load_texture(path)',
        'const PAGE_SIZE: int = 60',
        'ModuleLibraryInspector.new()',
        'func _open_inspector(module_id: String) -> void:',
        'func _sync_inspector() -> void:',
    ):
        if required_term not in module_library_text:
            fail(f"Stage 10 Module Library BETA UX contract is missing: {required_term}", failures)
    module_inspector_text = (ROOT / "scripts/ui/module_library_inspector.gd").read_text(encoding="utf-8")
    for required_term in (
        'class_name ModuleLibraryInspector',
        'modules.library.inspector.developer_metadata',
        'source_package_sha256',
        'payload_sha256',
        'modules.library.inspector.capabilities',
        'modules.library.inspector.usage',
    ):
        if required_term not in module_inspector_text:
            fail(f"Stage 10.3 Module Library inspector contract is missing: {required_term}", failures)

    for required_term in (
        'window.files_dropped',
        '_module_view.handle_external_files(files)',
    ):
        if required_term not in hub_screen_stage975:
            fail(f"Stage 10 Module Library drag-and-drop contract is missing: {required_term}", failures)
    module_picker_text = (ROOT / "scripts/ui/module_picker_panel.gd").read_text(encoding="utf-8")
    for required_term in (
        'theme_type_variation = "LibraryDrawerPanel"',
        'func focus_search() -> void:',
        'NotLightL10n.connect_locale_changed(_on_locale_changed)',
        'func _on_locale_changed(_locale: String) -> void:',
        'modules.picker.search',
        'modules.picker.summary',
        'modules.picker.add',
        'ModuleArtworkLoader.load_texture(path)',
        'TextureRect.STRETCH_KEEP_ASPECT_COVERED',
    ):
        if required_term not in module_picker_text:
            fail(f"Stage 10 board Module Library drawer UX is missing: {required_term}", failures)
    for required_term in (
        '_module_picker.set_anchors_preset(Control.PRESET_RIGHT_WIDE)',
        'if should_open and _library_drawer_open:',
        '_set_library_drawer_open(false)',
        '_module_picker_tween.tween_property',
    ):
        if required_term not in hub_screen_stage975 and required_term not in (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8"):
            fail(f"Stage 10 mutually-exclusive module/resource drawer contract is missing: {required_term}", failures)

    board_schema_stage10 = (ROOT / "scripts/core/board_document_schema.gd").read_text(encoding="utf-8")
    portable_stage10 = (ROOT / "scripts/portable/notlight_portable_package_service.gd").read_text(encoding="utf-8")
    for required_term in ('CURRENT_VERSION: int = 13', '"module_objects"', '"note_portals"', 'collect_module_references'):
        if required_term not in board_schema_stage10:
            fail(f"Stage 11 board notes/module schema contract is missing: {required_term}", failures)
    for required_term in (
        '"module_dependencies": _module_dependencies_for_document(document)',
        'func _validate_board_module_records(document: Dictionary) -> String:',
        'ModuleStore.normalize_state(state_value as Dictionary)',
        'func _validate_board_module_dependencies(board: Dictionary, document: Dictionary) -> String:',
        'var records: Array = content.get("module_objects", []) as Array',
    ):
        if required_term not in portable_stage10:
            fail(f"Stage 10 portable module-state preservation contract is missing: {required_term}", failures)

    board_screen_stage10 = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    for required_term in (
        'ModulePickerPanel.new()',
        'ModuleSurfacePool.new()',
        'module_registry.default_state(clean_id)',
        'CreateModuleCommand.new(',
    ):
        if required_term not in board_screen_stage10:
            fail(f"Stage 10 board ModuleObject UX contract is missing: {required_term}", failures)

    search_snapshot_stage10 = (ROOT / "scripts/search/board_search_snapshot.gd").read_text(encoding="utf-8")
    search_panel_stage10 = (ROOT / "scripts/ui/board_search_panel.gd").read_text(encoding="utf-8")
    if 'model.modules.entity_ids' not in search_snapshot_stage10 or 'BoardEntityTypes.MODULE' not in search_snapshot_stage10:
        fail("Stage 10 ModuleObject search snapshot indexing is missing", failures)
    if 'board.search.type.module' not in search_panel_stage10:
        fail("Stage 10 ModuleObject search result type label is missing", failures)

    if asset_preview_path.is_file():
        asset_preview_stage10 = asset_preview_path.read_text(encoding="utf-8")
        for required_term in (
            'var _pdf_page_input: LineEdit',
            '_pdf_page_input.max_length = 6',
            '_pdf_page_input.text_submitted.connect(_on_pdf_page_submitted)',
            'func _on_pdf_page_submitted(value: String) -> void:',
        ):
            if required_term not in asset_preview_stage10:
                fail(f"Stage 10 direct PDF page-jump UX contract is missing: {required_term}", failures)

    sdk_contract_path = ROOT / "sdk/notlight_module_api_v1.json"
    if sdk_contract_path.is_file():
        try:
            sdk_contract = json.loads(sdk_contract_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"Stage 10 SDK contract JSON is invalid: {exc}", failures)
            sdk_contract = {}
        if sdk_contract.get("module_api_version") != 1 or sdk_contract.get("godot_version") != "4.4.1":
            fail("Stage 10 SDK contract target must stay pinned to Module API 1 / Godot 4.4.1", failures)
        if sdk_contract.get("module_id_example") != "notlight.stereometry":
            fail("Stage 10 SDK contract must use the solo-project notlight.* module namespace", failures)
        context_methods = sdk_contract.get("context", {}).get("methods", []) if isinstance(sdk_contract.get("context", {}), dict) else []
        if "get_module_instance_id" not in context_methods or "get_instance_id" in context_methods:
            fail("Stage 10 SDK context contract must avoid the native Object.get_instance_id() collision", failures)
        surface_contract = sdk_contract.get("surface", {}) if isinstance(sdk_contract.get("surface", {}), dict) else {}
        optional_surface_methods = surface_contract.get("optional_methods", []) if isinstance(surface_contract, dict) else []
        if "notlight_set_host_presentation" not in optional_surface_methods:
            fail("Stage 10.2 SDK contract must advertise optional module host presentation adaptation", failures)
        metadata_contract = sdk_contract.get("manifest_metadata_localization", {}) if isinstance(sdk_contract.get("manifest_metadata_localization", {}), dict) else {}
        if metadata_contract.get("keys") != {"name": "module.name", "description": "module.description"}:
            fail("Stage 10 Module API metadata localization keys must stay stable", failures)
        if metadata_contract.get("fallback_order") != ["requested_locale", "ru", "manifest_field"]:
            fail("Stage 10 Module API metadata localization fallback order must stay current -> RU -> manifest", failures)


    # Stage 11 built-in Notes core. Notes are logical documents backed by the
    # content-addressed Library, not modules and not SHA-identified logical assets.
    notes_repo_text = (ROOT / "scripts/notes/note_repository.gd").read_text(encoding="utf-8")
    notes_read_worker_text = (ROOT / "scripts/workers/note_read_worker.gd").read_text(encoding="utf-8")
    notes_index_worker_text = (ROOT / "scripts/workers/note_index_worker.gd").read_text(encoding="utf-8")
    notes_graph_model_text = (ROOT / "scripts/notes/notes_graph_model.gd").read_text(encoding="utf-8")
    notes_graph_canvas_text = (ROOT / "scripts/notes/notes_graph_canvas.gd").read_text(encoding="utf-8")
    notes_workspace_text = (ROOT / "scripts/notes/note_workspace_overlay.gd").read_text(encoding="utf-8")
    notes_portal_store_text = (ROOT / "scripts/core/note_portal_store.gd").read_text(encoding="utf-8")
    notes_portal_renderer_text = (ROOT / "scripts/board/note_portal_batch_renderer.gd").read_text(encoding="utf-8")
    notes_asset_kinds_text = (ROOT / "scripts/assets/asset_kinds.gd").read_text(encoding="utf-8")
    notes_import_caps_text = (ROOT / "scripts/assets/asset_import_capabilities.gd").read_text(encoding="utf-8")
    notes_import_validator_text = (ROOT / "scripts/assets/asset_import_content_validator.gd").read_text(encoding="utf-8")
    notes_catalog_text = (ROOT / "scripts/assets/asset_catalog.gd").read_text(encoding="utf-8")
    notes_library_text = (ROOT / "scripts/assets/asset_library_service.gd").read_text(encoding="utf-8")
    notes_board_view_text = (ROOT / "scripts/board/native_board_view.gd").read_text(encoding="utf-8")
    notes_render_policy_text = (ROOT / "scripts/core/board_render_policy.gd").read_text(encoding="utf-8")
    notes_board_screen_text = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    notes_hub_screen_text = (ROOT / "scripts/ui/hub_screen.gd").read_text(encoding="utf-8")
    notes_asset_view_text = (ROOT / "scripts/ui/asset_library_view.gd").read_text(encoding="utf-8")
    notes_asset_card_text = (ROOT / "scripts/ui/asset_library_card.gd").read_text(encoding="utf-8")
    notes_markdown_blocks_text = (ROOT / "scripts/notes/note_markdown_blocks.gd").read_text(encoding="utf-8")
    notes_preview_editor_text = (ROOT / "scripts/notes/note_preview_editor.gd").read_text(encoding="utf-8")
    notes_link_parser_text = (ROOT / "scripts/notes/note_link_parser.gd").read_text(encoding="utf-8")
    notes_portable_text = (ROOT / "scripts/portable/notlight_portable_package_service.gd").read_text(encoding="utf-8")
    notes_theme_text = (ROOT / "scripts/ui/notlight_theme.gd").read_text(encoding="utf-8")
    notes_navigation_text = (ROOT / "scripts/notes/notes_navigation_tree.gd").read_text(encoding="utf-8")
    notes_board_workspace_text = (ROOT / "scripts/notes/note_board_workspace_surface.gd").read_text(encoding="utf-8")
    notes_surface_pool_text = (ROOT / "scripts/notes/note_board_surface_pool.gd").read_text(encoding="utf-8")
    notes_preview_extractor_text = (ROOT / "scripts/notes/note_board_preview_extractor.gd").read_text(encoding="utf-8")
    notes_formula_block_text = (ROOT / "scripts/notes/note_formula_block.gd").read_text(encoding="utf-8")
    notes_inline_markup_text = (ROOT / "scripts/notes/note_inline_markup.gd").read_text(encoding="utf-8")
    notes_board_schema_text = (ROOT / "scripts/core/board_document_schema.gd").read_text(encoding="utf-8")

    for required_term in (
        "const NOTE: int = 7",
        'return NotLightL10n.text("asset.kind.note")',
        "static func is_board_insertable(kind: int) -> bool:",
        "kind == NOTE",
    ):
        if required_term not in notes_asset_kinds_text:
            fail(f"Stage 11 Notes asset-kind contract is missing: {required_term}", failures)
    for required_term in (
        "AssetKinds.is_board_insertable(_kind)",
        "AssetKinds.is_previewable(_kind)",
    ):
        if required_term not in notes_asset_card_text:
            fail(f"Stage 11 Resource Library Note-card UX contract is missing: {required_term}", failures)
    for required_term in (
        "TYPE_FRONTMATTER",
        "TYPE_MATH",
        "_frontmatter_end(lines)",
        "_is_list_line(text)",
        "_is_math_start(text)",
    ):
        if required_term not in notes_markdown_blocks_text:
            fail(f"Stage 11 Markdown source-span parser contract is missing: {required_term}", failures)
    for required_term in (
        r'var newline: String = "\r\n" if raw.contains("\r\n") else "\n"',
        'marker.trim_suffix(".").is_valid_int()',
        "NoteCodeEdit",
        "NoteRichText",
        "NoteCalloutPanel",
        "NoteFormulaBlock.new()",
        "DisplayServer.clipboard_set(editor.text)",
        "content_replace_requested.emit",
    ):
        if required_term not in notes_preview_editor_text:
            fail(f"Stage 11 editable-preview contract is missing: {required_term}", failures)
    for required_term in (
        "inline_ticks",
        "_fence_at(markdown, index)",
        "not _is_escaped(markdown, index)",
    ):
        if required_term not in notes_link_parser_text:
            fail(f"Stage 11 wiki-link extraction safety contract is missing: {required_term}", failures)

    for required_term in (
        'const NOTE_EXTENSIONS: Array[String] = ["md", "markdown"]',
        '"md": "text/markdown"',
        "AssetKinds.NOTE",
    ):
        if required_term not in notes_import_caps_text:
            fail(f"Stage 11 Markdown import registry contract is missing: {required_term}", failures)
    for required_term in (
        "const MAX_NOTE_BYTES: int = 8 * 1024 * 1024",
        "_is_valid_utf8(bytes)",
        "value == 0",
        "AssetKinds.NOTE",
    ):
        if required_term not in notes_import_validator_text:
            fail(f"Stage 11 Markdown validation contract is missing: {required_term}", failures)

    for required_term in (
        "const NOTE_METADATA_SCHEMA_VERSION: int = 2",
        "const CACHE_BYTE_BUDGET: int = 16 * 1024 * 1024",
        "const CACHE_ENTRY_BUDGET: int = 48",
        "NoteSaveWorker.new()",
        "NoteReadWorker.new()",
        "NoteIndexWorker.new()",
        "func request_content_load(note_id: String) -> bool:",
        "func request_save(note_id: String, content: String) -> bool:",
        "func add_explicit_link(source_note_id: String, target_note_id: String) -> bool:",
        "func relation_snapshot() -> Dictionary:",
        "return current_ids[0] if current_ids.size() == 1 else \"\"",
        "return alias_ids[0] if alias_ids.size() == 1 else \"\"",
        "delete_blob_if_unreferenced_path(old_relative_path)",
    ):
        if required_term not in notes_repo_text:
            fail(f"Stage 11 NoteRepository contract is missing: {required_term}", failures)
    for required_term in (
        "expected_hash: String",
        "expected_byte_size",
        "_sha256_hex(bytes)",
        "MAX_PENDING_JOBS",
    ):
        if required_term not in notes_read_worker_text:
            fail(f"Stage 11 note read-worker integrity contract is missing: {required_term}", failures)
    for required_term in (
        "expected_hash: String",
        "_sha256_hex(bytes)",
        "MAX_EXCERPT_CHARS",
        "MAX_PENDING_JOBS",
    ):
        if required_term not in notes_index_worker_text:
            fail(f"Stage 11 note index-worker contract is missing: {required_term}", failures)

    # Notes may share a content blob but must never share logical identity merely
    # because their SHA-256 matches.
    for required_term in (
        "allows_shared_hash: bool = int(asset.get(\"kind\", AssetKinds.OTHER)) == AssetKinds.NOTE",
        "int(asset.get(\"kind\", AssetKinds.OTHER)) != AssetKinds.NOTE",
    ):
        if required_term not in notes_catalog_text:
            fail(f"Stage 11 Note logical-identity catalog contract is missing: {required_term}", failures)
    if "if int(asset.get(\"kind\", AssetKinds.OTHER)) == AssetKinds.NOTE:" not in notes_library_text:
        fail("Stage 11 cleanup_unused must explicitly protect standalone Notes", failures)
    if "continue" not in notes_library_text[notes_library_text.find("func cleanup_unused"):notes_library_text.find("func cleanup_unused") + 1400]:
        fail("Stage 11 cleanup_unused Note protection is missing its skip path", failures)

    for required_term in (
        'const STORE_ID: StringName = &"note_portals"',
        '"asset_id": note_ids[index]',
        'str(record.get("asset_id", record.get("note_id", "")))',
    ):
        if required_term not in notes_portal_store_text:
            fail(f"Stage 11 NotePortal persistence contract is missing: {required_term}", failures)
    if '"note_portals"' not in board_schema_stage10 or "CURRENT_VERSION: int = 13" not in board_schema_stage10:
        fail("Stage 11 NotePortal board schema v13 contract is missing", failures)

    for required_term in (
        "const MAX_NODES: int = 20000",
        "const MAX_EDGES: int = 120000",
        "_edge_indices_by_node",
        "func query_edges_for_nodes(node_indices: PackedInt32Array) -> PackedInt32Array:",
        "_spatial_cells",
    ):
        if required_term not in notes_graph_model_text:
            fail(f"Stage 11 native Notes graph scaling contract is missing: {required_term}", failures)
    for forbidden_term in ("Graph" + "Edit", "Graph" + "Node"):
        if forbidden_term in notes_graph_canvas_text:
            fail(f"Stage 11 Notes graph must stay custom/native, found stock graph dependency: {forbidden_term}", failures)
    for required_term in (
        "query_edges_for_nodes",
        "relation_create_requested",
        "relation_remove_requested",
        "event.shift_pressed",
        "InputEventMagnifyGesture",
        "InputEventPanGesture",
        "app_settings.input_mode",
        "app_settings.camera_sensitivity",
        "app_settings.zoom_sensitivity",
        "app_settings.camera_speed",
    ):
        if required_term not in notes_graph_canvas_text:
            fail(f"Stage 11 native Notes graph interaction contract is missing: {required_term}", failures)

    for required_term in (
        "NotePreviewEditor.new()",
        "CodeEdit.new()",
        "NotesGraphCanvas.new()",
        "notes.status.loading",
        "request_content_load(note_id)",
        "_graph.focus_note(note_id, false)",
    ):
        if required_term not in notes_workspace_text:
            fail(f"Stage 11 Notes workspace UX contract is missing: {required_term}", failures)
    for required_term in (
        "candidate_ids: PackedInt64Array",
        "max_visible: int",
        "peek_board_preview",
        "_draw_markdown_preview",
        "_draw_code_run",
        "_draw_table_run",
        "_draw_math_run",
    ):
        if required_term not in notes_portal_renderer_text:
            fail(f"Stage 11 retained NotePortal renderer contract is missing: {required_term}", failures)
    for required_term in (
        "RENDER_REFRESH_NOTE_PORTAL",
        "_perform_note_portal_refresh",
        "_shared_note_portal_candidates",
        "max_visible_note_portals",
        "CreateNotePortalCommand.new(",
    ):
        if required_term not in notes_board_view_text:
            fail(f"Stage 11 NotePortal scheduler contract is missing: {required_term}", failures)
    if "var max_visible_note_portals: int = 2400" not in notes_render_policy_text:
        fail("Stage 11 NotePortal render budget is missing from BoardRenderPolicy", failures)

    for required_term in (
        "NoteWorkspaceOverlay.new()",
        "AssetKinds.NOTE",
        "_place_note_portal",
        "NotePortalStore.VIEW_WORKSPACE",
        "_note_surface_pool.activate",
        "notes_graph_requested",
    ):
        if required_term not in notes_board_screen_text:
            fail(f"Stage 11 board Notes UX contract is missing: {required_term}", failures)
    for required_term in ("NoteWorkspaceOverlay.new()", "AssetKinds.NOTE", "notes_graph_requested"):
        if required_term not in notes_hub_screen_text:
            fail(f"Stage 11 Hub/Library Notes UX contract is missing: {required_term}", failures)
    for required_term in ("signal notes_graph_requested", "AssetKinds.NOTE"):
        if required_term not in notes_asset_view_text:
            fail(f"Stage 11 Resource Library Notes integration is missing: {required_term}", failures)
    for required_term in ("NoteWorkspacePanel", "NotePreviewBlockPanel", "NoteCodeEdit"):
        if required_term not in notes_theme_text:
            fail(f"Stage 11 Notes semantic theme contract is missing: {required_term}", failures)

    # Portable import must not resolve a NotePortal to an arbitrary existing note
    # merely because another logical note has the same canonical Markdown hash.
    for required_term in (
        "var source_is_note: bool = int(record.get(\"kind\", AssetKinds.OTHER)) == AssetKinds.NOTE",
        "if int(asset.get(\"kind\", AssetKinds.OTHER)) != AssetKinds.NOTE:",
        "same_id_record",
        "asset_id_map[source_id] = source_id",
    ):
        if required_term not in notes_portable_text:
            fail(f"Stage 11 portable Note logical-identity contract is missing: {required_term}", failures)

    notes_smoke_path = ROOT / "tools/notes_core_smoke_test.gd"
    if not notes_smoke_path.is_file():
        fail("Stage 11 Notes core smoke test is missing", failures)
    else:
        notes_smoke_text = notes_smoke_path.read_text(encoding="utf-8")
        for required_term in (
            "same-content notes collapsed their logical IDs",
            "ambiguous wiki title was guessed instead of rejected",
            "NotePortal asset_id was not collected as a board resource reference",
            "native graph did not preserve textual+explicit edge provenance",
            "empty Markdown revision did not commit as zero bytes",
            "empty initial Markdown note creation failed",
            "local graph exceeded the requested three-hop depth",
        ):
            if required_term not in notes_smoke_text:
                fail(f"Stage 11 Notes smoke coverage is missing: {required_term}", failures)

    notes_workspace_text = (ROOT / "scripts/notes/note_workspace_overlay.gd").read_text(encoding="utf-8")
    for required_term in (
        "NotesNavigationTree.new()",
        "note_workspace_insert_requested",
        "_set_graph_local",
        "_set_graph_hops",
        "_begin_folder_rename",
        "_request_folder_delete",
    ):
        if required_term not in notes_workspace_text:
            fail(f"Stage 11.3 Notes workspace UX contract is missing: {required_term}", failures)

    for required_term in (
        "MAX_TREE_DEPTH",
        "_append_folder_branch",
        "_append_notes_to_parent",
        "_get_drag_data",
        "_drop_data",
        "note_move_requested",
    ):
        if required_term not in notes_navigation_text:
            fail(f"Stage 11.3 unified Notes navigation contract is missing: {required_term}", failures)

    for required_term in (
        "VIEW_WORKSPACE",
        "MAX_WORKSPACE_TABS",
        "workspace_tabs",
        "set_workspace_state",
    ):
        if required_term not in notes_portal_store_text:
            fail(f"Stage 11.3 rich NotePortal state contract is missing: {required_term}", failures)
    if '"note_portals": ["workspace_tabs"]' not in notes_board_schema_text:
        fail("Stage 11.3 workspace tabs are not included in board portable asset references", failures)

    for required_term in (
        "NotesNavigationTree.new()",
        "NotePreviewEditor.new()",
        "NotesGraphCanvas.new()",
        "ScrollContainer.new()",
        "MAX_WORKSPACE_TABS",
        "_build_graph_toolbar",
    ):
        if required_term not in notes_board_workspace_text:
            fail(f"Stage 11.3 board Notes workspace surface contract is missing: {required_term}", failures)
    for required_term in (
        "DEFAULT_MAX_ACTIVE_SURFACES: int = AppSettingsStore.DEFAULT_NOTE_WORKSPACE_SURFACES",
        "MAX_ACTIVE_SURFACES: int = AppSettingsStore.MAX_NOTE_WORKSPACE_SURFACES",
        "while _activation_order.size() >= max_active_surfaces",
        "close_surface(_activation_order[0])",
    ):
        if required_term not in notes_surface_pool_text:
            fail(f"Stage 11.3 bounded Notes surface-pool contract is missing: {required_term}", failures)

    for required_term in ("MAX_RUNS", '"kind": "code"', '"kind": "math"', '"kind": "table"'):
        if required_term not in notes_preview_extractor_text:
            fail(f"Stage 11.3 retained Markdown preview contract is missing: {required_term}", failures)
    for required_term in ("FormulaRenderService", "FormulaStore.DISPLAY_BLOCK", "request_texture"):
        if required_term not in notes_formula_block_text:
            fail(f"Stage 11.3 Note LaTeX block contract is missing: {required_term}", failures)
    for required_term in ("external://", "mailto:", "note://"):
        if required_term not in notes_inline_markup_text:
            fail(f"Stage 11.3 Markdown link contract is missing: {required_term}", failures)

    for required_term in ("workspace_insert_requested", "notes.place_simple_on_board", "notes.place_workspace_on_board"):
        if required_term not in notes_asset_card_text:
            fail(f"Stage 11.3 dual note insertion UX is missing: {required_term}", failures)
    if "note_workspace_insert_requested" not in notes_asset_view_text:
        fail("Stage 11.3 Resource Library does not expose rich Notes workspace insertion", failures)

    for required_term in ("NoteRichText", "NoteNavigationTree", "NoteBoardWorkspacePanel", "NoteFormulaPanel"):
        if required_term not in notes_theme_text:
            fail(f"Stage 11.3 Notes semantic theme contract is missing: {required_term}", failures)
    if 'theme.set_color("default_color", "NoteRichText"' not in notes_theme_text:
        fail("Stage 11.3 reading mode is missing explicit semantic text foreground", failures)

    graph_motion_slice_start = notes_graph_canvas_text.find("func _handle_mouse_motion")
    graph_motion_slice_end = notes_graph_canvas_text.find("func _handle_key", graph_motion_slice_start)
    if graph_motion_slice_start >= 0 and graph_motion_slice_end > graph_motion_slice_start:
        if "model.positions[" in notes_graph_canvas_text[graph_motion_slice_start:graph_motion_slice_end]:
            fail("Stage 11.3 graph nodes must not become draggable on ordinary pointer motion", failures)

    for runtime_path in (ROOT / "scripts").rglob("*.gd"):
        runtime_text = runtime_path.read_text(encoding="utf-8").lower()
        if ("ob" + "sidian") in runtime_text:
            fail(f"Stage 11.3 foreign product name leaked into runtime code: {runtime_path.relative_to(ROOT)}", failures)

    project_about_path = ROOT / "scripts/ui/project_about_dialog.gd"
    if not project_about_path.is_file():
        fail("Stage 11.2 About project dialog is missing", failures)
    else:
        project_about_text = project_about_path.read_text(encoding="utf-8")
        for required_term in ('"about.title"', '"about.body"', '"about.footer"'):
            if required_term not in project_about_text:
                fail(f"Stage 11.2 About project dialog contract is missing: {required_term}", failures)

    # Stage 11.7 editor/Markdown/formula UX hardening.
    stage117_library_service_path = ROOT / "scripts/assets/asset_library_service.gd"
    stage117_library_view_path = ROOT / "scripts/ui/asset_library_view.gd"
    stage117_inspector_path = ROOT / "scripts/ui/asset_inspector_panel.gd"
    stage117_theme_path = ROOT / "scripts/ui/notlight_theme.gd"
    stage117_formula_path = ROOT / "scripts/notes/note_formula_block.gd"
    stage117_formula_worker_path = ROOT / "scripts/workers/formula_image_load_worker.gd"
    stage117_workspace_path = ROOT / "scripts/notes/note_workspace_overlay.gd"
    if all(path.is_file() for path in (
        stage117_library_service_path,
        stage117_library_view_path,
        stage117_inspector_path,
        stage117_theme_path,
        stage117_formula_path,
        stage117_formula_worker_path,
        stage117_workspace_path,
    )):
        stage117_library_service = stage117_library_service_path.read_text(encoding="utf-8")
        stage117_library_view = stage117_library_view_path.read_text(encoding="utf-8")
        stage117_inspector = stage117_inspector_path.read_text(encoding="utf-8")
        stage117_theme = stage117_theme_path.read_text(encoding="utf-8")
        stage117_formula = stage117_formula_path.read_text(encoding="utf-8")
        stage117_formula_worker = stage117_formula_worker_path.read_text(encoding="utf-8")
        stage117_workspace = stage117_workspace_path.read_text(encoding="utf-8")
        for required_term in (
            "signal asset_metadata_changed(asset_id: String)",
            "asset_metadata_changed.emit(asset_id)",
        ):
            if required_term not in stage117_library_service:
                fail(f"Stage 11.7 narrow Library metadata signal contract is missing: {required_term}", failures)
        for required_term in (
            "library.asset_metadata_changed.connect(_on_asset_metadata_changed)",
            "func _on_asset_metadata_changed(_asset_id: String) -> void:",
        ):
            if required_term not in stage117_library_view:
                fail(f"Stage 11.7 metadata-only Library view refresh contract is missing: {required_term}", failures)
        update_start = stage117_library_service.find("func update_asset_details")
        update_end = stage117_library_service.find("\n\nfunc ", update_start + 1)
        update_slice = stage117_library_service[update_start:update_end if update_end >= 0 else len(stage117_library_service)]
        if "library_changed.emit()" in update_slice:
            fail("Stage 11.7 description/tag autosave must not emit coarse library_changed", failures)

        for required_term in (
            "_self_library_update_depth",
            "_update_asset_details_without_self_refresh",
            "_description_edit.focus_exited.connect(_flush_description)",
            "_description_edit.get_caret_line()",
            "_description_edit.scroll_vertical",
        ):
            if required_term not in stage117_inspector:
                fail(f"Stage 11.7 Resource Inspector autosave UX contract is missing: {required_term}", failures)
        for required_term in (
            'theme.set_font("bold_font", "NoteRichText"',
            'theme.set_font("italics_font", "NoteRichText"',
            'theme.set_font("bold_italics_font", "NoteRichText"',
            "SystemFont.new()",
            "note_bold_font.font_weight = 700",
            "note_italic_font.font_italic = true",
        ):
            if required_term not in stage117_theme:
                fail(f"Stage 11.7 Markdown typography contract is missing: {required_term}", failures)
        for required_term in (
            "_presentation_row_count()",
            "_prepare_aligned_line",
            "SINGLE_LINE_DISPLAY_HEIGHT",
        ):
            if required_term not in stage117_formula:
                fail(f"Stage 11.7 Notes formula presentation contract is missing: {required_term}", failures)
        for required_term in ("image.get_used_rect()", "image.get_region(region)"):
            if required_term not in stage117_formula_worker:
                fail(f"Stage 11.7 formula alpha-trim contract is missing: {required_term}", failures)
        if "if not _title_edit.has_focus():" not in stage117_workspace:
            fail("Stage 11.7 active Notes title must not be overwritten by background refresh", failures)
    else:
        fail("Stage 11.7 UX hardening source set is incomplete", failures)

    # Stage 11.8 Godot 4.4.1 constructor fix + SHA-pinned Resource Library embeds.
    stage118_embed_path = ROOT / "scripts/notes/note_resource_embed.gd"
    stage118_embed_block_path = ROOT / "scripts/notes/note_resource_embed_block.gd"
    stage118_portable_path = ROOT / "scripts/portable/notlight_portable_package_service.gd"
    stage118_export_dialog_path = ROOT / "scripts/ui/board_export_options_dialog.gd"
    stage118_fixture_path = ROOT / "test_notes/NOTLIGHT_MARKDOWN_FEATURE_TEST_STAGE11_8.md"
    if all(path.is_file() for path in (
        stage118_embed_path,
        stage118_embed_block_path,
        stage118_portable_path,
        stage118_export_dialog_path,
        stage118_fixture_path,
    )):
        stage118_embed = stage118_embed_path.read_text(encoding="utf-8")
        stage118_embed_block = stage118_embed_block_path.read_text(encoding="utf-8")
        stage118_portable = stage118_portable_path.read_text(encoding="utf-8")
        stage118_export_dialog = stage118_export_dialog_path.read_text(encoding="utf-8")
        stage118_fixture = stage118_fixture_path.read_text(encoding="utf-8")
        if "Transform2D(1.0, 0.26, 0.0, 1.0, 0.0, 0.0)" in stage117_theme:
            fail("Stage 11.8 must not use the unsupported six-scalar GDScript Transform2D constructor on Godot 4.4.1", failures)
        if "note_bold_font.font_weight = 700" not in stage117_theme or "note_italic_font.font_italic = true" not in stage117_theme:
            fail("Stage 11.9 Godot 4.4.1 SystemFont typography contract is missing", failures)
        for required_term in (
            'const PREFIX: String = "![[resource-sha256:"',
            "static func extract_hashes(markdown: String) -> PackedStringArray:",
            "AssetKinds.IMAGE",
            "AssetKinds.VIDEO",
            "AssetKinds.AUDIO",
            "AssetKinds.PDF",
        ):
            if required_term not in stage118_embed:
                fail(f"Stage 11.8 resource embed grammar is missing: {required_term}", failures)
        for required_term in ("find_asset_by_hash", "_image_cache.request_texture", "preview_requested.emit"):
            if required_term not in stage118_embed_block:
                fail(f"Stage 11.8 resource embed presentation is missing: {required_term}", failures)
        for required_term in (
            '"include_note_embeds": true',
            "_collect_note_embed_dependencies(note_ids)",
            '"note_embed_asset_ids"',
            "_board_note_embed_asset_ids(manifest)",
        ):
            if required_term not in stage118_portable:
                fail(f"Stage 11.8 portable embed dependency contract is missing: {required_term}", failures)
        for required_term in ("_include_note_embeds", '"exchange.board.include_note_embeds"'):
            if required_term not in stage118_export_dialog:
                fail(f"Stage 11.8 board export embed option is missing: {required_term}", failures)
        for required_term in (
            "**Жирный кириллический текст**",
            "*Курсивный кириллический текст*",
            "***Жирный курсив кириллицей***",
            "![[resource-sha256:",
        ):
            if required_term not in stage118_fixture:
                fail(f"Stage 11.8 Cyrillic/embed regression fixture is missing: {required_term}", failures)
    else:
        fail("Stage 11.8 embed hardening source set is incomplete", failures)

    # Stage 11.9 Notes media embeds / Library UX / portability hardening.
    stage119_preview_path = ROOT / "scripts/notes/note_preview_editor.gd"
    stage119_settings_path = ROOT / "scripts/settings/app_settings_store.gd"
    stage119_library_view_path = ROOT / "scripts/ui/asset_library_view.gd"
    stage119_references_path = ROOT / "scripts/assets/asset_reference_index.gd"
    stage119_inspector_path = ROOT / "scripts/ui/asset_inspector_panel.gd"
    if all(path.is_file() for path in (
        stage119_preview_path,
        stage119_settings_path,
        stage119_library_view_path,
        stage119_references_path,
        stage119_inspector_path,
    )):
        stage119_preview = stage119_preview_path.read_text(encoding="utf-8")
        stage119_settings = stage119_settings_path.read_text(encoding="utf-8")
        stage119_library_view = stage119_library_view_path.read_text(encoding="utf-8")
        stage119_references = stage119_references_path.read_text(encoding="utf-8")
        stage119_inspector = stage119_inspector_path.read_text(encoding="utf-8")
        for required_term in (
            "var _video_player: VideoStreamPlayer",
            "var _audio_player: AudioStreamPlayer",
            "_pdf_media.request_page",
            "ClassDB.class_exists(\"FFmpegVideoStream\")",
            "Metadata-only Library changes must not tear down an active decoder/player",
        ):
            if required_term not in stage118_embed_block:
                fail(f"Stage 11.9 rich Notes media embed contract is missing: {required_term}", failures)
        for required_term in (
            "while _embed_live_order.size() >= _embed_live_budget",
            "oldest.deactivate_live()",
            'snapshot.get("effective_note_embed_live_media"',
        ):
            if required_term not in stage119_preview:
                fail(f"Stage 11.9 bounded Notes media budget contract is missing: {required_term}", failures)
        for required_term in (
            "const SETTINGS_SCHEMA_VERSION: int = 19",
            "const MAX_NOTE_EMBED_LIVE_MEDIA: int = 64",
            "custom_note_embed_rich_preview",
        ):
            if required_term not in stage119_settings:
                fail(f"Stage 11.9 scalable Notes media setting is missing: {required_term}", failures)
        for required_term in (
            "var _folder_tree: Tree",
            "set_column_clip_content(0, true)",
            "scroll_horizontal_enabled = false",
            "item_collapsed.connect(_on_folder_tree_item_collapsed)",
            "item.set_tooltip_text(0, library.folder_path(folder_id))",
        ):
            if required_term not in stage119_library_view:
                fail(f"Stage 11.9 Library folder-tree UX contract is missing: {required_term}", failures)
        for required_term in (
            "func board_usage_count(asset_id: String) -> int:",
            "func note_embed_usage_count(asset_id: String) -> int:",
        ):
            if required_term not in stage119_references:
                fail(f"Stage 11.9 usage provenance contract is missing: {required_term}", failures)
        for required_term in ('"library.inspector.usage_boards"', '"library.inspector.usage_notes"'):
            if required_term not in stage119_inspector:
                fail(f"Stage 11.9 inspector usage provenance UI is missing: {required_term}", failures)
        for required_term in (
            'NotLightL10n.text("runtime.portable.notlight_portable_package_service.b9b15a3a25")',
            "func _validate_materialized_note_embed_closure(",
            "func _read_import_note_content(",
            'var record_value: Variant = asset.get("record", {})',
        ):
            if required_term not in stage118_portable:
                fail(f"Stage 11.9 portable embed verification contract is missing: {required_term}", failures)
    else:
        fail("Stage 11.9 media/embed UX hardening source set is incomplete", failures)

    if failures:
        print("Validation failed:")
        for item in failures:
            print(f"- {item}")
        return 1
    print("Validation passed: Stage 11.9 Notes media embeds, Library folder/usage UX, SHA-verified portable dependency closure, Godot 4.4.1 typography, and inherited contracts are consistent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
