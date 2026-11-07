# Vinecraft 

A single-player Bedrock-style voxel game written in V. It uses Sokol for the window,
input and graphics and the V `leveldb` module for Bedrock world storage. Worlds are
stored as `level.dat` and a LevelDB database under `db/`. Back up existing worlds
before opening them with the game.

```sh
./build/bin/vinecraft --world worlds/MyWorld --resource-pack path/to/resource-pack.zip
```

A procedural built-in resource pack is used when no pack is supplied. Additional
packs may be directories, ZIP/JAR files, or HTTP(S) URLs; earlier command-line
packs take precedence over later packs and the built-in pack.

## Building

Requirements: V, `~/.vmodules/leveldb`, a C toolchain, Git, libarchive and the
platform libraries required by V's Sokol backend. On Linux these include the X11,
OpenGL/EGL and ALSA development libraries. The renderer currently supplies GLSL
3.30 shaders.

The V compiler and LevelDB module revisions exercised by CI are specified in
`.github/workflows/ci.yml`. For example, install the module with:

```sh
git clone https://github.com/theoparis/v-leveldb.git ~/.vmodules/leveldb
```

Build and run the V tests:

```sh
make -j2
make test
./build/bim/vinecraft --help
sh tests/smoke.sh ./build/bin/vinecraft /tmp
```

Set `BUILD_DIR` to use another disposable build directory (default `build`), or `V`
to select the V compiler. `make clean` removes the executable and that build directory.

## Playing

```text
vinecraft [--resource-pack <zip|dir|url>]... [--world <dir>] [--seed n]
          [--render-distance 2..32] [--threads n] [--size WxH] [--fullscreen]
          [--no-vsync] [--pos x y z] [--yaw d] [--pitch d] [--time ticks]
          [--no-save] [--script "..."] [--frames n] [--write-builtin-pack out.zip]
```

Run `./vinecraft --help` for the complete option and scripted-action list.
`--no-save` opens a temporary copy of an existing world, so LevelDB recovery and
gameplay do not modify the original.

Controls: `WASD` move, `Space` jump (double-tap to toggle flight), `Shift`
sneak/descend, `Ctrl` or double-tap `W` sprint, mouse look, left click break,
right click place, middle click pick, `1`–`9`/wheel hotbar, `E` creative
inventory, `F3` debug, `F1` hide HUD, `F2` screenshot, `F11` fullscreen,
`-`/`=` render distance, `PgUp`/`PgDn` time of day, `T` freeze time, and `Esc`
menu.

The world is generated in chunks and streamed on worker threads; a separate
writer persists changed chunks. The renderer meshes sections on workers and
uploads them through Sokol on the main thread. The game includes basic movement,
block interaction, gravity and fluid updates, biome-tinted vegetation, sky,
clouds and particles.

## Resource packs

Packs use the official Java-style layout under `assets/minecraft/`, including
`blockstates/`, `models/block/`, and `textures/`. Models can refer to parents,
texture variables and blockstate variants. Missing files fall back to the built-in
pack. Export it with `./vinecraft --write-builtin-pack builtin.zip`.

## Tools

`make` also builds these programs under `build/v-deps/bin/` (or under
`$BUILD_DIR/bin/`):

```sh
build/v-deps/bin/worldmap 7 0 0 512 map.png 4
build/v-deps/bin/bench 42 8
build/v-deps/bin/packcheck path/to/resource-pack.zip --verbose
```

## Limitations

Only the overworld and creative-style block gameplay are implemented. There are
no mobs, items/drops, survival mechanics, sound, weather, structures, block
entities or redstone. The storage reader uses the first block layer of a
subchunk; waterlogging is not represented. Very old Snappy-compressed Bedrock
worlds are not supported by the LevelDB module. The renderer's shaders currently
target OpenGL 3.3; other Sokol graphics backends are not yet supported.
