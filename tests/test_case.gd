extends RefCounted

# Minimal assertion base for the headless test runner. Each test file extends
# this and defines methods named `test_*`; run_tests.gd discovers and calls them.

var failures: PackedStringArray = []
var checks := 0
var _current := ""
var _checks_at_begin := 0

func begin(name: String) -> void:
	_current = name
	_checks_at_begin = checks

# A test method that raises mid-way stops silently in GDScript, leaving no
# failure behind. Requiring at least one assertion per test turns that into a
# visible red instead of a false green.
func end() -> void:
	if checks == _checks_at_begin:
		fail("no assertions ran - the test most likely errored out (see the backtrace above)")

func fail(msg: String) -> void:
	failures.append("%s\n      %s" % [_current, msg])

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fail(msg)

func eq(actual: Variant, expected: Variant, msg: String) -> void:
	checks += 1
	if actual != expected:
		fail("%s\n      expected: %s\n      actual:   %s" % [msg, str(expected), str(actual)])

func approx(actual: float, expected: float, tol: float, msg: String) -> void:
	checks += 1
	if absf(actual - expected) > tol:
		fail("%s\n      expected: %f (+/- %f)\n      actual:   %f" % [msg, expected, tol, actual])

# --- shared helpers -------------------------------------------------------

# Returns the uniform names a .gdshader exposes. Empty means the shader failed
# to compile (Godot's dummy renderer still parses shader code headlessly).
func shader_uniform_names(path: String) -> PackedStringArray:
	var sh: Shader = load(path)
	if sh == null:
		return []
	var names: PackedStringArray = []
	for u in sh.get_shader_uniform_list():
		names.append(String(u.name))
	return names

# Reads a uniform's *declared* default out of the shader source.
#
# Godot's dummy (headless) renderer does not retain shader parameter defaults,
# so RenderingServer.shader_get_parameter_default() is unavailable here. The
# declaration in the .gdshader is the artifact that actually ships, so it is
# what gets asserted. Expected values come from the spec, never from the file.
func declared_default(path: String, uniform_name: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var src := f.get_as_text()
	var re := RegEx.new()
	var err := re.compile(r"uniform\s+\w+\s+" + uniform_name + r"\s*(:[^=;]*)?=\s*([^;]+);")
	if err != OK:
		return ""
	var m := re.search(src)
	if m == null:
		return ""
	return m.get_string(2).strip_edges()

func declared_default_float(path: String, uniform_name: String) -> float:
	var raw := declared_default(path, uniform_name)
	return raw.to_float() if raw.is_valid_float() else NAN
