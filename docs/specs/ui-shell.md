# Spec: UI Shell

> **Superseded in part (2026-09-29):** the look, the shell layout and the per-tab layouts (window, rows, tabs, motion, confirm dialog, main menu skin) now live in [menu-refresh.md](menu-refresh.md).

> Supersedes `docs/specs/ui-system.md`. Where the two disagree, this document wins.
> The older file is kept for its reasoning, not its conclusions.

## Problem Statement

The UI built in `ui-system.md` works and is wrong for the game that exists now.

Three things changed under it. The look was taken from a handheld-RPG summary screen — warm
charcoal panels, a light off-white header strip, ink text — which is not the direction any more.
The framework is a two-value enum (`NONE / PAUSE / INVENTORY`) that cannot express a modal over a
screen, so every future screen is another enum case and another hand-placed centered box. And
`docs/game-overview.md` (2026-09-08) now promises a hub menu, a map-select diorama, four
unlockable techs and timed contracts — a pile of screens the current shape has no room for.

There is also unfinished business the old spec logged as known gaps: `Tab` while paused is
ignored for reasons nobody will remember, the non-pausing inventory lets the player walk out of
frame with a frozen camera, and `F` with nothing focused falls through and mounts EXIA.

## Solution

**One full-screen shell, drawn as outlines over a dimmed world.** Screen name top-left, a tab
strip beneath a rule, a content region, a hint bar along the bottom. New screens become new tabs,
not new layouts.

Behind it, the `UI` autoload becomes a **screen registry and a stack**. The transition rules stay
a pure function, now over `(stack, action, shell_enabled)` instead of `(enum, action)`. One
reusable confirm modal is built in the same pass, because a modal over a screen is the case the
old flat enum genuinely could not express, and building the stack without it would be building
architecture that nothing proves.

The inventory folds into the shell as a tab and starts pausing the world, which deletes all three
known gaps above at once.

A `main_menu.tscn` is built in the same visual language. It is **not** made the boot scene.

## The Look

Neutral, unfilled, and quiet. The dim is the only darkening; every box is a hairline.

| Role | Value | Notes |
|---|---|---|
| Screen dim | `#000000` @ **65%** | one node, owned by the autoload |
| Border | `#FFFFFF` @ **85%**, 1px | every box, every rule |
| Text | `#FFFFFF` | |
| Text, secondary / locked | `#FFFFFF` @ **45%** | inactive tabs, locked techs, hint-bar labels |
| Selected row fill | `#FFFFFF` (opaque) | |
| Selected row text | `#000000` | |
| Panel fill | **none** | fully transparent; the dim shows through |
| Main-menu backdrop | `#050505` | flat, no world behind it |

Rules that follow from that:

- **Square corners, 0 radius**, as before.
- **No fills anywhere except the selected row.** That single white bar is the only bright mass on
  screen and it is what the eye finds first. Anything else filled competes with it.
- **The dim applies to every screen**, not just pause. With transparent panels there is nothing
  else making white text readable, and the inventory no longer has an excuse — it pauses now.
- **Hover moves focus** rather than drawing a second highlight, so exactly one row is ever lit.
  Carried forward unchanged from `ui-system.md`; it was right.

### Why neutral, when the old spec argued for warm

`ui-system.md` warm-tinted everything so the UI would not "read as a default engine overlay". The
counter-argument is in `project.godot`: `shader_globals/outline_color` is pure black. The world is
already inked in neutral black by the cel shader. White-on-black UI matches the art direction
rather than sitting beside it.

### Typeface

**Barlow Condensed** (OFL), downloaded to `assets/fonts/`. One face, everywhere.

With no fills, no colour and no ornament, the typeface is most of the visual identity — an
outline-and-white-text menu in Godot's default face looks like a debug overlay.

| Role | Size @1080p | Tracking | Case |
|---|---|---|---|
| Screen title | 44 | +6 | UPPER |
| Tab label | 22 | +4 | UPPER |
| Menu row | 24 | +3 | UPPER |
| Body / description | 18 | 0 | Sentence |
| Hint bar | 16 | +2 | UPPER |

**Chrome shouts, prose does not.** Titles, tabs, rows and hints are uppercase with tracking.
Anything that is a sentence — ability descriptions, the confirm modal's message — stays sentence
case, because uppercase prose is hard to read. Stated as a rule so there is no per-string
judgement call later.

## The Shell

