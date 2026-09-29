#pragma once
#include <array>
#include <vector>

#include "assets/block_models.hpp"
#include "world/chunk.hpp"

namespace ds {

struct Vertex {
  float x, y, z;     // section-local position
  float u, v;        // uv inside the tile
  float layer;       // atlas layer
  u8 r, g, b, a;     // tint * shading, alpha
  u8 sky, blk;       // light levels (0..255 = 0..15)
  u8 flags, pad;
};
static_assert(sizeof(Vertex) == 32);

struct MeshData {
  std::vector<Vertex> opaque;       // opaque + alpha-tested geometry
  std::vector<Vertex> translucent;  // blended geometry (water, ice)
  size_t quads() const { return (opaque.size() + translucent.size()) / 4; }
};

struct MeshInput {
  std::array<ChunkSnapshot, 9> chunks;  // 3x3 around the target, index = (dz+1)*3 + (dx+1)
  int section = 0;                      // 0..23
};

// Pure function of its inputs: safe to run on any thread.
void mesh_section(const MeshInput& in, const BlockModels& models, MeshData& out);

}  // namespace ds
