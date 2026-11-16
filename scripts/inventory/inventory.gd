extends Node

# Registered as the `Inventory` autoload. Holds the player's grid for the session (it survives
# scene changes, nothing is written to disk) and answers the world questions the screen and the
# ground items ask: who is the player, what is near him, take this, drop that.
# See docs/specs/inventory.md.

const WorldItemScript := preload("res://scripts/inventory/world_item.gd")

const PLAYER_GROUP := &"player"
const WORLD_ITEM_GROUP := &"world_item"

## The player's one container.
const GRID_W := 10
const GRID_H := 6

## Vicinity: metres from his feet (flat + vertical), and the ray's start height on him.
const VICINITY_RADIUS := 2.5
const VICINITY_EYE := 1.2
## F pickup: metres, and the half-angle off the camera's flat forward.
const PICKUP_REACH := 2.0
const PICKUP_CONE_DEG := 60.0
## The vicinity box is this many cells wide.
const VICINITY_W := 10
## Dropped items land this far in front of him, plus a little scatter.
const DROP_AHEAD := 0.6
const DROP_SCATTER := 0.25

## EXIA's stash: the pilot's overflow storage. See docs/specs/mech-stash.md.
const STASH_W := 10
const STASH_H := 12

const MECH_GROUP := &"mech"

## --- equipment (docs/specs/equipment-slots.md) -------------------------------------------------
## What the pilot wears and carries. One set, shared by both pilots; pilot9 reads it through
## `equipment_changed`. A slot holds one ItemStack, or nothing.
signal equipment_changed

const SLOT_HEAD := &"head"
const SLOT_BODY := &"body"
const SLOT_LEGS := &"legs"
const SLOT_BACK := &"back"
const SLOT_WEAPON_1 := &"weapon_1"
const SLOT_WEAPON_2 := &"weapon_2"
const EQUIP_SLOTS: Array[StringName] = [SLOT_HEAD, SLOT_BODY, SLOT_LEGS, SLOT_BACK, SLOT_WEAPON_1, SLOT_WEAPON_2]
const WEAPON_SLOTS: Array[StringName] = [SLOT_WEAPON_1, SLOT_WEAPON_2]

## A fresh game: hat, coat and an empty backpack worn, rifle on 1, revolver on 2.
const DEFAULT_LOADOUT := {
	&"head": "res://resources/items/cowboy_hat.tres",
	&"body": "res://resources/items/trench_coat.tres",
	&"back": "res://resources/items/backpack.tres",
	&"weapon_1": "res://resources/items/rifle_weapon.tres",
	&"weapon_2": "res://resources/items/revolver_weapon.tres",
}
## Every item that can be saved, by its `id`.
const ITEM_PATHS := [
	"res://resources/items/ration.tres",
	"res://resources/items/battery.tres",
	"res://resources/items/medkit.tres",
	"res://resources/items/rifle_crate.tres",
	"res://resources/items/crate.tres",
	"res://resources/items/cowboy_hat.tres",
	"res://resources/items/trench_coat.tres",
	"res://resources/items/backpack.tres",
	"res://resources/items/staff_weapon.tres",
	"res://resources/items/rifle_weapon.tres",
	"res://resources/items/revolver_weapon.tres",
]

const SAVE_VERSION := 2

## Whether the loadout is written to / read from `save_path`. Off under --headless (the tests).
var persist := true
var save_path := "user://loadout.json"
## slot name -> ItemStack.
var equipment := {}
var _save_queued := false

## TEST CONTENT (docs/specs/mech-stash.md, decision 10): what the stash starts with, so there is
## something to move. Delete when real loot exists.
const STASH_TEST_SEED := [
	"res://resources/items/rifle_crate.tres",
	"res://resources/items/medkit.tres",
	"res://resources/items/medkit.tres",
	"res://resources/items/battery.tres",
]

var grid := ItemGrid.new(GRID_W, GRID_H)
var stash := ItemGrid.new(STASH_W, STASH_H)

## The mech whose stash the inventory screen should open in STASH mode, set by open_stash() just
## before the screen opens and cleared when it closes. Null = the normal pilot screen.
var stash_mech: Node3D = null


const ItemIconsScript := preload("res://scripts/inventory/item_icons.gd")

var _icons: Node = null


func _ready() -> void:
	_icons = ItemIconsScript.new()
	_icons.name = "ItemIcons"
	add_child(_icons)


