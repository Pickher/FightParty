# Model-derived Medivac sprite

`idle.png` is an offline 512×512 RGBA orthographic render of the user's uploaded `assets/models/medivac/medivac.glb` at cloud/test commit `56db57a`. It is not a newly generated or redesigned model. Original geometry, UVs and embedded base-color material are preserved; neutral lighting and a fixed oblique camera produce the 2D view. Full source hash and render metadata are in `source.json`.

Source GLB: 500,748 bytes, 4,701 vertices, 6,056 triangles, one mesh/material, one embedded 1024×1024 JPEG. No bones or animation are introduced. The original GLB is not modified.

Reproduce offline with installed Blender 4.3.2:

```sh
blender --background --factory-startup -t 4 --python tools/art/bake_medivac.py
```

The script only loads this GLB and writes `idle.png`/`source.json`; it does not run Godot, the game, tests or packaging. CPU Cycles, 96 samples, fixed seed, no denoiser (the available Blender build lacks OpenImageDenoise). Different Blender versions may produce slightly different lighting pixels.

`UnitArt` lazily caches the texture once and fits its aspect ratio inside the existing unit/icon bounds. It retains original texture RGB and incoming UI alpha. Battlefield, shop and troop configuration all share this entry point. Existing hidden-enemy placeholders, team cues, selection/status overlays and medical beams are unchanged. If the sprite resource is unavailable, the old procedural Medivac silhouette remains the fallback. There is no per-unit 3D viewport or mesh instance.

This is one fixed view, not a directional/animated sprite sheet. Gameplay stats, collision, targeting, healing and replay rules are unchanged, so no rules/version bump is needed.

Static/asset QA: source hash and dimensions checked; transparent corners and non-clipped alpha bounds verified; visually inspected the 512 px render and 20/28 px downsample previews. Silhouette remains recognizable at small scale; fine medical markings need a closer view. No Godot import or in-game/runtime verification has been performed. Godot will import the PNG normally when the project is opened; visual acceptance in the real game remains pending.
