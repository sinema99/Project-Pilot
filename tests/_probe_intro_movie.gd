extends SceneTree

# Throwaway probe, WINDOWED: plays Intro_Movie through once on the real renderer and prints the
# frame times around each cut against the typical frame (docs/specs/intro-movie.md). Run:
#   godot --path . --script tests/_probe_intro_movie.gd

const AROUND := 4  # frames after each cut to report

var _movie: Node
var _deltas: PackedFloat64Array = []
var _cuts: Array[int] = []
var _last := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_movie = (load("res://Intro_Movie.tscn") as PackedScene).instantiate()
	_movie.shot_changed.connect(func(i: int) -> void: _cuts.append(_deltas.size()); print("cut to shot ", i + 1))
	root.add_child(_movie)
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	_deltas.append((now - _last) / 1000.0)
	_last = now
	if _movie.shot_index != 3:
		return false
	var flyover: AnimationPlayer = _movie.shots[3].get_node("AnimationPlayer")
	if flyover.is_playing():
		return false
	var sorted := _deltas.slice(_cuts[0] + 10)
	sorted.sort()
	print("frames %d, median %.1f ms, p99 %.1f ms, worst %.1f ms" % [sorted.size(),
			sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.99)], sorted[-1]])
	print("startup (under the black cover) worst %.1f ms" % _max(_deltas.slice(0, _cuts[0] + 1)))
	for c in _cuts.slice(1):
		print("cut at frame %d: %s ms" % [c, _deltas.slice(c - 1, c + AROUND)])
	return true


func _max(a: PackedFloat64Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m
