# Spec: the menu refresh

> **Status:** specced 2026-09-29 from a grilling session; built the same day (see "Built" at the end).
> **Supersedes:** "The Look", "The Shell" and the per-tab layouts in `docs/specs/ui-shell.md`; the
> dropdown rows in `docs/specs/settings.md`; the panel glass and world-dim numbers in
> `docs/specs/pilot9-hologram-pause.md`. The screen stack (`resolve()`), `shell_enabled`, the
> hologram shot/timeline/input forwarding and every `Settings` value are **unchanged**.
> **Touches:** `resources/ui_theme.tres`, `scenes/ui/*.tscn`, `scenes/ui/tabs/*.tscn`,
> `scripts/ui/shell.gd`, `scripts/ui/ui_manager.gd`, `scripts/ui/settings_screen.gd`,
> `scripts/ui/main_menu.gd`, `scripts/ui/confirm_dialog.gd`, `scripts/ui/tabs/*.gd`,
> `scripts/pilot9_hologram.gd`, `shaders/ui/hologram_panel.gdshader`,
> `shaders/ui/hologram_dim.gdshader`, plus new files under File layout.

## The ask

"The menu that pops up when the player presses esc is kind of clunky. If you go to settings the
scale is off and you cannot tab back to the other tabs. The whole menu system is kind of bad ...
I want a solid menu. Buttons feel good, when you click them they dim, when you hover selections
they get highlighted, stuff like that. I want to keep the same hologram effect but maybe make it
not so strong."

## The rule

**Every menu is one 1280 x 800 window with a fixed header and footer and a scrolling middle, built
from one set of rows that visibly react to hover, focus, press and disabled. The flat pause shows
that window centred over the dim; the hologram projects the same window onto its panel, with
quieter glass.**

## Why it is broken today (found, not guessed)

- The shell is a **full-screen 1920 x 1080 page** (96 px margins, title top-left, hints at the
  bottom). In hologram mode it is drawn into a **1600 x 1000 SubViewport** on a panel that covers
  ~55 % of the screen width, so every font lands at roughly half size.
- **No scene in `scenes/ui/` has a ScrollContainer.** SETTINGS is 17 rows + 3 section headers + a
  reset row at ~44 px each, which is taller than the panel. The VBox grows past its viewport, the
  shell is pushed out of shape, and the tab strip and hint bar end up away from where the mouse ->
  panel mapping expects them. That is the "scale is off" and the "cannot tab back".
- The floating dropdown on discrete settings rows is `top_level` (screen-space positioned), which is
  fragile inside a SubViewport and would be more so inside a scroll area.
- The theme has two row looks only: plain text, or a solid white block. There is no hover, pressed
  or disabled state, and the white block is what the hologram shader classifies as "text", so it
  renders as a solid slab.

## Decisions

Decided in the grilling, in order:

| # | Decision | Chosen |
|---|---|---|
| 1 | Scope | Pause shell + all four tabs, confirm dialog, standalone settings screen, and a **re-skin only** of the main menu. The interaction prompt (HUD) is out. |
| 2 | Row states | Idle / selected / pressed / disabled, below. Hover = focus: one highlight, ever. The solid white block is gone. |
| 3 | Sound | **None** this pass. |
| 4 | Hologram strength | Keep the beam, the build wipe and the camera swing. Drop the full mono-tint, thin the glass, halve the scanlines, remove the glitch band, soften the world dim. |
| 5 | Frame + scale | One **1280 x 800** window in both modes, scrolling content. SubViewport 1280 x 800. Flat mode = centred window. |
| 6 | Tabs | Q/E + click, wrap, hover/press states, sliding underline, Q/E keycaps at the strip ends, Esc closes from any tab, per-tab row memory while open. |
| 7 | Settings rows | `‹ VALUE ›` arrow selectors replace the dropdown. Sliders get a track, fill and number. |
| 8 | Look | Dark blue-black window, teal rim and accent, cut corners, off-white text, red-orange destructive buttons, Barlow Condensed kept. |
| 9 | Motion | Short, retargeting, never blocks input, runs while paused, ignores CAMERA MOTION. |
| 10 | Tab content | GAME unchanged; **ABILITIES = list + detail pane**; INVENTORY placeholder; SETTINGS per #7. |

Decided without a question of its own: **keyboard/gamepad confirm fires on press** with a 90 ms
pressed flash (waiting for key-up feels laggy); **the mouse fires on release**, so a press can be
cancelled by dragging off.

## The window

One scene, `scenes/ui/menu_window.tscn`, is the frame every screen sits in:

