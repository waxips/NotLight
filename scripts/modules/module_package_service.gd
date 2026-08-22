# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModulePackageService
extends Node

signal module_installed(module_id: String, version: String, restart_required: bool)
signal module_install_failed(message: String)

const STAGING_ROOT: String = "user://notlight/module_staging"
const MAX_MODULE_PACKAGE_BYTES: int = 512 * 1024 * 1024
const MAX_PREVIEW_BYTES: int = 8 * 1024 * 1024

var registry: ModuleRegistry
var _last_error: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _staging_root: String = STAGING_ROOT


func configure(module_registry: ModuleRegistry) -> void:
	registry = module_registry
	_rng.randomize()
	_staging_root = STAGING_ROOT
	if registry != null:
		var configured_staging: String = registry.get_staging_directory().strip_edges()
		if not configured_staging.is_empty():
			_staging_root = configured_staging
	_ensure_directory(_staging_root)
	NotLightPortablePackageFormat.cleanup_directory(_staging_root)


func get_last_error() -> String:
	return _last_error


func inspect_module(package_path: String) -> Dictionary:
	_last_error = ""
	if package_path.get_extension().to_lower() != NotLightPortablePackageFormat.MODULE_EXTENSION:
		return _error(NotLightL10n.text("runtime.modules.module_package_service.d8a19db711"))
	var size: int = _file_size(package_path)
	if size <= 0 or size > MAX_MODULE_PACKAGE_BYTES:
		return _error(NotLightL10n.text("runtime.modules.module_package_service.933489ac64"))
	var package_info: Dictionary = NotLightPortablePackageFormat.inspect(package_path)
	if not bool(package_info.get("ok", false)):
		return _error(str(package_info.get("error", NotLightL10n.text("runtime.modules.module_package_service.282d2bc75f"))))
	if str(package_info.get("package_type", "")) != NotLightPortablePackageFormat.PACKAGE_TYPE_MODULE:
		return _error(NotLightL10n.text("runtime.modules.module_package_service.f1efa9653e"))
	var manifest: Dictionary = package_info.get("manifest", {}) as Dictionary
	var module_value: Variant = manifest.get("module", {})
	if module_value is not Dictionary:
		return _error(NotLightL10n.text("runtime.modules.module_package_service.4ec1f9cd08"))
	var validated: Dictionary = ModuleManifest.validate(module_value as Dictionary)
	if not bool(validated.get("ok", false)):
		return _error(str(validated.get("error", NotLightL10n.text("runtime.modules.module_package_service.43160f3ef4"))))
	var normalized: Dictionary = validated.get("manifest", {}) as Dictionary
	var payload_index: Dictionary = package_info.get("payload_by_key", {}) as Dictionary
	var expected_keys: Dictionary = _expected_payload_keys(normalized)
	for raw_key: Variant in expected_keys.keys():
		if not payload_index.has(str(raw_key)):
			return _error(NotLightL10n.text("runtime.modules.module_package_service.c079a83609") % str(raw_key))
	# Module API v1 deliberately rejects undeclared payloads. This keeps the outer
	# container auditable and makes every durable byte attributable to manifest data.
	for raw_key: Variant in payload_index.keys():
		if not expected_keys.has(str(raw_key)):
			return _error(NotLightL10n.text("runtime.modules.module_package_service.24c595235a") % str(raw_key))
	package_info["module_manifest"] = normalized
	package_info["expected_payload_keys"] = expected_keys
	return package_info


