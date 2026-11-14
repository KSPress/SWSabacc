extends Node
## Exercise the production updater's completion/failure paths without network
## access or opening an installer. Run with an isolated APPDATA for user://.

var passed := 0
var failed := 0


func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: ", label)


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(Updater.DIR)
	var bytes := "APK test fixture".to_utf8_buffer()
	var manifest := {"version_code": ReleaseInfo.VERSION_CODE + 1, "version_name": "0.3.0", "size": bytes.size(),
		"apk_url": ReleaseInfo.DOWNLOAD_PREFIX + "v0.3.0/swu_sabacc.apk", "sha256": "APK test fixture".sha256_text()}
	Updater.busy = true
	Updater._completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check(not Updater.busy and not Updater.update_ready, "offline failure is nonblocking")
	Updater.busy = true
	Updater._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{}".to_utf8_buffer())
	check(not Updater.busy and not Updater.update_ready, "malformed manifest cannot install")
	var old := manifest.duplicate()
	old["version_code"] = ReleaseInfo.VERSION_CODE
	Updater._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(old).to_utf8_buffer())
	check(not Updater.busy and not Updater.update_ready, "same version never downloads")
	Updater.release = ReleaseInfo.parse(manifest)
	_write(Updater.PART, "truncated".to_utf8_buffer())
	Updater._downloading = true
	Updater._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	check(not Updater.update_ready and not FileAccess.file_exists(Updater.PART), "truncated APK is rejected and removed")
	_write(Updater.PART, bytes)
	Updater._downloading = true
	Updater._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray())
	check(Updater.update_ready and not Updater.busy, "verified download becomes installable")
	check(Updater._valid_apk(Updater.APK), "verified file promoted to cache")
	check(not FileAccess.file_exists(Updater.PART), "partial file removed after promotion")
	_write(Updater.APK, "APK test fixturE".to_utf8_buffer())
	check(not Updater._valid_apk(Updater.APK), "same-length tampered APK is rejected")
	Updater.install()
	check(not Updater.update_ready, "tampered cache cannot open installer")
	DirAccess.remove_absolute(Updater.APK)
	print("Updater flow: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
