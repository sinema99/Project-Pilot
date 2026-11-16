# Interaction panel (2026-11-12)

The interaction prompt is no longer a bottom-centre row. It is a small 3D panel floating beside
whoever the camera is following, Division-style, drawn PS1. Grilled 2026-11-12.

## Decisions

1. **One prompt.** EXIA's own `UI/Prompt` is deleted. EXIA bids `PILOT` / `EXIT` / `EXIT...`
   into the shared `InteractionPrompt` exactly like doors bid `OPEN`; closest bid wins (aboard
   EXIA bids distance 0). EXIA now reads the `interact` action (F, E, pad) instead of raw
   `KEY_F`, and defers a press when the panel is offering a nearer source.
2. **Anchor = the camera's target.** The active camera's nearest ancestor with
   `interaction_anchor()` says where the body is: pilot9 = 1.45 m up, 0.7 m out; EXIA = 6 m up,
   3 m out. No anchor (cutscene camera etc.) = 2.5 m ahead, 0.6 m right, 0.3 m down.
3. **Side.** Out along the camera's flattened right vector times `side`. pilot9's side is
   `_shoulder_target_side()`, so it follows X and the wall-run's auto side; EXIA's is +1.
4. **Look.** Cyan `[F]` keycap + word (Barlow Condensed SemiBold) on a dark plate with a 1-texel
   cyan edge. Yawed 20 deg in toward the body (near edge toward the camera), upright, unlit, no
   fog, no depth test (nothing covers it).
5. **PS1.** Face drawn into a 16-texel-high SubViewport, sampled nearest and cut at alpha 0.5
   (no font AA); vertex snap on the world's 240-line grid; affine UVs on; 15-bit colour through
   a 4x4 Bayer. Plate: was a 50% ordered-dither checker; REMOVED 2026-11-12 after play (hard to read the word) - `plate_coverage` 0, edge ring kept.
6. **Every LOOK.** Same panel under AIRFRAME, RETRO and COMPOSITE (`airframe_skip` meta).
7. **Follow.** Position and side ease over `follow_time` 0.1 s; switching anchor (pilot <-> EXIA)
   or reopening snaps.
8. **Show / hide.** Unfold from a line over 0.1 s, fold over 0.08 s; a word change while open
   swaps instantly; a spent button folds. Hidden while the tree is paused (it would draw over
   the hologram menu).
9. **Size.** Constant on screen: one texel = `texel_px` 3 px of a 1080-line screen (panel 48 px
   tall, about the old row). Note: that is finer than the world's 240p texel (4.5 px) - chosen
   so the word stays legible at today's size; raise `texel_px` to 4.5 for a true 240p match
   (panel 72 px tall).

## Files

- `scripts/ui/interaction_prompt.gd` - now a Node3D: bidding (unchanged API: `acquire`, `offer`,
  `commit`, `clear_now`, `current_source`, `key_label_for`) + placement + fold.
- `scripts/ui/interaction_panel_face.gd` - draws keycap + word at texel scale.
- `shaders/ui/interaction_panel.gdshader` - plate, edge, dither, snap, affine, 15-bit.
- `scenes/ui/interaction_prompt.tscn` - a bare Node3D in the group; children built in code.
- `scripts/mech.gd` - `prompt_text`, `_bid_prompt()`, `interaction_anchor()`; `scenes/mech.tscn`
  lost its `UI` layer.
- `scripts/pilot9.gd` - `interaction_anchor()`.
- `tests/test_interaction_panel.gd`.

## Tunables

Exports on InteractionPrompt: `texel_px`, `yaw_deg`, `follow_time`, `unfold_time`, `fold_time`,
`fold_floor`, `fallback_*`. Anchor heights/offsets are `PROMPT_ANCHOR_*` consts in pilot9.gd and
mech.gd.

## Known gaps

- Not probe-shot yet; anchor numbers are first guesses (EXIA's especially).
- Screen-space post (CinemaPost / DepthComposite under COMPOSITE, AIRFRAME's screen filter)
  still runs over it, since it is in the 3D pass.