## The rendered icon for `def`, or null (not drawn yet, or headless).
func icon_for(def: ItemDef) -> Texture2D:
	return _icons.icon_for(def) if _icons != null else null


func _init() -> void:
	seed_stash(stash)
	seed_equipment()
	if persist and not DisplayServer.get_name() == "headless":
		load_loadout()
		grid.changed.connect(save_soon)
		equipment_changed.connect(save_soon)
		equipment_changed.connect(_watch_pack)
		_watch_pack()


## Fills `g` with the test seed. Static so a test can seed a fresh grid.
static func seed_stash(g: ItemGrid) -> void:
	for path: String in STASH_TEST_SEED:
		var def := load(path) as ItemDef
		if def != null:
			g.add(def, 1)


## Every other vehicle's stash (speeders - docs/specs/speeder1.md), by the vehicle's key. Session
## only like `stash`: a scene change keeps them, quitting loses them.
var vehicle_stashes := {}


## The stash kept for `key`, made `w` x `h` and filled from `seed_paths` the first time it is asked
## for.
func vehicle_stash(key: StringName, w: int, h: int, seed_paths: Array) -> ItemGrid:
	if not vehicle_stashes.has(key):
		var g := ItemGrid.new(w, h)
		for path: String in seed_paths:
			var def := load(path) as ItemDef
			if def != null:
				g.add(def, 1)
		vehicle_stashes[key] = g
	return vehicle_stashes[key]


## The grid the stash screen shows for `vehicle`: its own `stash` if it carries one, else EXIA's.
func stash_of(vehicle: Node) -> ItemGrid:
	if vehicle != null and vehicle.get(&"stash") is ItemGrid:
		return vehicle.get(&"stash")
	return stash


## Opens the inventory screen in STASH mode for `mech`. False if a screen is already up.
func open_stash(mech: Node3D) -> bool:
	var ui := get_node_or_null(^"/root/UI")
	if ui == null or not ui.stack.is_empty() or not ui.shell_enabled or get_tree().paused:
		return false
	stash_mech = mech
	ui.open(&"inventory")
	return true


## The mech the player is driving and may open the stash of right now, or null.
func piloted_mech() -> Node3D:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(MECH_GROUP):
		if node is Node3D and node.get("pilot") != null and node.has_method(&"can_open_stash"):
			return node
	return null


# --- equipment ---------------------------------------------------------------------------------

static func is_weapon_slot(slot: StringName) -> bool:
	return WEAPON_SLOTS.has(slot)


## Whether `def` may be worn in `slot`. The two weapon slots take any weapon.
static func slot_accepts(slot: StringName, def: ItemDef) -> bool:
	if def == null or def.slot == &"" or not EQUIP_SLOTS.has(slot):
		return false
	return def.slot == &"weapon" if is_weapon_slot(slot) else def.slot == slot


func item_in(slot: StringName) -> ItemStack:
	return equipment.get(slot, null)


## The worn backpack's grid, or null with nothing on his back. docs/specs/pilot9-backpack.md.
func pack_grid() -> ItemGrid:
	var worn := item_in(SLOT_BACK)
	return worn.contents if worn != null else null


## Where picked-up things go, in order: his own grid, then the worn pack.
func carry_grids() -> Array[ItemGrid]:
	var out: Array[ItemGrid] = [grid]
	var packed := pack_grid()
	if packed != null:
		out.append(packed)
	return out


## Puts the whole `stack` (a container, contents and all) in the first free spot of `g`. False
## when there is no room or `g` refuses it.
static func place_anywhere(g: ItemGrid, stack: ItemStack) -> bool:
	if g == null or not g.accepts(stack.def):
		return false
	var spot := g.find_free(stack.def.size)
	return not spot.is_empty() and g.place(stack, spot["cell"], spot["rotated"])


## Adds `count` of `def` across `grids` in order (a container goes in whole, with `contents`).
## Returns how many went in.
static func add_to(grids: Array[ItemGrid], def: ItemDef, count: int, contents: ItemGrid = null) -> int:
	if def.is_container():
		for g in grids:
			if place_anywhere(g, ItemStack.new(def, 1, contents)):
				return 1
		return 0
	var left := count
	for g in grids:
		if left <= 0:
			break
		left -= g.add(def, left)
	return count - left

