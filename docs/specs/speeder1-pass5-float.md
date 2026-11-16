# Speeder1 pass 5 - Destiny float (2026-11-13)

Movement only. Grilled 6, all on the recommendation. Drive speeds, boost, hover, rider pose are untouched.

- **Slide:** full float. Steady slip = atan(yaw rate / grip): grip_low 1.6, grip_high 4, turn_rate_fast 1.3 -> ~39 deg at full lock. Slide starts at 40% of cruise (was 60%). It builds at 6/s and lets go at 3/s (`slide_release_ease`), so releasing the stick grips back smoothly (~0.75 s).
- **Power slide:** kept as the deep end: yaw x1.6, grip 1.1 (`drift_grip`, eased in by `_drift`) -> ~58 deg.
- **Tilt:** bank = 0.8 x slip + 0.4 x stick (`bank_unit`), cap 55 deg, ease 4. Rider lean follows the bank. Throttle / brake pitch 5 / 6 deg.
- **Camera:** nose-led. `view_heading` mixes 25% of the way to the travel line; recenter 2.0; rolls 18% of the bank.
- **Air:** nose turns at 1.4, path fixed, slide state decays at 0.8/s (a hop out of a drift lands still sliding and re-grips), bank eases to level at 0.8/s.
