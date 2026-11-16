# AIRFRAME shadows in trial: lighter

2026-11-12. Grilled with the user (5 questions). In play, AIRFRAME's shadows read as pitch black /
navy: anything out of the sun gets only the environment's ambient fill, which was a blue-grey
(0.36, 0.44, 0.66) at 0.55 energy, about 6 % of the sunlit ground in linear light (24 % on screen).

## Decisions

1. **AIRFRAME only.** RETRO and COMPOSITE light their shadows their own way and are untouched.
2. **About half as bright as sunlit ground**, measured on screen (sRGB), not in linear light.
3. **A light cool tint**: still sky-lit blue-grey, less saturated than before.
4. **One fill for everything**: cast shadows and the shaded sides of objects (mech, coat, ship,
   ramps) both lighten. No shader work; it is the ambient light.
5. **Trial only; Jetpack keeps the original.** `res://Jetpack.tscn` stays the reference with
   `resources/airframe_environment.tres` unchanged.

Unchanged: hard shadows, the sun (Jetpack's colour, 1.6 energy, 45 deg), sky, fog.

## Built

- `resources/airframe_trial_environment.tres`: a copy of the shared environment with
  `ambient_light_color` (0.62, 0.68, 0.82) at `ambient_light_energy` 0.9 (fill 0.56, 0.61, 0.74
  vs 0.20, 0.24, 0.36 before).
- `scripts/rendering/airframe_look.gd`: `ENVIRONMENT` points at the trial copy. AirframeLook is
  only used in trial; Jetpack's JetpackLook never touched the environment.
- Measured with `tests/_probe_airframe_shot.gd` at the trial spawn (75 %): shadowed ground went
  from (6, 14, 40) to (38, 44, 64) on screen against sunlit (94, 93, 96), a 0.52 on-screen
  ratio (was 0.24). The mech's lit white faces sit closer to clipping than before.
- `tests/test_airframe_look.gd`: the trial environment is expected while AIRFRAME is on; new
  `test_trial_shadows_are_lifted_and_jetpack_keeps_its_own`.

Tuning: raise/lower `ambient_light_energy` in the trial copy; push the colour toward grey for a
neutral shadow or toward (0.36, 0.44, 0.66) for the old blue.
