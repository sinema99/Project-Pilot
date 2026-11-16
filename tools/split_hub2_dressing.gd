extends SceneTree

# ONE-OFF (2026-11-14): moves hub2's Dressing subtree out of scenes/hub2.tscn.
#   godot --headless --path . --script tools/split_hub2_dressing.gd -- src      -> scenes/hub2_dressing_src.tscn
#   godot --headless --path . --script tools/split_hub2_dressing.gd -- rewire   -> hub2.tscn gets scenes/hub2_dressing.scn
const HUB := "res://scenes/hub2.tscn"
const SRC := "res://scenes/hub2_dressing_src.tscn"
const BAKED := "res://scenes/hub2_dressing.scn"

func _initialize() -> void:
	var mode := OS.get_cmdline_user_args()[0]
	var hub := (load(HUB) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var dressing := hub.get_node("Dressing")
	if mode == "src":
		hub.remove_child(dressing)
		for d in dressing.find_children("*", "", true, true):
			if d.owner == hub:
				d.owner = dressing
		dressing.owner = null
		var p := PackedScene.new()
		var err := p.pack(dressing)
		if err == OK:
			err = ResourceSaver.save(p, SRC)
		print("split src: ", error_string(err), " nodes ", dressing.find_children("*", "", true, true).size())
		dressing.free()
	else:
		var idx := dressing.get_index()
		hub.remove_child(dressing)
		dressing.free()
		var baked := (load(BAKED) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		baked.name = "Dressing"
		hub.add_child(baked)
		hub.move_child(baked, idx)
		baked.owner = hub
		var p := PackedScene.new()
		var err := p.pack(hub)
		if err == OK:
			err = ResourceSaver.save(p, HUB)
		print("rewire: ", error_string(err))
	hub.free()
	quit()
