class_name ConquestGalaxy
extends RefCounted

const FACTIONS := [
	{"name": "Empire", "leader": "SOR_010", "base": "SOR_023", "home": "Coruscant", "trait": "imperial", "emblem": "galactic_empire", "color": Color("#ff757a")},
	{"name": "Rebels", "leader": "SOR_005", "base": "SOR_029", "home": "Yavin", "trait": "rebel", "emblem": "rebel_alliance", "color": Color("#72ceff")},
	{"name": "Underworld", "leader": "LAW_015", "base": "LAW_023", "home": "Nal Hutta", "trait": "underworld", "emblem": "fett_crest", "color": Color("#ffc56d")},
]

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
}

const SPECIALTIES := {
	"Geonosis": "separatist", "Kamino": "clone", "Mandalore": "mandalorian",
	"Tatooine": "tusken", "Kashyyyk": "wookiee", "Kuat": "imperial", "Kessel": "underworld", "Dathomir": "night",
}

const NATIVE_RECRUITS := {
	"Tatooine": {"native_tusken": "Tusken Raiders", "native_jawa": "Jawas and sandcrawlers"},
	"Kashyyyk": {"native_wookiee": "Wookiees", "native_wookiee_vehicle": "Wookiee vehicles"},
	"Geonosis": {"native_battle_droid": "Separatist battle droids"},
	"Kamino": {"native_clone": "Clone veterans", "native_republic_vehicle": "Republic vehicles"},
}

# Additional commanders are curated by printing. Traits alone also include
# Republic generals, pre-war rulers, and post-Endor remnant commanders.
const ERA_COMMANDERS := [
	["SOR_001", "SOR_002", "SOR_006", "SOR_007", "SOR_011", "SOR_016", "LAW_008", "LOF_014",
		"SEC_006", "SEC_010", "SEC_011", "SEC_014", "JTL_002", "JTL_005", "HMW_004", "SHD_001"],
	["SOR_008", "SOR_009", "SOR_013", "SOR_014", "SOR_018", "LOF_004", "LAW_001", "LAW_005",
		"LAW_006", "LAW_009", "LAW_010", "JTL_003", "JTL_008", "JTL_016", "JTL_017", "SEC_012",
		"SEC_013", "SEC_015", "HMW_009", "IBH_001"],
	["SOR_003", "SOR_012", "SOR_015", "SOR_017", "LAW_007", "LAW_013", "LAW_014", "LAW_017",
		"LAW_018", "SHD_005", "SHD_010", "SHD_013", "SHD_015", "SHD_017", "JTL_009", "JTL_015", "SEC_007", "HMW_015"],
]
const LOCAL_COMMANDERS := {
	"Tatooine": ["HMW_018"], "Kashyyyk": ["HMW_009", "SOR_003", "LAW_013", "HMW_010"],
	"Mandalore": ["SOR_014", "SHD_001"], "Geonosis": ["KYB_005"], "Kamino": ["TS26_006"],
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
	"Luke Skywalker", "Luthen Rael", "Major Partagaz", "Mas Amedda", "Max Rebo", "Moff Jerjerrod",
	"Mon Mothma", "Owen Lars", "Qi'ra", "R2-D2", "R5-D4", "Rex", "Rio Durant", "Ryder Azadi",
	"Sabine Wren", "Salacious Crumb", "Saw Gerrera", "Seventh Sister", "Sly Moore", "Syril Karn",
	"Tarfful", "Teeka", "The Chieftain", "Third Sister", "Tobias Beckett", "Urrr'k", "Vaneé", "Vel Sartha",
	"Wedge Antilles", "Wicket", "Wolffe", "Yanna", "Zeb Orrelios",
]
const ERA_EXCLUDED_PRINTS := [
	"HMW_225", "TWI_211", "ASH_033", "ASH_060", "ASH_158",
]
const HOME_NAMES := {"Yavin": "Yavin 4"}


static func display_name(world: String) -> String:
	return HOME_NAMES.get(world, world)


static func leader_variants(lib: CardLibrary, faction: int, world := "", starters := false) -> Array:
	var original := lib.get_card(FACTIONS[faction]["leader"])
	var local: Array = LOCAL_COMMANDERS.get(world, [])
	var found := []
	for id in lib.cards:
		var card := lib.get_card(id)
		if card.get("type") != "leader":
			continue
		var eligible: bool = not card.get("custom", false) and card["name"] == original["name"]
		if not starters:
			eligible = eligible or id in ERA_COMMANDERS[faction] or id in local
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


static func native_match(card: Dictionary, roster: String) -> bool:
	var traits: Array = card["traits"]
	match roster:
		"native_tusken": return "tusken" in traits
		"native_jawa": return "jawa" in traits or card["id"] == "LAW_238"
		"native_wookiee": return "wookiee" in traits
		"native_wookiee_vehicle": return card["id"] in ["HMW_093", "SOR_195"]
		"native_battle_droid": return "droid" in traits and "separatist" in traits
		"native_clone": return "clone" in traits and "trooper" in traits and not "imperial" in traits
		"native_republic_vehicle": return "republic" in traits and "vehicle" in traits
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
