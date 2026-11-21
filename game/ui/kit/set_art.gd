extends RefCounted

const SETS := ["SOR", "SHD", "TWI", "JTL", "LOF", "SEC", "LAW", "ASH", "HMW", "IBH"]


static func texture(code: String, kind: String) -> Texture2D:
	if code not in SETS:
		return null
	var path := "res://ui/art/sets/%s/%s" % [code.to_lower(), kind]
	for extension in [".png", ".jpg"]:
		if ResourceLoader.exists(path + extension):
			return load(path + extension)
	return null


static func background_id(code: String) -> String:
	return "set_" + code.to_lower()
