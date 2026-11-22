class_name ConquestGalaxy
extends RefCounted

const FACTIONS := [
	{"name": "Empire", "leader": "SOR_010", "base": "SOR_023", "home": "Coruscant", "trait": "imperial", "emblem": "galactic_empire", "color": Color.WHITE},
	{"name": "Rebels", "leader": "SOR_005", "base": "SOR_029", "home": "Yavin", "trait": "rebel", "emblem": "rebel_alliance", "color": Color("#ff9d41")},
	{"name": "Hutts", "leader": "LAW_015", "base": "LAW_023", "home": "Nal Hutta", "trait": "underworld", "emblem": "fett_crest", "color": Color("#63d88c")},
]
const LOCAL_CONTROL := {
	"Kamino": {"name": "Republic", "emblem": "galactic_republic", "color": Color("#f0525e")},
	"Geonosis": {"name": "Separatists", "emblem": "separatists", "color": Color("#68a5ff")},
}
const NEUTRAL := {"name": "Neutral", "color": Color("#9ca9b3")}
const FACTION_ICONS := ["empire", "rebels", "hutts"]
const PLANET_ICONS := {
	"Bespin": "bespin", "Dathomir": "dathomir", "Kashyyyk": "kashyyyk", "Mandalore": "mandalore",
	"Naboo": "naboo", "Tatooine": "tatooine", "Geonosis": "separatists", "Kamino": "republic",
}

# World coordinates are in pixels on the supplied 1280 × 960 map.
const WORLDS := {
	"Coruscant": Vector2(592, 404), "Yavin": Vector2(899, 223), "Nal Hutta": Vector2(1127, 493),
	"Corellia": Vector2(702, 490), "Naboo": Vector2(907, 731), "Geonosis": Vector2(1110, 746),
	"Kamino": Vector2(1217, 588), "Mandalore": Vector2(903, 184),
	"Kuat": Vector2(734, 467), "Kashyyyk": Vector2(1030, 416), "Kessel": Vector2(1188, 376),
	"Scarif": Vector2(1101, 656), "Hoth": Vector2(609, 824), "Endor": Vector2(454, 652),
	"Tatooine": Vector2(1094, 710), "Dathomir": Vector2(885, 107),
	"Bespin": Vector2(611, 805), "Mustafar": Vector2(681, 838), "Fondor": Vector2(647, 610),
	"Lothal": Vector2(1200, 285), "Mon Cala": Vector2(1170, 261), "Felucia": Vector2(1081, 256),
	"Jakku": Vector2(483, 586), "Crait": Vector2(885, 833), "Dagobah": Vector2(772, 875),
	"Utapau": Vector2(746, 900), "Ryloth": Vector2(1080, 771), "Eriadu": Vector2(749, 802),
	"Taris": Vector2(934, 138), "Alderaan": Vector2(708, 410), "Jedha": Vector2(430, 410),
	"Onderon": Vector2(832, 379),
	"Sullust": Vector2(732, 772), "Umbara": Vector2(964, 440),
}

const SPECIALTIES := {
	"Geonosis": "separatist", "Kamino": "clone", "Mandalore": "mandalorian",
	"Tatooine": "tusken", "Kashyyyk": "wookiee", "Kuat": "imperial", "Kessel": "underworld", "Dathomir": "night",
}

