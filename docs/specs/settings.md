# settings

**2026-09-14.** A settings screen that writes to disk: window mode, resolution, vsync, frame
cap, brightness, render scale, shadow quality, anti-aliasing, the pixel filter, two
sensitivities and FOV. Reached from the shell's SETTINGS tab while playing, and from the main
menu's SETTINGS entry while not.

## The problem

`docs/specs/ui-shell.md` built a SETTINGS tab and put nothing in it, and the reason it gave was
honest: *"Options that actually write and persist settings are out of scope; that work touches a
save system which does not exist."* It still does not exist. **No script or scene in this
project contains the string `user://`** — nothing has ever been written to disk at runtime.

So the shell ships a tab reading "No settings yet." and the main menu ships a SETTINGS button
whose entire body is `print("[UI] Settings - not implemented yet.")`. Two doors, both painted on.

The requirement is not "a settings menu". It is **the first thing in this project that remembers
anything between launches**, and the shape of that is worth more thought than the twelve rows
sitting on top of it.

## Scope, decided up front

**Settings only. Not a save system.** `docs/game-overview.md` promises tech unlocks, map
progress, contracts and cosmetics, all of which need persistence too. They do not need *this*
persistence. Settings are per-machine and must survive a deleted save; run state is per-
playthrough and must not. They end up in separate files whatever happens, so building a general
save service now would mean designing a format around the one client least like the others.

**Two things asked for are not built, on facts rather than preference:**

- **Volume.** There is no `AudioStreamPlayer` anywhere in the project and no custom audio buses.
  The game is silent. A volume row would move a number attached to nothing, and the day sound
  arrives it will want a bus layout the row would have to be rewritten against anyway.
- **Key rebinding.** `ui-shell.md` lists it out of scope, and separately: `player.gd` and
  `mech.gd` read raw keycodes rather than InputMap actions — `mech.gd:243` tests `KEY_F`
  directly. A rebinding screen would silently fail to rebind half the game's verbs. That is
  worse than not having one.

**There is no Low / Medium / High preset**, because there are no LOD meshes to switch between and
a preset that only moves shadows and MSAA is three rows wearing a hat. SHADOW QUALITY, RENDER
SCALE and ANTI-ALIASING are exposed individually, and are the three real levers the project owns
today.

## What it is

```
scripts/settings.gd                     autoload `Settings`: the model, the file, the apply
scripts/rendering/brightness.gd         autoload `Brightness`: CanvasLayer 90, the gamma overlay
shaders/brightness.gdshader             pow(screen, 1/gamma)

scenes/ui/tabs/tab_settings.tscn        the rows - instanced twice, see Two Hosts
scripts/ui/tabs/tab_settings.gd
scenes/ui/settings_screen.tscn          title + content box + hint bar, for the main menu
scripts/ui/settings_screen.gd

tests/test_settings.gd                  headless, against the static model
```

Touched: `project.godot` (the two autoloads, and Left/Right come off the tab actions),
`scripts/ui/main_menu.gd`, `scripts/ui/confirm_dialog.gd` (a countdown), `scripts/ui/shell.gd`
(one hint), `scripts/ui/tabs/tab_empty.gd` (its header comment), `scripts/pilot9.gd`,
`scripts/mech.gd`, `scripts/rendering/pixelate.gd`, `scenes/trial.tscn` and
`scenes/test_platform.tscn` (one group each).

## The model is static

The registry and every value operation are **static functions on `settings.gd` with no tree
behind them**, the same discipline `ui_manager.gd` applies to `resolve()` and for the same
reason: these are the parts that fail silently. A row that clamps wrong at one end, a config that
loads a stale key as garbage, a default that drifts from `project.godot` — all of them look
exactly like a settings screen that works.

```gdscript
# key, label, section, values, default index
const DEFS := [ ... ]

static func step(key: StringName, index: int, direction: int) -> int
static func sanitise(raw: Dictionary) -> Dictionary
static func defaults() -> Dictionary
```

