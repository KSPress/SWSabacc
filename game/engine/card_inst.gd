class_name CardInst
extends RefCounted
## One physical card (or token) in a match. All runtime state lives here;
## the printed card stays in `data` (shared, never mutated).

var uid := 0
var id := ""
var data: Dictionary = {}
var owner := 0
var controller := 0
var zone := "deck"          # deck hand discard resource ground space base leader upgrade removed
var exhausted := false
var damage := 0
var upgrades: Array = []    # CardInst attached to this unit
# The unit owns its upgrades. A strong reference back to the unit forms a
# RefCounted cycle and leaks the whole attachment group after every match.
var _attached_to: WeakRef
var attached_to: CardInst:
	get:
		return _attached_to.get_ref() if _attached_to != null else null
	set(value):
		_attached_to = weakref(value) if value != null else null
var deployed := false       # leader is on its unit side
var epic_used := false
var entered_phase := -1     # phase serial when it entered play (Hidden)
var entry_serial := 0
var mods: Array = []        # lasting effects: {p, h, kw, v, lose_kw, dur, serial}
var flags: Dictionary = {}  # campaign/scenario flags: protected, cannot_attack, ...
var ability_uses: Dictionary = {}
var is_token := false
var battle: WeakRef
var _calculating_aura := false


func _init(p_uid := 0, p_id := "", p_data := {}, p_owner := 0) -> void:
	uid = p_uid
	id = p_id
	data = p_data
	owner = p_owner
	controller = p_owner
	var t: String = data.get("type", "")
	is_token = t.begins_with("token")


func card_type() -> String:
	if is_pilot_upgrade():
		return "upgrade"
	if deployed:
		return "unit"
	var t: String = data.get("type", "")
	if t == "token_unit":
		return "unit"
	if t == "token_upgrade":
		return "upgrade"
	return t


func is_pilot_upgrade() -> bool:
	return zone == "upgrade" and data.has("pilot")


func upgrade_abilities() -> Array:
	return data["pilot"]["abilities"] if is_pilot_upgrade() else data.get("abilities", [])


func name() -> String:
	return data.get("name", id)


func title() -> String:
	var sub: String = data.get("subtitle", "")
	return name() + (", " + sub if sub != "" else "")


func is_leader() -> bool:
	return data.get("type", "") == "leader"


func in_play() -> bool:
	return zone == "ground" or zone == "space"


func arena() -> String:
	if in_play():
		return zone
	if zone == "upgrade" and attached_to:
		return attached_to.arena()
	if deployed or is_leader():
		return data.get("leader_unit", {}).get("arena", "ground")
	var a = data.get("arena")
	return a if a != null else "ground"


func unique() -> bool:
	return data.get("unique", false)


func traits() -> Array:
	return data.get("traits", [])


func has_trait(t: String) -> bool:
	return t.to_lower() in traits()


func aspects() -> Array:
	return data["pilot"]["aspects"] if is_pilot_upgrade() else data.get("aspects", [])


func printed_power() -> int:
	if is_pilot_upgrade():
		return int(data["pilot"]["power"])
	if deployed:
		return int(data.get("leader_unit", {}).get("power", 0))
	return int(data.get("power", 0))


func printed_hp() -> int:
	if is_pilot_upgrade():
		return int(data["pilot"]["hp"])
	if deployed:
		return int(data.get("leader_unit", {}).get("hp", 0))
	return int(data.get("hp", 0))


## Own abilities plus those granted by attached upgrades.
func abilities() -> Array:
	var out: Array = []
	var src: Array = data.get("leader_unit", {}).get("abilities", []) if deployed else data.get("abilities", [])
	if is_pilot_upgrade():
		src = upgrade_abilities()
	for a in src:
		if not a.get("granted", false):
			out.append(a)
	for modifier in mods:
		out.append_array(modifier.get("abilities", []))
	for u in upgrades:
		for a in u.upgrade_abilities():
			if a.get("granted", false):
				if a.has("limit"):
					var granted: Dictionary = a.duplicate()
					granted["grant_source"] = u.uid
					out.append(granted)
				else:
					out.append(a)
	return out


func abilities_with(trigger: String) -> Array:
	var out: Array = []
	for a in abilities():
		if a.get("trigger", "") == trigger:
			out.append(a)
	return out


func _printed_keywords() -> Array:
	if is_pilot_upgrade():
		return []
	if deployed:
		return data.get("leader_unit", {}).get("keywords", [])
	return data.get("keywords", [])


## Sum of keyword values (Raid 2 + Raid 1 = 3). Returns 0 when absent, 1 for valueless keywords.
func kw(k: String) -> int:
	var match_game: Match = battle.get_ref() if battle else null
	if match_game and in_play() and match_game.keyword_suppressed(self, k):
		return 0
	for m in mods:
		if m.get("lose_kw", "") == k:
			return 0
	var total := 0
	var found := false
	var aura := _continuous("kw", k)
	if aura > 0:
		found = true
		total += aura
	for e in _printed_keywords():
		if e.get("k", "") == k:
			found = true
			total += int(e.get("v", 1))
	for u in upgrades:
		for a in u.upgrade_abilities():
			if a.get("trigger", "") == "attached_kw" and a.get("kw", "") == k:
				found = true
				total += int(a.get("v", 1)) if int(a.get("v", 0)) > 0 else 1
	for m in mods:
		if m.get("kw", "") == k and modifier_active(m):
			found = true
			total += int(m.get("v", 1))
	if found and total <= 0:
		total = 1
	return total


func has_kw(k: String) -> bool:
	return kw(k) > 0


func keyword_list() -> Array:
	var out: Array = []
	for k in ["sentinel", "shielded", "grit", "saboteur", "ambush", "overwhelm", "raid", "restore",
			"hidden", "smuggle", "exploit", "coordinate", "piloting", "bounty", "support", "plot", "fortify"]:
		var v := kw(k)
		if v > 0:
			out.append({"k": k, "v": v})
	return out


func shield_count() -> int:
	var n := 0
	for u in upgrades:
		if u.data.get("name", "") == "Shield":
			n += 1
	return n


func power(attacking := false) -> int:
	var p := printed_power()
	p += _continuous("p")
	for u in upgrades:
		if u.data.get("name", "") != "Shield":
			p += u.printed_power()
	for m in mods:
		if modifier_active(m):
			p += int(m.get("p", 0))
	if has_kw("grit"):
		p += damage
	if attacking:
		p += kw("raid")
	return maxi(p, 0)


func max_hp() -> int:
	var h := printed_hp()
	h += _continuous("h")
	for u in upgrades:
		if u.data.get("name", "") != "Shield":
			h += u.printed_hp()
	for m in mods:
		h += int(m.get("h", 0))
	return h


func modifier_active(modifier: Dictionary) -> bool:
	if not modifier.has("while_source"):
		return true
	var m: Match = battle.get_ref() if battle else null
	var source := m.card(modifier["while_source"]) if m else null
	return source != null and source.in_play() and source.entry_serial == modifier["source_entry"]


func _continuous(field: String, keyword := "") -> int:
	if battle == null or _calculating_aura:
		return 0
	var m: Match = battle.get_ref()
	if m == null or not in_play():
		return 0
	_calculating_aura = true
	var result := m.continuous_bonus(self, field, keyword)
	_calculating_aura = false
	return result


func remaining_hp() -> int:
	return max_hp() - damage


func cost() -> int:
	if is_pilot_upgrade():
		return int(data["pilot"]["cost"])
	return int(data.get("cost", 0))


func describe() -> String:
	return "%s [%d/%d]" % [title(), power(), remaining_hp()]
