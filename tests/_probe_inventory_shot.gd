extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn, opens the inventory with Tab's own path, puts a few
# of the test items in the grid and saves screenshots. See docs/specs/inventory.md. Run:
#   godot --path . --script tests/_probe_inventory_shot.gd -- <out_dir>

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
			var pilot: Node = inv.player()
			print("pilot ", pilot, " can_open ", pilot.can_open_inventory() if pilot else false,
				" on_floor ", pilot.is_on_floor() if pilot else false)
			for item in get_nodes_in_group(&"world_item"):
				print("  ground ", item.name, " at ", item.global_position, " d ",
					pilot.global_position.distance_to(item.global_position))
			print("vicinity ", inv.vicinity(pilot).size())
			_shot("world")
			ui.open(&"inventory")
			_screen = ui._instances[&"inventory"]
			_step = 1
			_frames = 80
		1:
			if _frames < 100:
				return false
			print("vicinity listed ", _screen.vicinity_items().size(), " scale ", _screen.texel_scale())
			_shot("open_empty")
			# Pick two items up off the ground, carry one.
			for item in _screen.vicinity_items().duplicate():
				if item.def.id == &"medkit" or item.def.id == &"ration":
					inv.take(item)
			_screen._refresh_vicinity()
			var g: Control = _screen
			if not g.vicinity_items().is_empty():
				var r: Rect2i = g.box_rect(g.Box.VICINITY)
				g.left_click(r.position + Vector2i(8, 20))
				g._mouse = g.grid_cell_origin(Vector2i(6, 3)) + Vector2i(8, 8)
			_step = 2
			_frames = 80
		2:
			if _frames < 90:
				return false
			print("grid ", inv.grid.items.size(), " held ", _screen.held)
			_shot("open_items")
			ui.back()
			_step = 3
			_frames = 80
		3:
			if _frames < 90:
				return false
			print("closed, stack ", ui.stack, " pilot frozen ", inv.player().frozen)
			_shot("closed")
			return true
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/inventory_%s.png" % [_out, name]
	print("saved ", path, " ", img.save_png(path))