`step()` **clamps, it does not wrap.** Pressing Left on RESOLUTION at 1280x720 stays at
1280x720. Wrapping is right for the tab strip, where there are four destinations and you are
cycling; it is wrong for an ordered scale, where holding a key to reach the end and having the
value silently reappear at the other end is how you overshoot every time.

The applying half — `DisplayServer`, `RenderingServer`, the viewport, the gamma uniform — is a
thin `_apply(key, value)` match statement, and is deliberately not tested. See What The Test
Fences.

## Persistence

`user://settings.cfg`, via `ConfigFile`, three sections mirroring the three on screen:

```ini
[meta]
version=1

[display]
window_mode="borderless"
resolution=Vector2i(1920, 1080)
vsync="on"
max_fps=0
brightness=1.0

[graphics]
render_scale=1.0
shadow_quality="high"
msaa="4x"
pixel_filter=-1

[controls]
mouse_sensitivity=1.0
controller_sensitivity=1.0
fov=75.0
```

**Written on a 0.5 s debounce**, a one-shot `Timer` in the autoload restarted by every change.
Holding Left on MOUSE SENSITIVITY walks thirty-six values; writing a file on each is thirty-six
writes for one decision. Saving only on close is the other obvious answer and is worse — a
crash, an editor stop, or a `get_tree().quit()` path that misses the flush loses everything the
player just set, and the failure is invisible until next launch. Half a second is the most that
can ever be lost.

**A missing file is not an error**, it is a first launch: `defaults()` is used and nothing is
written until something changes.

**`sanitise()` is total.** Every key absent from the file falls back to its default; every value
not in its `values` list falls back to its default; a `version` that is not 1 is ignored
wholesale and defaults are used. A hand-edited or half-written config must produce a playable
game, because the recovery path for an unplayable one is a `user://` directory the player will
never find. The `version` key costs one line now and is the difference between a future rename
loading garbage and a future rename loading defaults.

## The rows

Thirteen, in three sections. Section headers reuse the `SectionHeader` theme variation that
`tab_abilities.gd` already draws for BASE KIT and TECH — it exists, it is 22 px at 45 % white,
and nothing new is needed.

| Section | Row | Values | Default |
|---|---|---|---|
| DISPLAY | WINDOW MODE | WINDOWED / BORDERLESS / EXCLUSIVE | BORDERLESS |
| | RESOLUTION | 16:9 list, filtered to the screen | native |
| | VSYNC | OFF / ON / ADAPTIVE | ON |
| | MAX FPS | UNCAPPED / 30 / 60 / 120 / 144 | UNCAPPED |
| | BRIGHTNESS | 0.60 - 1.40, step 0.05 | 1.00 |
| GRAPHICS | RENDER SCALE | 50% / 75% / 100% | 100% |
| | SHADOW QUALITY | LOW / MEDIUM / HIGH | HIGH |
| | ANTI-ALIASING | OFF / 2x / 4x / 8x | 4x |
| | PIXEL FILTER | OFF / 160x90 ... 640x360 | OFF |
| CONTROLS | MOUSE SENSITIVITY | 0.25x - 2.00x, step 0.05 | 1.00x |
| | CONTROLLER SENSITIVITY | 0.25x - 2.00x, step 0.05 | 1.00x |
| | FOV | 60 - 110, step 5 | 75 |
| | RESET TO DEFAULTS | - | - |

**Every graphics default is what `project.godot` runs today**, read off it rather than chosen:
`msaa_3d=2` is 4x, `directional_shadow/size=8192` with `soft_shadow_filter_quality=4` is HIGH,
the pixel filter ships `visible = false` in both scenes, `camera_3d.fov` is 75. A first launch
must render a frame identical to the game that exists now, or this feature has quietly changed
the art direction.

### DISPLAY

