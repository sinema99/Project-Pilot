class_name ItemDef
extends Resource

# What an item IS: one .tres per kind, shared by every copy. A copy in a grid or on the ground is
# an ItemStack / WorldItem holding one of these. See docs/specs/inventory.md.

@export var id: StringName = &""
## Shown in the info strip and on the item block. Uppercase by convention.
@export var display_name := ""
## Footprint in grid cells, upright (W x H).
@export var size := Vector2i.ONE
## 1 = does not stack.
@export var max_stack := 1
## The placeholder block colour in the grid and the placeholder box colour on the ground.
@export var color := Color(0.5, 0.5, 0.5)
## Optional real model for the ground. Null = a box sized from `size`.
@export var world_mesh: Mesh = null
## True = cargo: it can only live in a vehicle's stash, never the pilot's own grid, and a pilot
## moves it by carrying it in his hands. See docs/specs/pilot9-crate-carry.md.
@export var mech_only := false
## Which equipment slot wears it: &"head", &"body", &"legs" or &"weapon" (either weapon slot);
## &"" = not wearable. See docs/specs/equipment-slots.md.
@export var slot: StringName = &""
## A container's own grid (W x H), or ZERO for anything that holds nothing. Each copy carries its
## own grid on its ItemStack / WorldItem. See docs/specs/pilot9-backpack.md.
@export var container_size := Vector2i.ZERO
## A weapon's in-hand definition (what 1 / 2 draw). Null for anything that is not a weapon.
@export var held_item: HeldItem = null


## Colour-coding and Sort order: &"food", &"medical", &"ammo", &"gear" or &"junk".
@export var category: StringName = &"gear"
## The Inspect card's body text.
@export var description := ""
## Kilograms each, shown on the Inspect card when above 0.
@export var weight := 0.0

## Sort order, first to last.
const CATEGORIES: Array[StringName] = [&"medical", &"food", &"ammo", &"gear", &"junk"]


## Index into CATEGORIES (unknown = last).
func category_rank() -> int:
	var i := CATEGORIES.find(category)
	return i if i >= 0 else CATEGORIES.size()


func is_container() -> bool:
	return container_size.x > 0 and container_size.y > 0


func stackable() -> bool:
	return max_stack > 1
