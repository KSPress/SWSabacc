extends TouchScroll
## Keep only the visible cards and nearby rows loaded in large collections.

const GAP := 10.0
var _canvas: Control
var _ids: Array = []
var _tiles := {}
var _make: Callable
var _columns := 1
var _cell := Vector2.ONE


func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	vertical_scroll_mode = SCROLL_MODE_SHOW_ALWAYS
	scroll_deadzone = 12
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_canvas)
	get_v_scroll_bar().value_changed.connect(func(_value): _populate())
	resized.connect(_layout)
	_layout()


func show_cards(ids: Array, make: Callable, reset := true) -> void:
	_ids = ids
	_make = make
	if reset:
		scroll_vertical = 0
	_layout()


func tile_for(id: String) -> Control:
	var index := _ids.find(id)
	return _tiles.get(index)


func _layout() -> void:
	for tile in _tiles.values():
		_canvas.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	var width := maxf(1.0, size.x - get_v_scroll_bar().get_combined_minimum_size().x)
	_columns = clampi(int((width + GAP) / 152.0), 1, 9)
	_cell.x = (width - GAP * (_columns - 1)) / _columns
	_cell.y = _cell.x * CardView.PORTRAIT.y / CardView.PORTRAIT.x
	var rows := ceili(float(_ids.size()) / _columns)
	_canvas.custom_minimum_size.y = maxf(0.0, rows * (_cell.y + GAP) - GAP)
	_populate()


func _populate() -> void:
	if not _make.is_valid() or _ids.is_empty() or size.x < 20 or size.y < 1:
		return
	var pitch := _cell.y + GAP
	var first := maxi(0, floori(scroll_vertical / pitch) - 1) * _columns
	var end := mini(_ids.size(), (ceili((scroll_vertical + size.y) / pitch) + 1) * _columns)
	for index in _tiles.keys():
		if index < first or index >= end:
			var tile: Control = _tiles[index]
			_canvas.remove_child(tile)
			tile.queue_free()
			_tiles.erase(index)
	for index in range(first, end):
		if _tiles.has(index):
			continue
		var tile: Control = _make.call(_ids[index], _cell)
		tile.mouse_filter = Control.MOUSE_FILTER_PASS
		tile.position = Vector2(index % _columns, floori(float(index) / _columns)) * (_cell + Vector2.ONE * GAP)
		tile.size = _cell
		_canvas.add_child(tile)
		_tiles[index] = tile


static func place_card(card: CardView, cell: Vector2) -> void:
	var base := card.base_size()
	var factor := minf(cell.x / base.x, cell.y / base.y)
	card.pivot_offset = Vector2.ZERO
	card.home_scale = Vector2.ONE * factor
	card.scale = card.home_scale
	card.home_pos = (cell - base * factor) / 2.0
	card.position = card.home_pos
	card.hover_lift = false
	card.draggable = false
	card.in_scroll = true
	card.mouse_filter = Control.MOUSE_FILTER_PASS
