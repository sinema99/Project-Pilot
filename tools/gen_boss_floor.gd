extends SceneTree

# Paints the boss arena's floor (docs/specs/boss-arena.md, Rework): an old landing pad scraped by the
# wind, about DECK_SHARE of it bare deck and the rest snow, in flat cel tones. The image's centre is
# the cap's centre, image x is world x, image y is world z, and it spans BossArena.FLOOR_SPAN metres.
#
# Run from the project root, then --import:
#   godot --headless --path . --script tools/gen_boss_floor.gd

const OUT := "res://assets/boss_arena/floor.png"
const SIZE := 4096
const SPAN := 340.0
## The share of the cap's disc left as bare deck.
const DECK_SHARE := 0.3
## The cap's radius (m).
const RIM := 160.0
## The deck's slabs (m), and the seam between them.
const SLAB := 20.0
const SEAM := 0.3

const SNOW := Color(0.7, 0.71, 0.71)
const SNOW_SHADE := Color(0.635, 0.645, 0.66)
const DECK := [Color(0.52, 0.52, 0.525), Color(0.48, 0.48, 0.49), Color(0.56, 0.555, 0.55)]
const DECK_SEAM := Color(0.34, 0.34, 0.35)
const PAINT := Color(0.62, 0.53, 0.45)


func _initialize() -> void:
	var drift := _noise(11, 1.0 / 46.0, 4)
	var ragged := _noise(12, 1.0 / 5.0, 3)
	var banks := _noise(13, 1.0 / 30.0, 3)
	# How much snow lies at each pixel; the deck is whatever falls under the bar.
	var depth := PackedFloat32Array()
	depth.resize(SIZE * SIZE)
	var inside := PackedFloat32Array()
	for y in SIZE:
		for x in SIZE:
			var p := _metres(x, y)
			# Stretched along the wind (+x), and piling up toward the rim.
			var d := drift.get_noise_2d(p.x * 0.3, p.y) + ragged.get_noise_2d(p.x * 0.6, p.y) * 0.16
			d += smoothstep(RIM * 0.68, RIM, p.length()) * 0.55
			depth[y * SIZE + x] = d
			if x % 8 == 0 and y % 8 == 0 and p.length() < RIM:
				inside.append(d)
	inside.sort()
	var bar: float = inside[int(inside.size() * DECK_SHARE)]
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 3)
	var deck := 0
	var disc := 0
	for y in SIZE:
		for x in SIZE:
			var p := _metres(x, y)
			var d := depth[y * SIZE + x]
			var c: Color
			if d < bar:
				c = _deck(p)
				if p.length() < RIM:
					deck += 1
			elif d < bar + 0.035 or banks.get_noise_2d(p.x * 0.3, p.y) > 0.22:
				c = SNOW_SHADE
			else:
				c = SNOW
			if p.length() < RIM:
				disc += 1
			var i := (y * SIZE + x) * 3
			bytes[i] = c.r8
			bytes[i + 1] = c.g8
			bytes[i + 2] = c.b8
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, bytes)
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", OUT, " deck share ", float(deck) / disc)
	quit()


func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


func _metres(x: int, y: int) -> Vector2:
	return (Vector2(x, y) / SIZE - Vector2(0.5, 0.5)) * SPAN


## The deck at `p`: slabs a shade apart, dark seams, the pad's faded markings.
func _deck(p: Vector2) -> Color:
	var cell := (p / SLAB).floor()
	var within := p - cell * SLAB
	if minf(within.x, within.y) < SEAM:
		return DECK_SEAM
	return PAINT if _marked(p) else DECK[posmod(hash(cell), DECK.size())]


## The pad's markings: two rings, the touchdown cross, and eight bars inside the outer ring.
func _marked(p: Vector2) -> bool:
	var r := p.length()
	if absf(r - 104.0) < 2.5 or absf(r - 62.0) < 1.25:
		return true
	if (absf(p.x) < 3.0 and absf(p.y) < 34.0) or (absf(p.y) < 3.0 and absf(p.x) < 34.0):
		return true
	var a := fposmod(atan2(p.y, p.x) + PI / 8.0, PI / 4.0) - PI / 8.0
	return r > 72.0 and r < 96.0 and absf(a) * r < 2.5
