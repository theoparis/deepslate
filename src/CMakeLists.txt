add_library(deepslate_core STATIC
  nbt/nbt.cpp
  world/blocks.cpp
  world/block_defs.cpp
  world/chunk.cpp
  world/worldgen.cpp
  world/level_store.cpp
  world/world.cpp
  assets/image.cpp
  assets/resource_pack.cpp
  assets/builtin_pack.cpp
  assets/fallback_font.cpp
  assets/block_models.cpp
  render/gl.cpp
  render/mesher.cpp
  render/world_renderer.cpp
  render/ui.cpp
  render/sky.cpp
  render/clouds.cpp
  render/particles.cpp
  game/player.cpp
  game/raycast.cpp
  game/block_updates.cpp
  game/game.cpp)
target_include_directories(deepslate_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(deepslate_core PUBLIC ds_options leveldb ds_zlib simdjson::simdjson Eigen3::Eigen
  ${DS_FASTNOISE_TARGET} ds_archive ds_curl SDL3::SDL3 ds_stb Threads::Threads)

add_executable(deepslate main.cpp)
target_link_libraries(deepslate PRIVATE deepslate_core)

add_executable(worldmap ../tools/worldmap.cpp)
target_link_libraries(worldmap PRIVATE deepslate_core)

add_executable(bench ../tools/bench.cpp)
target_link_libraries(bench PRIVATE deepslate_core)
