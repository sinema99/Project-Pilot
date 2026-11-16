extends "res://tests/test_case.gd"

# AIRFRAME in trial (docs/specs/airframe-trial.md). How it LOOKS is the user's call in play and
# tests/_probe_airframe_shot.gd's; this fences what would fail quietly: a save stuck on RETRO, the
# 75 % not reaching the shaders, a map left wearing PS1 materials or Jetpack's sky after a switch,
# a glow turned into a matte block, and RETRO missing from maps that have no AIRFRAME.

const SETTINGS := preload("res://scripts/settings.gd")
const AIRFRAME := preload("res://scripts/rendering/airframe_look.gd")
const RETRO_LOOK := preload("res://scripts/rendering/retro_look.gd")
const CEL := preload("res://shaders/cel/cel-shader-base.gdshader")
const GRID := preload("res://shaders/metre_grid.gdshader")
const ENV := preload("res://resources/airframe_trial_environment.tres")
const JETPACK_ENV := preload("res://resources/airframe_environment.tres")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _box(parent: Node, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi

func _cel(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CEL
	m.set_shader_parameter(&"color", c)
	return m

## A map with a sun at 10 deg, a cel box, a grid box, a glow, a body-carried box, and the look.
func _scene() -> Dictionary:
	var parent := Node3D.new()
	var env_node := WorldEnvironment.new()
	env_node.environment = Environment.new()
	env_node.compositor = Compositor.new()
	parent.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-10, 30, 0)
	sun.light_energy = 0.7
	sun.shadow_blur = 0.6
	parent.add_child(sun)
	var cel_box := _box(parent, _cel(Color(0.8, 0.1, 0.1)))
	var grid := ShaderMaterial.new()
	grid.shader = GRID
	grid.set_shader_parameter(&"base_color", Color(0.3, 0.4, 0.5))
	var grid_box := _box(parent, grid)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow_box := _box(parent, glow)
	var body := CharacterBody3D.new()
	parent.add_child(body)
	var carried := _box(body, _cel(Color(0.1, 0.8, 0.1)))
	var look: AirframeLook = AIRFRAME.new()
	look.sun = sun
	look.intensity = 0.75
	parent.add_child(look)
	_tree().root.add_child(parent)
	return {"parent": parent, "look": look, "env": env_node, "sun": sun, "cel": cel_box,
		"grid": grid_box, "glow": glow_box, "carried": carried}

func _ps1(mi: MeshInstance3D) -> ShaderMaterial:
	var m := mi.get_surface_override_material(0) as ShaderMaterial
	return m if m != null and m.shader == AirframeLook.SURFACE_SHADER else null

# --- the setting -----------------------------------------------------------------

func test_a_save_from_before_airframe_moves_to_it_once() -> void:
	var old := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"look": "retro"})
	eq(old[&"look"], "airframe", "a pre-AIRFRAME save loads AIRFRAME")
	var chosen := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"look": "retro",
			SETTINGS.AIRFRAME_FLAG: true})
	eq(chosen[&"look"], "retro", "a save from now on keeps the LOOK the player picked")

func test_maps_without_airframe_show_retro() -> void:
	check(SETTINGS.retro_shows("airframe", false), "no AirframeLook: RETRO stands in")
	check(not SETTINGS.retro_shows("airframe", true), "trial: AIRFRAME, not RETRO")
	check(SETTINGS.retro_shows("retro", true) and SETTINGS.retro_shows("composite", true), "RETRO looks")

# --- 75 % ------------------------------------------------------------------------

