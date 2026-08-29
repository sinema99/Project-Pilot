extends SceneTree

# Headless test runner.
#   godot --headless --path . --script tests/run_tests.gd [-- <name-filter>]

const TEST_DIR := "res://tests/"

func _initialize() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = user_args[0]

	var total := 0
	var checks := 0
	var failures: PackedStringArray = []

	for file_name in _discover():
		var script: GDScript = load(TEST_DIR + file_name)
		if script == null:
			failures.append("%s\n      failed to load test script" % file_name)
			continue
		var case: RefCounted = script.new()
		for method_name in _test_methods(case):
			if filter != "" and not method_name.contains(filter):
				continue
			total += 1
			case.begin("%s::%s" % [file_name, method_name])
			case.call(method_name)
			case.end()
		checks += case.checks
		failures.append_array(case.failures)

	print("")
	if failures.is_empty():
		print("PASS  %d tests, %d checks" % [total, checks])
		quit(0)
	else:
		for f in failures:
			print("  FAIL  %s" % f)
		print("")
		print("FAIL  %d failed checks across %d tests (%d checks run)" % [failures.size(), total, checks])
		quit(1)

func _discover() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(f)
	out.sort()
	return out

func _test_methods(case: RefCounted) -> PackedStringArray:
	var seen: Dictionary = {}
	var out: PackedStringArray = []
	for m in case.get_method_list():
		var n := String(m.name)
		if n.begins_with("test_") and not seen.has(n):
			seen[n] = true
			out.append(n)
	out.sort()
	return out