**Godot cannot enumerate windowed modes.** There is no API for "what resolutions does this
display support in a window", so RESOLUTION is a hand-written 16:9 list — 1280x720, 1600x900,
1920x1080, 2560x1440, 3840x2160 — filtered to those at or below
`DisplayServer.screen_get_size()`, with the screen's own size appended if it is not already
there.

16:9 only, and that is not laziness: `project.godot` leaves `window/stretch/aspect` unset, so it
defaults to `keep`, and the UI is laid out at exactly 1920x1080 and letterboxed at any other
aspect. Every 16:9 size maps to the base viewport exactly. Offering 16:10 would be offering bars.

**MAX FPS exists because VSYNC OFF without it is a trap.** An uncapped menu on a static frame
will happily pin a GPU at four figures.

### GRAPHICS

**SHADOW QUALITY is the substitute for the quality preset you cannot have.** LOW / MEDIUM / HIGH
map to a 2048 / 4096 / 8192 directional atlas via
`RenderingServer.directional_shadow_atlas_set_size()`, with
`directional_soft_shadow_filter_set_quality()` moving alongside. An 8192 atlas at the highest
soft filter is close to the most expensive configuration Forward+ offers, and with no LOD meshes
to drop it is by a wide margin the largest frame-time lever in the project. It is also a look
decision — the cel treatment leans on those shadows — which is exactly why HIGH is the default
and the other two are opt-in.

**RENDER SCALE is the other half of the missing preset.** `Viewport.scaling_3d_scale` renders
the 3D at a fraction of window size and upscales it, leaving the UI — laid out at 1080p and
stretched — crisp. That split is worth having precisely because this game's UI is hairlines and
condensed type at 16 px, which is the first thing a global resolution drop would destroy.

Only 50 / 75 / 100. No supersampling above 100: the project has no performance headroom to spend,
and a row whose top entries make the game slower needs a warning the theme has no vocabulary for.

### CONTROLS

**Sensitivity is a multiplier, never a value.** This is the one row that would otherwise ship
broken.

`pilot9.gd:471` exports `mouse_sensitivity = 0.005`. `mech.gd:58` declares
`const MOUSE_SENSITIVITY = 0.0025` — a different number, in a different file, as a constant. A
setting wired to pilot9 alone works until you press F, and then the mech's camera moves at a
fixed speed the player cannot change and did not ask for. There is no message; it simply stops
obeying.

So `Settings.mouse_sensitivity` is a **scalar from 0.25x to 2.00x** applied to both, and
`mech.gd`'s const becomes a var. The authored values stay where they are and keep meaning what
they mean — the gap between pilot9's 0.005 and EXIA's 0.0025 is a deliberate feel decision about
a nine-metre machine, and a settings screen has no business flattening it.

### FOV applies live

FOV is the same argument in a different shape, and it is the one row that shipped broken.

The first build wrote `Settings.fov` into pilot9's `base_fov` field in `_ready()`, after the
`base_fov = camera_3d.fov` line that captures the rig's own value, and this document spent a
paragraph on getting that ordering right. The ordering was right and the row still did nothing:
a field written once at spawn is only ever as fresh as the last spawn, so the value saved to
disk, survived a relaunch, and never reached a pilot who already existed. The menu showed 80
and the game rendered 75. **A settings value that a consumer copies is a settings value that
does not apply.**

So `base_fov` is not a field. It is a property that reads the autoload:

```gdscript
var base_fov: float:
	get: return Settings.fov
```

`_handle_camera_fov()` is unchanged and `sprint_fov_boost` still stacks on top of it exactly as
before. There is nothing to push, nothing to order, and nothing to go stale — which is how the
two sensitivity rows worked correctly from the start, since `pilot9.gd` and `mech.gd` multiply
by `Settings.mouse_sensitivity` at the point of use on every frame they turn.

