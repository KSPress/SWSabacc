extends SceneTree

var failed := 0
var passed := 0


func check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: ", description)


func _init() -> void:
	var valid := {"version_code": 3, "version_name": "0.1.2", "size": 170000000,
		"apk_url": ReleaseInfo.DOWNLOAD_PREFIX + "v0.1.2/swu_kyber.apk", "sha256": "a".repeat(64)}
	check(not ReleaseInfo.parse(valid).is_empty(), "accept newer release")
	check(ReleaseInfo.parse(valid)["version_code"] > ReleaseInfo.VERSION_CODE, "numeric upgrade comparison")
	var old := valid.duplicate()
	old["version_code"] = 1
	check(ReleaseInfo.parse(old)["version_code"] <= ReleaseInfo.VERSION_CODE, "old release cannot upgrade")
	for key in valid:
		var missing := valid.duplicate()
		missing.erase(key)
		check(ReleaseInfo.parse(missing).is_empty(), "reject missing " + key)
	for url in ["http://github.com/KSPress/SWU-Kyber/releases/download/v1/swu_kyber.apk",
		"https://example.com/swu_kyber.apk", ReleaseInfo.DOWNLOAD_PREFIX + "../swu_kyber.apk",
		ReleaseInfo.DOWNLOAD_PREFIX + "v1/%2e%2e/swu_kyber.apk", ReleaseInfo.DOWNLOAD_PREFIX + "v1/other.apk"]:
		var bad := valid.duplicate()
		bad["apk_url"] = url
		check(ReleaseInfo.parse(bad).is_empty(), "reject untrusted APK URL")
	for pair in [["size", 0], ["size", ReleaseInfo.MAX_APK_BYTES + 1], ["size", "large"],
		["version_code", 2.5], ["version_code", -1], ["sha256", "oops"], ["sha256", "z".repeat(64)]]:
		var bad := valid.duplicate()
		bad[pair[0]] = pair[1]
		check(ReleaseInfo.parse(bad).is_empty(), "reject invalid " + pair[0])
	for bad in [null, [], "manifest", 1]:
		check(ReleaseInfo.parse(bad).is_empty(), "reject non-object manifest")
	print("Update manifest: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