func test_intensity_moves_every_effect_a_quarter_to_neutral() -> void:
	var s := _scene()
	var look: AirframeLook = s.look
	look.set_active(true)
	var m := _ps1(s.cel)
	approx(m.get_shader_parameter(&"shade_dark"), 0.8875, 1e-4, "shade dark 0.85 -> 0.89")
	approx(m.get_shader_parameter(&"shade_light"), 1.075, 1e-4, "shade light 1.10 -> 1.075")
	approx(m.get_shader_parameter(&"jitter_chance"), 0.09, 1e-4, "jitter 0.12 -> 0.09")
	approx(look.snap_lines_for(m), 0.0, 1e-3, "static world: no snap")
	check(m.get_shader_parameter(&"snap_enabled") == false, "static world snap off")
	approx(m.get_shader_parameter(&"texels_per_metre"), 16.0, 1e-4, "pixel size stays the rule")
	var f: ShaderMaterial = look._filter_material
	approx(f.get_shader_parameter(&"stripe_strength"), 0.105, 1e-4, "stripes")
	approx(f.get_shader_parameter(&"fringe_px"), 0.75, 1e-4, "fringe")
	approx(f.get_shader_parameter(&"fringe_edge_boost"), 1.125, 1e-4, "fringe edge boost")
	approx(f.get_shader_parameter(&"saturation"), 1.15, 1e-4, "saturation")
	approx(f.get_shader_parameter(&"contrast"), 1.09, 1e-4, "contrast")
	var lift: Vector3 = f.get_shader_parameter(&"lift")
	var gain: Vector3 = f.get_shader_parameter(&"gain")
	approx(lift.z, 0.015, 1e-4, "lift")
	approx(gain.x, 1.015, 1e-4, "gain")
	s.parent.free()

func test_jetpack_stays_the_full_reference_and_trial_is_75() -> void:
	var jet := (load("res://Jetpack.tscn") as PackedScene).get_state()
	var trial := (load("res://scenes/trial.tscn") as PackedScene).instantiate()
	var look := trial.get_node_or_null(^"AirframeLook") as AirframeLook
	check(look != null, "trial has an AirframeLook")
	if look != null:
		approx(look.intensity, 0.75, 1e-4, "trial at 75 %")
	trial.free()
	for i in jet.get_node_count():
		if jet.get_node_name(i) == &"JetpackLook":
			for p in jet.get_node_property_count(i):
				check(jet.get_node_property_name(i, p) != &"intensity", "Jetpack keeps intensity 1.0")

# --- shadows ---------------------------------------------------------------------

## docs/specs/airframe-trial-shadows.md: trial's own copy with a stronger, greyer fill so shadows sit
## near half the sunlit brightness; Jetpack keeps the original dark one.
func test_trial_shadows_are_lifted_and_jetpack_keeps_its_own() -> void:
	var fill := ENV.ambient_light_color * ENV.ambient_light_energy
	var old := JETPACK_ENV.ambient_light_color * JETPACK_ENV.ambient_light_energy
	check(fill.get_luminance() > old.get_luminance() * 2.0, "trial fill well above Jetpack's")
	check(fill.r / fill.b > old.r / old.b, "a less saturated blue")
	check(fill.b > fill.r, "still cool")
	var sky := ENV.sky.sky_material as ProceduralSkyMaterial
	var jet_sky := JETPACK_ENV.sky.sky_material as ProceduralSkyMaterial
	check(sky.sky_top_color.is_equal_approx(jet_sky.sky_top_color)
		and sky.sky_horizon_color.is_equal_approx(jet_sky.sky_horizon_color), "same sky")
	approx(ENV.fog_depth_begin, JETPACK_ENV.fog_depth_begin, 1e-4, "same fog")
	var jet := (load("res://Jetpack.tscn") as PackedScene).instantiate()
	var we := jet.find_children("*", "WorldEnvironment", true, false)
	check(we.size() == 1 and (we[0] as WorldEnvironment).environment == JETPACK_ENV, "Jetpack keeps the original")
	jet.free()

# --- swapping --------------------------------------------------------------------