**Both cameras respect it.** EXIA's own camera reads `Settings.fov` in `mech.gd`'s `_process()`,
next to the rig placement and before the handover block, so a pan reading `_handover_to.fov`
gets the current frame's value. This is not the sensitivity argument in reverse: the gap between
pilot9's 0.005 and EXIA's 0.0025 was a deliberate feel decision about a nine-metre machine,
but **no camera in `pilot9.tscn` or `mech.tscn` sets `fov` at all**. The 75 that `base_fov` used
to capture was Godot's default, not a framing choice, so there was no authored intent to
preserve — and a comfort setting that silently stops applying the moment you press F is the
same failure the sensitivity scalar exists to prevent.

`mech.gd`'s `_handover_from_fov = Settings.fov` line in `_ready()` is gone. `_begin_handover()`
overwrites that variable from `watching.fov` before anything ever reads it, so the line was
dead on arrival.

**No INVERT Y.** It is the only controls row that is new gameplay code rather than a scale on an
existing number — a flag threaded through pilot9's mouse path, pilot9's stick path and EXIA's.
`pilot9.gd`'s own header records that stick sign handling has already caused trouble once. It is
a small task and it is not this one.

## A row is a Button

`resources/ui_theme.tres` defines exactly four base types — `Button`, `Label`, `PanelContainer`,
`HSeparator` — plus Label variations. There is **no `HSlider`, no `OptionButton`, no `CheckBox`
entry at all.**

Drop an `HSlider` into the content box and it renders in Godot's stock theme: a grey rounded
grabber and a blue fill, in the middle of a screen built entirely from white hairlines and
Barlow Condensed. An `OptionButton` is worse, because it opens a `PopupMenu` needing its own
panel, hover, separator and checkmark styling. `ui-shell.md` chose a typeface and a hairline
palette specifically so the UI would not *"look like a default engine overlay"*, and stock
widgets are the fastest available way to undo that.

Meanwhile `Button` **is already the white selected row**: `styles/focus` and `styles/hover` are
both `StyleBoxFlat_row_selected`, `font_focus_color` is black. The thing the spec's look section
is built around is a focused Button and nothing else.

So every row, the continuous ones included, is a themed `Button`:

```
SHADOW QUALITY ........................................... HIGH
```

Label left, current value right, both inside the button so the white fill takes the whole row on
focus exactly like GAME's entries do. Left and Right step the value; Enter and a mouse click step
forward; held keys repeat on the InputMap's own echo events. Continuous settings become ordered
steps — brightness in 0.05s, FOV in 5s — which is a real loss of fine control on BRIGHTNESS and
MOUSE SENSITIVITY, accepted in exchange for zero new theme surface and one consistent selection
treatment on the screen.

A themed `HSlider` is the upgrade path if stepping proves too coarse in play. It is not free:
HSlider's grabber is an **icon**, a `Texture2D`, not a `StyleBox` — it needs a new art asset,
which is a different kind of task from a theme edit.

**RESET TO DEFAULTS goes through `UI.confirm`**, giving that modal a fourth caller. It sits below
CONTROLS, one row under FOV, in a list navigated with arrow keys — a confirm is not ceremony
there. It is also the only recovery path for a brightness setting dragged to unreadable, since
the timed revert below guards display mode only.

## Left and Right

`project.godot` binds `tab_prev` to **Left arrow** + Q + pad button 9, and `tab_next` to **Right
arrow** + E + pad button 10. `shell.gd:127` calls `set_input_as_handled()` on both whenever the
shell is on top. **Left and Right do not reach the focused control and never have.**

Nothing noticed, because until now no screen in the shell had a control that wanted them.

The arrows come off `tab_prev` / `tab_next`. Tabs stay on **Q / E** and on **LB / RB**, which is
the console idiom anyway — shoulders page, the stick and d-pad navigate. Left and Right then fall
through to `ui_left` / `ui_right`, which **are not overridden in `project.godot` at all** and so
still carry Godot's built-in defaults: arrow keys and d-pad. Row adjustment works on keyboard and
on a controller with no custom input handling written for either.