const NATIVE_RECRUITS := {
	"Tatooine": {"native_tusken": "Tusken Raiders", "native_jawa": "Jawas and sandcrawlers"},
	"Kashyyyk": {"native_wookiee": "Wookiees", "native_wookiee_vehicle": "Wookiee vehicles"},
	"Geonosis": {"native_battle_droid": "Separatist battle droids and vehicles"},
	"Kamino": {"native_clone": "Clone veterans", "native_republic_vehicle": "Republic vehicles"},
	"Naboo": {"native_naboo": "Naboo security and starfighters", "native_gungan": "Gungan forces"},
	"Dathomir": {"native_nightsister": "Nightsisters"},
	"Bespin": {"native_bespin": "Cloud City patrols and smugglers", "native_bounty_hunter": "Bounty hunters and ships"},
	"Mandalore": {"native_mandalorian": "Mandalorian warriors and ships"},
}
const FACTION_RECRUITS := {
	"Lothal": {
		0: {"native_lothal_imperial": "Lothal Imperial forces"},
		1: {"native_spectre": "The Spectres"},
	},
	"Endor": {
		0: {"native_death_star": "Death Star and Tempest forces"},
		1: {"native_ewok": "Ewok warriors"},
	},
}
const LOCAL_UNIT_PRINTS := {
	"native_lothal_imperial": ["IC27_024", "SEC_136", "SOR_180", "JTL_163"],
	"native_death_star": ["SOR_128", "SOR_083", "SHD_085", "SOR_084", "ASH_143", "JTL_107", "SOR_232"],
	"native_bespin": ["SOR_063", "LAW_108"],
}
const LOCAL_CATALOG_TRAITS := {
	"native_bounty_hunter": ["underworld"], "native_nightsister": ["night", "nightsister"],
	"native_spectre": ["spectre"], "native_wookiee": ["wookiee"],
	"native_jawa": ["jawa"], "native_tusken": ["tusken"], "native_ewok": ["ewok"],
}
const LOCAL_SUPPORT_PRINTS := {
	"native_bespin": ["LAW_111", "SOR_214", "SHD_123", "SHD_228", "LAW_169"],
	"native_nightsister": ["ASH_104"],
	"native_spectre": ["ASH_114"],
	"native_lothal_imperial": ["LAW_003", "SEC_011", "SOR_115", "LAW_076", "JTL_163"],
	"native_death_star": ["JTL_260", "HMW_206"],
	"native_ewok": ["HMW_193"],
	"native_wookiee": ["HMW_127", "SHD_205"],
	"native_tusken": ["HMW_240"],
	"native_clone": ["TWI_051", "TWI_102", "TWI_129", "TWI_169", "TWI_200", "TWI_251", "TS26_069"],
}
const LOCAL_VARIANTS := {
	"Dathomir": {0: ["LOF_005"], 1: ["HMW_001"]},
	"Endor": {0: ["SOR_007", "HMW_004"], 1: ["HMW_014"]},
	"Kamino": {0: ["HMW_003"], 1: ["SHD_009", "TS26_006", "HMW_006"]},
	"Mandalore": {0: ["SHD_001", "SHD_007", "ASH_008"], 1: ["SHD_018", "ASH_014", "SOR_014", "ASH_006", "SHD_012", "ASH_010"]},
}
const OUT_OF_ERA_UNDERWORLD_LEADERS := ["LAW_004", "TWI_016", "TWI_009", "SEC_018", "TS26_003", "TS26_005", "ASH_012"]

