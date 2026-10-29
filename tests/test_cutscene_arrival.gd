extends "res://tests/test_case.gd"

# docs/specs/cutscene-arrival.md. The shot's length and fade, the locked camera, the base laid out
# where the reference frame has it (towers and decks back on their table points), the base built
# into the land rather than floating over it, and the beacons blinking.
# How it looks is judged by eye (tests/_probe_arrival_shot.gd).

const SCENE := "res://scenes/cutscene_arrival.tscn"


func _shot() -> ArrivalShot:
	var s: ArrivalShot = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func test_arrival_root_length_and_fade() -> void:
	var s := _shot()
	eq(s.name, "Arrival", "root node")
	approx(s.shot_length(), 12.0, 1e-4, "10 s hold + 2 s fade")
	approx(s.animation_player.get_animation(ArrivalShot.SHOT).length, 12.0, 1e-4, "animation length")
	check(s.animation_player.is_playing(), "autoplays")
	eq(s.fade_at(0.0), 0.0, "clear at the start")
	eq(s.fade_at(10.0), 0.0, "clear until 10 s")
	approx(s.fade_at(11.0), 0.5, 1e-4, "half way at 11 s")
	eq(s.fade_at(12.0), 1.0, "black at the end")
	s.apply(12.0)
	approx(s.fade_rect.color.a, 1.0, 1e-4, "the fade rect is black at the end")
	s.free()


func test_arrival_camera_is_locked() -> void:
	var s := _shot()
	var start := s.camera.global_transform
	for t in [2.0, 7.5, 12.0]:
		s.apply(t)
		check(s.camera.global_transform.is_equal_approx(start), "camera unmoved at %.1f s" % t)
	approx(s.camera.fov, s.fov, 1e-4, "camera fov")
	check(s.camera.global_basis.z.y > 0.2, "looks down")
	s.free()


func test_arrival_base_sits_on_its_table_points() -> void:
	var s := _shot()
	eq(s.base.cap_tops.size(), ArrivalShot.TOWERS.size(), "five towers")
	for i in ArrivalShot.TOWERS.size():
		var row: Dictionary = ArrivalShot.TOWERS[i]
		var p := s.frame_point(s.base.cap_tops[i])
		check(p.distance_to(Vector2(row.u, row.v)) < 0.1, "%s cap at %s, wants (%s, %s)" % [row.name, p, row.u, row.v])
		check(s.base.cap_tops[i].y > s.land.height(s.base.cap_tops[i].x, s.base.cap_tops[i].z) + 40.0,
				"%s stands up out of the land" % row.name)
	for deck: Dictionary in ArrivalShot.DECKS:
		var outline := s.base.deck_outline(deck)
		var p := s.frame_point(Vector3(outline[0].x, deck.top, outline[0].y))
		check(p.distance_to(deck.outline[0]) < 0.1, "%s corner back on its frame point (%s)" % [deck.name, p])
	s.free()


func test_arrival_base_is_built_into_the_ridge() -> void:
	var s := _shot()
	# The lower deck's front edge sits just over the land, not on stilts (spec R1): the forest slope
	# climbs to within a few tens of metres of its underside band.
	var lower: Dictionary = ArrivalShot.DECKS[0]
	var outline := s.base.deck_outline(lower)
	var front := outline[3].lerp(outline[4], 0.5)
	var under: float = lower.top - lower.thick - lower.band
	var gap := under - s.land.height(front.x, front.y)
	check(gap > 0.0 and gap < 45.0, "lower deck front %.0f m over the land" % gap)
	# The snow hill behind the deck's left half rises above the deck.
	var hill: Dictionary = ArrivalShot.HILLS[0]
	var top := s.at_distance(hill.u, hill.v, hill.distance)
	check(s.land.height(top.x, top.z) > lower.top, "hill behind the deck rises above it")
	check(s.get_node("Forest").count > 1000, "a forest stands (%d trees)" % s.get_node("Forest").count)
	s.free()


func test_arrival_beacons_blink_out_of_step() -> void:
	var s := _shot()
	check(s.base.beacon_spots.size() >= 10, "beacons on the caps and the top tier")
	eq(s.beacon_at(0.0, 0.0), 1.0, "lit at the start of its period")
	eq(s.beacon_at(s.beacon_on + 0.01, 0.0), 0.0, "then dark")
	eq(s.beacon_at(s.beacon_period, 0.0), 1.0, "lit again a period later")
	var lit := 0
	for i in s.base.beacon_spots.size():
		lit += int(s.beacon_at(0.0, fposmod(i * 0.61, s.beacon_period)))
	check(lit < s.base.beacon_spots.size(), "not all lit at once")
	s.free()


