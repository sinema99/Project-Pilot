extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn, opens the inventory, and shoots the polish pass -
# category glyphs + hover, a held item snapped with its preview, the popup, the Inspect card.
#   godot --path . --script tests/_probe_inventory_polish.gd -- <out_dir>

var _frames := 0
var _out := ""
var _step := 0
var _screen: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	root.size = Vector2i(1920, 1080)
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 90:
		return false
	var ui := root.get_node(^"UI")
	var inv := root.get_node(^"Inventory")
	match _step:
		0:
			inv.persist = false  # never write the real loadout from a probe
			inv.grid.items.clear()
			ui.open(&"inventory")
			_screen = ui._instances[&"inventory"]
			for path in ["res://resources/items/ration.tres", "res://resources/items/medkit.tres",
					"res://resources/items/battery.tres", "res://resources/items/rifle_crate.tres"]:
				inv.grid.add(load(path), 3 if path.ends_with("ration.tres") else 1)
			_step = 1
			_frames = 80
		1:
			if _frames < 100:
				return false
			# Hover an item.
			_screen._mouse = _screen.grid_cell_origin(Vector2i(0, 0)) + Vector2i(4, 4)
			_wait_shot("hover", 2)
		2:
			if _wait == 0:
				# Pick the medkit up and hold it over a free cell: snapped, cyan preview.
				var med = _find(inv, "MEDKIT")
				_screen.left_click(_screen.grid_cell_origin(med.cell) + Vector2i(4, 4))
				_screen._mouse = _screen.grid_cell_origin(Vector2i(6, 2)) + Vector2i(9, 9)
			_wait_shot("held_fit", 3)
		3:
			if _wait == 0:
				# Over the crate: red.
				var crate = _find(inv, "RIFLE CRATE")
				_screen._mouse = _screen.grid_cell_origin(crate.cell) + Vector2i(4, 4)
			_wait_shot("held_bad", 4)
		4:
			if _wait == 0:
				_screen._return_held()
				var r = _screen.grid_cell_origin(Vector2i(0, 0)) + Vector2i(4, 4)
				_screen._mouse = r
				_screen.open_menu(r)
			_wait_shot("popup", 5)
		5:
			if _wait == 0:
				_screen._mouse = _screen.menu_rect().position + Vector2i(8, 36)
				_screen.menu_choose(&"inspect")
				_screen._close_menu()
			_wait_shot("inspect", 6)
		6:
			if _wait == 0:
				_screen._card_def = null
				_screen.sort_all()
			_wait_shot("sorted", 7)
		7:
			print("done")
			return true
	return false


var _wait := 0
func _wait_shot(name: String, next: int) -> void:
	_wait += 1
	if _wait < 12:
		return
	_wait = 0
	var img := root.get_texture().get_image()
	print("saved ", "%s/inv_%s.png" % [_out, name], " ", img.save_png("%s/inv_%s.png" % [_out, name]))
	_step = next


func _find(inv: Node, display: String) -> ItemStack:
	for it in inv.grid.items:
		if it.def.display_name == display:
			return it
	return null
