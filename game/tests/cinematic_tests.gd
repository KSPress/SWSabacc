extends "res://tests/shots.gd"
var checks := 0
var failures := 0


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)


func _go(screen: String, parameters := {}) -> void:
	Router.go(screen, parameters)
	await _wait(0.65)


func _run() -> void:
	Save.data = Save.default_data()
	Sabacc.set_setting("perf_mode", false)
	Sabacc.settings["anim_speed"] = 1.0
	Progression.ensure_account()
	for kind in ["force", "initiative"]:
		for face in ["front", "back"]:
			var texture := Art.ui_texture("tokens/sabacc_%s_%s" % [kind, face])
			check(texture != null and texture.get_size() == Vector2(400, 550), "custom Sabacc face " + kind + face)
	var card := CardInst.new()
	card.zone = "ground"
	card.data = {"name": "Yoda", "traits": ["force"], "aspects": ["heroism", "command"]}
	check(AttackStyle.of(card)["style"] == "saber" and AttackStyle.of(card)["palette"] == "green", "Yoda uses green")
	card.data["aspects"] = ["villainy", "vigilance"]
	card.data["name"] = "Darth Vader"
	check(AttackStyle.of(card)["palette"] == "red", "Villainy uses red saber")
	card.data["aspects"] = ["heroism", "vigilance"]
	card.data["name"] = "Luke Skywalker"
	check(AttackStyle.of(card)["palette"] == "blue", "Luke uses blue")
	card.data["traits"] = ["trooper"]
	card.data["name"] = "Test trooper"
	check(AttackStyle.of(card)["palette"] == "red", "Heroism blaster red")
	card.data["aspects"] = ["villainy"]
	check(AttackStyle.of(card)["palette"] == "green", "Villainy blaster green")
	card.data["aspects"] = []
	check(AttackStyle.of(card)["palette"] == "yellow", "neutral blaster yellow")
	await _size(1280, 720)
	await _go("menu")
	var stage := Control.new()
	UIKit.fill_rect(stage)
	get_tree().current_scene.add_child(stage)
	var dim := ColorRect.new()
	dim.color = Color("070b13")
	UIKit.fill_rect(dim)
	stage.add_child(dim)
	var initiative := TableTokens.InitiativeCoin.new()
	initiative.position = Vector2(420, 220)
	initiative.scale = Vector2.ONE * 3
	stage.add_child(initiative)
	var force := TableTokens.ForceOrb.new()
	force.position = Vector2(730, 220)
	force.scale = Vector2.ONE * 3.6
	stage.add_child(force)
	force.gather()
	await _wait(0.12)
	check(force._flip > -1 and force._flip < 1, "Force gain flips between back and front")
	await _shot("sabacc_gather_midflip")
	await _wait(0.8)
	check(force.active and force._flip == 1, "Force gain lands face up")
	await _shot("sabacc_fronts")
	initiative.flip_to(true)
	force.spend()
	await _wait(0.23)
	await _shot("sabacc_spend_midflip")
	await _wait(0.12)
	check(initiative.claimed, "initiative settles on claimed back")
	await _shot("sabacc_claimed_back")
	await _wait(0.6)
	check(not force.active and not force.visible and force._flip == -1, "Force spend lands back and leaves table")
	stage.queue_free()
	# The field layer itself must differ even with the glyph hidden.
	Cosmetics.set_gm(true)
	Cosmetics.equip("background", "emblem")
	var hashes := {}
	for entry in Cosmetics.catalog["emblems"]:
		Cosmetics.equip("emblem", entry["id"])
		await _wait(0.06)
		get_tree().current_scene.bg._datapad._badge.visible = false
		await _shot("signature_" + entry["id"])
		var bytes := get_viewport().get_texture().get_image().get_data()
		hashes[bytes.hex_encode().sha256_text()] = true
	check(hashes.size() == 25, "25 independently rendered emblem signatures")
	Cosmetics.set_gm(false)
	for dimensions in [[360, 640], [540, 1200], [768, 1024], [1280, 720], [1024, 768], [2560, 1080]]:
		await _size(dimensions[0], dimensions[1])
		await _go("collection")
		var overlay := InspectOverlay.open(get_tree().current_scene, "SOR_017")
		await _wait(0.6)
		check(overlay._panels.size() == 4, "four dossiers at %s" % [str(dimensions)])
		var card_rect := Rect2(overlay._card.position, overlay._card.base_size() * overlay._card.scale)
		check(card_rect.get_center().distance_to(overlay.get_viewport_rect().size / 2) < 2, "card centered")
		for panel in overlay._panels:
			check(not panel.get_rect().intersects(card_rect), "dossier avoids card")
		await _shot("inspector_%s_%s" % dimensions)
		overlay._expand_panel(0)
		await _wait(0.35)
		check(is_instance_valid(overlay._expanded) and overlay._expanded._layer.layer > 50, "anatomy expands above inspector")
		var aspects: Array = []
		for node in overlay._expanded.find_children("*", "", true, false):
			if node is AspectIcon:
				aspects.append(node.aspect)
		check(aspects == CardDB.card("SOR_017")["aspects"], "expanded aspect icons preserve identity")
		check(overlay._expanded._panel.get_rect().size.x <= overlay.get_viewport_rect().size.x, "expanded anatomy fits viewport")
		await _shot("anatomy_%s_%s" % dimensions)
		overlay._expanded.close()
		await _wait(0.3)
		overlay._flip()
		await _wait(0.5)
		check(overlay._back, "leader flip retains dossiers")
		overlay.close_overlay()
		await _wait(0.35)
	# Stage the existing real-match animation harness and capture each attack.
	await _anims()
	print("CINEMATIC: %d checks, %d failed" % [checks, failures])
	if failures:
		get_tree().quit(1)
