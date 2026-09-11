extends "res://tests/test_case.gd"

# Covers docs/specs/map-crease-ink.md.
#
# Nothing here can judge the look. --headless runs the dummy renderer, which parses shader
# source (so uniforms and their declared defaults are readable) but never compiles or draws
# anything. The look is judged by playing scenes/trial.tscn.
#
# What IS worth pinning is the wiring, because every one of these fails *silently* and
# leaves a game that still runs, just without lines:
#   - a shader that stopped parsing reports no uniforms rather than an error,
#   - a next_pass overwritten by hand drops a whole pass with no warning,
#   - and Godot stores a shader_parameter under a name no uniform claims without complaining
#     (see the set_shader_parameter("color", ...) note in scripts/rendering/apply_stylized.gd),
#     so a renamed dial goes quiet instead of red.

const SHADER_PATH := "res://shaders/cel/crease.gdshader"
const CREASE_PATH := "res://resources/cel_crease_material.tres"
const OUTLINE_PATH := "res://resources/cel_outline_material.tres"
const GROUND_PATH := "res://resources/cel_ground.tres"
const CHARACTER_PATH := "res://resources/cel_character.tres"

# Every dial the spec names, with the default the spec names. Expected values come from the
# spec, never from the file - a test that reads the value it is checking asserts nothing.
const DIALS := {
	"crease_angle_deg": 28.0,
	"max_depth_jump": 0.25,
	"convex_scale": 1.5,
	"line_width_px": 2.0,
	"fade_start_m": 45.0,
	"fade_end_m": 120.0,
	"ink_opacity": 1.0,
}

# Runtime load, not preload: preload of a missing path is a parse-time failure, which makes
# --script fall back to running the main scene and hang.
func _material(path: String) -> ShaderMaterial:
	return load(path) as ShaderMaterial

# The resource paths of `mat` and everything down its next_pass chain, `mat` included.
# Guarded against a cycle, which a hand-edited .tres can express and which would otherwise
# hang the suite rather than fail it.
func _chain(mat: Material) -> PackedStringArray:
	var out: PackedStringArray = []
	var node := mat
	while node != null and out.size() < 8:
		out.append(node.resource_path)
		node = node.next_pass
	return out

# --- the shader -----------------------------------------------------------

func test_shader_loads() -> void:
	check(load(SHADER_PATH) is Shader, "%s should load as a Shader" % SHADER_PATH)

func test_shader_exposes_every_dial() -> void:
	var names := shader_uniform_names(SHADER_PATH)
	check(not names.is_empty(), "the shader exposes no uniforms at all - it most likely failed to parse")
	for dial in DIALS:
		check(names.has(dial), "the shader should expose '%s'" % dial)

func test_dial_defaults_match_the_spec() -> void:
	for dial in DIALS:
		approx(declared_default_float(SHADER_PATH, dial), DIALS[dial], 0.0001,
				"'%s' should be declared with the spec's default" % dial)

# The colour is deliberately NOT a uniform on this shader. It reads the same
# `global uniform vec4 outline_color` the hull does, so the two blacks cannot drift apart.
func test_the_ink_colour_is_the_shared_global() -> void:
	var f := FileAccess.open(SHADER_PATH, FileAccess.READ)
	check(f != null, "%s should be readable" % SHADER_PATH)
	if f == null:
		return
	var src := f.get_as_text()
	check(src.contains("global uniform vec4 outline_color"),
			"the crease shader should take its colour from the shared outline_color global")
	check(not shader_uniform_names(SHADER_PATH).has("crease_color"),
			"the crease should not carry a colour of its own")

# The depth buffer is the whole technique - without it there is no crease test, and the
# hint is the one line that cannot be inferred from anything else in the file.
func test_the_shader_reads_the_depth_buffer() -> void:
	var f := FileAccess.open(SHADER_PATH, FileAccess.READ)
	check(f != null, "%s should be readable" % SHADER_PATH)
	if f == null:
		return
	check(f.get_as_text().contains("hint_depth_texture"),
			"the crease test reconstructs positions from the depth buffer")

# --- the material ---------------------------------------------------------

func test_crease_material_is_on_the_crease_shader() -> void:
	var mat := _material(CREASE_PATH)
	check(mat != null, "%s should load as a ShaderMaterial" % CREASE_PATH)
	if mat == null:
		return
	check(mat.shader != null, "the crease material should carry a shader")
	if mat.shader != null:
		eq(mat.shader.resource_path, SHADER_PATH, "the crease material should be on the crease shader")

# --- the chain ------------------------------------------------------------
#
# base -> crease -> hull. The order matters: the hull draws last and therefore over the
# crease, because the silhouette is the bolder line and nothing thin should sit on top of it.

func test_the_map_chain_is_base_then_crease_then_hull() -> void:
	var ground := _material(GROUND_PATH)
	check(ground != null, "%s should load" % GROUND_PATH)
	if ground == null:
		return
	var chain := _chain(ground)
	eq(chain.size(), 3, "the map should be drawn in three passes, got: %s" % str(chain))
	if chain.size() != 3:
		return
	eq(chain[0], GROUND_PATH, "the first pass is the flat colour")
	eq(chain[1], CREASE_PATH, "the crease ink is the second pass")
	eq(chain[2], OUTLINE_PATH, "the hull silhouette stays last, drawing over the crease")

# The regression this exists for: adding the crease by replacing the hull rather than by
# inserting in front of it. The map would lose its outer edge against the sky and nothing
# would say so.
func test_the_map_still_gets_its_hull_outline() -> void:
	var ground := _material(GROUND_PATH)
	check(ground != null, "%s should load" % GROUND_PATH)
	if ground == null:
		return
	check(_chain(ground).has(OUTLINE_PATH), "the map must still reach the hull outline pass")

# "Only on the map" is enforced by material assignment and by nothing else, so this is the
# assertion that carries the whole scoping claim.
func test_characters_do_not_get_crease_ink() -> void:
	var character := _material(CHARACTER_PATH)
	check(character != null, "%s should load" % CHARACTER_PATH)
	if character == null:
		return
	var chain := _chain(character)
	check(not chain.has(CREASE_PATH),
			"characters keep base + hull only; the crease pass is the map's, got: %s" % str(chain))
	check(chain.has(OUTLINE_PATH), "characters should still get their hull outline")
