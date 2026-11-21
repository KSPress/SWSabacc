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
	"Kuat": "imperial", "Kessel": "underworld", "Dathomir": "nightsister",
}

const LOCAL_LEADERS := {"Mandalore": "mandalorian", "Geonosis": "separatist", "Kamino": "clone"}
const HOME_NAMES := {"Yavin": "Yavin 4"}


static func display_name(world: String) -> String:
	return HOME_NAMES.get(world, world)


static func leader_variants(lib: CardLibrary, faction: int, world := "", starters := false) -> Array:
	var original := lib.get_card(FACTIONS[faction]["leader"])
	var local: String = LOCAL_LEADERS.get(world, "")
	var found := []
	for id in lib.cards:
		var card := lib.get_card(id)
		if card.get("type") != "leader" or card.get("custom", false):
			continue
		var traits: Array = card.get("traits", [])
		var eligible: bool = card["name"] == original["name"]
		if not starters:
			eligible = eligible or FACTIONS[faction]["trait"] in traits or (not local.is_empty() and local in traits)
		if eligible:
			found.append(id)
	found.sort_custom(func(a, b):
		return "%s %s" % [lib.get_card(a)["name"], lib.get_card(a).get("subtitle", "")] \
			< "%s %s" % [lib.get_card(b)["name"], lib.get_card(b).get("subtitle", "")])
	return found

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
