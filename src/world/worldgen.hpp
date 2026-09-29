#pragma once
// Procedural overworld generator (FastNoise2 driven). Fully deterministic per seed and
// thread-safe: generate() only reads immutable state.
#include <FastNoise/FastNoise.h>

#include "world/chunk.hpp"

namespace ds {

class WorldGen {
 public:
  static constexpr int SEA_LEVEL = 62;

  explicit WorldGen(i64 seed);
  std::unique_ptr<Chunk> generate(ChunkPos pos) const;
  i64 seed() const { return seed_; }
  // Approximate surface height at a world column (used to place the spawn).
  int surface_height(int wx, int wz) const;

 private:
  struct Column {
    int height;   // top solid block y
    u8 biome;
    float temp, hum;
  };
  static constexpr int PAD = 4;
  static constexpr int EXT = 16 + 2 * PAD;
  using ColumnGrid = std::array<Column, EXT * EXT>;
  void compute_columns(ChunkPos pos, ColumnGrid& out) const;
  void carve_and_fill(Chunk& c, const ColumnGrid& cols) const;
  void place_ores(Chunk& c) const;
  void place_features(Chunk& c, const ColumnGrid& cols) const;

  i64 seed_;
  int s32_;
  FastNoise::SmartNode<> continental_, hills_, ridged_, temperature_, humidity_, cave_a_, cave_b_, cheese_, detail_;
};

}  // namespace ds
