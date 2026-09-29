#pragma once
// Chunk column storage. A column is 16x16 blocks and spans y = -64 .. 319 (24 sub-chunks),
// like a Bedrock overworld chunk. Sub-chunks are copy-on-write so worker threads can
// read immutable snapshots while the main thread keeps editing the world.
#include <array>
#include <memory>

#include "world/blocks.hpp"

namespace ds {

constexpr int CHUNK_W = 16;
constexpr int MIN_Y = -64;
constexpr int MAX_Y = 320;  // exclusive
constexpr int NUM_SUBS = 24;
constexpr int MIN_SUB = -4;  // sub-chunk index of the lowest section

// Block index inside a sub-chunk: same order Bedrock stores it on disk (x, z, y).
constexpr int sub_index(int x, int y, int z) { return (x << 8) | (z << 4) | y; }
constexpr int col_index(int x, int z) { return x * 16 + z; }

struct SubChunk {
  std::array<BlockId, 4096> b{};
  BlockId get(int x, int y, int z) const { return b[sub_index(x, y, z)]; }
};

// True for blocks that stop skylight (used for the heightmap).
inline bool blocks_sky(BlockId id) {
  return Blocks::get().info(id).flags & (BF_Opaque | BF_Liquid | BF_Leaves);
}
// True for blocks that fully stop light (used for the lighting heightmap).
inline bool blocks_light(BlockId id) { return Blocks::get().info(id).flags & BF_Opaque; }

// Immutable view of a chunk column, safe to use from any thread.
struct ChunkSnapshot {
  ChunkPos pos;
  std::array<std::shared_ptr<const SubChunk>, NUM_SUBS> subs;
  std::array<i16, 256> height{};        // absolute y of the highest sky-blocking block + 1 (MIN_Y if none)
  std::array<i16, 256> light_height{};  // same, counting only fully opaque blocks
  std::array<u8, 256> biome{};

  BlockId get(int lx, int y, int lz) const {
    if (y < MIN_Y || y >= MAX_Y) return 0;
    auto& s = subs[(y >> 4) - MIN_SUB];
    return s ? s->get(lx, y & 15, lz) : BlockId(0);
  }
};

class Chunk {
 public:
  ChunkPos pos;
  std::array<std::shared_ptr<SubChunk>, NUM_SUBS> subs;
  std::array<i16, 256> height{};
  std::array<i16, 256> light_height{};
  std::array<u8, 256> biome{};
  bool dirty = false;

  Chunk() { height.fill(MIN_Y); light_height.fill(MIN_Y); }

  BlockId get(int lx, int y, int lz) const {
    if (y < MIN_Y || y >= MAX_Y) return 0;
    auto& s = subs[(y >> 4) - MIN_SUB];
    return s ? s->get(lx, y & 15, lz) : BlockId(0);
  }

  // Copy-on-write set. Returns true if the block changed.
  bool set(int lx, int y, int lz, BlockId id) {
    if (y < MIN_Y || y >= MAX_Y) return false;
    auto& s = subs[(y >> 4) - MIN_SUB];
    if (!s) {
      if (id == 0) return false;
      s = std::make_shared<SubChunk>();
    } else if (s.use_count() > 1) {
      s = std::make_shared<SubChunk>(*s);
    }
    BlockId& slot = s->b[sub_index(lx, y & 15, lz)];
    if (slot == id) return false;
    slot = id;
    return true;
  }

  void recompute_column_height(int lx, int lz) {
    int h = MIN_Y, lh = MIN_Y;
    for (int si = NUM_SUBS - 1; si >= 0 && lh == MIN_Y; si--) {
      auto& s = subs[si];
      if (!s) continue;
      for (int y = 15; y >= 0; y--) {
        BlockId id = s->b[sub_index(lx, y, lz)];
        if (id == 0) continue;
        int wy = (si + MIN_SUB) * 16 + y + 1;
        if (h == MIN_Y && blocks_sky(id)) h = wy;
        if (blocks_light(id)) { lh = wy; break; }
      }
    }
    if (h == MIN_Y) h = lh;
    height[col_index(lx, lz)] = static_cast<i16>(h);
    light_height[col_index(lx, lz)] = static_cast<i16>(lh);
  }
  void recompute_heights() {
    for (int x = 0; x < 16; x++)
      for (int z = 0; z < 16; z++) recompute_column_height(x, z);
  }

  ChunkSnapshot snapshot() const {
    ChunkSnapshot s;
    s.pos = pos;
    for (int i = 0; i < NUM_SUBS; i++) s.subs[i] = subs[i];
    s.height = height;
    s.light_height = light_height;
    s.biome = biome;
    return s;
  }
  bool empty() const {
    for (auto& s : subs)
      if (s) return false;
    return true;
  }
};

// Biome ids (Bedrock numbering).
namespace Biome {
enum : u8 {
  Ocean = 0, Plains = 1, Desert = 2, Hills = 3, Forest = 4, Taiga = 5, Swamp = 6, FrozenOcean = 10, SnowyPlains = 12, Beach = 16,
  Jungle = 21, DeepOcean = 24, BirchForest = 27, DarkForest = 29, ColdTaiga = 30, Savanna = 35,
};
struct Climate { float temperature, downfall; };
Climate climate(u8 biome);
}  // namespace Biome

}  // namespace ds
