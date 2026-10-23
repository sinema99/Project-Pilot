class_name DescentShafts
extends MeshInstance3D

# The light shafts in the descent shot (docs/specs/descent-composite.md row 4), and in the flyover:
# soft slanted cards falling from the cloud break onto the city. In descent each runs from just behind
# the deck's front edge (tucked into the cloud) down to the ground at a chosen distance, and faces
# the locked camera.
# All the cards are one mesh. Brightness breathes on the shot clock, so seeking shows the same frame.

const SHADER := preload("res://shaders/cutscene/descent_shaft.gdshader")
## How far above the deck base (m) a card's top starts, so the cloud hides it.
const TOP_TUCK := 40.0

var material: ShaderMaterial


## Builds one card per row of `table` (see DescentShot.SHAFTS).
func build(table: Array) -> void:
	build_cards(cards_from_table(table), DescentShot.CAMERA_POSITION)


## Builds one card per [top, foot, top width, foot width, strength, phase] (world points, metres),
## each facing `eye`. The flyover's shafts come in this way (docs/specs/shots-composite.md row 6).
func build_cards(cards: Array, eye: Vector3) -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = card_mesh(cards, eye)


## The descent table's rows as world cards: [top sketch x, foot sketch x, foot distance (m), top
## width (m), foot width (m), strength, phase].
static func cards_from_table(table: Array) -> Array:
	var cards := []
	for row: Array in table:
		var top := DescentShot.deck_edge_point(row[0]) + Vector3(0.0, TOP_TUCK, 0.0)
		var foot := DescentShot.sketch_point(Vector2(row[1], DescentShot.HORIZON_PX), row[2])
		foot.y = 0.0
		cards.append([top, foot, row[3], row[4], row[5], row[6]])
	return cards


## The descent cards. Static so the tests can check the geometry without a scene.
static func shaft_mesh(table: Array) -> ArrayMesh:
	return card_mesh(cards_from_table(table), DescentShot.CAMERA_POSITION)


## One soft quad per card, turned about its own axis to face `eye`. Colour carries strength (r) and
## phase (g) for the shader.
static func card_mesh(cards: Array, eye: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for card: Array in cards:
		var top: Vector3 = card[0]
		var foot: Vector3 = card[1]
		var axis := (foot - top).normalized()
		var mid := (top + foot) * 0.5
		var side := axis.cross(eye - mid).normalized()
		var tw: float = card[2] * 0.5
		var fw: float = card[3] * 0.5
		var col := Color(card[4], card[5], 0.0, 1.0)
		var quad := [
			[top - side * tw, Vector2(0, 0)], [top + side * tw, Vector2(1, 0)],
			[foot + side * fw, Vector2(1, 1)], [foot - side * fw, Vector2(0, 1)],
		]
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_uv(quad[i][1])
			st.add_vertex(quad[i][0])
	return st.commit()


## Shows shot time `t`, with lightning `flash` (0..1).
func apply(t: float, flash: float) -> void:
	material.set_shader_parameter(&"time", t)
	material.set_shader_parameter(&"flash", flash)
