# Mech stash (2026-11-12)

EXIA carries a 10 x 12 stash - the pilot's overflow storage. Reached from the ground through a
scrollable option list on the interaction panel (PILOT / STASH), or with Tab while aboard. The
same commit locks the pilot's third-person camera at 2 m and turns EXIA's exit into a hold.
Grilled 2026-11-12.

Status: built 2026-11-12.

## Decisions

1. **Stash = 10 x 12 `ItemGrid`**, `Inventory.stash` on the autoload next to the pilot's
   `Inventory.grid`. Session only like the pilot grid (survives scene changes, gone on quit, no
   disk). One stash for "the" EXIA - several mechs would each need their own; later problem.
2. **Stash screen = the inventory screen in STASH mode**: EXIA portrait | pilot 10 x 6 | stash
   10 x 12, in the right-hand box where the vicinity was. Same screen from outside (STASH option)
   and inside (Tab). No vicinity box in this mode - ground loot is not reachable from it (pick
   it up with Tab first).
   - Deviation from the grill: the right-hand box already shows 15 rows, so the 12-row stash fits
     whole and no scroll was built (the agreed wheel scroll had nothing to do). A stash taller than
     15 rows would need one.
3. **Moving items.** Both grids are real, arranged grids: LMB takes, LMB places, R rotates. RMB
   quick-moves to the first free spot of the OTHER grid (pilot <-> stash), stacks merge first, no
   room = nothing happens. Nothing can be dropped on the ground from this screen.
4. **EXIA portrait**: the pilot portrait's technique - a pose mirror of EXIA's live skeleton in
   the studio world, wearing its live materials, framed head to feet, LMB drag turns it. From
   outside it shows the parked crouch.
   - Framing is by EXIA's POSED vertices, not its bones (the bone span framed a torso close-up)
     and not `get_aabb()` (a skinned mesh reports its bind-space box): each vertex is skinned by
     its heaviest bone once on open, and the body is centred on the turntable axis. The pilot
     keeps his bone framing. Measured once per open, so a mech that stands up mid-open keeps the
     crouch's framing.
5. **Option list on the panel.** On foot near EXIA the panel stacks `PILOT` over `STASH`. The
   `[F]` keycap sits beside the highlighted row, whose word is bright; the other row is dimmed to
   ~40%. Wheel down / up moves the highlight, clamped (no wrap); a change snaps (no tween). F does
   the highlighted one. Leaving the panel (out of range, outbid, hidden) resets it to `PILOT`.
   The wheel only does this while a multi-option offer is showing. No gamepad yet.
6. **STASH from outside** needs the pilot able to open his inventory (`can_open_inventory()`)
   and no screen open. He is frozen beside the mech exactly like the normal Tab.
7. **Tab aboard** opens the stash screen at any speed; refused while climbing in, sealing,
   unsealing or climbing down, and in the air. While it is open EXIA gets no drive or look input:
   it brakes with its normal release / stop settle and idles. F is dead (the screen eats the
   keyboard), so no exit hold can start behind it; a hold already running is cancelled.
8. **Hold to exit.** Aboard, the panel shows nothing. Pressing F unfolds `[F] EXIT` with a cyan
   bar under the word filling over 0.6 s. Letting go early drains it (the panel folds); a full
   bar is the old tap: slow and on the floor = out now; otherwise the existing braking wait,
   panel reading `EXIT...` (bar full). Letting go of F during the wait cancels it.
9. **Camera locked at 2 m.** The pilot's third-person arm is `camera_distance` 2.0 and the wheel
   zoom is deleted. The zoom-shaped lift / tilt curves stay as they were and settle at their 2 m
   values. First person is unchanged; EXIA's camera never had wheel zoom.
10. **Test content.** The stash starts with a Rifle crate, two Medkits and a Battery (TEST
    CONTENT in `inventory.gd`); the pilot grid still starts empty.

## Files

- `scripts/inventory/inventory.gd` - `stash`, `STASH_W/H`, test seed, `open_stash()`,
  `stash_mech`, `piloted_mech()`.
- `scripts/ui/inventory_screen.gd` - STASH mode: right box is the stash grid, two-grid
  take / place / quick-move.
- `scripts/ui/inventory_portrait.gd` - `show_body(node, model)`: pilot or EXIA.
- `scripts/ui/interaction_prompt.gd` + `interaction_panel_face.gd` - `offer()` takes options and
  a progress; wheel selection; `selected_option()`.
- `scripts/mech.gd` - PILOT / STASH bid, hold-to-exit, `can_open_stash()`, `set_stash_hold()`.
- `scripts/pilot9.gd` - wheel zoom removed, `camera_distance` 2.0.
- `tests/test_mech_stash.gd`.

## Tunables

`mech.gd`: `EXIT_HOLD_TIME` 0.6. `inventory.gd`: `STASH_W`, `STASH_H`.
`interaction_panel_face.gd`: `ROW_STEP`, `DIM`, `BAR_H`.

## Known gaps

- No gamepad for the option list or the stash screen.
- One stash shared by every EXIA in the session.