func test_arrival_outpost_stands_on_its_peak() -> void:
	var s := _shot()
	# Spec R3: the sister outpost top right, on a far peak, its deck just over the land.
	var o := ArrivalShot.OUTPOST
	var p := s.frame_point(s.base.outpost_top)
	check(p.distance_to(Vector2(o.u, o.v)) < 0.1, "outpost deck at %s, wants (%s, %s)" % [p, o.u, o.v])
	check(p.x > 60.0 and p.y < 30.0, "top right")
	var top := s.base.outpost_top
	var gap := top.y - ArrivalBase.OUTPOST_THICK - s.land.height(top.x, top.z)
	check(gap > 0.0 and gap < 60.0, "outpost deck %.0f m over its peak" % gap)
	check(s.base.has_node("OutpostTower1"), "outpost towers built")
	s.free()


func test_arrival_forest_follows_the_terrain() -> void:
	var s := _shot()
	var land := s.land
	# Spec R2-2: the terrain decides. Gentle low slopes carry forest; above the treeline, on rock
	# faces, on ridgelines and on cleared ground it does not.
	check(land.forest_score(-300.0, 0.85, 0.0, 0.0) > 0.9, "low gentle slope is forest")
	eq(land.forest_score(land.treeline + 10.0, 0.85, 0.0, 0.0), 0.0, "none above the treeline")
	eq(land.forest_score(-300.0, 0.4, 0.0, 0.0), 0.0, "none on a rock face")
	eq(land.forest_score(-300.0, 0.85, 0.3, 0.0), 0.0, "none on a ridgeline")
	eq(land.forest_score(-300.0, 0.85, 0.0, 1.0), 0.0, "none on cleared ground")
	# Avalanche chutes run down the fall line.
	check(land.chute_paths.size() >= 10, "%d chutes" % land.chute_paths.size())
	for path in land.chute_paths:
		var top := land.height(path[0].x, path[0].y)
		var bottom := land.height(path[path.size() - 1].x, path[path.size() - 1].y)
		check(top - bottom > 40.0, "chute falls %.0f m" % (top - bottom))
	s.free()


func test_arrival_base_has_an_apron_and_a_road() -> void:
	var s := _shot()
	var land := s.land
	# Spec R1/R2-1: cleared ground just past the Lower deck's front edge, shade at the wall's foot.
	var outline := s.base.deck_outline(ArrivalShot.DECKS[0])
	var front := outline[3].lerp(outline[4], 0.5)
	var c := land.clear_at(front.x, front.y + 10.0)
	check(c.x > 0.9, "apron cleared in front of the deck (%.2f)" % c.x)
	check(land.clear_at(front.x, front.y - 25.0).y > 0.5, "the wall's foot is in shade")
	# Spec R2-8: the road leaves a portal on the deck's front, in frame, and is cleared.
	var p := s.frame_point(land.portal)
	check(p.x > 20.0 and p.x < 60.0 and p.y > 60.0 and p.y < 100.0, "portal in frame at %s" % p)
	var out := Vector2(land.portal.x, land.portal.z) + land.portal_out * 30.0
	check(land.clear_at(out.x, out.y).x > 0.9, "road cleared out of the portal")
	s.free()


func test_arrival_roofs_and_towers_have_jobs() -> void:
	var s := _shot()
	# Spec R2-3: pads on the Lower deck's roof, a hangar on its front fascia.
	eq(s.base.pads.size(), ArrivalShot.PADS.size(), "pads")
	for pad in s.base.pads:
		approx(pad.y, ArrivalShot.DECKS[0].top, 1e-3, "pad on the Lower deck")
	check(s.frame_point(s.base.hangar).y > 60.0, "hangar on the front fascia")
	# Spec R2-4: the exhaust tower's stacks feed the plume; the comms mast's light is on its tip.
	check(s.base.plume_spots.size() == 5, "five stacks")
	check(s.clouds.has_node("plume%d" % (ArrivalClouds.CARDS.size())), "a steam plume")
	var comms: Vector3 = s.base.cap_tops[0]
	var tip := 0.0
	for b in s.base.beacon_spots:
		if Vector2(b.x, b.z).distance_to(Vector2(comms.x, comms.z)) < 1.0:
			tip = maxf(tip, b.y - comms.y)
	check(tip > ArrivalShot.TOWERS[0].cap, "beacon on the mast tip, %.0f m up" % tip)
	s.free()


func test_arrival_has_its_own_post() -> void:
	var s := _shot()
	# Spec R2-7: the arrival's CinemaPost is its own, so tuning it leaves the other shots alone.
	var effects := s.world_environment.compositor.compositor_effects
	eq(effects.size(), 2, "depth composite + cinema post")
	check(effects[0] is DepthComposite, "depth composite first")
	var own := load("res://resources/cinema_post_arrival.tres") as CinemaPost
	approx(effects[1].aberration, own.aberration, 1e-6, "the arrival's own post")
	approx(effects[1].vignette_strength, own.vignette_strength, 1e-6, "its vignette")
	check(own.aberration < CinemaPost.new().aberration, "less edge CA than the default")
	s.free()