The pad was never affected — d-pad left and right (buttons 13 and 14) are bound to nothing. This
is a keyboard-only collision with a two-line fix, listed under Amendments below because it
contradicts a row of `ui-shell.md`'s input table.

**The hint keycap reads `LEFT/RIGHT`, not arrow glyphs.** `shell.gd`'s own comment on
`DEFAULT_HINTS` explains why: Barlow Condensed has no arrow glyphs and a missing one renders as a
box. The settings tab declares
`[W/S SELECT] [LEFT/RIGHT ADJUST] [ENTER CONFIRM] [Q/E TAB] [ESC CLOSE]`.

## Brightness is an overlay

**There is no shared `Environment` to write to.** `trial.tscn:22` and `test_platform.tscn:16`
each embed their own `Environment` sub-resource, and the main menu has no 3D at all. Writing
`adjustment_brightness` would mean a group lookup plus `adjustment_enabled = true` set correctly
in every scene, forever — and `game-overview.md` is explicit that **five hand-modeled districts
are the entire remaining project**. That is five future scenes each of which must remember, with
a failure mode of "brightness silently does nothing in map 3".

So brightness is a full-screen pass owned by an autoload, and the project already has the
pattern: `shaders/pixelate.gdshader` reads `hint_screen_texture` from a `ColorRect` on a
`CanvasLayer` and crunches the finished frame. The gamma shader is the same trick with a shorter
body:

```glsl
COLOR = vec4(pow(texture(screen_tex, SCREEN_UV).rgb, vec3(1.0 / gamma)), 1.0);
```

True gamma rather than an alpha wash, so it lifts shadows instead of fogging the image toward
grey — which matters more than usual here, because the cel pipeline puts a lot of information in
near-black and the outline pass is pure black by definition.

### Layer 90, under the UI

`UI` is `layer = 100`. The pixel filter and the interaction prompt are both on the default layer
1. The gamma overlay sits at **90**: above the world and above the pixel filter — the downsample
is a stylistic pass on the render, and brightness belongs after it — and **below the menus**.

Two reasons it goes under rather than over. The UI's legibility was tuned by eye against a 65 %
dim, and a gamma multiplied on top of that makes the menu the least readable thing on screen at
exactly the moment the player is trying to read the row that would fix it. And `ui-shell.md` is
emphatic that the dim is one node and *"two stacked screens must not double-darken"* — a second
full-screen darkening pass over the UI layer is that rule broken by a different route.

The bonus is that it makes a calibration screen unnecessary: the world is still visible through
the 65 % dim while the shell is open, so changing BRIGHTNESS previews live against real geometry.

`mouse_filter = MOUSE_FILTER_IGNORE` on the rect, or it eats every click on the game beneath it.

## Live apply, and the timed revert

**Every row applies the instant it changes.** BRIGHTNESS, both sensitivities and FOV can only be
judged by feel, and an Apply button would mean setting them blind. It also keeps any notion of
dirty state out of a screen that otherwise has none.

Two rows can strand a player: a RESOLUTION larger than the display, or an EXCLUSIVE mode the
monitor rejects. Both leave someone unable to reach the menu that would undo them, and the manual
fix is deleting a file in `user://`.

So **WINDOW MODE and RESOLUTION additionally push the confirm modal with a fifteen-second
countdown** — `KEEP THIS DISPLAY MODE?` — reverting to the previous pair if it expires. CONFIRM
keeps it; CANCEL reverts immediately. Nothing else in the screen gets a countdown, because
nothing else can hide the screen.

**The confirm is debounced, not per-step.** The first build raised it on every arrow press, and
the modal takes focus, so walking the resolution list from 1280x720 to 3840x2160 was four
separate modal round-trips — the row interrogating you once per notch about a change you were
still in the middle of making. Stepping is now silent and restarts a one-second timer; a second
after you stop, one confirm covers the whole run.

