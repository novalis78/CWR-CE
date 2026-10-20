# Meadow grass study

A small, original static-mesh example for the Mac creator workflow. It generates
curved grass blades, a colour texture, and three visual LODs (504 / 168 / 56
triangles), then packs an optional addon. It does not replace world vegetation.
This is a pipeline prototype, not final art or a landscape performance benchmark.

```sh
bash examples/vegetation/build.sh
```

Set `BLENDER` and `POSEIDON_TOOLS` to override the executable paths. The generator
does not need game assets. The engine viewer needs the Remastered demo or full data.
All generated files go to `build/grass-study` by default:

- `grass-study.blend`: editable source with the three meshes and packed texture.
- `source/nvl_grass/`: MLOD model, PAA texture, and config.
- `@grass-study/`: optional mod with the `NVL_GrassStudy` object class.
- `grass-study.png`: Blender render, not an in-game screenshot.

Add `@grass-study` in the launcher, then click **Preview Model…** and choose
`source/nvl_grass/grass.p3d`. Press F1 in the viewer for controls. Removing the
mod from the launcher disables it. The mod adds an object class; it does not
automatically place grass in existing missions or replace terrain objects.

For an automated capture using the game's renderer from the repository root:

```sh
dist/arm64-macos-rwdi-local/PoseidonGameDemo \
  --work-dir /path/to/Demo --mod "$PWD/build/grass-study/@grass-study" \
  --window --no-strict --no-splash --no-mouse-grab --timeout 30 \
  --viewer --model "$PWD/build/grass-study/source/nvl_grass/grass.p3d" \
  --auto-screenshot "120:$PWD/build/grass-study/engine-preview.png"
```

The MLOD writer in `create_grass.py` only handles this generated static mesh.
It does not export arbitrary Blender scenes, rigged characters, proxies, or
collision meshes. Grass is intentionally non-colliding. The next art pass can
refine blade shape, colours, and LOD transitions before any wider replacement.

Use DXT1 for this opaque texture. DXT5 currently produces texture-format errors
in the runtime mip loader, despite being supported by the conversion utility.