## Wears `stack` in `slot` and returns whatever was there (null if nothing). Refuses (returns
## `stack` itself, nothing changes) when the slot does not take it.
func equip(slot: StringName, stack: ItemStack) -> ItemStack:
	if stack == null or not slot_accepts(slot, stack.def):
		return stack
	var old: ItemStack = equipment.get(slot, null)
	equipment[slot] = stack
	equipment_changed.emit()
	return old


## Takes whatever is in `slot` off and returns it (null if empty).
func unequip(slot: StringName) -> ItemStack:
	var old: ItemStack = equipment.get(slot, null)
	if old != null:
		equipment.erase(slot)
		equipment_changed.emit()
	return old


## The default loadout, without touching the grid.
func seed_equipment() -> void:
	equipment.clear()
	for slot in DEFAULT_LOADOUT:
		var def := load(DEFAULT_LOADOUT[slot]) as ItemDef
		if def != null:
			equipment[slot] = ItemStack.new(def, 1)


func _def_by_id(id: String) -> ItemDef:
	for path: String in ITEM_PATHS:
		var def := load(path) as ItemDef
		if def != null and String(def.id) == id:
			return def
	return null


## The grid and the slots as plain data.
func loadout_to_dict() -> Dictionary:
	var worn := {}
	for slot in equipment:
		var st := equipment[slot] as ItemStack
		worn[String(slot)] = {"id": String(st.def.id)}
		if st.contents != null:
			worn[String(slot)]["contents"] = _grid_to_list(st.contents)
	return {"version": SAVE_VERSION, "grid": _grid_to_list(grid), "equipment": worn}


## A grid's items as plain data; a container's own contents nest inside its entry.
static func _grid_to_list(g: ItemGrid) -> Array:
	var items: Array = []
	for it in g.items:
		var e := {"id": String(it.def.id), "count": it.count, "x": it.cell.x, "y": it.cell.y,
			"rot": it.rotated}
		if it.contents != null:
			e["contents"] = _grid_to_list(it.contents)
		items.append(e)
	return items


## Fills `g` from `_grid_to_list` data. Unknown ids are skipped; a bad spot falls back to the first
## free one.
func _list_into_grid(list: Array, g: ItemGrid) -> void:
	for e: Dictionary in list:
		var def := _def_by_id(str(e.get("id", "")))
		if def == null or not g.accepts(def):
			continue
		var stack := ItemStack.new(def, int(e.get("count", 1)))
		if stack.contents != null:
			_list_into_grid(e.get("contents", []), stack.contents)
		if not g.place(stack, Vector2i(int(e.get("x", 0)), int(e.get("y", 0))), bool(e.get("rot", false))):
			if def.is_container():
				place_anywhere(g, stack)
			else:
				g.add(def, stack.count)


## Replaces the grid and the slots with `data`. Unknown ids and bad spots are skipped.
func loadout_from_dict(data: Dictionary) -> void:
	for it in grid.items.duplicate():
		grid.remove(it)
	equipment.clear()
	_list_into_grid(data.get("grid", []), grid)
	var worn: Dictionary = data.get("equipment", {})
	for slot_name: String in worn:
		var def := _def_by_id(str((worn[slot_name] as Dictionary).get("id", "")))
		if def != null and slot_accepts(StringName(slot_name), def):
			var stack := ItemStack.new(def, 1)
			if stack.contents != null:
				_list_into_grid((worn[slot_name] as Dictionary).get("contents", []), stack.contents)
			equipment[StringName(slot_name)] = stack
	# One-time (save version 2, 2026-11-14): the rifle took weapon 1 from the staff. An older save's
	# staff moves into the grid so it is not lost.
	if int(data.get("version", 1)) < 2:
		var on_one: ItemStack = equipment.get(SLOT_WEAPON_1, null)
		var rifle := _def_by_id("rifle")
		if rifle != null and on_one != null and String(on_one.def.id) == "staff":
			equipment[SLOT_WEAPON_1] = ItemStack.new(rifle, 1)
			grid.add(on_one.def, 1)
	equipment_changed.emit()


func save_loadout() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(loadout_to_dict()))


## Reads `save_path` if it is there; a fresh game keeps the default loadout.
func load_loadout() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (parsed is Dictionary):
		return false
	loadout_from_dict(parsed)
	return true


## The worn pack's grid saves like the main one.
func _watch_pack() -> void:
	var packed := pack_grid()
	if packed != null and not packed.changed.is_connected(save_soon):
		packed.changed.connect(save_soon)


