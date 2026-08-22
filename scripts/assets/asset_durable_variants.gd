# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetDurableVariants
extends RefCounted

# This registry is the single source of truth for asset metadata namespaces that
# own durable blob variants. Keep cache-only derivatives out of this list.
const SUPPORTED_NAMESPACES: PackedStringArray = ["video", "audio", "pdf"]


static func namespace_for_kind(kind: int) -> String:
	match kind:
		AssetKinds.VIDEO:
			return "video"
		AssetKinds.AUDIO:
			return "audio"
		AssetKinds.PDF:
			return "pdf"
		_:
			return ""


static func namespace_for_asset(asset: Dictionary) -> String:
	return namespace_for_kind(int(asset.get("kind", AssetKinds.OTHER)))


static func state_from_asset(asset: Dictionary) -> Dictionary:
	var media_namespace: String = namespace_for_asset(asset)
	if media_namespace.is_empty():
		return {}
	var metadata_value: Variant = asset.get("metadata", {})
	if metadata_value is not Dictionary:
		return {}
	var state_value: Variant = (metadata_value as Dictionary).get(media_namespace, {})
	return state_value as Dictionary if state_value is Dictionary else {}


static func blob_relpaths(asset: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var primary: String = str(asset.get("blob_relpath", "")).strip_edges()
	if not primary.is_empty():
		result.append(primary)
	var metadata_value: Variant = asset.get("metadata", {})
	if metadata_value is not Dictionary:
		return result
	var metadata: Dictionary = metadata_value as Dictionary
	for media_namespace: String in SUPPORTED_NAMESPACES:
		var state_value: Variant = metadata.get(media_namespace, {})
		if state_value is not Dictionary:
			continue
		var variants_value: Variant = (state_value as Dictionary).get("variants", {})
		if variants_value is not Dictionary:
			continue
		for raw_variant: Variant in (variants_value as Dictionary).values():
			if raw_variant is not Dictionary:
				continue
			var relpath: String = str((raw_variant as Dictionary).get("blob_relpath", "")).strip_edges()
			if not relpath.is_empty() and not result.has(relpath):
				result.append(relpath)
	return result