# Planet-specific recruitment supplements each faction's home roster.
const REGIONAL_COMMANDERS := {
	"Coruscant": {0: ["SOR_006", "SEC_006", "SEC_014"]},
	"Yavin": {1: ["SOR_009", "LAW_010", "IBH_001", "SOR_018", "LAW_005"]},
	"Nal Hutta": {2: ["SOR_012", "SHD_010", "HMW_015"]},
	"Corellia": {0: ["SOR_002"], 1: ["JTL_017", "SEC_015"], 2: ["SOR_017", "LAW_017", "SHD_013", "JTL_015"]},
	"Naboo": {0: ["SOR_011", "LOF_014"], 1: ["LAW_006"], 2: ["LAW_014"]},
	"Mandalore": {0: ["SHD_001"], 1: ["SOR_014"]},
	"Kuat": {0: ["JTL_005"]},
	"Kashyyyk": {1: ["HMW_009"], 2: ["SOR_003", "LAW_013"]},
	"Kessel": {2: ["SEC_007", "SHD_015"]},
	"Scarif": {0: ["SOR_001", "LAW_008"], 1: ["SOR_013", "SEC_012"]},
	"Hoth": {1: ["JTL_008"]},
	"Tatooine": {2: ["SOR_015", "LAW_007", "JTL_009"]},
	"Lothal": {0: ["SOR_016", "JTL_002", "SEC_011"], 1: ["SOR_008", "LAW_009", "LOF_004"]},
	"Mon Cala": {1: ["JTL_016"]},
	"Felucia": {2: ["SHD_005"]},
	"Alderaan": {1: ["SEC_013"]},
	"Jedha": {1: ["LAW_001"]},
	"Fondor": {0: ["SEC_010"]},
}
const LOCAL_COMMANDERS := {
	"Bespin": ["JTL_003", "LAW_018", "SHD_017"],
}
const LATER_OR_EARLIER_TRAITS := ["first order", "resistance", "new republic", "high republic", "old republic", "sith eternal"]
const ERA_NAMED_UNITS := [
	"0-0-0", "2-1B Surgical Droid", "4-LOM", "A'Koba", "Admiral Ackbar", "Admiral Motti", "Admiral Ozzel",
	"Admiral Piett", "Alexsandr Kallus", "Bail Organa", "Ben Kenobi", "Bib Fortuna", "Biggs Darklighter",
	"Boba Fett", "Bodhi Rook", "Bossk", "BT-1", "C-3PO", "Cassian Andor", "Cham Syndulla", "Chewbacca",
	"Chirrut Îmwe", "Chopper", "Colonel Yularen", "Crix Madine", "Darth Vader", "Dedra Meero", "Dengar",
	"Director Krennic", "Doctor Aphra", "Dryden Vos", "Eighth Brother", "Emperor Palpatine", "Enfys Nest",
	"Ezra Bridger", "Fenn Rau", "Fifth Brother", "Gar Saxon", "General Dodonna", "General Draven",
	"General Rieekan", "General Tagge", "General Veers", "Grand Admiral Thrawn", "Grand Inquisitor",
	"Grand Moff Tarkin", "Greedo", "Han Solo", "Hera Syndulla", "Highsinger", "Hondo Ohnaka", "IG-88",
	"Iden Versio", "Jabba the Hutt", "Jyn Erso", "K-2SO", "K-2S0", "Kanan Jarrus", "Ketsu Onyo",
	"King Grakchawwaa", "Krrsantan", "L3-37", "Lando Calrissian", "Leia Organa", "Lieutenant Childsen",
	"Luke Skywalker", "Luthen Rael", "Major Partagaz", "Mas Amedda", "Max Rebo", "Merrin", "Moff Jerjerrod", "Morgan Elsbeth", "Jar Jar Binks",
	"Mon Mothma", "Owen Lars", "Qi'ra", "R2-D2", "R5-D4", "Rex", "Rio Durant", "Ryder Azadi",
	"Sabine Wren", "Salacious Crumb", "Saw Gerrera", "Seventh Sister", "Sly Moore", "Syril Karn",
	"Tarfful", "Teeka", "The Chieftain", "The Ghost", "Phantom", "Third Sister", "Tobias Beckett", "Urrr'k", "Vaneé", "Vel Sartha",
	"Wedge Antilles", "Wicket", "Wolffe", "Yanna", "Zeb Orrelios", "Arihnda Pryce", "Chief Chirpa", "Teebo",
]
const ERA_EXCLUDED_PRINTS := [
	"HMW_225", "TWI_211", "ASH_033", "ASH_060", "ASH_158",
]
const HOME_NAMES := {"Yavin": "Yavin 4"}
const LEGACY_ORBITAL_ART := {"Kessel": "kessel", "Mustafar": "mustafar", "Felucia": "felucia"}


static func display_name(world: String) -> String:
	return HOME_NAMES.get(world, world)


static func territory_identity(world: String, owner: int) -> Dictionary:
	return FACTIONS[owner] if owner >= 0 else LOCAL_CONTROL.get(world, NEUTRAL)


static func planet_icon(world: String, owner: int) -> String:
	match world:
		"Endor", "Lothal":
			return world.to_lower() + ("-empire" if owner == 0 else "-rebels")
		"Mandalore":
			if owner == 2:
				return "shadow-collective"
	return PLANET_ICONS.get(world, "")


static func territory_icon(world: String, owner: int) -> String:
	var local := planet_icon(world, owner)
	return local if not local.is_empty() else (FACTION_ICONS[owner] if owner >= 0 else "")


static func worlds_for_size(count: int) -> Array:
	var worlds := WORLDS.keys().slice(0, count)
	if count == 32:
		worlds[worlds.find("Crait")] = "Sullust"
		worlds[worlds.find("Taris")] = "Umbara"
	return worlds


static func supplied_planet(world: String) -> Texture2D:
	var path := "res://assets/conquest/planets/%s.png" % world.to_lower().replace(" ", "-")
	return load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null


