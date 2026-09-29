#pragma once
// Turns Java-format blockstates + models from a PackStack into baked quads (block-local
// geometry with atlas layers), and owns the block texture atlas (a 2D texture array).
#include <map>
#include <unordered_map>

#include "assets/image.hpp"
#include "assets/resource_pack.hpp"
#include "world/blocks.hpp"

namespace ds {

enum Dir : int { DOWN = 0, UP = 1, NORTH = 2, SOUTH = 3, WEST = 4, EAST = 5 };

struct BakedQuad {
  float pos[4][3];  // block-local (0..1), counter-clockwise seen from outside
  float uv[4][2];   // 0..1 inside the tile
  u16 layer = 0;
  i8 cull = -1;     // neighbour face that hides this quad, or -1
  i8 dir = UP;      // shading direction
  i8 tint = -1;
  bool shade = true;
  bool boundary = false;  // lies on the block boundary: ambient occlusion applies
};

struct BakedBlock {
  std::vector<BakedQuad> quads;
  bool missing = false;
};

class BlockModels {
 public:
  explicit BlockModels(const PackStack& packs);
  ~BlockModels();

  // Bakes every block registered so far. Call once before meshing starts.
  void build();
  // Bakes one block state (used for blocks registered later, e.g. from foreign worlds).
  void bake(BlockId id);

  const BakedBlock* baked(BlockId id) const { return table_[id].load(std::memory_order_acquire); }

  // ---- atlas
  int tile_size() const { return tile_; }
  u16 layer_of(const std::string& texture);  // e.g. "block/stone"; 0 = missing texture
  u16 water_layer() const { return water_layer_; }
  u16 lava_layer() const { return lava_layer_; }
  size_t layer_count() const;
  int capacity() const { return capacity_; }
  // Copies layers [from, count) into `out` and returns the new count (thread-safe).
  size_t copy_layers(size_t from, std::vector<u8>& out) const;

  // ---- tints
  u32 tint_color(Tint kind, u8 biome) const { return tints_[static_cast<int>(kind)][biome]; }

  // Icon layers for UI: top, front(south), side(east). flat = single sprite (plants, torches).
  struct Icon { u16 top = 0, left = 0, right = 0; bool flat = false; };
  Icon icon(BlockId id) const;

 private:
  struct Element;
  struct Model;
  struct ModelRef { std::string name; int x = 0, y = 0; bool uvlock = false; };
  struct BlockState;

  const Model* load_model(const std::string& name, int depth = 0);
  const BlockState* load_blockstate(const std::string& name);
  void bake_locked(BlockId id);
  void bake_model(const ModelRef& ref, int block_tint_hint, BakedBlock& out);
  u16 add_layer_locked(const std::string& name);
  void init_tints();
  Image load_tile(const std::string& texture, bool* found);

  const PackStack& packs_;
  mutable std::mutex m_;
  std::unique_ptr<std::atomic<const BakedBlock*>[]> table_;
  std::vector<std::unique_ptr<BakedBlock>> owned_;

  int tile_ = 16;
  int capacity_ = 1024;
  std::vector<u8> pixels_;           // layer-major, tile*tile*4 bytes each
  std::atomic<size_t> layers_{0};
  std::unordered_map<std::string, u16> layer_ids_;
  u16 water_layer_ = 0, lava_layer_ = 0;

  std::unordered_map<std::string, std::unique_ptr<Model>> models_;
  std::unordered_map<std::string, std::unique_ptr<BlockState>> states_;
  Image grass_map_, foliage_map_;
  std::array<std::array<u32, 256>, 6> tints_{};
};

}  // namespace ds