```
+-- 96px margin ------------------------------------------------+
|                                                               |  64px top
|  PAUSED                                                       |  title, 44
|                                                               |
|  GAME    ABILITIES    INVENTORY    SETTINGS                   |  tabs, 22
|  ====                                                         |  2px active underline
| ------------------------------------------------------------- |  1px rule
| +-----------------------------------------------------------+ |
| |                                                           | |
| | [######## RESUME ########################################] | |  selected: white fill
| |   RESTART                                                 | |
| |   BACK TO MAIN MENU                                       | |
| |   QUIT TO DESKTOP                                         | |
| |                                                           | |  1px content box
| +-----------------------------------------------------------+ |
|                                                               |
|  [UP/DN] SELECT   [ENTER] CONFIRM   [L/R] TAB   [ESC] CLOSE   |  hint bar, 16
+---------------------------------------------------------------+  48px bottom
```

- **Active tab is underlined, not filled.** The filled-white treatment belongs to row selection;
  two solid white blocks on one screen fight each other. Inactive tabs sit at 45%.
- **Selected row fills edge to edge** inside the content box.
- **The hint bar is data, not decoration.** Each screen declares its own prompts as
  `[{key, label}]` and the bar renders them; keys sit in a 1px outlined keycap.
- Reference resolution stays 1920x1080 with `canvas_items` stretch, unchanged.

## Tabs

**GAME - ABILITIES - INVENTORY - SETTINGS.** No MAP tab — `game-overview.md` calls the diorama a
late task that "must not jump the queue", and a map tab with no map in it is the emptiest possible
frame.

### GAME

| Entry | Behaviour |
|---|---|
| Resume | `UI.close()` |
| Restart | `get_tree().reload_current_scene()` |
| Back to Main Menu | confirm modal, then loads `main_menu.tscn` |
| Quit to Desktop | confirm modal, then `get_tree().quit()` |

`Restart` is honest about what it means today: there is no checkpoint system, so it reloads the
scene. It is the single most useful button during a playtest phase, which is the phase this
project is in. When checkpoints land, this entry changes meaning, and that is fine.

### ABILITIES

**The only tab with real content, and that is the point.** `ui-system.md`'s largest complaint was
that an empty window cannot validate a theme. One tab with real rows fixes it.

Two sections. **BASE KIT** reads live off `pilot9.gd`'s existing exports; **TECH** is the four
unlocks from `game-overview.md`, all locked, with no backing state yet.

| Section | Row | Source |
|---|---|---|
| Base kit | Slide | `can_slide` |
| Base kit | Slide buffer | `can_buffer_slide` |
| Base kit | Slide hold | `can_hold_slide` |
| Base kit | Mantle | `can_climb` |
| Base kit | Double jump | `air_jumps > 0` |
| Base kit | Walk | `can_walk` |
| Base kit | Auto-slide on steep ground | `can_auto_slide` |
| Tech | Double jump - Air dash - Wall-run - Rail grind | hardcoded, all locked |

Unlocked rows draw at full white; locked rows at 45%, with the description still readable.

**The lookup.** pilot9 joins a new `player` group — the project has **no groups at all** today, so
this introduces the convention. The tab resolves its source with
`get_tree().get_first_node_in_group(&"player")` and **must** handle null: the main menu has no
pilot9, and neither does a headless test. With no player found, every row renders locked.

### INVENTORY

Empty content box, one line of 45% text saying so. No items, no grid, no data model — the same
explicit decision as before, now inside a shell that gives it a shape.

### SETTINGS

Empty content box, same treatment. Options that actually write and persist settings are out of
scope; that work touches a save system which does not exist.

## Main Menu

`scenes/ui/main_menu.tscn`, its own scene, flat `#050505` backdrop.

- Game title top-left at title size, option list below: **START - SETTINGS - QUIT**.
- `START` loads a scene from an **exported path**, defaulting to `res://scenes/trial.tscn` — the
  scene actually being played (`game-overview.md`: "the active testbed"). Re-pointing it at map #1
  later is one field in the inspector.
- `SETTINGS` is its own stub entry, not a route into the shell — the shell is a pause construct
  and does not exist outside a running game. It matches the shell's empty settings tab and does
  nothing yet.
- `QUIT` goes through the confirm modal.

**`project.godot`'s `run/main_scene` is not changed.** It stays `test_platform.tscn`. The dev loop
is F6 on `trial.tscn`, and a menu gate in front of every playtest is friction paid on every
iteration. Flipping the boot scene is one line, later.

