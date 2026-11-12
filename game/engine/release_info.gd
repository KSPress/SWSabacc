class_name ReleaseInfo
extends RefCounted
## Validate the release manifest before trusting an APK URL or allocating disk.

const VERSION_CODE := 14
const VERSION_NAME := "0.7.4"
const DOWNLOAD_PREFIX := "https://github.com/KSPress/SWSabacc/releases/download/"
const MAX_APK_BYTES := 512 * 1024 * 1024


static func parse(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var d: Dictionary = value
	if typeof(d.get("version_code")) not in [TYPE_INT, TYPE_FLOAT] or typeof(d.get("size")) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	if float(d["version_code"]) != int(d["version_code"]) or int(d["version_code"]) <= 0:
		return {}
	if float(d["size"]) != int(d["size"]) or int(d["size"]) <= 0 or int(d["size"]) > MAX_APK_BYTES:
		return {}
	for key in ["version_name", "apk_url", "sha256"]:
		if not d.get(key) is String or d[key].is_empty():
			return {}
	var url: String = d["apk_url"]
	if not url.begins_with(DOWNLOAD_PREFIX) or not url.ends_with("/swu_sabacc.apk"):
		return {}
	var tag := url.trim_prefix(DOWNLOAD_PREFIX).trim_suffix("/swu_sabacc.apk")
	if tag.is_empty() or "/" in tag or "?" in tag or "#" in tag or "%" in tag or ".." in tag:
		return {}
	var digest: String = d["sha256"].to_lower()
	if digest.length() != 64:
		return {}
	for ch in digest:
		if not ch in "0123456789abcdef":
			return {}
	return {"version_code": int(d["version_code"]), "version_name": d["version_name"],
		"size": int(d["size"]), "apk_url": url, "sha256": digest}