static func leader_variants(lib: CardLibrary, faction: int, world := "", starters := false) -> Array:
	var original := lib.get_card(FACTIONS[faction]["leader"])
	var local: Array = LOCAL_COMMANDERS.get(world, [])
	var local_alignment: Array = LOCAL_VARIANTS.get(world, {}).get(faction, [])
	var rosters := native_recruits(world, faction)
	var found := []
	for id in lib.cards:
		var card := lib.get_card(id)
		if card.get("type") != "leader" or card.get("custom", false):
			continue
		var eligible: bool = card["name"] == original["name"] and (starters or world == FACTIONS[faction]["home"])
		if not starters:
			eligible = eligible or id in REGIONAL_COMMANDERS.get(world, {}).get(faction, []) or id in local or id in local_alignment
			eligible = eligible or (world == "Mandalore" and faction == 2 and "mandalorian" in card["traits"])
			if not eligible:
				eligible = rosters.keys().any(func(roster):
					return not roster in ["native_nightsister", "native_clone", "native_mandalorian"] and local_catalog_match(card, roster))
		if eligible:
			found.append(id)
	found.sort_custom(func(a, b):
		return "%s %s" % [lib.get_card(a)["name"], lib.get_card(a).get("subtitle", "")] \
			< "%s %s" % [lib.get_card(b)["name"], lib.get_card(b).get("subtitle", "")])
	return found


static func era_unit(card: Dictionary) -> bool:
	if card.get("type") != "unit" or card["id"] in ERA_EXCLUDED_PRINTS:
		return false
	var traits: Array = card["traits"]
	if traits.any(func(tag): return tag in LATER_OR_EARLIER_TRAITS):
		return false
	# Unnamed troops, ships and droids may be in service after their original war.
	if not card.get("unique", false) or card.get("subtitle", "").is_empty():
		return true
	return card["name"] in ERA_NAMED_UNITS or card["id"] in ["TWI_085", "TWI_097", "SEC_048", "IC27_041"]


static func native_recruits(world: String, faction: int) -> Dictionary:
	return FACTION_RECRUITS.get(world, {}).get(faction, NATIVE_RECRUITS.get(world, {}))


static func local_catalog_match(card: Dictionary, roster: String) -> bool:
	var id: String = card["id"]
	if roster == "native_lothal_imperial" and card["name"] == "Grand Admiral Thrawn":
		return true
	if id in LOCAL_SUPPORT_PRINTS.get(roster, []):
		return true
	var traits: Array = card["traits"]
	if id in ERA_EXCLUDED_PRINTS or traits.any(func(tag): return tag in LATER_OR_EARLIER_TRAITS):
		return false
	if roster == "native_clone":
		return "clone" in traits and not "imperial" in traits
	if roster == "native_bounty_hunter" and card["type"] == "leader":
		return "underworld" in traits and not id in OUT_OF_ERA_UNDERWORLD_LEADERS
	return LOCAL_CATALOG_TRAITS.get(roster, []).any(func(tag): return tag in traits)


static func native_match(card: Dictionary, roster: String) -> bool:
	var traits: Array = card["traits"]
	if LOCAL_UNIT_PRINTS.has(roster):
		return card["id"] in LOCAL_UNIT_PRINTS[roster]
	match roster:
		"native_tusken": return "tusken" in traits
		"native_jawa": return "jawa" in traits or card["id"] == "LAW_238"
		"native_wookiee": return "wookiee" in traits
		"native_wookiee_vehicle": return card["id"] in ["HMW_093", "SOR_195"]
		"native_battle_droid":
			return "separatist" in traits and ("droid" in traits or "vehicle" in traits) and (not card["unique"] or card["id"] == "TWI_085")
		"native_clone": return "clone" in traits and "trooper" in traits and not "imperial" in traits
		"native_republic_vehicle": return "republic" in traits and "vehicle" in traits
		"native_spectre": return "spectre" in traits and "rebel" in traits
		"native_ewok": return "ewok" in traits
		"native_naboo": return "naboo" in traits and ("vehicle" in traits or "trooper" in traits)
		"native_gungan": return "gungan" in traits and (not card["unique"] or card["id"] == "SEC_111")
		"native_nightsister":
			return "night" in traits and not "undead" in traits and (not card["unique"] or card["id"] in ["LOF_160", "ASH_050"])
		"native_bounty_hunter":
			return "bounty hunter" in traits or ("underworld" in traits and "vehicle" in traits and card["arena"] == "space")
		"native_mandalorian":
			return "mandalorian" in traits and (not card["unique"] or card["name"] in [
				"Sabine Wren", "Gar Saxon", "Ketsu Onyo", "Fenn Rau", "Bo-Katan Kryze", "Mandalorian Warrior"])
	return false

