extends ScreenBase
## Title screen. Floating showcase cards can be grabbed and flung around.

const TitleButton = preload("res://ui/kit/menu_button.gd")

var _title_box: VBoxContainer
var _buttons: GridContainer
var _floaters: Array = []
var _foot: Label
var _t := 0.0
var _profile_button: SabaccButton
var _profile_badge: ProfileBadge
var _stats_button: SabaccButton


func build() -> void:
	_profile_button = SabaccButton.make("Profile", SabaccButton.Style.GHOST)
	_profile_button.custom_minimum_size = Vector2(150, 54)
	_profile_button.pressed.connect(func(): Router.go("customization"))
	body.add_child(_profile_button)
	_stats_button = SabaccButton.make("", SabaccButton.Style.GOLD, "stats")
	_stats_button.custom_minimum_size = Vector2(58, 56)
	_stats_button.tooltip_text = "Account stats"
	_stats_button.pressed.connect(func(): Router.go("stats"))
	add_child(_stats_button)
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
	_buttons = GridContainer.new()
	_buttons.add_theme_constant_override("h_separation", 12)
	_buttons.add_theme_constant_override("v_separation", 6)
	body.add_child(_buttons)
	var items := [
		["Campaigns", "orbit", func(): Router.go("hub", {"section": "campaigns"}), false],
		["Battles", "crossed_sabers", func(): Router.go("hub", {"section": "battles"}), true],
		["Collection Vault", "collection", func(): Router.go("collection"), false],
		["Customization", "sliders", func(): Router.go("customization"), false],
		["Settings", "gear", func(): Router.go("settings"), true],
		["Exit", "back", exit_application, false],
	]
	var i := 0
	for it in items:
		var b := TitleButton.new()
		b.text = it[0]
		b.glyph = it[1]
		b.pale = it[3]
		b.pressed.connect(it[2])
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
	var safe := safe_rect()
	_stats_button.position = Vector2(safe.end.x - 58, safe.position.y)
	_profile_button.position = Vector2(r.size.x - 150, 0)
	_profile_badge.position = Vector2(4, 0)
	_buttons.columns = 1 if p else 2
	var row_count := ceili(_buttons.get_child_count() / float(_buttons.columns))
	var button_width := minf(520.0, r.size.x - 12.0) if p else minf(390.0, (r.size.x - 36.0) / 2.0)
	var button_height := clampf((r.size.y - (250.0 if p else 130.0)) / row_count - 6.0, 44.0, 83.0)
	for button in _buttons.get_children():
		button.custom_minimum_size = Vector2(button_width, button_height)
	_title_box.get_node("Logo").custom_minimum_size.y = clampf(r.size.y * 0.13, 74.0, 132.0) if p else 92.0
	_title_box.position = Vector2(0, maxf(72, r.size.y * 0.04) if p else 0.0)
	_title_box.size = Vector2(r.size.x, 0)
	await get_tree().process_frame
	var bs := _buttons.get_combined_minimum_size()
	_buttons.size = bs
	# Reserve space for every button and the footer before placing the showcase.
	var button_top := minf(r.size.y * (0.52 if p else 0.5), r.size.y - 70.0 - bs.y)
	_buttons.position = Vector2((r.size.x - bs.x) / 2.0, button_top)
	_foot.position = Vector2(0, r.size.y - 50)
	_foot.size = Vector2(r.size.x, 40)
	# Landscape: cards live in the side gutters left/right of the button grid.
	var gutter := (r.size.x - bs.x) / 2.0
	var showcase_top := _title_box.position.y + _title_box.get_combined_minimum_size().y + 22.0
	var showcase_height := maxf(0.0, button_top - showcase_top - 22.0)
	var fsc := minf(r.size.y * 0.16, showcase_height * 0.8) / CardView.PORTRAIT.y if p else minf(r.size.y * 0.34 / CardView.PORTRAIT.y, maxf(0.0, gutter - 28.0) / CardView.LANDSCAPE.x)
	for i in _floaters.size():
		var cv: CardView = _floaters[i]
		cv.visible = fsc >= 0.14
		if not cv.visible:
			continue
		cv.home_scale = Vector2(fsc, fsc)
		cv.scale = cv.home_scale
		var cw := cv.size.x * fsc
		var hp: Vector2
		if p:
			hp = Vector2(r.size.x * (0.5 + (i - 1) * 0.31) - cw / 2.0, showcase_top)
		else:
			var center := gutter * 0.5 if i < 2 else r.size.x - gutter * 0.5
			hp = Vector2(center - cw / 2.0, r.size.y * (0.28 + (i % 2) * 0.36))
		# CardView scales about its center, so compensate for its pivot.
		hp -= cv.pivot_offset * (1.0 - fsc)
		cv.home_pos = hp
		cv.home_rot = (i - 1) * 0.12
		if not cv.is_dragging() and not cv.top_level:
			cv.position = hp
