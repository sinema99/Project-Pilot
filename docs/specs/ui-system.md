# Spec: Basic UI System

## Problem Statement

Mech Delivery Prototype has no UI layer. The only on-screen element in the game is a single
`Label` living inside `scenes/mech.tscn`, styled with raw anchor offsets and driven directly
by `mech.gd`. There is no theme, no shared window widget, no way to pause, and no screen the
player can open on purpose.

That is fine for one prompt and wrong for everything after it. The zone spec already promises
a loading transition, shortcut gates, and delivery missions; each of those wants a screen.
Building them one at a time, each styling its own controls inline, means the look drifts and
a colour change becomes an edit in every scene.

There is also a concrete blocker: `Esc` is currently bound to a mouse-capture toggle in
`player.gd`, which is the key a pause menu needs.

## Solution

One `Theme` resource defines the look. One reusable window scene provides the frame — a
charcoal body with a light header strip, square corners, an ink border. Two screens instance
that window: a **pause menu** that freezes the world behind a dimmed screen, and an
**inventory** popup that does not.

A single autoload (`UI`) owns which screen is open, whether the tree is paused, and the mouse
mode. Its transition rules are a pure function so they can be tested without a running tree.

## The Look

Taken from a handheld-RPG summary screen the developer supplied as reference: a flat
rectangular panel, dark body, light header bar carrying the screen's title, boxed rows inside.
Warm-tinted rather than neutral, so it sits in the same world as the Moebius art direction
instead of reading as a default engine overlay.

| Role | Hex | Notes |
|---|---|---|
| Window body | `#3A3532` | warm charcoal |
| Header bar | `#EFE9DF` | warm off-white |
| Header text | `#1A1410` | ink, from the Moebius palette |
| Body text | `#EDE6DA` | |
| Border | `#1A1410` | 1px, around the whole window |
| Field / row fill | `#47413D` | one step lighter than the body |
| Button hover + focus | `#5A534E` | identical values — see below |
| Button pressed | `#2E2A27` | |
| Screen dim (pause) | `#0A0806` @ 60% | warm near-black, not pure black |

- **Square corners, 0 radius.** The reference is square and the brief asked for a plain
  rectangle.
- **Godot's default font**, sizes 20 (header title) / 18 (buttons) / 16 (body) at 1080p.
  Deliberately a placeholder: because the theme is shared, swapping the face later is one
  property on one file. A pixel font was considered and rejected for now — it is a strong
  identity commitment that sits awkwardly against a hand-inked Moebius world.
- **`hover` and `focus` are the same colour on purpose.** Mouse hover moves focus rather than
  drawing a second highlight, so exactly one item is ever highlighted.

**The compositor does not touch any of this.** `CompositorEffect` runs on the 3D render; a
`CanvasLayer` draws over the finished frame. UI gets no outline, no grain, no fog. That
contrast is accepted, and the warm tint is what keeps it from reading as an accident.

## Screens

### Pause — `P`

- Freezes the world (`get_tree().paused = true`). The `UI` autoload runs with
  `PROCESS_MODE_ALWAYS`, without which nothing could unpause it.
- Full-screen dim at 60%, window centered on top.
- Window **shrinks to fit** its contents rather than taking a fixed size, so the entry list can
  change without picking new numbers. Buttons stretch to the full inner width so the stack is
  not ragged.
- Title: **"Paused"**. No close button — "Resume" is right there.
- Entries: **Resume** *(live)* · **Options** *(stub)* · **Back to Main Menu** *(stub)* ·
  **Quit to Desktop** *(live)*.
- "Back to Main Menu" **cannot** work yet: no main menu scene exists. It stays a visible stub
  rather than being half-wired to something that reloads `main.tscn` and pretends.

### Inventory — `Tab`

- **Does not pause.** The world keeps simulating and the player keeps walking.
- Centered, fixed **900x600**. Title **"Inventory"**. Has a close button.
- **Empty.** No items, no grid, no tabs, no data model — the frame only. Contents arrive when
  items exist.

Releasing the cursor is what disables the camera, and it costs no code: `player.gd` and
`mech.gd` both gate mouse-look on `Input.mouse_mode == MOUSE_MODE_CAPTURED`, while movement is
polled unguarded. So "can move, cannot look" falls out of the existing controllers untouched.

Accepted consequence: with the camera frozen, WASD stays relative to wherever the camera was
pointing, and the player can walk out of frame.

## Screen State Rules

One screen at a time. Never both.

| Input | Nothing open | Pause open | Inventory open |
|---|---|---|---|
| `P` | open Pause, freeze | close, unfreeze | close Inventory, open Pause, freeze |
| `Tab` | open Inventory, world runs | *ignored* | close |
| `Esc` | — | close, unfreeze | close |

