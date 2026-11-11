extends ScreenBase
## Title screen. Floating showcase cards can be grabbed and flung around.

var _title_box: VBoxContainer
var _buttons: GridContainer
var _floaters: Array = []
var _foot: Label
var _t := 0.0
var _profile_button: SabaccButton
var _profile_badge: ProfileBadge


func build() -> void:
	_profile_button = SabaccButton.make("Profile", SabaccButton.Style.GHOST)
	_profile_button.custom_minimum_size = Vector2(150, 54)
	_profile_button.pressed.connect(func(): Router.go("customization"))
	body.add_child(_profile_button)
	_profile_badge = ProfileBadge.new()
	_profile_badge.size = Vector2(76, 76)
	body.add_child(_profile_badge)
	bg.backdrop = Art.ui_texture("swu_background")
	bg.backdrop_alpha = 0.45
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 0)
	body.add_child(_title_box)
	var banner := TextureRect.new()
	banner.texture = Art.ui_texture("sabacc_title")
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.custom_minimum_size = Vector2(0, 150)
	banner.name = "Logo"
	banner.pivot_offset = Vector2(0, 75)
	_title_box.add_child(banner)
	_title_box.add_child(UIKit.label(Sabacc.GAME_SUBTITLE, 18, Sabacc.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_buttons = GridContainer.new()
	_buttons.add_theme_constant_override("h_separation", 16)
	_buttons.add_theme_constant_override("v_separation", 14)
	body.add_child(_buttons)
	var items := [
		["Campaigns", SabaccButton.Style.PRIMARY, "boss", func(): Router.go("hub", {"section": "campaigns"}), true],
		["Battles", SabaccButton.Style.REBEL, "fight", func(): Router.go("hub", {"section": "battles"}), false],
		["Deck Builder", SabaccButton.Style.GOLD, "deck", func(): Router.go("decks"), false],
		["Collection Vault", SabaccButton.Style.GOLD, "collection", func(): Router.go("collection"), false],
		["Card Packs (%d)" % Progression.packs().size(), SabaccButton.Style.GOLD, "star", func(): Router.go("packs"), false],
		["Customization", SabaccButton.Style.PRIMARY, "gear", func(): Router.go("customization"), false],
		["Settings", SabaccButton.Style.GHOST, "gear", func(): Router.go("settings"), false],
		["Exit", SabaccButton.Style.EMPIRE, "back", exit_application, false],
	]
	var i := 0
	for it in items:
		var b := SabaccButton.make(it[0], it[1], it[2], it[4])
		b.custom_minimum_size = Vector2(320, 72)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(it[3])
		_buttons.add_child(b)
		UIKit.pop_in(b, 0.15 + i * 0.07)
		i += 1
	_foot = UIKit.label("v%s · Unofficial, non-commercial fan project. Star Wars and SWU are © Lucasfilm Ltd. / Fantasy Flight Games." % Sabacc.VERSION, 13, Color(Sabacc.C_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_foot)
	_spawn_floaters()
	# The full-width title container covers this corner in landscape layouts.
	# Keep the profile navigation above it so real pointer input reaches it.
	body.move_child(_profile_button, -1)


func exit_application() -> void:
	if OS.has_feature("web"):
		var modal := ModalPanel.open(self)
		modal.text("Close this browser tab to exit the game.")
		var back := SabaccButton.make("Back to menu")
		back.pressed.connect(modal.close)
		modal.add_action(back)
	else:
		get_tree().quit()


func _spawn_floaters() -> void:
	# A fresh random trio every time the menu opens: units and leaders with art.
	var pool: Array = []
	for id in CardDB.lib.cards:
		var c: Dictionary = CardDB.lib.cards[id]
		if c.get("custom", false) or c.get("type", "") != "unit":
			continue
		if c.get("type") == "unit" and int(c.get("cost", 0)) < 2:
			continue
		pool.append(id)
	pool.shuffle()
	var avail: Array = []
	for id in pool:
		if Art.has_art(CardDB.card(id).get("art", id)):
			avail.append(id)
		if avail.size() >= 3:
			break
	for i in mini(3, avail.size()):
		var cv := CardView.create(avail[i])
		cv.hover_lift = false
		cv.home_scale = Vector2(0.42, 0.42)
		cv.scale = cv.home_scale
		cv.drag_released.connect(func(c, _p): c.spring_home())
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		body.add_child(cv)
		body.move_child(cv, 0)
		_floaters.append(cv)


func _process(dt: float) -> void:
	_t += dt
	for i in _floaters.size():
		var cv: CardView = _floaters[i]
		if cv.is_dragging() or cv.top_level:
			continue
		cv.rotation = cv.home_rot + sin(_t * 0.6 + i) * 0.05
		cv.position = cv.position.lerp(cv.home_pos + Vector2(0, sin(_t * 0.9 + i * 2.0) * 10.0), 0.08)
	var t := _title_box.get_node_or_null("Title")
	if t:
		t.modulate = Color(1, 1, 1).lerp(Color(0.75, 0.95, 1.1), 0.5 + 0.5 * sin(_t * 1.5))


func relayout(p: bool, r: Rect2) -> void:
	_profile_button.position = Vector2(r.size.x - 150, 0)
	_profile_badge.position = Vector2(4, 0)
	_buttons.columns = 1 if p else 2
	_title_box.get_node("Logo").custom_minimum_size.y = 132 if p else 92
	_title_box.position = Vector2(0, maxf(72, r.size.y * 0.04) if p else 0.0)
	_title_box.size = Vector2(r.size.x, 0)
	await get_tree().process_frame
	var bs := _buttons.get_combined_minimum_size()
	_buttons.size = bs
	# Reserve space for every button and the footer before placing the showcase.
	# Seven portrait buttons used to extend below the window on a 16:9 phone.
	var button_top := minf(r.size.y * (0.52 if p else 0.5), r.size.y - 70.0 - bs.y)
	_buttons.position = Vector2((r.size.x - bs.x) / 2.0, button_top)
	_foot.position = Vector2(0, r.size.y - 50)
	_foot.size = Vector2(r.size.x, 40)
	# Landscape: cards live in the side gutters left/right of the button grid.
	var gutter := (r.size.x - bs.x) / 2.0 - 20.0
	var showcase_top := _title_box.position.y + _title_box.get_combined_minimum_size().y + 22.0
	var showcase_height := maxf(0.0, button_top - showcase_top - 22.0)
	var fsc := minf(r.size.y * 0.16, showcase_height * 0.8) / CardView.PORTRAIT.y if p else clampf(minf(r.size.y * 0.34 / CardView.PORTRAIT.y, gutter * 0.75 / CardView.LANDSCAPE.x), 0.25, 1.0)
	for i in _floaters.size():
		var cv: CardView = _floaters[i]
		cv.home_scale = Vector2(fsc, fsc)
		cv.scale = cv.home_scale
		var hp: Vector2
		if p:
			var cw := cv.size.x * fsc
			hp = Vector2(r.size.x * (0.5 + (i - 1) * 0.31) - cw / 2.0, showcase_top)
			# CardView scales about its centre, so compensate its pivot to place
			# the visible top edge inside the showcase instead of over a button.
			hp -= cv.pivot_offset * (1.0 - fsc)
		else:
			var left := i < 2
			var x := gutter * 0.15 if left else r.size.x - gutter * 0.25 - cv.size.x * fsc
			hp = Vector2(x, r.size.y * (0.18 + (i % 2) * 0.36))
		cv.home_pos = hp
		cv.home_rot = (i - 1) * 0.12
		if cv.position == Vector2.ZERO:
			cv.position = hp
