extends "res://tests/test_case.gd"

# Covers the 2026-11-12 interaction panel: one shared PS1 prompt floating beside whoever the
# camera follows, which EXIA now bids into like the doors. See docs/specs/interaction-panel.md.
#
# A --script run steps no physics and draws nothing, so the placement and the look are checked
# by tests/_probe_interaction_panel.gd screenshots. What this fences is the bookkeeping that
# fails quietly: which source wins, that EXIA no longer draws its own, and the anchors.

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const FACE_SCRIPT := preload("res://scripts/ui/interaction_panel_face.gd")
const PANEL_SHADER_PATH := "res://shaders/ui/interaction_panel.gdshader"
const MechScene := preload("res://scenes/mech.tscn")


func _prompt() -> Node:
	var p: Node = (load(PROMPT_SCRIPT.SCENE_PATH) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	return p


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


func test_the_prompt_is_a_3d_node_not_a_canvas_layer() -> void:
	var p := _prompt()
	check(p is Node3D, "the prompt lives in the world now")
	check(p.is_in_group(PROMPT_SCRIPT.GROUP), "and is found by its group")
	check(p.get_node_or_null("Panel") is MeshInstance3D, "it draws one quad")
	check(p.get_node_or_null("Face") is SubViewport, "from a tiny face viewport")
	_drop(p)


func test_closest_bid_wins_and_its_word_shows() -> void:
	var p := _prompt()
	var near := Node.new()
	var far := Node.new()
	p.offer(far, 3.0, &"interact", "PILOT")
	p.offer(near, 1.0, &"interact", "OPEN")
	p.commit()
	check(p.current_source == near, "the nearer source is offered")
	eq(p.shown_text(), "OPEN", "with its word")
	check(p.is_showing(), "and the panel opens")
	p.commit()
	check(p.current_source == null, "no bids next frame: nothing offered")
	check(not p.is_showing(), "and it folds")
	eq(p.shown_text(), "OPEN", "keeping its word while it folds")
	near.free()
	far.free()
	_drop(p)


func test_clear_now_folds_the_panel() -> void:
	var p := _prompt()
	var src := Node.new()
	p.offer(src, 1.0, &"interact", "OPEN")
	p.commit()
	p.clear_now()
	check(p.current_source == null, "a spent button stops being offered at once")
	check(not p.is_showing(), "and the panel folds")
	src.free()
	_drop(p)


func test_the_face_viewport_fits_the_word() -> void:
	var p := _prompt()
	var src := Node.new()
	p.offer(src, 1.0, &"interact", "EXIT...")
	p.commit()
	var vp: SubViewport = p.get_node("Face")
	eq(vp.size.x, FACE_SCRIPT.width_for("EXIT..."), "the face is as wide as the word needs")
	eq(vp.size.y, FACE_SCRIPT.HEIGHT, "and one fixed height")
	check(FACE_SCRIPT.width_for("PILOT") > FACE_SCRIPT.width_for("OPEN") - 8,
		"widths come from the font, not a constant")
	src.free()
	_drop(p)


func test_the_shader_keeps_the_ps1_switches() -> void:
	var names := shader_uniform_names(PANEL_SHADER_PATH)
	for u in ["snap_enabled", "snap_lines", "affine_enabled", "colour_15bit", "plate_coverage"]:
		check(names.has(u), "the panel shader has %s" % u)
	approx(declared_default_float(PANEL_SHADER_PATH, "snap_lines"), 720.0, 0.001,
		"snaps on a fine 720-line grid")


func test_exia_draws_no_prompt_of_its_own() -> void:
	var exia := MechScene.instantiate()
	check(exia.get_node_or_null("UI/Prompt") == null, "the old bottom-centre row is gone")
	exia.free()


func test_exia_words_follow_its_state() -> void:
	var exia: Node3D = MechScene.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(exia)
	exia._update_prompt()
	eq(exia.prompt_text, "", "nobody near: nothing to offer")
	var body := Node3D.new()
	exia.player_in_range = body
	exia._update_prompt()
	eq(exia.prompt_text, "PILOT", "a pilot in reach is offered PILOT")
	exia.embark_left = 1.0
	exia._update_prompt()
	eq(exia.prompt_text, "", "nothing while she climbs")
	exia.embark_left = 0.0
	exia.player_in_range = null
	exia.pilot = body
	exia._update_prompt()
	eq(exia.prompt_text, "", "aboard: nothing until F goes down (hold to exit, 2026-11-12)")
	exia.exit_hold = 0.0
	exia._update_prompt()
	eq(exia.prompt_text, "EXIT", "holding F: EXIT")
	exia.exit_hold = -1.0
	exia.pilot = null
	body.free()
	_drop(exia)


func test_exia_anchors_the_panel_beside_its_chest() -> void:
	var exia: Node3D = MechScene.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(exia)
	var a: Dictionary = exia.interaction_anchor()
	check(a.point.y > 4.0, "up at the chest, not the feet")
	eq(a.side, 1.0, "camera-right")
	check(a.offset > 1.0, "far enough out to clear the hull")
	_drop(exia)
