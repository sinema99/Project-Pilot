extends "res://tests/test_case.gd"

# The hologram pause menu's rules, asserted against docs/specs/pilot9-hologram-pause.md. The look
# (colour, glow, ring fit, framing) can only be judged in play; everything with a number is here.

const RIG := "res://scripts/pilot9_hologram.gd"

func _rig() -> GDScript:
	return load(RIG) as GDScript

func test_mode_is_flat_unless_every_condition_holds() -> void:
	var r := _rig()
	check(r.hologram_mode(true, true, true, true), "all four true -> hologram")
	check(not r.hologram_mode(false, true, true, true), "setting off -> flat")
	check(not r.hologram_mode(true, false, true, true), "no host (main menu) -> flat")
	check(not r.hologram_mode(true, true, false, true), "pilot hidden (aboard EXIA) -> flat")
	check(not r.hologram_mode(true, true, true, false), "not the current camera -> flat")

func test_shot_is_behind_and_to_his_right() -> void:
	var r := _rig()
	var head := Vector3(2, 1.6, 3)
	# Facing +Z: his right is -X (the rig's convention), behind is -Z.
	var p: Vector3 = r.shot_position(head, Vector3(0, 0, 1), 1.1, 0.55, 0.15)
	approx(p.z, head.z - 1.1, 0.001, "behind him")
	approx(p.x, head.x - 0.55, 0.001, "to his right (-X when facing +Z)")
	approx(p.y, head.y + 0.15, 0.001, "a little above the head")
	# Facing +X: his right is +Z.
	var q: Vector3 = r.shot_position(head, Vector3(1, 0, 0), 1.1, 0.55, 0.15)
	approx(q.x, head.x - 1.1, 0.001, "behind, facing +X")
	approx(q.z, head.z + 0.55, 0.001, "right, facing +X")

func test_a_tilted_pose_gives_the_same_shot() -> void:
	var r := _rig()
	var head := Vector3(0, 1.6, 0)
	var level: Vector3 = r.shot_position(head, Vector3(0, 0, 1), 1.1, 0.55, 0.15)
	var tilted: Vector3 = r.shot_position(head, Vector3(0, 0.6, 1).normalized(), 1.1, 0.55, 0.15)
	check(level.is_equal_approx(tilted), "the height of his facing never tips the shot")

func test_swing_takes_the_short_way() -> void:
	var r := _rig()
	var from := deg_to_rad(170.0)
	var to := deg_to_rad(-190.0)
	var halfway: float = r.swing_yaw(from, to, 0.5)
	# 170 and -190 are 0 degrees apart, so halfway must still be 170, not 0 (the long way).
	approx(absf(angle_difference(halfway, from)), 0.0, 0.001, "no slow 360")
	var mid: float = r.swing_yaw(deg_to_rad(170.0), deg_to_rad(-160.0), 0.5)
	approx(absf(angle_difference(mid, deg_to_rad(185.0))), 0.0, 0.001, "20 degrees, across the seam")

func test_wall_clamp_never_enters_his_head() -> void:
	var r := _rig()
	var head := Vector3.ZERO
	var target := Vector3(0, 0, -1.2)
	var blocked: Vector3 = r.swept_position(head, head, target, 0.05, 0.45)
	approx(blocked.distance_to(head), 0.45, 0.001, "clamped to the minimum distance")
	var clear: Vector3 = r.swept_position(head, head, target, 1.0, 0.45)
	check(clear.is_equal_approx(target), "an open sweep reaches the shot")
	var half: Vector3 = r.swept_position(head, head, target, 0.6, 0.45)
	approx(half.distance_to(head), 0.72, 0.001, "stops where the sweep did")

func test_ray_to_uv_centre_edges_and_miss() -> void:
	var r := _rig()
	var size := Vector2(2.0, 1.0)
	var panel := Transform3D(Basis(), Vector3(0, 0, -3))
	var centre = r.ray_to_uv(Vector3.ZERO, Vector3(0, 0, -1), panel, size)
	check(centre != null and (centre as Vector2).is_equal_approx(Vector2(0.5, 0.5)), "centre -> (0.5, 0.5)")
	var corner = r.ray_to_uv(Vector3(-1, 0.5, 0), Vector3(0, 0, -1), panel, size)
	check(corner != null and (corner as Vector2).is_equal_approx(Vector2(0.0, 0.0)), "top-left corner -> (0, 0)")
	check(r.ray_to_uv(Vector3(5, 0, 0), Vector3(0, 0, -1), panel, size) == null, "a miss is null")
	var edge = r.ray_to_uv(Vector3(5, 0, 0), Vector3(0, 0, -1), panel, size, true)
	check(edge != null and is_equal_approx((edge as Vector2).x, 1.0), "a release off the panel clamps to the edge")
	check(r.ray_to_uv(Vector3.ZERO, Vector3(0, 0, 1), panel, size) == null, "behind the ray is null")

func test_turned_panel_keeps_its_corners() -> void:
	var r := _rig()
	var size := Vector2(2.0, 1.25)
	var panel := Transform3D(Basis(Vector3.UP, deg_to_rad(-17.0)), Vector3(1, 0.3, -2.5))
	for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var world := panel * Vector3(c.x * 0.99 * size.x * 0.5, c.y * 0.99 * size.y * 0.5, 0.0)
		var origin := Vector3(0, 0, 0)
		var uv = r.ray_to_uv(origin, (world - origin).normalized(), panel, size)
		check(uv != null, "a ray through the corner lands on the turned panel")
		if uv != null:
			var want := Vector2(0.5 + c.x * 0.495, 0.5 - c.y * 0.495)
			check((uv as Vector2).is_equal_approx(want), "corner maps to the matching UV %s" % c)

func test_input_waits_for_the_open_to_settle() -> void:
	var r := _rig()
	check(not r.input_live(0.3, true), "blocked while the panel is still moving")
	check(not r.input_live(0.6, true), "blocked just before it is usable")
	check(r.input_live(1.0, true), "live at t = 1")
	check(not r.input_live(1.0, false), "never live while closing")

func test_beam_flares_then_holds_a_faint_rest() -> void:
	var r := _rig()
	check(is_zero_approx(r.beam_strength(0.0, 0.1)), "dark at t = 0")
	check(is_equal_approx(r.beam_strength(0.35, 0.1), 1.0), "full at the flare peak")
	check(r.beam_strength(0.5, 0.1) > 0.1, "still easing down mid-way")
	check(is_equal_approx(r.beam_strength(0.85, 0.1), 0.1), "settles on the rest level")
	check(is_equal_approx(r.beam_strength(0.85, 0.1), r.beam_strength(2.0, 0.1)), "and holds")

func test_setting_row_defaults_off() -> void:
	var found := false
	for row in load("res://scripts/settings.gd").DEFS:
		if row[0] == &"hologram_menu":
			found = true
			eq(row[3][row[4]], "off", "HOLOGRAM MENU defaults off")
	check(found, "the HOLOGRAM MENU row exists")

func test_shaders_compile() -> void:
	for path in ["hologram_panel", "hologram_beam", "hologram_dim", "hologram_stencil"]:
		var sh := load("res://shaders/ui/%s.gdshader" % path) as Shader
		check(sh != null, "%s loads" % path)

# The menu window is 1280 x 800 in both modes, and the panel maps 1:1 onto it.
func test_panel_resolution_matches_the_menu_window() -> void:
	var rig = load("res://scripts/pilot9_hologram.gd").new()
	eq(rig.panel_resolution, Vector2i(1280, 800), "the hologram viewport is the menu window's size")
	rig.free()
