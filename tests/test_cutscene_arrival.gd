extends "res://tests/test_case.gd"

# docs/specs/cutscene-arrival.md. The shot's length and fade, the locked camera, the base laid out
# where the reference frame has it (towers and decks back on their table points), the base built
# into the land rather than floating over it, and since revision 5 abandoned: no lights, no craft,
# broken, overgrown, and since revision 6 nothing alive moving (no birds).
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
	# The snow hill behind the deck's left half rises above the deck (behind it since spec R4-1).
	var hill: Dictionary = ArrivalShot.HILLS[0]
	var top := s.at_distance(hill.u, hill.v, hill.distance)
	check(s.land.height(top.x, top.z) > lower.top, "hill behind the deck rises above it")
	check(s.get_node("Forest").count > 1000, "a forest stands (%d trees)" % s.get_node("Forest").count)
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


func test_arrival_abandoned() -> void:
	var s := _shot()
	var b := s.base
	# Spec R5-0: no beacons, no craft, no pads, no plume, nothing plowed; the hangar mouth stays.
	eq(s.find_children("Beacon*", "", true, false).size(), 0, "no beacons")
	for key in ["plowed", "accent", "craft"]:
		check(not b._mats.has(key), "no %s material" % key)
	eq(s.clouds.find_children("plume*", "", true, false).size(), 0, "no steam plume")
	check(s.frame_point(b.hangar).y > 60.0, "hangar mouth still on the front fascia")
	# Spec R5-3: the collapse hole is in the Lower deck's roof, in frame, about 50 m across.
	var lower := b.deck_outline(ArrivalShot.DECKS[0])
	check(b.hole != Vector3.INF and Geometry2D.is_point_in_polygon(Vector2(b.hole.x, b.hole.z), lower), "hole in the Lower deck")
	var across := ArrivalBase._area(b.hole_outline)
	check(across > PI * 18.0 * 18.0 and across < PI * 32.0 * 32.0, "hole %.0f m2" % across)
	# Spec R5-2: RightTower's rim a third gone, the others only bitten, the comms mast snapped.
	check(b.rim_loss.RightTower > 0.2 and b.rim_loss.RightTower < 0.45, "RightTower rim %.2f gone" % b.rim_loss.RightTower)
	for name in ["LeftTower", "CentreTower", "RightWide", "FarTower"]:
		check(b.rim_loss[name] > 0.0 and b.rim_loss[name] < 0.08, "%s rim %.3f bitten" % [name, b.rim_loss[name]])
	var comms: Dictionary = ArrivalShot.TOWERS[0]
	check(b.mast_top - b.cap_tops[0].y < comms.cap * 0.8, "comms mast snapped (%.0f m up)" % (b.mast_top - b.cap_tops[0].y))
	check(b.rim_loss.has("OutpostTower1") and b.rim_loss.OutpostTower1 > 0.2, "outpost's tallest cap broken")
	# Spec R5-7: 3-5 bites per main deck, the right extension's sagging slab among them.
	for deck: Dictionary in ArrivalShot.DECKS:
		var n := 0
		for bite in b.bites:
			n += int(bite.deck == deck.name)
		check(n >= 3 and n <= 5, "%s: %d bites" % [deck.name, n])
	check(b.bites.any(func(x: Dictionary) -> bool: return x.slump and x.deck == "Right"), "a sagging slab on the right extension")
	check(not b.rubble.is_empty(), "rubble under the big bites")
	s.free()


func test_arrival_overgrown() -> void:
	var s := _shot()
	var g := s.get_node("Growth") as ArrivalGrowth
	# Spec R5-3: about a third of the low roofs grow, ~15% of the upper tiers.
	for deck: Dictionary in ArrivalShot.DECKS:
		var c: float = g.coverage.get(deck.name, 0.0)
		if deck.top <= 0.0:
			check(c > 0.3 and c < 0.4, "%s roof %.2f grown" % [deck.name, c])
		else:
			check(c > 0.1 and c < 0.2, "%s roof %.2f grown" % [deck.name, c])
	check(g.roof_clumps > 1000, "%d roof clumps" % g.roof_clumps)
	check(g.slot_clumps > 20, "%d scrub clumps up through the structure" % g.slot_clumps)
	# R5b: moss and scrub on the building, but every tree stands on the land.
	var off_land := 0
	for t: Transform3D in g._trees:
		var p := t.origin + Vector3.UP * 0.4
		if absf(p.y - s.land.height(p.x, p.z)) > 2.0:
			off_land += 1
	eq(off_land, 0, "trees standing on the building")
	# Spec R5-4: curtains on the walls, the left tower's shaft listed as the most covered.
	check(g.curtains > 300, "%d curtains" % g.curtains)
	var left_cover := 0.0
	for f in s.base.walls:
		left_cover = maxf(left_cover, f.cover)
	approx(left_cover, 0.75, 1e-6, "the left tower carries the most")
	# Spec R5-5: the road and the power cut grown back with young trees.
	check(g.young_trees > 100, "%d young trees" % g.young_trees)
	check(g.has_node("Trees") and g.has_node("Curtains"), "growth meshes")
	s.free()


