extends Node
## Offline-first APK updates. Network failures never block boot or a match.
## Android always owns the final installation confirmation and signature check.

signal status_changed

const MANIFEST_URL := "https://github.com/KSPress/SWSabacc/releases/latest/download/sabacc-update.json"
const DIR := "user://updates"
const PART := DIR + "/download.part"
const APK := DIR + "/swu_sabacc.apk"

var status := "Updates are available on Android."
var busy := false
var update_ready := false
var release: Dictionary = {}
var _http: HTTPRequest
var _downloading := false
var _prompted := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.body_size_limit = 16384
	add_child(_http)
	_http.request_completed.connect(_completed)
	Router.screen_changed.connect(_screen_changed)
	if OS.has_feature("android"):
		_set_status("Updates checked automatically when online.")
		if Sabacc.settings.get("auto_update", true) and not OS.has_feature("editor"):
			await get_tree().create_timer(2.0).timeout
			check()


func _set_status(message: String) -> void:
	status = message
	status_changed.emit()


func check() -> void:
	if busy:
		return
	busy = true
	update_ready = false
	_downloading = false
	_http.download_file = ""
	_http.timeout = 15.0
	_http.body_size_limit = 16384
	_set_status("Checking for updates…")
	if _http.request(MANIFEST_URL, ["User-Agent: SWSabacc/" + ReleaseInfo.VERSION_NAME]) != OK:
		_fail("Could not check for updates. You can keep playing offline.")


func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Update server unavailable. You can keep playing offline.")
		return
	if _downloading:
		if not _valid_apk(PART):
			_fail("Update verification failed. Your installed game is unchanged.")
			return
		if DirAccess.rename_absolute(PART, APK) != OK:
			_fail("Could not save the update. Your installed game is unchanged.")
			return
		busy = false
		update_ready = true
		_prompted = false
		_set_status("Version %s is ready to install." % release["version_name"])
		_offer_install()
		return
	release = ReleaseInfo.parse(JSON.parse_string(body.get_string_from_utf8()))
	if release.is_empty():
		_fail("Invalid update information. Your installed game is unchanged.")
		return
	if release["version_code"] <= ReleaseInfo.VERSION_CODE:
		busy = false
		_set_status("You have the latest version (%s)." % ReleaseInfo.VERSION_NAME)
		return
	if DirAccess.make_dir_recursive_absolute(DIR) != OK:
		_fail("Not enough storage for the update.")
		return
	if _valid_apk(APK):
		busy = false
		update_ready = true
		_prompted = false
		_set_status("Version %s is ready to install." % release["version_name"])
		_offer_install()
		return
	_downloading = true
	_http.download_file = PART
	_http.timeout = 600.0
	_http.body_size_limit = release["size"]
	_set_status("Downloading version %s (%d MB). You can keep playing." % [release["version_name"], ceili(release["size"] / 1000000.0)])
	if _http.request(release["apk_url"]) != OK:
		_fail("Could not download the update. You can keep playing offline.")


func _valid_apk(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size := f.get_length()
	f.close()
	return size == release["size"] and FileAccess.get_sha256(path) == release["sha256"]


func _fail(message: String) -> void:
	busy = false
	update_ready = false
	_downloading = false
	if FileAccess.file_exists(PART):
		DirAccess.remove_absolute(PART)
	_set_status(message)


func _screen_changed(_path: String) -> void:
	_offer_install()


func _offer_install() -> void:
	var scene := get_tree().current_scene
	if not update_ready or _prompted or scene == null or not scene.scene_file_path.ends_with("main_menu.tscn"):
		return
	_prompted = true
	var dialog := ConfirmationDialog.new()
	dialog.title = "Game update ready"
	dialog.dialog_text = "Version %s has downloaded. Install now?\nYour saved progress is kept. Android will ask you to confirm installation." % release["version_name"]
	dialog.ok_button_text = "Install update"
	dialog.cancel_button_text = "Later"
	dialog.confirmed.connect(install)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	scene.add_child(dialog)
	dialog.popup_centered(Vector2i(480, 220))


func install() -> void:
	if not update_ready or not _valid_apk(APK):
		_fail("Update file unavailable. Check for updates again.")
		return
	if OS.shell_open(ProjectSettings.globalize_path(APK)) != OK:
		_set_status("Could not open the installer. Download from GitHub Releases.")