Which makes *when the revert target is captured* the load-bearing detail. It is taken on the
**first** step of a run and held, never overwritten. Four steps forward and CANCEL returns you
to where you began rather than to the third notch — reverting to a value you were only passing
through would strand you in a different way than the one this exists to prevent.

`confirm_dialog.gd` grows an optional `countdown: float` on `setup()`, appending the remaining
seconds to the message and emitting `cancelled` when it reaches zero. It keeps the property that
makes it reusable: **it still only reports which button was pressed** — the timeout emits the
same `cancelled` a click does, and `ui_manager.gd` continues to own the callback. The dialog does
not learn what a display mode is.

The timer runs while paused for free: the dialog is a child of the `UI` autoload, which is
`PROCESS_MODE_ALWAYS`, and children inherit it.

## The editor exemption

`project.godot` sets `window/size/window_width_override=2560x1440`, which applies **only when
running from the editor**. The F6 playtest window is 1440p; an exported build would be a 1080p
window.

If `Settings` applied a saved window mode and resolution on boot it would override that override,
and every F6 would go fullscreen. That is friction paid on every iteration of a project whose QA
loop is "play it" — the same argument `ui-shell.md` used for refusing to make the main menu the
boot scene.

**The first build drew that line in the wrong place.** It skipped those two rows in the editor
*entirely*, which meant they were inert in the only way this project is ever played during
development — while still raising the fifteen-second confirm. Pressing Right on RESOLUTION
changed nothing, then asked whether you wanted to keep the nothing. The row was not broken in
some subtle way; it was switched off, and the confirm made it look like it was working.

Applying a setting is two moments, and only one of them was ever the problem:

- **On change** — a row the player just stepped. This applies everywhere, editor included. It is
  the only way these two rows can be QA'd at all, since this project is tested by playing it.
- **On boot** — the sweep `_load()` does over every row at startup. This is what fights
  `window_width_override`, and this is what stays exempt in the editor. An exported build has no
  such override and applies both.

`_apply()` takes a `booting` flag and `_skip_display()` is the whole of the rule. Everything
else — vsync, frame cap, brightness, render scale, shadows, MSAA, the pixel filter, sensitivity,
FOV — applies in-editor on boot and on change exactly as it does in a build.

Default window mode is **BORDERLESS at the display's native size**, which is what a player
expects on first launch and avoids a 1080p window floating on a larger monitor.

## Two hosts, one content scene

The shell is a pause construct and does not exist on the title screen; `ui-shell.md` says so, and
routing the main menu into it would put RESUME and RESTART in front of a game that is not
running.

So `tab_settings.tscn` holds the rows and nothing else, and is instanced **twice**:

- by `shell.gd`, from its existing `TABS` array — no change to `shell.gd` beyond one hint;
- by `settings_screen.tscn`, a thin frame of title, content box and hint bar, registered in
  `ui_manager.gd`'s `SCREENS` as `&"settings"` with `pauses: true`.

`main_menu.gd`'s `print()` becomes `UI.open(&"settings")`. The stack handles the rest already:
`BACK` pops one level to an empty stack, and `cursor_captured` stays false because
`shell_enabled` is false on the main menu. **Nothing in `resolve()` changes**, which is the point
of having registered screens at all.

`&"settings"` is **only ever pushed by the main menu**. In-game the same rows are reached as a
tab, not as a stack entry; pushing the screen over the shell would draw the settings twice.

The cost is about thirty lines of chrome duplicated between `settings_screen.tscn` and
`shell.tscn`. Extracting the shell's title and hint-bar construction into something shared is the
cleaner answer, and was rejected as a refactor of working UI code performed ahead of the feature
that motivates it. If a third host ever appears, that is the moment.