# Long routes connect through intervening junctions on the map.
const LANES := [
	["Coruscant", "Corellia", Vector2(656, 431)],
	["Coruscant", "Yavin", Vector2(655, 369), Vector2(775, 350), Vector2(851, 244)],
	["Yavin", "Mandalore", Vector2(855, 201)],
	["Yavin", "Nal Hutta", Vector2(979, 301), Vector2(1095, 361), Vector2(1075, 476)],
	["Corellia", "Naboo", Vector2(812, 590), Vector2(919, 629)],
	["Naboo", "Geonosis", Vector2(951, 693), Vector2(1030, 730)],
	["Nal Hutta", "Kamino", Vector2(1150, 558), Vector2(1210, 550)],
	["Kamino", "Geonosis", Vector2(1188, 623), Vector2(1157, 638), Vector2(1141, 713)],
	["Coruscant", "Kuat"], ["Corellia", "Kuat"], ["Kuat", "Kashyyyk", Vector2(862, 452), Vector2(967, 440)],
	["Kashyyyk", "Nal Hutta"], ["Nal Hutta", "Kessel", Vector2(1132, 386)],
	["Kamino", "Scarif", Vector2(1188, 623)], ["Scarif", "Tatooine"], ["Tatooine", "Geonosis"],
	["Corellia", "Endor", Vector2(601, 543), Vector2(486, 586)], ["Endor", "Hoth", Vector2(493, 738)],
	["Hoth", "Naboo", Vector2(612, 774), Vector2(735, 767)], ["Mandalore", "Dathomir", Vector2(934, 140)],
	["Hoth", "Bespin"], ["Bespin", "Mustafar"], ["Mustafar", "Eriadu"], ["Hoth", "Eriadu"],
	["Eriadu", "Utapau"], ["Utapau", "Dagobah"], ["Dagobah", "Crait"], ["Crait", "Naboo"],
	["Eriadu", "Naboo"], ["Tatooine", "Ryloth"], ["Ryloth", "Geonosis"],
	["Corellia", "Fondor"], ["Fondor", "Jakku"], ["Jakku", "Endor"],
	["Coruscant", "Alderaan"], ["Alderaan", "Kuat"], ["Coruscant", "Jedha"], ["Jedha", "Jakku"],
	["Alderaan", "Onderon"], ["Onderon", "Yavin"], ["Onderon", "Kashyyyk"],
	["Dathomir", "Taris"], ["Taris", "Mandalore"], ["Taris", "Felucia", Vector2(1008, 180)],
	["Felucia", "Mon Cala"], ["Mon Cala", "Lothal"], ["Lothal", "Kessel"], ["Felucia", "Kashyyyk"],
	["Eriadu", "Sullust"], ["Sullust", "Naboo"],
	["Onderon", "Umbara"], ["Umbara", "Kashyyyk"], ["Umbara", "Naboo", Vector2(947, 635)],
]


static func lane_points(lane: Array) -> PackedVector2Array:
	return PackedVector2Array([WORLDS[lane[0]]] + lane.slice(2) + [WORLDS[lane[1]]])


static func lane_distance(from: String, to: String) -> float:
	var points := points_between(from, to)
	var distance := 0.0
	for i in range(1, points.size()):
		distance += points[i - 1].distance_to(points[i])
	return distance


static func points_between(from: String, to: String) -> PackedVector2Array:
	for lane in LANES:
		if lane[0] == from and lane[1] == to:
			return lane_points(lane)
		if lane[0] == to and lane[1] == from:
			var points := lane_points(lane)
			points.reverse()
			return points
	return PackedVector2Array()


static func travel_position(from: String, to: String, progress: float) -> Vector2:
	var points := points_between(from, to)
	var left := lane_distance(from, to) * clampf(progress, 0.0, 1.0)
	for i in range(1, points.size()):
		var leg := points[i - 1].distance_to(points[i])
		if left <= leg:
			return points[i - 1].lerp(points[i], left / maxf(leg, 1.0))
		left -= leg
	return WORLDS[to]