**The main menu does not pause the tree and keeps the cursor visible.** It is a scene, not an
overlay, so the stack's pause/cursor derivation has to treat it differently — see below.

## Confirm Modal

`scenes/ui/confirm_dialog.tscn`. Centered outlined box over the same dim: title, a sentence-case
message, two rows — **CONFIRM / CANCEL**, focus defaulting to CANCEL.

Pushed on top of whatever is open. Used by `Quit to Desktop`, `Back to Main Menu`, and the main
menu's `QUIT` — every action that throws away an unsaved run.

Opened by call, not by input action:

```gdscript
UI.confirm("Quit to desktop?", "Any unsaved progress will be lost.", func() -> void:
    get_tree().quit())
```

## Screen Stack

The `UI` autoload holds a registry and a stack of `StringName`s. Registry entries carry the scene
path and whether the screen pauses.

| Name | Scene | Pauses |
|---|---|---|
| `&"shell"` | `scenes/ui/shell.tscn` | yes |
| `&"confirm"` | `scenes/ui/confirm_dialog.tscn` | yes |

An **empty stack means gameplay**: nothing drawn, no dim, tree running, cursor captured.

### The rules, as a pure function

`resolve(stack, action, shell_enabled) -> {stack, paused, cursor_captured}`

No nodes, no tree, no side effects. The autoload calls it and applies the result. Same reasoning
as the old spec: this is the only part of the UI that can be silently wrong — a world stuck
paused, a cursor that never recaptures — so it is the part that gets asserted.

| Action | Empty stack | Top is `shell` | Top is `confirm` |
|---|---|---|---|
| `BACK` (Esc / P / Start / pad B) | push `shell` | clear | pop one |
| `CLOSE` (Resume, or a screen dismissing itself) | — | clear | clear |
| `PUSH(name)` | push | push | push |

Derived, never stored separately:

- `paused` = any name on the stack pauses. Falls to `false` the instant the stack empties, which
  is the failure this design is most afraid of.
- `cursor_captured` = the stack is empty **and** `shell_enabled`.

### `shell_enabled`

A single flag, false while the main menu is the current scene. With it false, `BACK` is a no-op
(Esc does nothing on the title screen) and the cursor stays visible even though the stack is
empty. `main_menu.gd` clears it in `_ready()`; `UI.start_game(path)` sets it back and loads the
scene.

This is what keeps the main menu out of the stack entirely, rather than modelling a screen that is
also a scene.

### Two rules decided outright

1. **Esc on a non-GAME tab closes the whole shell.** It does not step back to the GAME tab. Tabs
   are not stack levels; only modals are. A tab strip you have to back out of one tab at a time is
   a worse tab strip.
2. **The dim is one node owned by the autoload**, shown whenever the stack is non-empty. Screens
   do not own one and cannot opt out. Two stacked screens must not double-darken.

## Input

| Action | Keyboard | Gamepad |
|---|---|---|
| `ui_accept` | **Enter, Space** | A / Cross |
| `ui_cancel` | Esc | B / Circle |
| `pause` | **Esc**, P | Start |
| `ui_up` / `ui_down` | Arrows, **W / S** | D-pad |
| `tab_prev` / `tab_next` | **Left / Right, Q / E** | LB / RB |
| `inventory` | **removed** | **removed** |

Three bindings change because the constraints that forced them are gone.

- **`Esc` becomes pause.** It moved to `P` only because `Esc` was a mouse-capture toggle in
  `player.gd` — and that toggle was deleted in the same change that introduced the rule. The
  reason has not existed for a while. `P` stays as a second binding.
- **`Space` returns to `ui_accept`.** It was excluded because `player.gd` polled
  `Input.is_key_pressed(KEY_SPACE)` inside `_physics_process`, which never sees consumed events.
  Every screen now pauses, paused nodes do not process, and polled input stops dead. Space is
  safe.
- **`F` is removed from `ui_accept`.** It was only ever chosen because it was safe, and it carries
  a logged bug: `F` with nothing focused falls through and mounts EXIA. `mech.gd:236` reads
  `KEY_F` as a raw keycode in `_unhandled_input`, so removing it from the action map does not
  touch boarding.
- **`inventory` / `Tab` is deleted.** The inventory is a tab in a shell now. `Tab` also happens to
  be Godot's built-in `ui_focus_next`, which the old manager had to fight inside `_input`; that
  workaround goes with it.

**WASD is now available for menu navigation** because there is no longer a screen that runs over a
live world. This forecloses ever adding one without revisiting the binding — accepted.