**Both instances exist simultaneously** — `ui_manager.gd` spawns every registered screen in
`_ready()`. They cannot disagree, because neither holds state: both read `Settings` on show.
`tab_settings.gd` rebuilds its rows in `focus_first()`, which the autoload calls whenever a
screen reaches the top of the stack, exactly as `tab_abilities.gd` already does to avoid going
stale against a player spawned later.

`tab_empty.gd` survives — INVENTORY still uses it — but its header comment claims it is shared
with SETTINGS and needs correcting.

## The pixel filter

Alone among the rows, this one does not drive a global. `PixelFilter` is a `CanvasLayer` *inside
each scene* (`trial.tscn:208`, `test_platform.tscn:82`), shipping `visible = false`, driven by
`pixelate.gd`'s QA keys `O`, `[`, `]` and backslash, bound as raw keycodes.

Two problems: the setting must reach a node that may not exist — the main menu has none — and its
value can drift the moment somebody presses `]`.

**`PixelFilter` joins a `pixel_filter` group in both scenes.** `pixelate.gd` reads `Settings` in
`_ready()` and applies it; the row writes through the group with `get_first_node_in_group()` and
tolerates null. This is the third use of the group-lookup convention `ui-shell.md` introduced
with `&"player"` and `button-door.md` reused, and it costs one property on one node per scene.

**The QA keys stay, and write back through `Settings`.** They exist so the filter can be A/B'd
mid-playtest without pausing, which is worth keeping; routing them through the same setter means
pressing `]` and then opening the menu shows agreement rather than a lie. The alternative —
moving the filter beside the gamma overlay in an autoload — is the tidier end state, and was
rejected for now because it deletes a working scene-level effect from two scenes during a task
about something else.

## What the test fences

`tests/test_settings.gd`, headless, loading the script and calling static functions with no tree
— the shape `test_ui_manager.gd` uses on `resolve()`, and for the reason it states.

Ranked by how silently each fails:

1. **`sanitise()` is total.** An empty dictionary, a missing section, an unknown key, a value
   outside its list, and a wrong `version` each produce a complete, playable set of defaults. A
   config that half-loads gives a game that looks fine and is configured wrong.
2. **Defaults match `project.godot`.** Asserted by reading the file, the way
   `test_pilot9_jump_feel.gd:462` already reads it: `msaa_3d=2` is the 4x default,
   `directional_shadow/size=8192` is HIGH. A first launch must not change the render.
3. **`step()` clamps at both ends and does not wrap**, on a discrete row and on a stepped
   continuous one. The classic off-by-one, and invisible in play.
4. **Round-trip.** Every key written and read back returns its own value, including the
   `Vector2i` resolution, which is the one type `ConfigFile` could plausibly mangle.
5. **Every `DEFS` entry has a default that is a member of its own `values`.** A typo here makes
   one row unselectable at its default and is otherwise undetectable.
6. **Left and Right are not bound to `tab_prev` or `tab_next` in `project.godot`.** The whole
   row-adjustment mechanism rests on this, and it is one careless InputMap edit from coming back.

Two more were added after the first build shipped, both fencing failures it actually had:

7. **The suite does not read `user://settings.cfg`.** Autoloads load during headless runs, so
   `Settings` was reading the developer's own config and every test touching a settings-driven
   number silently inherited it. A fresh clone passed and the same commit failed on a machine
   where somebody had nudged a slider — which is what turned two tests in
   `test_pilot9_sprint_fov.gd` red, on tests that have nothing to do with settings.
   `Settings.is_test_run()` makes a headless run take the first-launch path and never write.

   It tests `DisplayServer.get_name() == "headless"` rather than `OS.has_feature("headless")`,
   which is **false** under `--headless`: that feature set describes an *export*, and a headless
   run of the editor binary is not one. The display driver is the thing that actually differs.

8. **FOV reaches a pilot who already exists.** Asserted in `test_pilot9_sprint_fov.gd` by moving
   `Settings.fov` *after* `_ready()` has run and checking `base_fov` followed. A field captured
   at spawn passes any assertion made on the spawn frame, which is why the original version of
   that test — asserting `base_fov == camera_3d.fov` — was green for the whole period the row
   did nothing.