func test_arrival_moss_lines_up() -> void:
	var s := _shot()
	var b := s.base
	# Spec R6-1: shaft growth only in the bays between the ribs, rim fringes stop at the lower rim's
	# foot, the skybridge's growth follows its sag.
	var shafts := 0
	var rims := 0
	for f in b.walls:
		if not f.has("kind"):
			continue
		var i := -1
		for k in ArrivalShot.TOWERS.size():
			if ArrivalShot.TOWERS[k].name == f.tower:
				i = k
		var top: Vector3 = b.cap_tops[i]
		var c := Vector2(top.x, top.z)
		var r: float = ArrivalShot.TOWERS[i].cap
		if f.kind == &"shaft":
			shafts += 1
			for k in b.ribs:
				var ray := c + Vector2.from_angle(TAU * k / b.ribs) * r * 4.0
				check(Geometry2D.segment_intersects_segment(c, ray, f.a, f.b) == null, "%s shaft bay clear of rib %d" % [f.tower, k])
		else:
			rims += 1
			check(f.top - f.bottom <= (b.rim_height + b.gap_height + b.lower_rim_height) * r + 0.01,
					"%s rim fringe stops at the lower rim" % f.tower)
	check(shafts >= 8 * 2, "%d shaft bays" % shafts)
	check(rims > 0, "%d rim faces" % rims)
	check(b.walls.any(func(f: Dictionary) -> bool: return f.get("sag", 0.0) > 0.0), "skybridge growth sags")
	s.free()


func test_arrival_no_birds() -> void:
	var s := _shot()
	# Spec R6: the flock is gone.
	check(not s.has_node("Birds"), "no flock")
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


func test_arrival_structure_pass() -> void:
	var s := _shot()
	var b := s.base
	# Spec R3-1: the left tower stands down the slope, its footing well under the deck, not on a knoll.
	var left := b.cap_tops[0]
	var ground := s.land.height(left.x, left.z)
	check(ground < ArrivalShot.DECKS[0].top - 100.0, "left tower's ground %.0f m, under the deck" % ground)
	# Spec R3-2: the skybridge runs from the Lower deck into the left tower's shaft.
	eq(b.skybridge.size(), 2, "skybridge built")
	var lower := b.deck_outline(ArrivalShot.DECKS[0])
	check(Geometry2D.is_point_in_polygon(Vector2(b.skybridge[0].x, b.skybridge[0].z), lower), "bridge lands in the deck")
	check(Vector2(b.skybridge[1].x, b.skybridge[1].z).distance_to(Vector2(left.x, left.z)) < ArrivalShot.TOWERS[0].shaft,
			"bridge enters the shaft")
	check(b.has_node("Skybridge"), "skybridge mesh")
	# Spec R3-6: the power line has pylons down the cut, and the fuel farm stands on the plant deck.
	check(b.pylons >= 2, "%d pylons" % b.pylons)
	check(b.fuel_farm != Vector3.INF, "fuel farm placed")
	var right := b.deck_outline(ArrivalShot.DECKS[1])
	check(Geometry2D.is_point_in_polygon(Vector2(b.fuel_farm.x, b.fuel_farm.z), right), "fuel farm on the plant deck")
	check(s.frame_point(b.fuel_farm).x < 100.0, "fuel farm in frame")
	# Spec R3-8: small parts read by tone, so their materials carry no crease ink; massing keeps it.
	var fine := b._mats.fine_wall as ShaderMaterial
	var glass := b._mats.glass as ShaderMaterial
	check(fine.next_pass == null, "fine parts have no ink")
	check(glass.next_pass != null, "the glazing band is inked like the massing")
	s.free()


