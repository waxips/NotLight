<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# NotLight Module API v1

NotLight Module API v1 is the first-party contract for executable modules hosted by NotLight. The machine-readable contract is `sdk/notlight_module_api_v1.json`; this document explains the intended boundaries for module authors and maintainers.

## Compatibility contract

- Module API version: **1**
- Godot runtime version: **4.4.1**
- Code modules are **trusted executable extensions**, not a security sandbox.
- Installing or updating executable module code takes effect after an application restart.

A manifest that declares an unsupported module API version or Godot runtime is rejected by the core manifest validator.

## Entry object

A code module entry object must implement:

- `notlight_get_default_state`
- `notlight_normalize_state`
- `notlight_create_surface`

The created surface must implement `notlight_attach_context`. It may also implement `notlight_set_host_state` and `notlight_set_host_presentation`.

## Host context

The host context exposes the v1 methods listed in `sdk/notlight_module_api_v1.json`, including module/instance identity, locale-aware text lookup, theme snapshot access, capability discovery, state commit, and last-error inspection. The context emits state, theme, and locale change signals.

## Capabilities

Module API v1 recognizes these capabilities:

- `board.instance_state`
- `localization.read`
- `theme.read`

Capabilities are normalized and validated by `ModuleManifest`; unknown capability requests are not silently granted.

## State limits

Canonical instance state is JSON-compatible and bounded by the host. The v1 contract currently limits serialized state to 524,288 bytes, nesting depth to 20, arrays/dictionaries to 4,096 items, strings to 65,536 characters, and asset references to 128.

Module state is core-owned and normalized before persistence. Modules should treat state commits as transactional requests rather than mutating NotLight storage directly.

## Localization

The canonical metadata locale is Russian (`ru`). Display-name/description lookup falls back in this order:

1. requested locale;
2. Russian;
3. the manifest field.

The same metadata policy is used by the module library, picker, preview, and note embeds.

## Portable-board policy

Portable board packages preserve a module ID plus canonical instance state. Executable module payloads are **not** embedded into a board package automatically. This avoids turning ordinary board exchange into implicit executable-code distribution.

## Security model

A module containing executable GDScript/native code has the privileges of trusted application extension code. Do not install code modules from untrusted sources. Package path validation, hashes, manifests, and state limits reduce accidental/corrupt input risk but do not create a sandbox around malicious executable code.

## Source of truth

When this prose and the machine-readable contract disagree, maintainers should fix the discrepancy before release. `sdk/notlight_module_api_v1.json` and the validators in `scripts/modules/` are the normative implementation references for API v1.