**Not tested:** `DisplayServer`, `RenderingServer`, `Viewport` and the gamma uniform. A headless
run has no window, no display server worth the name, and no rendering to inspect; asserting them
would be testing Godot. This is the deliberate trade behind making the model static — the
untested half is a `match` statement with no branches of its own.

## What this is not

Not a save system. Nothing here knows about tech unlocks, checkpoints or contracts, and the
`[meta] version` key is the only concession to a future beyond settings.

Not an accessibility pass. No colourblind modes, no subtitle settings, no UI scale, no reduced
motion, no hold-versus-toggle. FOV happens to serve motion sickness and brightness happens to
serve poor displays, but neither was chosen for that, and the screen should not be mistaken for
having covered it.

Not a rebinding screen, not a volume mixer, not a quality preset — each for a reason given above
rather than by omission.

## Amendments to ui-shell.md

- **Out of Scope loses "Settings that do anything."** Resolution, sensitivity and volume were
  listed together; the first two are now built, and volume is out for a different reason.
- **The input table's tab row changes.** `tab_prev` / `tab_next` were listed as *"Left / Right,
  Q / E"*; Left and Right are removed, and the reasoning is in Left And Right above.
- **SETTINGS is no longer an empty tab**, and the main menu's SETTINGS entry is no longer a stub.
  `ui-shell.md`'s claim that it *"does nothing yet"* is superseded.
- **"No new HUD" was already superseded** by `button-door.md`'s interaction prompt. The gamma
  overlay is a second always-present full-screen layer, and is noted here for the same reason.

## Known Gaps

- **Continuous settings are stepped, not dragged.** BRIGHTNESS crosses its range in seventeen
  presses and MOUSE SENSITIVITY in thirty-six, with held-key repeat carrying most of it. If that
  reads as coarse in play, the fix is a themed `HSlider` and a grabber texture — an art task, not
  a theme edit.
- **The fifteen-second revert guards display mode only.** BRIGHTNESS can still be set to
  unreadable; RESET TO DEFAULTS is the way back, and it is a row you must be able to read to find.
- **Non-16:9 displays letterbox**, because `stretch/aspect` defaults to `keep`. Unchanged from
  today, but a resolution list makes it visible for the first time.
- **RESOLUTION is a hardcoded list.** Godot exposes no windowed-mode enumeration, so an unusual
  panel gets its native size appended and nothing else tailored.
- **Thirty lines of chrome are duplicated** between `settings_screen.tscn` and `shell.tscn`.
- **The pixel filter remains scene-owned**, so it is absent on the main menu and the row is inert
  there. Moving it beside the gamma overlay is the end state.
- **Nothing validates the screen at a non-1080p window**, which was already `ui-shell.md`'s last
  known gap, and is now a screen whose whole purpose is changing that window.
- **`mech.gd` gains its first settings dependency.** It reads sensitivity in `_unhandled_input()`
  and FOV in `_process()`, which is a new coupling in a file `button-door.md` already flagged as
  entangled and overdue its own pass.
- **Nine of the thirteen rows have never been watched running.** MOUSE SENSITIVITY and
  ANTI-ALIASING are confirmed by use; FOV and the display rows are covered above. VSYNC, MAX FPS,
  BRIGHTNESS, RENDER SCALE, SHADOW QUALITY, PIXEL FILTER and CONTROLLER SENSITIVITY are believed
  correct from reading, and a headless suite cannot see a window, so none of them is fenced by
  anything but eyes on the game.
- **`is_test_run()` also covers the `--quit-after` smoke boot**, which therefore boots on shipped
  defaults rather than the local config. That is the intent — a smoke boot should be
  deterministic — but it means the boot path for a *saved* config is only ever exercised by
  playing.