- **`P` always reaches pause**, even from the inventory. Stopping the game should not require
  dismissing something else first.
- **`Tab` while paused is ignored.** The alternatives are incoherent: it would either unfreeze
  the world (contradicting the pause) or show a non-pausing screen over a frozen one.
- **Cursor** is released whenever any screen is open, recaptured when none is.

## Input

Godot's built-in `ui_*` actions are used where possible; two bindings are overridden and two
actions are new.

| Action | Keyboard | Gamepad |
|---|---|---|
| `ui_accept` | F, Enter | A / Cross |
| `ui_cancel` | Esc | B / Circle |
| `pause` | P | Start |
| `inventory` | Tab | Select / Back |

- **`Space` is removed from `ui_accept`.** It has to be. `player.gd` polls
  `Input.is_key_pressed(KEY_SPACE)` for the grounded jump inside `_physics_process`, which
  never sees events — so a focused button consuming the Space *event* would not stop the jump,
  and confirming a menu item would make the player hop.
- **`F` is safe as confirm** for the mirror-image reason: `mech.gd` reads F as an event in
  `_unhandled_input`, so a focused button consuming it correctly suppresses enter/exit Exia.
- **Menu navigation is not on WASD.** With the inventory open the world is live, so `W` walks
  the player. Arrow keys and the D-pad are the only conflict-free option. Mouse is the expected
  path for keyboard-and-mouse players; D-pad navigation exists for controller.
- **`Esc` has exactly one job** (close the open window). Pause moved to `P` specifically to
  avoid binding `Esc` to two actions.

### Control remap (shipped ahead of this work)

`C` and `Ctrl` were swapped, as a separate step, so a movement regression could not hide inside
a UI change:

| Key | Was | Now |
|---|---|---|
| `C` | dash | **crouch** |
| `Ctrl` | crouch | **dash** |

`Shift` stays sprint. Each action **kept its own reading style**, not its key: crouch is still a
polled edge (per the comment explaining why it must not depend on events arriving), dash is
still a true `not event.echo` event.

The `Esc` mouse-capture toggle in `player.gd` was deleted. It is fully subsumed by pause, which
releases the cursor anyway — and leaving it would have been an active bug, since dismissing a
menu could recapture and then immediately re-toggle.

## File Layout

```
resources/ui_theme.tres          Theme - colours, styleboxes, font sizes

scenes/ui/ui_window.tscn         the reusable frame
scenes/ui/pause_menu.tscn
scenes/ui/inventory.tscn

scripts/ui/ui_manager.gd         autoload `UI` - screen state, pause, cursor
scripts/ui/ui_window.gd          title, show_close_button, close_requested
scripts/ui/pause_menu.gd
scripts/ui/inventory.gd          intentionally empty; first real behaviour lands here

tests/test_ui_manager.gd         the transition table
tests/test_ui_theme.gd           theme loads and defines the key colours
```

`UI` is the autoload name — short at every call site. The script keeps the filename
`ui_manager.gd` so it stays greppable.

### Why the transition rules are a pure function

`resolve(current, input) -> {screen, paused, cursor}` takes no nodes and touches no tree. The
autoload calls it and then applies the result. Two reasons: the rules are the only part of this
work that can be silently wrong (a cursor that never recaptures, a world stuck paused), and it
sidesteps the question of whether autoloads are even instantiated under
`godot --headless --script tests/run_tests.gd`.

## Out of Scope

- **Any inventory contents** — items, icons, grid, tabs, stacking, use/drop. The window is an
  empty frame by explicit decision.
- **An options screen** and **a main menu scene**. Both are stub buttons.
- **Folding the mech's `PromptLabel` into the theme.** It stays as-is; the theme gives it
  somewhere to go later.
- **Migrating movement input to InputMap actions.** `player.gd` and `mech.gd` keep polling raw
  keycodes. This leaves a split convention (UI on actions, movement on keycodes) — accepted,
  because migrating a 300-line controller that was just tuned is its own change.
- **Diegetic / printed UI styling** (paper texture, ink lines, grain on the panel). Wanted
  eventually; too much for a "very basic" first pass.
- **Controller support beyond menu navigation.** Gameplay is keyboard-only.

## Known Gaps

- **An empty window cannot validate the theme.** Scrolling, long labels, row separators, and an
  empty state all go untested until real content exists. Expect some values to move.
- **`F` falls through to gameplay when nothing has focus.** With the inventory open and no
  button focused, pressing `F` next to Exia will mount or dismount. Harmless while the
  inventory is empty (nothing can take focus); revisit when it has clickable contents.
- **The grain keeps moving while paused.** The compositor advances its seed per *rendered*
  frame, and pausing does not stop rendering. Left deliberately — live grain over a frozen
  frame reads as a printed page.
