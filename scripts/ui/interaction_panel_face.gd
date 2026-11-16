extends Control

# The interaction panel's face: the keycap and the word(s), drawn at texel scale into the panel's
# SubViewport. See docs/specs/interaction-panel.md and docs/specs/mech-stash.md.
#
# Everything is placed on whole texels and drawn as filled 1-texel rects or plain glyphs. The
# shader cuts the result at alpha 0.5, so any antialiasing the font brings is thrown away and
# what is left is chunky texels. The plate and the edge ring are the shader's, not this file's.
#
# One word = the original single row. Several = an option list: rows stacked ROW_STEP apart, the
# keycap beside the selected row only, the others dimmed. A progress >= 0 adds a bar under the
# last row (the hold-to-exit fill).

const FONT := preload("res://assets/fonts/PixelifySans.ttf")

## The ui theme's DialogTitle / Keycap cyan.
const CYAN := Color(0.251, 0.949, 0.902)
## The selected row of a list: brighter, toward white.
const BRIGHT := Color(0.78, 1.0, 0.98)
## Share of CYAN an unselected row is drawn at. Darkened, not faded: the shader cuts alpha at
## 0.5, so a translucent glyph would vanish.
const DIM := 0.4

## Panel height in texels for one row. Width follows the longest word.
const HEIGHT := 16
## Texels between rows of a list.
const ROW_STEP := 12
## Texels from the edge ring to the keycap.
const MARGIN := 3
## The keycap box, square, texels.
const CAP := 10
## Texels between the keycap and the word, and after the word to the edge.
const GAP := 4
const TAIL := 4
const WORD_FONT_SIZE := 12
const KEY_FONT_SIZE := 10
## The progress bar: texels tall, and the extra height it adds under the last row.
const BAR_H := 2
const BAR_ROOM := 3

var key_text := "F"
var words: PackedStringArray = PackedStringArray([""])
var selected := 0
## < 0 = no bar.
var progress := -1.0

## Kept for callers that read the single word.
var word_text: String:
	get:
		return words[selected] if selected < words.size() else ""


## The texel width the face needs for `word` - what the SubViewport is sized to.
static func width_for(word: String) -> int:
	var w := FONT.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_FONT_SIZE).x
	return MARGIN + CAP + GAP + int(ceil(w)) + TAIL


## The texel size for a list of words, with or without the bar.
static func size_for(list: PackedStringArray, with_bar: bool) -> Vector2i:
	var w := 0
	for word in list:
		w = maxi(w, width_for(word))
	var h := HEIGHT + maxi(list.size() - 1, 0) * ROW_STEP + (BAR_ROOM if with_bar else 0)
	return Vector2i(w, h)


func set_content(key: String, word: String) -> void:
	set_list(key, PackedStringArray([word]), 0, -1.0)


func set_list(key: String, list: PackedStringArray, index: int, bar: float) -> void:
	key_text = key
	words = list if not list.is_empty() else PackedStringArray([""])
	selected = clampi(index, 0, words.size() - 1)
	progress = bar
	queue_redraw()


func _draw() -> void:
	var many := words.size() > 1
	for i in words.size():
		var row_top := i * ROW_STEP
		var is_sel := i == selected
		if is_sel:
			_draw_cap(row_top)
		var col := (BRIGHT if is_sel else CYAN * Color(DIM, DIM, DIM, 1.0)) if many else CYAN
		var word_base := float(row_top) + floorf((HEIGHT + _cap_height(WORD_FONT_SIZE)) * 0.5 + 0.5)
		draw_string(FONT, Vector2(MARGIN + CAP + GAP, word_base), words[i], HORIZONTAL_ALIGNMENT_LEFT,
			-1, WORD_FONT_SIZE, col)
	if progress >= 0.0:
		var x0 := MARGIN + CAP + GAP
		var x1 := int(size.x) - TAIL
		var y := (words.size() - 1) * ROW_STEP + HEIGHT - 2
		var full := x1 - x0
		# The track, dark but opaque so it survives the alpha cut; then the fill.
		draw_rect(Rect2(x0, y, full, BAR_H), CYAN * Color(0.25, 0.25, 0.25, 1.0))
		var fill := roundi(full * clampf(progress, 0.0, 1.0))
		if fill > 0:
			draw_rect(Rect2(x0, y, fill, BAR_H), CYAN)


func _draw_cap(row_top: int) -> void:
	@warning_ignore("integer_division")
	var top := row_top + (HEIGHT - CAP) / 2
	# The keycap: a one-texel cyan box.
	draw_rect(Rect2(MARGIN, top, CAP, 1), CYAN)
	draw_rect(Rect2(MARGIN, top + CAP - 1, CAP, 1), CYAN)
	draw_rect(Rect2(MARGIN, top, 1, CAP), CYAN)
	draw_rect(Rect2(MARGIN + CAP - 1, top, 1, CAP), CYAN)
	# Baselines by cap height, so the glyphs sit in the middle of the box and the row.
	var kw := FONT.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT_SIZE).x
	var kx := float(MARGIN) + floorf((CAP - kw) * 0.5 + 0.5)
	var key_base := float(top) + floorf((CAP + _cap_height(KEY_FONT_SIZE)) * 0.5 + 0.5)
	draw_string(FONT, Vector2(kx, key_base), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		KEY_FONT_SIZE, CYAN)


# Barlow's caps are 0.7 em; the word is always uppercase.
static func _cap_height(font_size: int) -> float:
	return round(font_size * 0.7)