func install_module(package_path: String) -> Dictionary:
	_last_error = ""
	if registry == null:
		return _error(NotLightL10n.text("runtime.modules.module_package_service.0b106fa3b8"))
	var inspected: Dictionary = inspect_module(package_path)
	if not bool(inspected.get("ok", false)):
		return inspected
	var manifest: Dictionary = inspected.get("module_manifest", {}) as Dictionary
	var module_id: String = str(manifest.get("module_id", ""))
	var version: String = str(manifest.get("version", ""))
	var payload_index: Dictionary = inspected.get("payload_by_key", {}) as Dictionary
	var payload_descriptor: Dictionary = payload_index.get(str(manifest.get("payload_key", "payload.pck")), {}) as Dictionary
	var payload_hash: String = str(payload_descriptor.get("sha256", "")).to_lower()
	var version_key: String = "%s_%s" % [version, payload_hash.substr(0, 16)]
	for existing_key: String in registry.installed_version_keys(module_id):
		var existing_manifest: Dictionary = registry.read_version_manifest(module_id, existing_key)
		if str(existing_manifest.get("version", "")) != version:
			continue
		var install: Dictionary = _read_json(registry.version_directory(module_id, existing_key).path_join(ModuleRegistry.INSTALL_METADATA_FILE))
		if str(install.get("payload_sha256", "")).to_lower() == payload_hash:
			var state_same: Dictionary = registry.state_snapshot(module_id)
			if str(state_same.get("active_version_key", "")) == existing_key or str(state_same.get("pending_version_key", "")) == existing_key:
				return {"ok": true, "module_id": module_id, "version": version, "restart_required": not registry.is_module_active(module_id), "duplicate": true}
			state_same["pending_version_key"] = existing_key
			state_same["pending_remove"] = false
			state_same["last_error"] = ""
			if not registry.write_install_state(module_id, state_same):
				return _error(registry.get_last_error())
			return {"ok": true, "module_id": module_id, "version": version, "restart_required": true, "duplicate": true}
		return _error(NotLightL10n.text("runtime.modules.module_package_service.7bc409a9e2"))
	var state: Dictionary = registry.state_snapshot(module_id)
	var baseline_version: String = _highest_known_version(module_id)
	if not baseline_version.is_empty() and ModuleManifest.compare_versions(version, baseline_version) < 0:
		return _error(NotLightL10n.text("runtime.modules.module_package_service.4e5276130d"))

	var staging: String = _new_staging_directory()
	var materialized: Dictionary = NotLightPortablePackageFormat.materialize_payloads(
		inspected,
		inspected.get("expected_payload_keys", {}) as Dictionary,
		staging
	)
	if not bool(materialized.get("ok", false)):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _error(str(materialized.get("error", NotLightL10n.text("runtime.modules.module_package_service.0bab771f3d"))))
	var version_stage: String = staging.path_join("version")
	if not _ensure_directory(version_stage):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _error(NotLightL10n.text("runtime.modules.module_package_service.a1859e28c3"))
	var files: Dictionary = materialized.get("files", {}) as Dictionary
	if not _populate_version_stage(version_stage, manifest, files, payload_index, package_path):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _error(_last_error)
	var module_dir: String = registry.module_directory(module_id)
	var versions_dir: String = module_dir.path_join(ModuleRegistry.VERSIONS_DIR)
	if not _ensure_directory(versions_dir):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _error(NotLightL10n.text("runtime.modules.module_package_service.d802cd80ba"))
	var final_dir: String = versions_dir.path_join(version_key)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(final_dir)):
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _error(NotLightL10n.text("runtime.modules.module_package_service.bb274a62d0"))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(version_stage), ProjectSettings.globalize_path(final_dir)) != OK:
		NotLightPortablePackageFormat.cleanup_directory(staging)
		return _error(NotLightL10n.text("runtime.modules.module_package_service.5352e1a631"))
	NotLightPortablePackageFormat.cleanup_directory(staging)
	if state.is_empty():
		state = {
			"active_version_key": "",
			"pending_version_key": "",
			"pending_remove": false,
			"last_error": "",
		}
	state["pending_version_key"] = version_key
	state["pending_remove"] = false
	state["last_error"] = ""
	if not registry.write_install_state(module_id, state):
		# The candidate is not referenced by durable registry state yet, so it is
		# safe to remove. Never leave an install that the registry cannot account for.
		NotLightPortablePackageFormat.cleanup_directory(final_dir)
		return _error(registry.get_last_error())
	registry.refresh_catalog()
	module_installed.emit(module_id, version, true)
	return {"ok": true, "module_id": module_id, "version": version, "restart_required": true, "duplicate": false}


func install_external_files(paths: PackedStringArray) -> Dictionary:
	var installed: int = 0
	var errors: Array[String] = []
	for path: String in paths:
		if path.get_extension().to_lower() != NotLightPortablePackageFormat.MODULE_EXTENSION:
			continue
		var result: Dictionary = install_module(path)
		if bool(result.get("ok", false)):
			installed += 1
		else:
			errors.append(str(result.get("error", NotLightL10n.text("runtime.modules.module_package_service.14ff4743ee"))))
	return {"ok": errors.is_empty(), "installed": installed, "errors": errors}