## One write per burst of changes.
func save_soon() -> void:
	if _save_queued or not persist:
		return
	_save_queued = true
	_write_later.call_deferred()


func _write_later() -> void:
	_save_queued = false
	save_loadout()


## The pilot being played, or null (main menu, cutscene scenes, headless tests).
func player() -> Node3D:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node is Node3D and node.get("controlled") != false and (node as Node3D).is_visible_in_tree():
			return node
	return null


## Takes as much of a ground item as fits. Frees it when all of it went in. Returns how many.
func take(item: Node) -> int:
	if item == null or not is_instance_valid(item) or item.def == null or item.def.mech_only:
		return 0
	var n := add_to(carry_grids(), item.def, item.count, item.get(&"contents"))
	item.count -= n
	if item.count <= 0:
		item.queue_free()
		# Out of the group at once: a rescan this frame must not list it.
		item.remove_from_group(WORLD_ITEM_GROUP)
	return n


func can_take(item: Node) -> bool:
	if item == null or item.def == null or item.def.mech_only:
		return false
	for g in carry_grids():
		if g.capacity_for(item.def) > 0:
			return true
	return false


## Takes the whole `stack` out of the grid (if it is in it) and puts it on the ground in front of
## `pilot`. Returns the WorldItem, or null with no pilot or scene.
func drop(stack: ItemStack, pilot: Node3D) -> Node3D:
	if stack == null or pilot == null or not pilot.is_inside_tree():
		return null
	for g in carry_grids():
		g.remove(stack)
	var item: Node3D = WorldItemScript.new()
	item.def = stack.def
	item.count = stack.count
	item.contents = stack.contents
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else pilot.get_parent()
	host.add_child(item)
	var forward := Vector3.FORWARD
	if pilot.get("character") is Node3D:
		var yaw: float = (pilot.get("character") as Node3D).rotation.y
		forward = Vector3(sin(yaw), 0.0, cos(yaw))
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * DROP_SCATTER
	var at := pilot.global_position + forward * DROP_AHEAD + scatter
	item.global_position = floor_below(pilot, at)
	item.rotation.y = randf() * TAU
	return item


## The floor under `at` (one ray down from half a metre above), else `at` itself.
func floor_below(context: Node3D, at: Vector3) -> Vector3:
	var space := context.get_world_3d().direct_space_state if context.get_world_3d() != null else null
	if space == null:
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 3.0)
	if context is CollisionObject3D:
		q.exclude = [(context as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else at


## Every ground item within VICINITY_RADIUS of `pilot` with a clear ray from his chest, nearest
## first.
func vicinity(pilot: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if pilot == null or not pilot.is_inside_tree():
		return out
	var space := pilot.get_world_3d().direct_space_state
	var eye := pilot.global_position + Vector3.UP * VICINITY_EYE
	var found: Array = []
	for node in get_tree().get_nodes_in_group(WORLD_ITEM_GROUP):
		var item := node as Node3D
		if item == null or item.is_queued_for_deletion() or item.get("def") == null:
			continue
		var d := pilot.global_position.distance_to(item.global_position)
		if d > VICINITY_RADIUS:
			continue
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(eye, item.global_position + Vector3.UP * 0.05)
			q.exclude = [(pilot as CollisionObject3D).get_rid()] if pilot is CollisionObject3D else []
			if not space.intersect_ray(q).is_empty():
				continue
		found.append([d, item])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for pair in found:
		out.append(pair[1])
	return out


## Auto-pack for the vicinity box: each size in order goes to the first free spot of a
## `width`-wide, endless grid, upright before rotated. Returns, per size, {"cell", "rotated"}.
## A size wider than `width` either way gets the row below everything, upright and clipped.
static func pack(sizes: Array, width: int) -> Array:
	var rows := 0
	for s: Vector2i in sizes:
		rows += maxi(s.x, s.y)
	var g := ItemGrid.new(width, maxi(rows, 1))
	var out: Array = []
	for s: Vector2i in sizes:
		var spot := g.find_free(s)
		if spot.is_empty():
			spot = {"cell": Vector2i(0, rows), "rotated": false}
		else:
			var dummy := ItemStack.new(_size_def(s))
			g.place(dummy, spot["cell"], spot["rotated"])
		out.append(spot)
	return out


static func _size_def(s: Vector2i) -> ItemDef:
	var d := ItemDef.new()
	d.size = s
	return d
