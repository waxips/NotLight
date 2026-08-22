# SPDX-License-Identifier: GPL-3.0-or-later
class_name WindowsPowerStatusProvider
extends PowerStatusProvider

const POWERSHELL_COMMAND: String = "[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; $b=@(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1); if($b.Count -eq 0){'{\"present\":false}'}else{$x=$b[0]; [pscustomobject]@{present=$true;percent=[int]$x.EstimatedChargeRemaining;charging=(@(6,7,8,9)-contains [int]$x.BatteryStatus)}|ConvertTo-Json -Compress}"


func is_supported() -> bool:
	return OS.has_feature("windows")


func executable_path() -> String:
	return "powershell.exe"


func arguments() -> PackedStringArray:
	return PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-Command",
		POWERSHELL_COMMAND,
	])


func parse_output(stdout_text: String, stderr_text: String, exit_code: int) -> Dictionary:
	if exit_code != 0:
		return {"supported": true, "present": false, "percent": -1, "charging": false, "error": stderr_text.strip_edges().left(512)}
	var parsed: Variant = JSON.parse_string(stdout_text.strip_edges())
	if parsed is not Dictionary:
		return {"supported": true, "present": false, "percent": -1, "charging": false, "error": NotLightL10n.text("runtime.platform.power.invalid_json")}
	var source: Dictionary = parsed as Dictionary
	if not bool(source.get("present", false)):
		return {"supported": true, "present": false, "percent": -1, "charging": false}
	return {
		"supported": true,
		"present": true,
		"percent": clampi(int(source.get("percent", -1)), 0, 100),
		"charging": bool(source.get("charging", false)),
	}