func _expected_payload_keys(manifest: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var payload_key: String = str(manifest.get("payload_key", "payload.pck"))
	if not payload_key.is_empty():
		result[payload_key] = true
	var icon_key: String = str(manifest.get("icon_key", ""))
	if not icon_key.is_empty():
		result[icon_key] = true
	var preview_key: String = str(manifest.get("preview_key", ""))
	if not preview_key.is_empty():
		result[preview_key] = true
	var license_key: String = str(manifest.get("license_key", ""))
	if not license_key.is_empty():
		result[license_key] = true
	var notices_key: String = str(manifest.get("notices_key", ""))
	if not notices_key.is_empty():
		result[notices_key] = true
	var localizations: Dictionary = manifest.get("localizations", {}) as Dictionary
	for raw_locale: Variant in localizations.keys():
		result[str(localizations[raw_locale])] = true
	return result


func _populate_version_stage(
	version_stage: String,
	manifest: Dictionary,
	materialized_files: Dictionary,
	payload_index: Dictionary,
	package_path: String
) -> bool:
	var payload_key: String = str(manifest.get("payload_key", "payload.pck"))
	var payload_destination: String = version_stage.path_join("payload.pck")
	if not _copy_payload(materialized_files, payload_key, payload_destination):
		return false
	if not _verify_staged_payload(payload_destination, payload_index, payload_key):
		return false
	var localizations: Dictionary = manifest.get("localizations", {}) as Dictionary
	if not _ensure_directory(version_stage.path_join("localization")):
		return false
	for raw_locale: Variant in localizations.keys():
		var locale: String = str(raw_locale)
		var localization_key: String = str(localizations[raw_locale])
		var localization_destination: String = version_stage.path_join("localization/%s.json" % locale)
		if not _copy_payload(materialized_files, localization_key, localization_destination):
			return false
		if not _verify_staged_payload(localization_destination, payload_index, localization_key):
			return false
		if not _validate_localization_file(localization_destination, str(manifest.get("module_id", "")), locale, locale == "ru"):
			return false
	var icon_key: String = str(manifest.get("icon_key", ""))
	if not icon_key.is_empty():
		var extension: String = icon_key.get_extension().to_lower()
		if extension != "svg" and extension != "png" and extension != "webp":
			return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.0622fbc58e"))
		var icon_destination: String = version_stage.path_join("icon.%s" % extension)
		if not _copy_payload(materialized_files, icon_key, icon_destination):
			return false
		if not _verify_staged_payload(icon_destination, payload_index, icon_key):
			return false
	var preview_key: String = str(manifest.get("preview_key", ""))
	if not preview_key.is_empty():
		var preview_descriptor: Dictionary = payload_index.get(preview_key, {}) as Dictionary
		if int(preview_descriptor.get("byte_size", -1)) < 0 or int(preview_descriptor.get("byte_size", 0)) > MAX_PREVIEW_BYTES:
			return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.6f25fbe8be"))
		var preview_extension: String = preview_key.get_extension().to_lower()
		var preview_destination: String = version_stage.path_join("preview.%s" % preview_extension)
		if not _copy_payload(materialized_files, preview_key, preview_destination):
			return false
		if not _verify_staged_payload(preview_destination, payload_index, preview_key):
			return false
	var license_key: String = str(manifest.get("license_key", ""))
	if not license_key.is_empty():
		var license_destination: String = version_stage.path_join("LICENSE")
		if not _copy_payload(materialized_files, license_key, license_destination):
			return false
		if not _verify_staged_payload(license_destination, payload_index, license_key):
			return false
	var notices_key: String = str(manifest.get("notices_key", ""))
	if not notices_key.is_empty():
		var notices_destination: String = version_stage.path_join("THIRD_PARTY_NOTICES.md")
		if not _copy_payload(materialized_files, notices_key, notices_destination):
			return false
		if not _verify_staged_payload(notices_destination, payload_index, notices_key):
			return false
	var payload_descriptor: Dictionary = payload_index.get(payload_key, {}) as Dictionary
	var install: Dictionary = {
		"schema": "notlight.module_install",
		"schema_version": 1,
		"installed_at_unix": int(Time.get_unix_time_from_system()),
		"source_package_sha256": FileAccess.get_sha256(package_path).to_lower(),
		"payload_sha256": str(payload_descriptor.get("sha256", "")).to_lower(),
		"payload_byte_size": int(payload_descriptor.get("byte_size", 0)),
		"package_payloads": _payload_digest_snapshot(payload_index),
	}
	var manifest_path: String = version_stage.path_join(ModuleRegistry.VERSION_MANIFEST_FILE)
	if not _write_json(manifest_path, manifest):
		return false
	install["module_manifest_sha256"] = FileAccess.get_sha256(manifest_path).to_lower()
	if not _write_json(version_stage.path_join(ModuleRegistry.INSTALL_METADATA_FILE), install):
		return false
	return true


func _verify_staged_payload(path: String, payload_index: Dictionary, key: String) -> bool:
	var descriptor_value: Variant = payload_index.get(key, {})
	if descriptor_value is not Dictionary:
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.669b12d508") % key)
	var descriptor: Dictionary = descriptor_value as Dictionary
	var expected_size: int = int(descriptor.get("byte_size", -1))
	var expected_hash: String = str(descriptor.get("sha256", "")).strip_edges().to_lower()
	if expected_size < 0 or expected_hash.length() != 64:
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.5d13645303") % key)
	if _file_size(path) != expected_size or FileAccess.get_sha256(path).to_lower() != expected_hash:
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.9c9d7b85d8") % key)
	return true


func _validate_localization_file(path: String, module_id: String, locale: String, require_nonempty: bool) -> bool:
	var result: Dictionary = ModuleLocalizationBundle.read_file(path, module_id, locale, require_nonempty)
	if not bool(result.get("ok", false)):
		return _fail_bool(str(result.get("error", NotLightL10n.text("runtime.modules.module_package_service.90ef86f635"))))
	return true


func _payload_digest_snapshot(payload_index: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = payload_index.keys()
	keys.sort()
	for raw_key: Variant in keys:
		var descriptor_value: Variant = payload_index.get(raw_key, {})
		if descriptor_value is not Dictionary:
			continue
		var descriptor: Dictionary = descriptor_value as Dictionary
		result[str(raw_key)] = {
			"sha256": str(descriptor.get("sha256", "")).to_lower(),
			"byte_size": int(descriptor.get("byte_size", 0)),
		}
	return result


func _copy_payload(files: Dictionary, key: String, destination: String) -> bool:
	var source: String = str(files.get(key, ""))
	if source.is_empty() or not FileAccess.file_exists(source):
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.eaf1d2bfa8") % key)
	if not _ensure_directory(destination.get_base_dir()):
		return false
	var input: FileAccess = FileAccess.open(source, FileAccess.READ)
	var output: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if input == null or output == null:
		if input != null:
			input.close()
		if output != null:
			output.close()
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.5ac4fa6667"))
	while input.get_position() < input.get_length():
		var remaining: int = int(input.get_length() - input.get_position())
		var chunk: PackedByteArray = input.get_buffer(mini(NotLightPortablePackageFormat.COPY_CHUNK_BYTES, remaining))
		if chunk.is_empty() or not output.store_buffer(chunk):
			input.close()
			output.close()
			return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.fc04f851e9"))
	input.close()
	output.flush()
	var error: Error = output.get_error()
	output.close()
	if error != OK:
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.8ead5a2618"))
	# Materialization was already checksum-verified. Verify the second durable copy
	# as well so a partial/corrupted filesystem write is rejected before commit.
	if FileAccess.get_sha256(source).to_lower() != FileAccess.get_sha256(destination).to_lower():
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.d80949442c"))
	return true


func _highest_known_version(module_id: String) -> String:
	var result: String = ""
	for version_key: String in registry.installed_version_keys(module_id):
		var manifest: Dictionary = registry.read_version_manifest(module_id, version_key)
		var version: String = str(manifest.get("version", ""))
		if ModuleManifest.is_valid_version(version) and (result.is_empty() or ModuleManifest.compare_versions(version, result) > 0):
			result = version
	return result


func _new_staging_directory() -> String:
	for attempt: int in range(64):
		var token: String = "%d_%08x_%02d" % [Time.get_ticks_usec(), _rng.randi(), attempt]
		var path: String = _staging_root.path_join("install_%s" % token)
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			_ensure_directory(path)
			return path
	return _staging_root.path_join("install_fallback_%d" % Time.get_ticks_usec())


func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.f42b84669b"))
	var ok: bool = file.store_string(JSON.stringify(data, "  ", false, true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if not ok or error != OK:
		return _fail_bool(NotLightL10n.text("runtime.modules.module_package_service.36f5437ddf"))
	return true


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _ensure_directory(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	return DirAccess.make_dir_recursive_absolute(absolute) == OK


func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size: int = int(file.get_length())
	file.close()
	return size


func _error(message: String) -> Dictionary:
	_last_error = message
	module_install_failed.emit(message)
	return {"ok": false, "error": message}


func _fail_bool(message: String) -> bool:
	_last_error = message
	return false