```
MenuWindow (Control, 1280 x 800, centred)
  Frame (Panel, "MenuFrame" style)
    Margin (40 px left/right, 28 top, 20 bottom)
      Column (VBox)
        Header   title label + tab strip (optional)       fixed
        Rule     1 px teal @ 40 %                          fixed
        Scroll   ScrollContainer, horizontal off           grows
          <content>
        Footer   hint bar                                  fixed
```

- **Logical size 1280 x 800.** It never grows with its content; only `Scroll` does.
- **Scrolling:** vertical only. A thin scrollbar (4 px, teal @ 50 %, no buttons) is drawn only
  when the content is taller than the area. W/S move focus and `ScrollContainer.follow_focus`
  keeps the focused row in view with ~48 px of lead so the next row is always visible. The mouse
  wheel scrolls without moving focus.
- **Flat mode:** the window is centred in the game's 1920 x 1080 canvas (stretch mode stays
  `canvas_items`, so it scales with the window like everything else) over the dim.
- **Hologram mode:** the rig's SubViewport becomes **1280 x 800** (`panel_resolution`) and the
  window fills it exactly. The panel keeps its current on-screen footprint, so text is ~25 %
  larger on screen than today. `panel_height_fraction` / `panel_max_width_fraction` stay as the
  size knobs.
- **Users of the window:** the shell (title "PAUSED" + tab strip), the standalone settings screen
  (title "SETTINGS", no tab strip, same SETTINGS content), and - at 560 x 260, no scroll, no tab
  strip - the confirm dialog. The main menu does **not** use the window (see Main menu).

## The rows

One themed look, used by every selectable thing: GAME's buttons, the main menu's buttons,
ABILITIES list entries, SETTINGS rows, the confirm dialog's buttons, and the tabs themselves (tabs
use the same states on their own variation, `MenuTab`).

| State | Look |
|---|---|
| **Idle** | No background. Text off-white at **70 %**. |
| **Selected** (focus, which hover gives) | Teal fill @ **16 %**, a **3 px solid teal bar** on the left edge, text at **100 %**, label nudged **6 px right**. |
| **Pressed** (held) | Fill and text **dim to ~55 %** of their selected values while held; spring back on release. |
| **Disabled** | Text at **35 %**, no hover, **skipped by W/S** (`focus_mode = NONE`). |
| **Destructive + selected** | As selected, but the fill and bar are **red-orange** (`#FF6A3D`) instead of teal. Used by QUIT TO DESKTOP, BACK TO MAIN MENU, the main menu's QUIT and the confirm dialog's confirm button when its action loses progress. |

- **Hover moves focus** (as today, via `mouse_entered -> grab_focus`), so the mouse and the
  keyboard can never disagree about which row is lit.
