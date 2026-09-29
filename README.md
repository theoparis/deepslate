# Deepslate Edition

A single-player, multithreaded, Bedrock-Edition-style voxel game written in **C++26** and built with
**LLVM/Clang, LLD, CMake and Ninja**. It reads and writes worlds in the **Bedrock level format**
(`level.dat` + a LevelDB chunk database) and renders with blockstates, models and textures taken from a
resource pack in the official `assets/minecraft/...` layout that you pass on the command line.

```
deepslate --resource-pack path/to/26.x-resource-pack.zip --world worlds/MyWorld
```

Without `--resource-pack` a procedurally generated built-in pack is used, so the game always runs.

## Features

* **Infinite procedural world** (FastNoise2): continents and oceans, plains, forests, birch forests, taiga,
  snowy plains, deserts, savanna, hills and mountains with snow caps, beaches, tunnels and caverns, deepslate
  layer and bedrock floor, ore veins, trees, flowers, grass, cacti and sugar cane. World height -64 .. 319.
* **Bedrock world format** (minimal but real):
  * `level.dat`: 8-byte header (storage version, length) + little-endian NBT.
  * `db/`: LevelDB with **raw-deflate block compression** (Mojang's fork).
  * Chunk keys `x:i32le z:i32le [dim] tag [sub-chunk y]`; tags `0x2C` version, `0x2B` Data3D (height map +
    per-sub-chunk biome palettes), `0x2F` SubChunkPrefix (version-9 sub-chunks, paletted 1/2/3/4/5/6/8/16-bit
    storages with persistent NBT palettes), `0x36` finalized state; player in `~local_player`.
  * Reads version 1/8/9 sub-chunks, so worlds saved by the real game load (unknown blocks are still shown).
  * Cross-checked against [Amulet](https://www.amulet-editor.com/) (an independent implementation).
* **Resource packs** in the official layout, from a `.zip`/`.jar`, a directory, or an `http(s)` URL
  (downloaded with libcurl and cached). Packs stack; the built-in pack is always the bottom layer.
  Read: `blockstates/*.json` (variants + multipart), `models/block/**` (parents, `#texture` variables, elements,
  per-face UV/rotation/cullface/tintindex, element and blockstate x/y rotation), `textures/block/*.png`
  (any square size, animated strips with `.mcmeta`), `textures/colormap/{grass,foliage}.png` (biome tints),
  `textures/font/ascii.png`, `textures/gui/sprites/hud/*`, `textures/environment/*`.
* **Multithreading:** a priority thread pool generates/loads chunks and meshes sub-chunks (nearest first); a
  dedicated writer thread persists chunks; the main thread only integrates results and uploads to the GPU.
  World data is copy-on-write per sub-chunk, so workers read immutable snapshots without locks.
* **Renderer** (OpenGL 3.3 core via SDL3): texture-array atlas with mipmaps and animation, per-vertex ambient
  occlusion, smooth flood-filled **sky light and block light**, translucent water with flowing depths, lava,
  day/night cycle with sun, moon and stars, fog, frustum culling, biome-tinted grass/leaves/water.
* **Gameplay:** walking/sprinting/sneaking/swimming/flying physics with step-up, breaking and placing
  (slab halves, stair facing, log axes), block picking, hotbar, creative inventory, sand/gravel gravity,
  water/lava flow, autosave.

## Building

Requirements: Clang >= 17 (18+ recommended), LLD, CMake >= 3.25, Ninja, git, and the usual SDL3 build
prerequisites (X11 and/or Wayland development headers, on Debian/Ubuntu: `libx11-dev libxext-dev libxcursor-dev
libxi-dev libxrandr-dev libxfixes-dev libxss-dev libxkbcommon-dev libwayland-dev libgl-dev libegl-dev
libasound2-dev libudev-dev libssl-dev`).

```
cmake --preset release
cmake --build --preset release
ctest --preset release        # or: ctest --test-dir build/release
build/release/src/deepslate --help
```

Everything else is fetched with **FetchContent** (pinned tags): the Mojang-style LevelDB fork
(`theoparis/leveldb`), zlib-ng (compat mode), simdjson, libarchive, curl, SDL3, FastNoise2, Eigen3 and stb.
`-DDEEPSLATE_SYSTEM_DEPS=ON` (preset `system-deps`) prefers system packages instead; either way a dependency
that is unavailable one way is tried the other way before failing.

C++26 note: the project uses `-std=c++2c` where the toolchain does not know `cxx_std_26` yet (Clang 18 /
CMake 3.28). Other presets: `debug`, `asan` (ASan+UBSan on the game code) and `tsan`.

## Running

```
deepslate [--resource-pack <zip|dir|url>]... [--world <dir>] [--seed n] [--render-distance 2..32]
          [--threads n] [--size WxH] [--fullscreen] [--no-vsync] [--pos x y z] [--yaw d] [--pitch d]
          [--time ticks] [--no-save] [--script "..."] [--frames n] [--write-builtin-pack out.zip]
```

Controls: `WASD` move, `Space` jump (double-tap: toggle flight), `Shift` sneak / descend, `Ctrl` or double-tap
`W` sprint, mouse look, `LMB` break, `RMB` place, `MMB` pick block, `1-9`/wheel hotbar, `E` creative
inventory, `F3` debug, `F1` hide HUD, `F2` screenshot, `F11` fullscreen, `-`/`=` render distance,
`PgUp`/`PgDn` time of day, `T` freeze time, `Esc` menu.

### Resource pack layout

The pack is expected in the official structure, for example:

```
pack.mcmeta
assets/minecraft/blockstates/oak_log.json
assets/minecraft/models/block/{cube_all,cube_column,oak_log,...}.json
assets/minecraft/textures/block/{stone,oak_log,oak_log_top,water_still,...}.png(.mcmeta)
assets/minecraft/textures/colormap/{grass,foliage}.png
assets/minecraft/textures/font/ascii.png
assets/minecraft/textures/gui/sprites/hud/{hotbar,hotbar_selection,crosshair}.png
assets/minecraft/textures/environment/{sun,moon_phases}.png
```

Block identifiers are Bedrock's flattened names (`minecraft:oak_log` + `pillar_axis`, `minecraft:oak_slab` +
`minecraft:vertical_half`, ...). Each is mapped to the Java blockstate that the pack provides
(`stone_stairs` -> `cobblestone_stairs`, `reeds` -> `sugar_cane`, `snow` -> `snow_block`, ...) and the
Bedrock block states are translated to Java properties (`pillar_axis` -> `axis`, `weirdo_direction` ->
`facing`, ...). The tile size of the atlas is taken from the pack (`stone.png`); textures of other sizes are
scaled to it. Missing files fall through to the built-in pack, and a missing model shows the classic
magenta/black checkerboard.

`deepslate --write-builtin-pack builtin.zip` writes the built-in pack in the same layout, which is a handy
starting point for your own pack.

## Layout of the code

```
src/util      logging, hashing, byte reader/writer, priority thread pool
src/nbt       little-endian NBT
src/world     block registry + table, chunks (copy-on-write sub-chunks), generator, Bedrock storage, world manager
src/assets    resource packs (zip/dir/url), built-in pack, blockstate/model baking, atlas
src/render    GL loader, camera, mesher, world renderer, UI, sky
src/game      player physics, ray casting, block updates (gravity, fluids), game loop
tests         unit tests + end-to-end smoke test (needs xvfb-run)
tools         worldmap (top-down generator preview), fallback font generator
```

Threading model in one paragraph: `World::update` (main thread) submits *load-or-generate* jobs nearest-first;
finished chunks are queued back and integrated on the main thread, which is the only place chunks are mutated.
`WorldRenderer::update` snapshots the 3x3 chunk neighbourhood of a dirty section (a handful of `shared_ptr`
copies) and submits a *mesh* job; workers run the pure function `mesh_section` (block window, light flood
fill, culling, AO, quads) and push vertex data back for a time-boxed upload. Edits copy-on-write the touched
sub-chunk, so in-flight jobs keep a consistent view.

## Testing

`deepslate_tests` covers the NBT and Bedrock codecs (including bit-packing layout and legacy sub-chunk
versions), storage round trips, world generation determinism and thread safety, pack loading (zip, directory,
layering), model baking, meshing (culling, light, fluids), physics, ray casting, fluid/gravity simulation and
the thread pool. `smoke.sh` runs the real game under `xvfb-run` with Mesa software rendering, edits a
world, saves, restarts and checks the edit came back from disk.

## Known limitations

No mobs, items/drops, survival mechanics (health, hunger, crafting), sound, weather, dimensions (the
overworld only), structures, block entities (chests, signs), redstone, or multi-block/tall plants and doors.
Blocks outside the built-in set (from real worlds) are drawn from the pack's model when the pack has one
and are otherwise shown as missing-texture cubes. Fluid flow follows simple level rules (no slopes,
no infinite water sources). Only the block layer of a sub-chunk is read (waterlogging is ignored), and
LevelDB blocks compressed with Snappy (very old worlds) are not readable.
