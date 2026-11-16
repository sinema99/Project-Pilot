extends "res://tests/test_case.gd"

# The backpack (docs/specs/pilot9-backpack.md): a container in the BACK slot, contents that travel
# with it, no nesting, the screen's pack box / pack windows / tooltip, the save, and pilot9.

const SCREEN_TSCN := "res://scenes/ui/inventory_screen.tscn"
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PACK := preload("res://resources/items/backpack.tres")
const MEDKIT := preload("res://resources/items/medkit.tres")
const RATION := preload("res://resources/items/ration.tres")
const WorldItemScript := preload("res://scripts/inventory/world_item.gd")
const BackpackMesh := preload("res://scripts/items/backpack_mesh.gd")


func _inv() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"Inventory")


func _reset() -> void:
	var inv := _inv()
	inv.persist = false
	for it in inv.grid.items.duplicate():
		inv.grid.remove(it)
	inv.seed_equipment()
	inv.equipment_changed.emit()


func _screen() -> Control:
	var s: Control = (load(SCREEN_TSCN) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	s.present()
	return s


func _centre(r: Rect2i) -> Vector2i:
	return r.position + r.size / 2


func test_pack_def() -> void:
	eq(PACK.size, Vector2i(4, 4), "4x4 in a grid")
	eq(PACK.container_size, Vector2i(6, 4), "holds 6x4")
	eq(PACK.slot, &"back", "worn on the back")
	check(_inv().slot_accepts(&"back", PACK), "the BACK slot takes it")
	check(not _inv().slot_accepts(&"body", PACK), "the BODY slot does not")


func test_each_pack_has_its_own_grid() -> void:
	var a := ItemStack.new(PACK)
	var b := ItemStack.new(PACK)
	check(a.contents != null and a.contents != b.contents, "two packs, two grids")
	eq([a.contents.width, a.contents.height], [6, 4], "6x4")
	eq(ItemStack.new(MEDKIT).contents, null, "a medkit holds nothing")


func test_no_packs_in_packs() -> void:
	var a := ItemStack.new(PACK)
	check(not a.contents.accepts(PACK), "refused by accepts()")
	eq(a.contents.add(PACK, 1), 0, "add() refuses it")
	check(not a.contents.place(ItemStack.new(PACK), Vector2i.ZERO, false), "place() refuses it")
	eq(a.contents.capacity_for(PACK), 0, "no capacity for one")
	eq(a.contents.add(MEDKIT, 1), 1, "other things go in")
	check(_inv().grid.accepts(PACK), "his own grid takes a pack")


func test_sort_and_undo_keep_contents() -> void:
	var g := ItemGrid.new(10, 6)
	var p := ItemStack.new(PACK)
	p.contents.add(MEDKIT, 1)
	g.place(ItemStack.new(RATION, 2), Vector2i(5, 0), false)
	g.place(p, Vector2i(0, 2), false)
	var snap := g.snapshot()
	g.sort_items()
	var after: ItemStack = null
	for it in g.items:
		if it.def == PACK:
			after = it
	eq(after.contents, p.contents, "sort keeps the pack's grid")
	g.restore(snap)
	for it in g.items:
		if it.def == PACK:
			after = it
	eq(after.contents.items.size(), 1, "restore keeps the contents")


func test_take_fills_grid_then_pack() -> void:
	_reset()
	var inv := _inv()
	while inv.grid.add(MEDKIT, 1) > 0:
		pass
	var item: Node3D = WorldItemScript.new()
	item.def = MEDKIT
	item.count = 1
	(Engine.get_main_loop() as SceneTree).root.add_child(item)
	check(inv.can_take(item), "room in the pack counts")
	eq(inv.take(item), 1, "taken")
	eq(inv.pack_grid().items.size(), 1, "it went into the pack")
	_reset()


func test_drop_and_take_keep_contents() -> void:
	_reset()
	var inv := _inv()
	var worn: ItemStack = inv.unequip(&"back")
	worn.contents.add(MEDKIT, 1)
	inv.grid.place(worn, Vector2i.ZERO, false)
	var pilot := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(pilot)
	var ground: Node3D = inv.drop(worn, pilot)
	check(ground != null and ground.contents == worn.contents, "the ground pack keeps its grid")
	eq(inv.grid.items.size(), 0, "it left his grid")
	eq(inv.take(ground), 1, "picked back up")
	var back: ItemStack = inv.grid.items[0]
	eq(back.contents.items[0].def, MEDKIT, "with the medkit still inside")
	pilot.queue_free()
	_reset()


func test_save_roundtrip_keeps_contents() -> void:
	_reset()
	var inv := _inv()
	inv.pack_grid().add(RATION, 3)
	var spare := ItemStack.new(PACK)
	spare.contents.add(MEDKIT, 1)
	inv.grid.place(spare, Vector2i(0, 0), false)
	var parsed: Variant = JSON.parse_string(JSON.stringify(inv.loadout_to_dict()))
	_reset()
	inv.loadout_from_dict(parsed)
	eq(inv.pack_grid().items[0].def, RATION, "the worn pack's ration came back")
	eq(inv.pack_grid().items[0].count, 3, "all three")
	eq(inv.grid.items[0].contents.items[0].def, MEDKIT, "the pack in his grid kept its medkit")
	_reset()


func test_screen_slot_row_and_pack_box() -> void:
	_reset()
	var s := _screen()
	var g: Rect2i = s.box_rect(s.Box.GRID)
	var legs: Rect2i = s.slot_rect(&"legs")
	var back: Rect2i = s.slot_rect(&"back")
	var w1: Rect2i = s.slot_rect(&"weapon_1")
	check(back.position.x > legs.end.x and back.end.x < w1.position.x, "BACK sits after LEGS, before the weapons")
	check(w1.position.x - back.end.x > back.position.x - legs.end.x, "the weapon gap is wider")
	var p: Rect2i = s.box_rect(s.Box.PACK)
	check(p.position.y > g.end.y, "the pack box is under the grid")
	check(p.end.y <= s.box_rect(s.Box.PORTRAIT).end.y, "and fits the column")
	# A medkit placed through the pack box lands in the pack.
	var at: Vector2i = s.pack_cell_origin(Vector2i(2, 1)) + Vector2i(8, 8)
	s.held = ItemStack.new(MEDKIT)
	s.left_click(at)
	eq(s.held, null, "placed")
	eq(_inv().pack_grid().item_at(Vector2i(2, 1)).def, MEDKIT, "in the pack at (2, 1)")
	# A pack on the cursor is refused by the pack box.
	s.held = ItemStack.new(PACK)
	s.left_click(s.pack_cell_origin(Vector2i(0, 0)) + Vector2i(8, 8))
	check(s.held != null, "no pack in the pack")
	s.held = null
	s.queue_free()
	_reset()


func test_no_pack_no_box() -> void:
	_reset()
	var s := _screen()
	_inv().unequip(&"back")
	eq(s.pack_cell_at(s.pack_cell_origin(Vector2i.ZERO) + Vector2i(4, 4)), Vector2i(-1, -1), "no pack, no pack cells")
	s.queue_free()
	_reset()


func test_tooltip_info() -> void:
	_reset()
	var s := _screen()
	var info: Dictionary = s.hover_info(_centre(s.slot_rect(&"back")))
	eq(info["def"], PACK, "the worn pack")
	eq(s.hover_info(_centre(s.slot_rect(&"legs"))), {"slot": &"legs"}, "an empty slot names itself")
	check(s.tooltip_allowed(), "shown with empty hands")
	s.held = ItemStack.new(MEDKIT)
	check(not s.tooltip_allowed(), "hidden while holding")
	s.held = null
	s.queue_free()
	_reset()


func _ground_pack(s: Control) -> Node3D:
	var ground: Node3D = WorldItemScript.new()
	ground.def = PACK
	(Engine.get_main_loop() as SceneTree).root.add_child(ground)
	var listed: Array[Node3D] = [ground]
	s._vicinity = listed
	s._packed = _inv().pack([PACK.size], _inv().VICINITY_W)
	return ground


func _ground_spot(s: Control) -> Vector2i:
	return s._content_rect(s.Box.VICINITY).position + Vector2i(8, 8)


func test_ground_pack_is_just_its_item() -> void:
	_reset()
	var s := _screen()
	var ground := _ground_pack(s)
	check(ground.contents != null, "a placed pack makes its grid")
	eq(s._vicinity_rows(), PACK.size.y, "the vicinity holds only the 4x4 item, no grid under it")
	eq(s.vicinity_item_at(_ground_spot(s)), ground, "the pack itself is listed")
	ground.queue_free()
	s.queue_free()
	_reset()


func test_ground_pack_menu() -> void:
	_reset()
	var s := _screen()
	var ground := _ground_pack(s)
	var ids: Array = []
	for e in s.menu_for(_ground_spot(s))["entries"]:
		ids.append(e["id"])
	eq(ids, [&"take", &"equip", &"open", &"inspect"], "TAKE, EQUIP, OPEN, INSPECT")
	# The pack in his own grid gets the same pair.
	_inv().grid.place(ItemStack.new(PACK), Vector2i(0, 0), false)
	ids.clear()
	for e in s.menu_for(s.grid_cell_origin(Vector2i(1, 1)) + Vector2i(8, 8))["entries"]:
		ids.append(e["id"])
	eq(ids, [&"drop", &"equip", &"open", &"inspect"], "DROP, EQUIP, OPEN, INSPECT in his grid")
	ground.queue_free()
	s.queue_free()
	_reset()


func test_open_window() -> void:
	_reset()
	var s := _screen()
	var ground := _ground_pack(s)
	ground.contents.add(MEDKIT, 1)
	var m: Dictionary = s.menu_for(_ground_spot(s))
	s.menu_choose(&"open", m["target"])
	eq(s.windows().size(), 1, "one window")
	var w: Dictionary = s.windows()[0]
	var item_rect: Rect2i = m["target"]["rect"]
	check(not s.window_rect(w).intersects(item_rect.grow(-1)), "opens beside the pack, not over it")
	var r: Rect2i = s.window_rect(w)
	check(r.position.x >= 0 and r.end.x <= s._texels.x and r.position.y >= 0 and r.end.y <= s._texels.y, "on the canvas")
	# Its grid is the real one: hover, take, place.
	var origin: Vector2i = s.window_grid_origin(w)
	eq(s.hover_info(origin + Vector2i(8, 8))["def"], MEDKIT, "its items hover")
	# Opening it again only raises it.
	s.menu_choose(&"open", m["target"])
	eq(s.windows().size(), 1, "no duplicate")
	# SHIFT out of it lands in his grid; SHIFT from his grid goes back into it.
	s.shift_click(origin + Vector2i(8, 8))
	eq(ground.contents.items.size(), 0, "out of the pack")
	eq(_inv().grid.items[0].def, MEDKIT, "into his grid")
	s.shift_click(s.grid_cell_origin(_inv().grid.items[0].cell) + Vector2i(8, 8))
	eq(ground.contents.items.size(), 1, "SHIFT from his grid goes into the open pack")
	# Drag by the title bar: moves, stays on the canvas.
	var title: Rect2i = s.window_title_rect(w)
	check(s.window_press(title.position + Vector2i(6, 4)), "title grabbed")
	s.window_drag_to(Vector2i(-500, -500))
	eq(w["pos"], Vector2i.ZERO, "clamped to the canvas")
	s._win_drag = -1
	# The X closes it.
	check(s.window_press(_centre(s.window_close_rect(w))), "X pressed")
	eq(s.windows().size(), 0, "closed")
	ground.queue_free()
	s.queue_free()
	_reset()


func test_several_windows() -> void:
	_reset()
	var s := _screen()
	var a := ItemStack.new(PACK)
	var b := ItemStack.new(PACK)
	_inv().grid.place(a, Vector2i(0, 0), false)
	_inv().grid.place(b, Vector2i(4, 0), false)
	# Both menus first: a's window opens beside a, over b.
	var ma: Dictionary = s.menu_for(s.grid_cell_origin(Vector2i(0, 0)) + Vector2i(8, 8))
	var mb: Dictionary = s.menu_for(s.grid_cell_origin(Vector2i(4, 0)) + Vector2i(8, 8))
	s.menu_choose(&"open", ma["target"])
	check(s.vicinity_item_at(s.window_grid_origin(s.windows()[0])) == null and s.slot_at(s.window_grid_origin(s.windows()[0])) == &"", "a window hides what is under it")
	s.menu_choose(&"open", mb["target"])
	eq(s.windows().size(), 2, "two at once")
	eq(s.front_window_grid(), b.contents, "the last opened is in front")
	s.raise_window(0)
	eq(s.front_window_grid(), a.contents, "raised")
	# Dropping a pack out of his grid closes its window.
	_inv().grid.remove(a)
	s._prune_windows()
	eq(s.windows().size(), 1, "its window went with it")
	s.queue_free()
	_reset()


func test_equip_from_ground_swaps() -> void:
	_reset()
	var s := _screen()
	var worn: ItemStack = _inv().item_in(&"back")
	worn.contents.add(RATION, 1)
	var ground := _ground_pack(s)
	ground.contents.add(MEDKIT, 1)
	ground.position = Vector3(3, 0, 4)
	var new_grid: ItemGrid = ground.contents
	s.menu_choose(&"open", s.menu_for(_ground_spot(s))["target"])
	s.menu_choose(&"equip", s.menu_for(_ground_spot(s))["target"])
	eq(_inv().pack_grid(), new_grid, "the ground pack is worn, contents and all")
	eq(s.windows().size(), 0, "its window closed")
	var swapped: Node3D = null
	for n in (Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"world_item"):
		if n != ground and n.contents == worn.contents:
			swapped = n
	check(swapped != null, "the old pack lies on the ground with its ration")
	if swapped != null:
		eq(swapped.position, Vector3(3, 0, 4), "where the new one was")
		swapped.queue_free()
	s.queue_free()
	_reset()


func test_equip_from_grid_swaps() -> void:
	_reset()
	var s := _screen()
	var worn: ItemStack = _inv().item_in(&"back")
	var pack := ItemStack.new(PACK)
	_inv().grid.place(pack, Vector2i(2, 1), false)
	s.menu_choose(&"equip", s.menu_for(s.grid_cell_origin(Vector2i(2, 1)) + Vector2i(8, 8))["target"])
	eq(_inv().item_in(&"back"), pack, "worn")
	eq(_inv().grid.item_at(Vector2i(2, 1)), worn, "the old one took its grid spot")
	s.queue_free()
	_reset()


func test_mesh_builds() -> void:
	var m: ArrayMesh = BackpackMesh.build()
	eq(m.get_surface_count(), 5, "canvas, seam, leather, metal, thruster")
	var tris := 0
	for i in m.get_surface_count():
		tris += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	check(tris > 150 and tris < 1200, "low poly (%d tris)" % tris)
	var aabb := m.get_aabb()
	check(aabb.size.y > 0.6 and aabb.size.y < 0.8, "about 0.7 m tall with the thrusters (%.2f)" % aabb.size.y)
	check(aabb.size.x > 0.4 and aabb.size.x < 0.52, "about 0.4 m wide plus side pockets (%.2f)" % aabb.size.x)


func test_pilot_wears_it_from_the_slot() -> void:
	_reset()
	var p: Node3D = (load(PILOT_TSCN) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	check(p.is_backpack_on(), "on by default")
	check(p.backpack.pack.visible and p.backpack.pack.get_child_count() == 5 and p.backpack.straps.is_empty(), "the pack, no straps")
	_inv().unequip(&"back")
	check(not p.is_backpack_on() and not p.backpack.pack.visible, "off when the slot empties")
	p.queue_free()
	_reset()
