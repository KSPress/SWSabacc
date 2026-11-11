extends ScreenBase
## Settings (spec 8.6): performance mode, animation speed, audio, orientation,
## decorative Aurebesh, save reset.

var _box: VBoxContainer
var _gm: HSlider
var _gm_status: Label


func _refresh_gm() -> void:
	_gm.set_value_no_signal(1 if Cosmetics.state()["gm"] else 0)
	_gm_status.text = "GM · Everything unlocked" if Cosmetics.state()["gm"] else "Normal · Earn your collection"
	_gm_status.modulate = Sabacc.C_EMPIRE if Cosmetics.state()["gm"] else Sabacc.C_TEXT


func build() -> void:
	set_header("Settings")
	var scroll := TouchScroll.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	_box.add_child(UIKit.label("Appearance", 24, Appearance.color_at()))
	var profile := SabaccButton.make("Profile, card backs & backgrounds", SabaccButton.Style.PRIMARY)
	profile.pressed.connect(func(): Router.go("customization"))
	_box.add_child(profile)
	var gm_box := VBoxContainer.new()
	_gm_status = UIKit.label("", 25, Sabacc.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	gm_box.add_child(_gm_status)
	var gm := HSlider.new()
	gm.name = "GMSlider"
	gm.min_value = 0
	gm.max_value = 1
	gm.step = 1
	gm.scrollable = false
	gm.custom_minimum_size.y = 76
	var thumb := Image.new()
	thumb.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="56" height="56"><rect x="3" y="3" width="50" height="50" rx="12" fill="#a82322" stroke="#ff7266" stroke-width="3"/><path d="M23 18v20M32 18v20" stroke="#fff0df" stroke-width="3"/></svg>')
	var thumb_texture := ImageTexture.create_from_image(thumb)
	gm.add_theme_icon_override("grabber", thumb_texture)
	gm.add_theme_icon_override("grabber_highlight", thumb_texture)
	gm.tooltip_text = "Left: normal progression. Right: GM, everything unlocked."
	gm.add_theme_stylebox_override("slider", UIKit.chamfer(Sabacc.C_PANEL, Sabacc.C_EMPIRE, 10, 2))
	gm.add_theme_stylebox_override("grabber_area", UIKit.chamfer(Color(Sabacc.C_EMPIRE, 0.35), Sabacc.C_EMPIRE, 10, 2))
	gm.add_theme_stylebox_override("grabber_area_highlight", UIKit.chamfer(Color(Sabacc.C_EMPIRE, 0.55), Sabacc.C_EMPIRE, 10, 2))
	_gm = gm
	Cosmetics.changed.connect(_refresh_gm)
	gm.value_changed.connect(func(value): Cosmetics.set_gm(value >= 0.5))
	gm_box.add_child(gm)
	gm_box.add_child(UIKit.label("NORMAL PROGRESSION                         GM UNLOCK ALL", 16, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_box.add_child(gm_box)
	_refresh_gm()
	var theme_help := UIKit.label("Win games to earn emblems, card backs and scene backgrounds. GM grants access to everything while preserving your earned collection.", 17, Sabacc.C_DIM)
	theme_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(theme_help)
	_toggle("Performance mode (static backgrounds, fewer particles)", "perf_mode")
	_toggle("Decorative Aurebesh text", "show_aurebesh")
	_slider("Animation speed", "anim_speed", 0.5, 2.5, 0.1)
	_slider("Sound effects", "sfx_volume", 0.0, 1.0, 0.05)
	_toggle("Background music", "music_enabled")
	_slider("Music", "music_volume", 0.0, 1.0, 0.05)
	var qm := OptionButton.new()
	var modes := ["one_lane", "traditional", "ground", "space"]
	for k in modes:
		qm.add_item("Quick Play: %s" % Sabacc.QUICK_MODES[k][0])
	qm.selected = maxi(0, modes.find(Sabacc.settings.get("quick_mode", "traditional")))
	qm.custom_minimum_size.y = 52
	qm.clip_text = true
	qm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	qm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qm.item_selected.connect(func(i): Sabacc.set_setting("quick_mode", modes[i]))
	_box.add_child(qm)
	var qdesc := UIKit.label(Sabacc.QUICK_MODES[modes[qm.selected]][1], 15, Sabacc.C_DIM)
	qdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(qdesc)
	qm.item_selected.connect(func(i): qdesc.text = Sabacc.QUICK_MODES[modes[i]][1])
	var orient := OptionButton.new()
	for o in ["auto", "portrait", "landscape"]:
		orient.add_item("Orientation: " + o.capitalize())
	orient.selected = ["auto", "portrait", "landscape"].find(Sabacc.settings.get("orientation", "auto"))
	orient.custom_minimum_size.y = 52
	orient.clip_text = true
	orient.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	orient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orient.item_selected.connect(func(i): Sabacc.set_setting("orientation", ["auto", "portrait", "landscape"][i]))
	_box.add_child(orient)
	if OS.has_feature("android"):
		_toggle("Download game updates automatically", "auto_update")
		var update_status := UIKit.label(Updater.status, 17, Sabacc.C_DIM)
		update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(update_status)
		var update_button := SabaccButton.make("Check for updates", SabaccButton.Style.GHOST)
		_box.add_child(update_button)
		var refresh := func():
			update_status.text = Updater.status
			update_button.text = "Install update" if Updater.update_ready else "Check for updates"
			update_button.disabled = Updater.busy
		Updater.status_changed.connect(refresh)
		update_button.pressed.connect(func():
			if Updater.update_ready:
				Updater.install()
			else:
				Updater.check())
		refresh.call()
	var stats: Dictionary = Save.data.get("stats", {})
	_box.add_child(UIKit.label("Matches %d · Wins %d · Vault %d cards" % [int(stats.get("matches", 0)), int(stats.get("wins", 0)), Save.data.get("vault", []).size()], 18, Sabacc.C_DIM))
	var reset := SabaccButton.make("Reset all progress", SabaccButton.Style.EMPIRE)
	reset.pressed.connect(func():
		if reset.text != "Tap again to confirm":
			reset.text = "Tap again to confirm"
			return
		Save.data = Save.default_data()
		Save.write()
		Router.go("menu"))
	_box.add_child(reset)
	var legal := UIKit.label("%s %s — an unofficial, non-commercial fan project. Star Wars, Star Wars: Unlimited, card names, text and art are property of Lucasfilm Ltd. and Fantasy Flight Games. No affiliation or endorsement. Original engine; no Hearthstone/Blizzard code or assets." % [Sabacc.GAME_TITLE, Sabacc.VERSION], 15, Sabacc.C_DIM)
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(legal)


func _toggle(label: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = Sabacc.settings.get(key, false)
	c.add_theme_font_size_override("font_size", 20)
	c.custom_minimum_size.y = 52
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.toggled.connect(func(on): Sabacc.set_setting(key, on))
	_box.add_child(c)


func _slider(label: String, key: String, mn: float, mx: float, step: float) -> void:
	var h := HBoxContainer.new()
	var l := UIKit.label(label, 20)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Sabacc.settings.get(key, 1.0))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 44
	s.value_changed.connect(func(v): Sabacc.set_setting(key, v))
	h.add_child(s)
	_box.add_child(h)


func relayout(_p: bool, r: Rect2) -> void:
	var scroll: ScrollContainer = body.get_node("Scroll")
	var w := minf(r.size.x, 820.0)
	scroll.position = Vector2((r.size.x - w) / 2.0, 0)
	scroll.size = Vector2(w, r.size.y)
	_box.custom_minimum_size.x = w - 16