- **Firing:** mouse on release (`action_mode = BUTTON_RELEASE`, Godot's default for the pointer);
  `ui_accept` on press, with the pressed look held for 90 ms so the dim is always seen.
- The states are drawn by a small script on the row (`MenuRow`, see File layout), not by
  swapping theme variations, because the nudge and the bar animate and a StyleBox cannot tween.
  The theme still carries the colours and font sizes so they are editable in one place.

## Tabs

- The strip sits in the header, right of the title. Each tab is a `MenuTab` button with the row
  states (no left bar - tabs get an underline instead).
- **Active tab:** text 100 % and a **2 px teal underline** that **slides** to the new tab over
  **120 ms** (ease-out), resizing to the new label's width. Inactive tabs are idle (70 %) and
  hover-highlight on the pointer. Tabs still never take keyboard focus.
- **Keycaps** `Q` and `E` sit at the left and right ends of the strip (they leave the hint bar).
- **Q/E and clicking** switch tabs. Both **wrap** (Q on GAME -> SETTINGS).
- **W on the first row does not climb into the strip.** Focus stays in the content.
- **Esc closes the whole menu** from any tab, as today. Tabs are not levels.
- **Row memory:** each tab remembers its last focused row (and scroll position) **while the menu
  stays open**. Switching tabs restores it; first visit focuses the first row at scroll 0. Closing
  the menu forgets all of it - the next Esc starts on GAME, first row, as today.

## SETTINGS rows

Layout of every row: `LABEL` left, control right-aligned in a fixed-width column (~300 px) so all
the controls line up.

- **Discrete rows** (WINDOW MODE, RESOLUTION, VSYNC, MAX FPS, RENDER SCALE, SHADOW QUALITY,
  ANTI-ALIASING, PIXEL FILTER, CAMERA MOTION, HOLOGRAM MENU, MOVEMENT EFFECTS):
  `‹  VALUE  ›`.
  - The arrows are always drawn: dim when the row is idle, bright when it is selected.
  - **Clicking an arrow** steps one value and keeps focus on the row. Clicking the row itself
    focuses it and does nothing else.
  - **Left/Right** step it, as today.
  - **No wrap:** at either end the arrow that would go further is drawn at 35 % and does nothing,
    so you can see where you are in the list.
  - On/off rows use the same selector (`‹ ON ›`); there is one discrete control.
  - **The dropdown is removed** (`_options_panel`, `_expanded_key`, `_add_options` and their input
    handling in `tab_settings.gd`).
- **Slider rows** (BRIGHTNESS, MOUSE SENSITIVITY, CONTROLLER SENSITIVITY, FOV):
  `[=======|------]  72`.
  - A 4 px track, teal fill up to the handle, a small square handle, the value right of it.
  - Drag or click the track to jump; Left/Right step one notch, as today.
  - The track is dim when the row is idle, bright when selected.
- **Values apply immediately**, as today. **The display revert confirm is unchanged**
  (`DISPLAY_SETTLE`, revert values, the confirm dialog).
- **Section headers** (DISPLAY, GRAPHICS, CONTROLS): teal, 18 px, SemiBold, letter-spacing ~3 px,
  with a 20 px gap above each after the first. The embedded-editor note stays under DISPLAY in
  `BodyDim`.
- **RESET TO DEFAULTS** stays the last row, and is destructive-tinted.

## The other tabs

- **GAME:** RESUME / RESTART / BACK TO MAIN MENU / QUIT TO DESKTOP, a left-aligned column of rows.
  The last two are destructive. Behaviour unchanged.
- **ABILITIES:** two columns.
  - **Left (~45 %):** a compact list, one row per ability - name, and a small status tag on the
    right (`UNLOCKED` in teal, `LOCKED` at 35 %). Section headers BASE KIT and TECH. Rows are
    focusable (for the detail pane) but pressing them does nothing.
  - **Right:** a detail pane - the selected ability's name (24 px SemiBold), status, and
    description (`Body`, wrapped). It updates as focus moves, with the same 120 ms fade as a tab
    switch.
  - Still read live off pilot9's exports; data unchanged.
- **INVENTORY:** "Nothing carried." centred, `BodyDim`. Unchanged content.

## Confirm dialog

- The same window style at **560 x 260**, centred over whatever is behind it (the shell window,
  the main menu, or the hologram panel's viewport).
- Title (`DialogTitle`), message (`Body`), two rows side by side: CANCEL left, the confirm action
  right. Focus starts on **CANCEL**. The confirm row is destructive when its action loses
  progress (all current callers do).
- The window behind it dims a further **~30 %** while it is up.

## Main menu (re-skin only)

Same layout, same three buttons (START / SETTINGS / QUIT), same title position. It picks up the new
rows (QUIT destructive), colours, font sizes and the teal title treatment. No window frame, no new
background.

## The look

| Token | Value |
|---|---|
| Window fill | `#0B1216` @ 88 % |
| Window rim | 1 px teal @ 40 % |
| Cut corners | 14 px 45° notch, top-left and bottom-right (drawn by `MenuFrame`) |
| Accent (teal) | `#40F2E6` - the hologram's existing tint |
| Destructive | `#FF6A3D` |
| Text | `#E8F1F2`; idle 70 %, selected 100 %, disabled 35 % |
| Screen dim (flat) | black @ 65 %, as today |
| Font | Barlow Condensed - Medium for rows and body, SemiBold for title, tabs, headers |
| Sizes | title 40, tabs 24, rows 26, section headers 18, body 20, hints 16 |

Keycaps in the hint bar and on the tab strip: 1 px teal @ 60 % outline, teal text, no fill.

## Motion

All tweens run with `Tween.set_pause_mode(TWEEN_PAUSE_PROCESS)` / nodes on `PROCESS_MODE_ALWAYS`,
because the tree is paused. **CAMERA MOTION off does not affect them** - they are UI, not camera.

| Event | Motion |
|---|---|
| Flat open | dim fades in over 150 ms; window fades in and scales 97 % -> 100 % over 140 ms, ease-out. **Input live immediately.** |
| Flat close | window fades out over 100 ms. **The tree unpauses and the cursor recaptures on the Esc press**, not after the fade. |
| Row selected | fill, bar and 6 px nudge animate in over 80 ms; the row losing focus animates out over 80 ms. Each change **retargets** from the current value - fast W/S never queues. |
| Row pressed | dim in ~40 ms, back on release; 90 ms hold for keyboard confirm. |
| Tab switch | content slides in 16 px **from the side you moved toward** (E from the right, Q from the left) and fades up over 120 ms; underline slides 120 ms. |
| Confirm open | fade + 95 % -> 100 % over 100 ms; the window behind dims a further 30 %. |
| Hologram mode | the window's own open fade/scale is **skipped** - the panel's reveal wipe is the open. Rows, tabs and the confirm dialog animate as above. |

Unpausing on the Esc press is flat mode only. In hologram mode the tree stays paused until the
camera is home, as `pilot9-hologram-pause.md` already specifies.

## The hologram, toned down

Kept as-is: the camera swing and shot, the beam, the reveal wipe, the timeline, input forwarding,
paused-until-home, the stencil that keeps pilot out of the dim.

`shaders/ui/hologram_panel.gdshader`:

- **No full mono-tint.** The viewport's colours pass through with a light teal cast
  (`mix(ui.rgb, ui.rgb * tint_cast, 0.25)` or similar), so the white/70 %/35 % hierarchy and the
  red-orange destructive tint survive. New uniform `tint_amount` (default 0.25).
- **Glass:** the window's own dark fill is now what shows as glass (the viewport is no longer
  transparent behind the frame). `glass_alpha` 0.78 -> **0.55**, applied to the frame's pixels;
  pixels outside the frame (the cut corners) are fully transparent.
- **Scanlines:** `scan_strength` 0.07 -> **0.035**, on the glass only, never on text, as today.
- **Glitch band: removed.**
- **Edge glow:** `edge * 0.7` bright border -> a **thin rim** (~1/3 the width, ~0.3 strength). The
  frame's own 1 px teal rim does most of the work now.
- The "text stays solid" rule stays.

`shaders/ui/hologram_dim.gdshader` defaults: `darken` 0.5 -> **0.35**, `desaturate` 0.6 -> **0.3**,
`vignette` 0.55 -> **0.3**.

`scripts/pilot9_hologram.gd`: `panel_resolution` -> `Vector2i(1280, 800)`. Nothing else.

## File layout

New:
- `scenes/ui/menu_window.tscn` + `scripts/ui/menu_window.gd` - the frame: header, rule, scroll,
  footer; `set_title()`, `set_tabs()`, `set_hints()`, `set_content()`; open/close fade for flat mode.
- `scripts/ui/menu_row.gd` (`class_name MenuRow`, extends Button) - the four states, the nudge, the
  left bar, the destructive flag, the keyboard pressed flash. Used for every row and (as a
  variation) every tab.
- `scripts/ui/menu_frame.gd` - draws the window fill, rim and cut corners (`_draw`).
- `scripts/ui/tabs/settings_selector_row.gd` - the `‹ VALUE ›` row.

Edited:
- `resources/ui_theme.tres` - new palette, sizes, `MenuTab` / `SectionHeader` / keycap looks; the
  white `StyleBoxFlat_row_selected` goes.
- `scenes/ui/shell.tscn`, `scripts/ui/shell.gd` - hosts `menu_window`; tab underline slide, wrap,
  row memory, keycaps on the strip.
- `scenes/ui/settings_screen.tscn`, `scripts/ui/settings_screen.gd` - hosts `menu_window`, no tabs.
- `scenes/ui/confirm_dialog.tscn`, `scripts/ui/confirm_dialog.gd` - small window, CANCEL-first,
  destructive confirm.
- `scripts/ui/ui_manager.gd` - flat open/close tweens; unpause on the press; the extra dim under a
  confirm. **`resolve()` is not touched.**
- `scripts/ui/tabs/tab_settings.gd`, `settings_slider_row.gd` - selector rows, slider restyle,
  dropdown removed.
- `scripts/ui/tabs/tab_abilities.gd` + scene - list + detail pane.
- `scripts/ui/tabs/tab_game.gd` + scene, `scripts/ui/main_menu.gd` + scene - `MenuRow`s,
  destructive flags.
- `scripts/pilot9_hologram.gd`, `shaders/ui/hologram_panel.gdshader`,
  `shaders/ui/hologram_dim.gdshader` - per "The hologram, toned down".
- `docs/specs/ui-shell.md`, `docs/specs/settings.md`, `docs/specs/pilot9-hologram-pause.md` - a
  pointer to this spec from each superseded section.

## Tests

- **`resolve()` untouched** - `tests/test_ui_manager.gd` stack tests pass unedited.
- **Window never grows** - with SETTINGS' full row set, the shell window's size is exactly
  1280 x 800 and the header and footer rects lie inside it (the regression for "scale is off").
- **Scroll follows focus** - focusing the last SETTINGS row scrolls it fully into view.
- **Tabs** - Q on the first tab goes to the last and E on the last goes to the first; clicking a
  tab switches to it; every tab is reachable from SETTINGS by mouse and by Q/E (the regression for
  "cannot tab back").
- **Row memory** - focus row 5 on SETTINGS, go to GAME and back: row 5 is focused. Close and reopen:
  GAME, row 0.
- **Selector** - Right at the last value does nothing and the right arrow reports disabled; clicking
  the left arrow steps down and focus stays on the row; values reach `Settings` immediately.
- **Dropdown gone** - no `top_level` control is created by the SETTINGS tab.
- **Row states** - a disabled `MenuRow` is skipped by focus navigation; keyboard accept fires on
  press; destructive rows report their tint.
- **Flat unpause on press** - after Esc closes the flat shell, `get_tree().paused` is false in the
  same frame, before the fade ends.
- **Hologram viewport** - `panel_resolution` is 1280 x 800 and the shell fills it.
- `tests/test_ui_theme.gd`, `tests/test_settings.gd`, `tests/test_pilot9_hologram.gd` updated for
  the new theme entries, the removed dropdown and the new resolution.
- Feel (timings, nudge, dim amounts, hologram strength) can only be judged in play; every number
  above is a named constant or export.

## Out of scope

- Sound (decided #3). No audio bus, no UI VOLUME row.
- A main menu redesign (layout, background, animation) - re-skin only.
- The interaction prompt / any HUD.
- Rebindable controls, new settings, new tab content.
- Gamepad glyphs in the hint bar (keycaps stay keyboard names).
- Any change to the hologram shot, beam, timing or input forwarding.

## Known risks

- **ScrollContainer inside a SubViewport with forwarded mouse events** - wheel events must be
  forwarded like clicks; check `follow_focus` works when focus comes from a pushed key event.
- **Glass alpha from the frame** - the panel shader now needs the viewport's alpha to tell frame
  from corner cut-outs; the SubViewport must keep `transparent_bg = true`.
- **Letter-spacing** in Barlow Condensed is a `FontVariation` `spacing_glyph` - check it does not
  break the width of the ABILITIES status tags.

## Built

Built 2026-09-29 to the text above. Where the build departs from, or fills a gap in, the spec:

- **No `class_name`.** `MenuRow` is `scripts/ui/menu_row.gd`, loaded by `preload` / `extends "res://..."`.
  A `class_name` needs the editor's global class cache, which a headless run does not refresh.
- **Tab bodies build once.** The SETTINGS rows and ABILITIES list are created once and re-synced by a
  `refresh()` method (the shell calls it on every show), never freed and rebuilt, so the shell's
  remembered focus paths stay valid. SETTINGS builds on the first `refresh()` rather than `_ready()`
  because the UI autoload's `_ready` can run before `Settings` exists.
- **`present()` / `dismiss()` on screens.** `ui_manager.gd::_update_screens` calls `present(in_hologram)`
  on a screen that just arrived and `dismiss()` (a 100 ms fade, then hide) on the shell or settings
  screen that just left, flat mode only; the tree is unpaused before the fade. `set_behind_dialog()`
  puts a 30 % `Veil` over the window under a confirm.
- **Enter on an on/off selector flips it**; on a longer list it does nothing. (The spec left ENTER on
  selectors undefined.)
- **Hint bar:** the Q/E hint moved to keycaps on the tab strip; the bodies' hints no longer list it.
- **Scroll lead:** `MenuWindow.scroll_target()` is the pure rule (48 px lead); a row lit by the
  pointer (`MenuRow.last_hover_frame`) is not scrolled into view, or hovering near an edge would
  scroll the row out from under the cursor.
- **Tabs' hover** is tracked by the tab itself (they never take focus).
- **Idle ability tags** are teal `UNLOCKED` / dim `LOCKED`; the ABILITIES rows use tighter padding so
  all eleven fit without scrolling.
- Checked with `tests/test_menu_refresh.gd` and screenshots of the flat and hologram menus (GAME,
  ABILITIES, SETTINGS top and bottom, confirm). **Not yet played:** hover feel, the nudge, timings,
  the hologram glass strength, mouse over the projected panel and wheel scrolling through it.
