# PS1 UI pass (2026-11-12)

Grilled with the user, then built. Menus, inventory and HUD get one PS1 look.

## Decisions
- **No checkerboard anywhere.** The inventory checker was the 4x4 Bayer screen-door in
  `shaders/ui/inventory_ps1.gdshader` (plate alpha 0.85 became a dither). Alpha is now a hard 0.5
  cut, plates are opaque, 15-bit colour is plain rounding (bands, never dither).
- **Look only, layouts unchanged.** Plus stepped menu motion (window open/close, tab switch in
  thirds, selection in quarters) and a blinking selector bar (450 ms).
- **Font:** Pixelify Sans (OFL, `assets/fonts/PixelifySans.ttf`, licence beside it) replaces Barlow
  everywhere; theme sizes cut ~15% because it is wider.
- **Palette:** cyan stays the single accent, flat fills, no blends.
- **HUD:** restyle what exists (mission clock/message/keys, speeder boost bar as 16 hard segments,
  interaction face). Nothing new on screen.
- **Audio:** none. **Backdrops (hologram, main menu):** untouched.
- **Frames:** 1 px bevel (bright top-left, dark bottom-right), notched corners; banded 3-step title
  bars (inventory) and a two-band selected-row fill (menus). `Ps1Plate` is the shared HUD plate.

## Not played yet
Probe screenshots only. Tunables: `BLINK_MS`, `SEGMENTS`, step counts in `menu_window.gd`.