func test_arrival_revision_4() -> void:
	var s := _shot()
	var land := s.land
	# Spec R4-1: the hill behind the Lower deck no longer comes up through its roof (or Mid's).
	for i in [0, 2]:
		var deck: Dictionary = ArrivalShot.DECKS[i]
		var poly := s.base.deck_outline(deck)
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		var worst := -INF
		for gx in 40:
			for gz in 40:
				var p := box.position + box.size * Vector2((gx + 0.5) / 40.0, (gz + 0.5) / 40.0)
				if Geometry2D.is_point_in_polygon(p, poly):
					worst = maxf(worst, land.height(p.x, p.y))
		check(worst < deck.top - 5.0, "%s: land %.0f m under its %.0f m roof" % [deck.name, worst, deck.top])
	# Spec R4-2: the left tower stands on a bastion, and the land clears only round its wall, so the
	# trees come to it down the slope (the side toward the camera; the deck's apron is on the other).
	var left: Dictionary = ArrivalShot.TOWERS[0]
	check(left.get("bastion", 0.0) > 0.0, "left tower has a bastion")
	var top := s.base.cap_tops[0]
	var rb: float = left.shaft * left.bastion
	var cleared := 0
	for k in [1, 2, 3]:
		var q := Vector2(top.x, top.z) + Vector2.from_angle(TAU * k / 8.0) * (rb + 25.0)
		if land.clear_at(q.x, q.y).x > 0.5:
			cleared += 1
	eq(cleared, 0, "downhill points 25 m out of the bastion cleared")
	# Spec R4-3: the road is laid on a rounded centreline, as a mesh of its own.
	check(land.road_path.size() > 20, "road rounded through its hairpins (%d points)" % land.road_path.size())
	check(s.base.has_node("Road"), "road mesh")
	# Spec R4-6, R4b: the spire stands far out (about 11 km) in the gap the user drew, on a low level
	# snowfield just above the cloud sea, with no rock at its foot, and runs on off the top of the frame.
	var spire := s.get_node("Spire") as ArrivalSpire
	var at := s.frame_point(spire.foot)
	check(at.x > 45.0 and at.x < 60.0 and at.y > 16.0 and at.y < 26.0, "spire foot at frame %s" % at)
	var far := Vector2(spire.foot.x, spire.foot.z).length()
	check(far > 10000.0 and far < 12000.0, "spire %.0f m out" % far)
	check(absf(land.height(spire.foot.x, spire.foot.z) - spire.foot.y) < 6.0, "spire stands on its snowfield")
	var rise := spire.foot.y - ArrivalClouds.SEA.y
	check(rise > 10.0 and rise < 60.0, "snowfield %.0f m above the cloud sea" % rise)
	var field: float = ArrivalShot.SPIRE.field
	var worst := 0.0
	for k in 16:
		for r: float in [field * 0.3, field * 0.7, field + ArrivalShot.SPIRE.shoulder * 0.5]:
			var q := Vector2(spire.foot.x, spire.foot.z) + Vector2.from_angle(TAU * k / 16.0) * r
			var n := Vector3(land.height(q.x - 5.0, q.y) - land.height(q.x + 5.0, q.y), 10.0,
					land.height(q.x, q.y - 5.0) - land.height(q.x, q.y + 5.0)).normalized()
			worst = maxf(worst, 1.0 - n.y)
	var flattest := 1.0 - worst
	check(flattest > land.snow_threshold and land.forest_score(spire.foot.y, flattest, 0.0, 0.0) < 0.15,
			"snowfield open snow, no rock or forest (normal y %.4f)" % flattest)
	check(not spire.has_node("Slabs"), "no slabs at the foot")
	check(spire.has_node("Drift"), "snow drift where the shaft meets the field")
	var frame_top := s.at_distance(ArrivalShot.SPIRE.u, 0.0, ArrivalShot.SPIRE.distance).y
	check(spire.foot.y + spire.height * spire.built_to > frame_top + 200.0, "spire runs off the top of the frame")
	check(spire.radius_at(frame_top) > 100.0, "still %.0f m wide where it leaves the frame" % spire.radius_at(frame_top))
	var bands := int((frame_top - spire.foot.y) / spire.section)
	check(bands >= 4 and bands <= 8, "%d ledge bands in frame" % bands)
	# Spec R4-5: the right side has its own cloud bank.
	var right := 0
	for card: Array in ArrivalClouds.CARDS:
		if card[0] == &"bank" and card[1] > 75.0:
			right += 1
	check(right >= 4, "%d bank heaps on the right" % right)
	s.free()