func test_on_swaps_what_it_owns_and_off_gives_it_all_back() -> void:
	var s := _scene()
	var look: AirframeLook = s.look
	var cel_mat: Material = (s.cel as MeshInstance3D).get_surface_override_material(0)
	var glow_mat: Material = (s.glow as MeshInstance3D).get_surface_override_material(0)
	var old_env: Environment = s.env.environment
	var old_comp: Compositor = s.env.compositor
	var old_basis: Basis = (s.sun as DirectionalLight3D).global_basis
	look.set_active(true)
	var cel_ps1 := _ps1(s.cel)
	check(cel_ps1 != null, "cel box wears PS1")
	if cel_ps1 != null:
		eq(cel_ps1.get_shader_parameter(&"mapping"), 0, "the level is world-projected")
		var c: Color = cel_ps1.get_shader_parameter(&"albedo_color")
		approx(c.r, 0.8, 1e-4, "in its own colour")
	var grid_ps1 := _ps1(s.grid)
	check(grid_ps1 != null, "metre grid wears PS1")
	if grid_ps1 != null:
		var g: Color = grid_ps1.get_shader_parameter(&"albedo_color")
		approx(g.b, 0.5, 1e-4, "in its base colour")
	check((s.glow as MeshInstance3D).get_surface_override_material(0) == glow_mat, "glows keep theirs")
	var carried := _ps1(s.carried)
	check(carried != null and carried.get_shader_parameter(&"mapping") == 1,
		"a box riding a body is object-projected")
	check(s.env.environment == ENV and s.env.compositor == null, "trial's AIRFRAME environment, no compositor")
	var towards := (s.sun as DirectionalLight3D).global_basis.z
	approx(rad_to_deg(asin(towards.y)), 45.0, 0.01, "sun 45 deg up")
	var flat_old := Vector2(old_basis.z.x, old_basis.z.z).normalized()
	var flat_new := Vector2(towards.x, towards.z).normalized()
	approx(flat_old.dot(flat_new), 1.0, 1e-4, "on the map's own bearing")
	approx((s.sun as DirectionalLight3D).light_energy, 1.6, 1e-4, "Jetpack's sun")
	check(look.filter_visible(), "screen filter up")

	look.set_active(false)
	check((s.cel as MeshInstance3D).get_surface_override_material(0) == cel_mat, "cel back")
	check(s.env.environment == old_env and s.env.compositor == old_comp, "environment back")
	check((s.sun as DirectionalLight3D).global_basis.is_equal_approx(old_basis), "sun back")
	approx((s.sun as DirectionalLight3D).light_energy, 0.7, 1e-4, "sun energy back")
	approx((s.sun as DirectionalLight3D).shadow_blur, 0.6, 1e-4, "sun blur back")
	check(not look.filter_visible(), "filter gone")
	s.parent.free()

func test_key_5_turns_the_surfaces_off_in_place() -> void:
	var s := _scene()
	var look: AirframeLook = s.look
	look.set_active(true)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_5
	e.pressed = true
	look._unhandled_input(e)
	check(_ps1(s.cel) == null, "5: own materials back")
	check(look._label.visible, "label flashes")
	look._unhandled_input(e)
	check(_ps1(s.cel) != null, "5 again: PS1 again")
	look.set_active(false)
	look._unhandled_input(e)
	check(look.look_enabled, "keys do nothing while another LOOK is on")
	s.parent.free()

func test_nodes_arriving_while_on_are_swapped() -> void:
	var s := _scene()
	var look: AirframeLook = s.look
	look.set_active(true)
	var late := _box(s.parent, _cel(Color(0.2, 0.2, 0.9)))
	look._swap_late(late)
	check(_ps1(late) != null, "late node swapped")
	look.set_active(false)
	check(_ps1(late) == null, "and given back")
	s.parent.free()

func test_settings_switch_hands_over_between_retro_and_airframe() -> void:
	var settings: Node = _tree().root.get_node(^"Settings")
	var saved: Variant = settings.get_value(&"look")
	settings.set_value(&"look", "retro")
	var s := _scene()
	var retro: RetroLook = RETRO_LOOK.new()
	s.parent.add_child(retro)
	retro.apply_look(true)
	settings.set_value(&"look", "airframe")
	check(s.look.active and not retro.pixel, "AIRFRAME on, RETRO off")
	check(_ps1(s.cel) != null, "PS1 sits on the cel original, not a RETRO twin")
	settings.set_value(&"look", "composite")
	check(not s.look.active and retro.pixel and retro.composite, "COMPOSITE back")
	settings.set_value(&"look", saved)
	s.parent.free()
