# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetId
extends RefCounted


static func make_uuid() -> String:
	var crypto: Crypto = Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(16)
	if bytes.size() != 16:
		return _fallback_id()
	bytes[6] = (int(bytes[6]) & 0x0f) | 0x40
	bytes[8] = (int(bytes[8]) & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]


static func make_temporary_id(prefix: String) -> String:
	var safe_prefix: String = prefix.strip_edges().to_lower()
	if safe_prefix.is_empty():
		safe_prefix = "tmp"
	return "%s_%s" % [safe_prefix, make_uuid().replace("-", "")]


static func _fallback_id() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return "%08x-%04x-4%03x-%04x-%08x%04x" % [
		int(Time.get_ticks_usec()) & 0xffffffff,
		rng.randi() & 0xffff,
		rng.randi() & 0x0fff,
		0x8000 | (rng.randi() & 0x3fff),
		rng.randi(),
		rng.randi() & 0xffff,
	]