## In-Game UI

EXIA's `PromptLabel` (`scenes/mech.tscn`) adopts the new language: Barlow, white, uppercase, with
the key in a 1px outlined keycap matching the hint bar. Today it is a raw `Label` with hardcoded
offsets, a 28px default font and a 6px black outline — the only UI a player sees while actually
playing, and the last thing left in the old visual language.

`PROMPT_ENTER` / `PROMPT_EXIT` drop the key from their strings — `"F pilot"` becomes `"PILOT"` —
because the key now lives in the keycap beside them. `mech.gd` gains one node reference: `prompt`
(the row, which is what shows and hides) alongside `prompt_label` (the word, which is what
changes).

**No new HUD.** `game-overview.md` rules out a health bar, minimap, compass and waypoints, and
nothing damages the player yet. There is genuinely nothing else to draw.

## File Layout

```
assets/fonts/BarlowCondensed-*.ttf     the face

resources/ui_theme.tres                rewritten: neutral, unfilled, Barlow

scenes/ui/shell.tscn                   the full-screen tabbed shell
scenes/ui/tabs/tab_game.tscn
scenes/ui/tabs/tab_abilities.tscn
scenes/ui/tabs/tab_inventory.tscn
scenes/ui/tabs/tab_settings.tscn
scenes/ui/confirm_dialog.tscn
scenes/ui/main_menu.tscn

scripts/ui/ui_manager.gd               autoload `UI`: registry, stack, dim, pause, cursor
scripts/ui/shell.gd                    tabs, hint bar, title
scripts/ui/tabs/tab_game.gd
scripts/ui/tabs/tab_abilities.gd
scripts/ui/tabs/tab_empty.gd           shared by INVENTORY and SETTINGS until either has content
scripts/ui/confirm_dialog.gd
scripts/ui/main_menu.gd

tests/test_ui_manager.gd               rewritten against the stack
tests/test_ui_theme.gd                 loosened to structure
```

Deleted: `scenes/ui/ui_window.tscn`, `scenes/ui/pause_menu.tscn`, `scenes/ui/inventory.tscn`,
`scripts/ui/ui_window.gd`, `scripts/ui/pause_menu.gd`, `scripts/ui/inventory.gd`.

The autoload keeps the name `UI` and the filename `ui_manager.gd` — short at every call site,
greppable on disk.

## Tests

`test_ui_manager.gd` is rewritten against `resolve()`:

- Esc from gameplay opens the shell, pauses, releases the cursor.
- Esc from the shell clears it, unpauses, recaptures.
- A modal pushed over the shell: Esc pops **one** level, the shell survives, still paused.
- `CLOSE` from a modal clears everything, not just the modal.
- `shell_enabled = false`: Esc is a no-op, tree unpaused, cursor **not** captured.
- Paused is never true with an empty stack — asserted directly, in its own case.

`test_ui_theme.gd` stops asserting hex and asserts **structure**: the theme resource loads, the
font resource resolves, and the named type variations exist. A test pinned to exact colours would
have to be edited alongside every look tweak, and this pass is going to make dozens.

## Out of Scope

- **Settings that do anything.** Resolution, sensitivity, volume, rebinding — all need persistence
  that does not exist.
- **Any inventory contents.**
- **A MAP tab, or the diorama.**
- **Save state.** The tech unlocks display as locked because they have no backing store.
- **A gameplay HUD layer.**
- **Making the main menu the boot scene.**
- **Migrating movement input to InputMap actions.** `player.gd` and `mech.gd` keep reading raw
  keycodes. Still a split convention, still accepted.
- **Localisation.** Uppercase is applied as a display transform rather than typed into strings, so
  this does not paint into a corner — but no string table is built.

## Known Gaps

- **ABILITIES couples the UI to gameplay state.** It is the first such coupling in the project,
  and its shape — a group lookup, null-safe, read-only — is what a future save system inherits.
  Worth looking at again the moment unlock flags become persistent rather than exported.
- **Uppercase Barlow Condensed at 45% opacity is the least legible combination in this spec**, and
  locked tech rows are exactly that. Expect to raise that alpha after seeing it.
- **The dim is a flat rect over a live frame.** The cel compositor's grain keeps moving underneath
  it while paused, as before. Left deliberately.
- **`Restart` reloads the scene, which is not what restart will mean later.** Accepted for the
  playtest phase.
- **Nothing validates the shell at a non-1080p window size** until it is played at one.
