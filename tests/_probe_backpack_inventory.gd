extends SceneTree

# Throwaway probe, WINDOWED: the inventory with a worn backpack (a medkit in it), the trial TestLoot
# backpack listed in the vicinity with a ration inside, and the tooltip over the BACK slot. Never
# writes the real loadout. See docs/specs/pilot9-backpack.md.
#   godot --path . --script tests/_probe_backpack_inventory.gd -- <out_dir>

const PACK := preload("res://resources/items/backpack.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")
const RATION := preload("res://resources/items/ration.tres")

var _frames := 0
var _out := ""
var _step := 0
var _screen: Control


func _initialize() -> void:
	var inv := root.get_node_or_null(^"/root/Inventory")
	if inv != null:
		inv.persist = false
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
			inv.persist = false
			if inv.item_in(&"back") == null:
				inv.equip(&"back", ItemStack.new(PACK))
			inv.pack_grid().add(MEDKIT, 1)
			for item in get_nodes_in_group(&"world_item"):
				if item.def == PACK:
					item.contents.add(RATION, 2)
			ui.open(&"inventory")
			_screen = ui._instances[&"inventory"]
			_step = 1
			_frames = 80
		1:
			if _frames < 100:
				return false
			_screen._refresh_vicinity()
			print("vicinity ", _screen.vicinity_items().size())
			_shot("vicinity_plain")
			var ground: Node3D = null
			for it in _screen.vicinity_items():
				if it.def == PACK:
					ground = it
			var spot: Vector2i = _screen._content_rect(_screen.Box.VICINITY).position
			for i in _screen.vicinity_items().size():
				if _screen.vicinity_items()[i] == ground:
					spot += (_screen._vic_spot(i) - Vector2i(0, _screen._vic_scroll)) * 16 + Vector2i(8, 8)
			_screen.open_menu(spot)
			_screen._mouse = spot
			_step = 10
			_frames = 80
		10:
			if _frames < 90:
				return false
			_shot("pack_menu")
			_screen.menu_choose(&"open", _screen._menu["target"])
			_screen._close_menu()
			_screen._mouse = _screen.window_grid_origin(_screen.windows()[0]) + Vector2i(8, 8)
			_step = 11
			_frames = 80
		11:
			if _frames < 90:
				return false
			_shot("pack_window")
			_screen._mouse = _screen.slot_rect(&"back").get_center()
			_step = 2
			_frames = 80
		2:
			if _frames < 90:
				return false
			_shot("tooltip_back")
			_screen._mouse = _screen.pack_cell_origin(Vector2i(0, 0)) + Vector2i(8, 8)
			_step = 3
			_frames = 80
		3:
			if _frames < 90:
				return false
			_shot("tooltip_pack_item")
			ui.back()
			return true
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/backpack_inv_%s.png" % [_out, name]
	print("saved ", path, " ", img.save_png(path))
