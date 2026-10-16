extends "res://tests/test_case.gd"

# docs/specs/intro-movie.md. The order, the hand-off on each shot's `finished`, the hold at the end,
# skip / restart keys, parking the other shots, and the storm fog global following the live shot.
# Whether the cuts hitch is measured windowed (tests/_probe_intro_movie.gd).

const SCENE := "res://Intro_Movie.tscn"


func _movie() -> Node:
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	m.autoplay = false
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	m.begin()
	return m


func _key(m: Node, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	m._input(e)


func _live_only(m: Node, index: int) -> void:
	for i in m.shots.size():
		var shot: Node = m.shots[i]
		if i == index:
			check(shot.get_parent() == m, "shot %d is live in the movie" % (i + 1))
			check(shot.process_mode == Node.PROCESS_MODE_INHERIT, "live shot %d processes" % (i + 1))
		else:
			check(shot.get_parent() is SubViewport, "shot %d is parked in its viewport" % (i + 1))
			check(shot.process_mode == Node.PROCESS_MODE_DISABLED, "parked shot %d is paused" % (i + 1))


func test_order_is_the_four_shots() -> void:
	var m := _movie()
	var names: Array[String] = []
	for s: Node in m.shots:
		names.append(s.scene_file_path.get_file())
	eq(names, ["cutscene_intro_space.tscn", "cockpit.tscn", "cutscene_descent.tscn",
			"cutscene_flyover.tscn"], "shot order")
	eq(m.shot_index, 0, "opens on shot 1")
	_live_only(m, 0)
	m.free()


func test_each_finish_hard_cuts_to_the_next_and_the_last_holds() -> void:
	var m := _movie()
	for i in 3:
		m.shots[i].finished.emit()
		eq(m.shot_index, i + 1, "shot %d finished -> shot %d" % [i + 1, i + 2])
		_live_only(m, i + 1)
	var ap: AnimationPlayer = m.shots[3].get_node("AnimationPlayer")
	check(ap.is_playing() and ap.current_animation_position < 0.1, "flyover plays from its start")
	m.shots[3].finished.emit()
	eq(m.shot_index, 3, "flyover's end holds")
	m.free()


func test_a_parked_shots_late_finish_is_ignored() -> void:
	var m := _movie()
	m.shots[2].finished.emit()
	eq(m.shot_index, 0, "descent finishing while parked does nothing")
	m.free()


func test_keys_skip_and_restart() -> void:
	var m := _movie()
	_key(m, KEY_RIGHT)
	_key(m, KEY_RIGHT)
	eq(m.shot_index, 2, "two rights -> descent")
	_key(m, KEY_LEFT)
	eq(m.shot_index, 1, "left -> cockpit")
	_key(m, KEY_RIGHT)
	_key(m, KEY_RIGHT)
	_key(m, KEY_RIGHT)
	eq(m.shot_index, 3, "right stops at the flyover")
	_key(m, KEY_R)
	eq(m.shot_index, 0, "R -> shot 1")
	_live_only(m, 0)
	_key(m, KEY_LEFT)
	eq(m.shot_index, 0, "left stops at shot 1")
	for s: Node in m.shots:
		check(not s.is_processing_input(), "%s's own R / Esc is off" % s.name)
	m.free()


func test_start_shot() -> void:
	var m: Node = (load(SCENE) as PackedScene).instantiate()
	m.autoplay = false
	m.start_shot = 3
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	m.begin()
	eq(m.shot_index, 2, "start_shot 3 opens on the descent")
	m.free()


# The fog itself is a shader global, which the headless dummy renderer doesn't keep.
func test_storm_follows_the_live_shot() -> void:
	var m := _movie()
	eq(m.live_storms.size(), 0, "intro space: no storm, fog off")
	m.go_to(2)
	eq(m.live_storms, [m.shots[2].get_node("Storm")], "descent's own storm applied")
	m.go_to(3)
	eq(m.live_storms, [m.shots[3].get_node("Storm")], "flyover's own storm applied")
	m.go_to(1)
	eq(m.live_storms.size(), 0, "cockpit: no storm, fog off")
	m.free()


func test_live_shot_uses_its_own_camera() -> void:
	var m := _movie()
	for i in 4:
		m.go_to(i)
		var cam := m.get_viewport().get_camera_3d()
		check(cam != null and m.shots[i].is_ancestor_of(cam), "shot %d's camera is current" % (i + 1))
	m.free()
