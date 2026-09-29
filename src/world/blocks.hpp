#pragma once
// Block registry. Blocks are identified on disk the Bedrock way (a name such as
// "minecraft:oak_log" plus a compound of block states); in memory each unique
// (name, states) pair gets a 16-bit runtime id.
#include <functional>
#include <memory>
#include <shared_mutex>
#include <string>
#include <unordered_map>

#include "nbt/nbt.hpp"
#include "util/common.hpp"

namespace ds {

using BlockId = u16;

struct StateValue {
  enum Kind : u8 { Byte, Int, String } kind = Byte;
  i32 i = 0;
  std::string s;
  static StateValue byte(int v) { return {Byte, v, {}}; }
  static StateValue integer(int v) { return {Int, v, {}}; }
  static StateValue string(std::string v) { return {String, 0, std::move(v)}; }
  bool operator==(const StateValue&) const = default;
};
// Always kept sorted by key so equal state sets compare/hash equal.
using StateMap = std::vector<std::pair<std::string, StateValue>>;

void sort_states(StateMap& m);
std::string state_key(std::string_view name, const StateMap& m);
const StateValue* find_state(const StateMap& m, std::string_view key);

enum BlockFlag : u32 {
  BF_Solid = 1u << 0,        // has collision
  BF_Opaque = 1u << 1,       // full opaque cube: hides neighbouring faces, blocks skylight
  BF_Liquid = 1u << 2,
  BF_Replaceable = 1u << 3,  // placing a block replaces it (air, water, tall grass...)
  BF_Cutout = 1u << 4,       // alpha-tested texture
  BF_Translucent = 1u << 5,  // alpha-blended pass
  BF_Emissive = 1u << 6,     // rendered fullbright
  BF_Unbreakable = 1u << 7,
  BF_Plant = 1u << 8,
  BF_Leaves = 1u << 9,
  BF_NoTarget = 1u << 10,    // cannot be selected with the crosshair
  BF_Unknown = 1u << 11,     // not part of the built-in set (e.g. from a foreign world)
};

enum class Kind : u8 { Air, CubeAll, Column, BottomTop, Grass, Cross, Slab, Stairs, Cactus, Torch, Liquid };
enum class Tint : u8 { None, Grass, Foliage, Water, Birch, Spruce };

// Procedural texture recipes used to synthesise the built-in fallback pack.
enum class TexStyle : u8 {
  Noise, Stone, Ore, Planks, LogSide, LogTop, Leaves, Bricks, StoneBricks, Plant, Flower, Glass, Sand,
  Dirt, GrassTop, GrassSide, GrassOverlay, Cactus, Torch, Sandstone, Bookshelf, Crafting, Tnt, Hay, Pumpkin,
  Gravel, Snow, Ice, Reeds, Mushroom, DeadBush, Fern, Water, Lava, Deepslate, Tuff, Glowstone, Obsidian, Bedrock
};
struct TexRecipe {
  std::string name;
  TexStyle style;
  u32 c1 = 0, c2 = 0;
};

struct BlockDef {
  std::string name;     // short name, "minecraft:" implied
  std::string display;
  Kind kind = Kind::CubeAll;
  Tint tint = Tint::None;
  u32 flags = 0;
  u8 emit = 0;
  u32 color = 0xFF00FF;      // fallback / map colour (RGB)
  std::string java;          // Java blockstate name (defaults to `name`)
  std::string tex[3];        // top/end, side, bottom texture names
  std::string overlay;       // Grass: side overlay texture
  bool creative = true;      // appears in the creative palette
  std::vector<TexRecipe> recipes;
  const std::string& java_name() const { return java.empty() ? name : java; }
};

struct Box { float min[3], max[3]; };

struct BlockInfo {
  std::string name;            // full "minecraft:stone"
  StateMap states;
  const BlockDef* def = nullptr;
  u32 flags = 0;
  u8 emit = 0;
  u8 fluid_depth = 0;          // liquid_depth state: 0 source, 1..7 flowing, >= 8 falling
  Tint tint = Tint::None;
  u8 nbox = 0;
  Box boxes[2]{};
  std::vector<std::pair<std::string, std::string>> java_props;  // for blockstate matching
  std::string java_override;   // Java blockstate name when it depends on the states (wall_torch)
  std::string display;
  u32 color = 0xFF00FF;

  bool solid() const { return flags & BF_Solid; }
  bool opaque() const { return flags & BF_Opaque; }
  bool liquid() const { return flags & BF_Liquid; }
  bool replaceable() const { return flags & BF_Replaceable; }
};

class Blocks {
 public:
  static Blocks& get();

  // Thread-safe. Registers unknown (name, states) combinations on demand.
  BlockId lookup_or_register(std::string_view full_name, StateMap states);
  // Default-state id for a short or full name; 0 (air) if unknown.
  BlockId find(std::string_view name) const;
  const BlockInfo& info(BlockId id) const { return *infos_[id].load(std::memory_order_acquire); }
  BlockId count() const { return static_cast<BlockId>(count_.load(std::memory_order_acquire)); }

  // Called (outside the registry lock) after a new block state is registered.
  void set_listener(std::function<void(BlockId)> fn);

  // Persistence helpers.
  nbt::Tag to_palette_entry(BlockId id) const;
  BlockId from_palette_entry(const nbt::Tag& t);

 private:
  Blocks();
  BlockId add_locked(std::string_view full_name, StateMap states);
  std::unique_ptr<std::atomic<const BlockInfo*>[]> infos_;  // lock-free lookup table
  std::vector<std::unique_ptr<BlockInfo>> owned_;            // ownership (guarded by m_)
  std::atomic<u32> count_{0};
  mutable std::shared_mutex m_;
  std::unordered_map<std::string, BlockId> by_key_;
  std::unordered_map<std::string, BlockId> default_by_name_;
  std::function<void(BlockId)> listener_;
};

const std::vector<BlockDef>& builtin_defs();
const BlockDef* find_def(std::string_view short_name);

// Frequently used ids, filled in when the registry is first created.
namespace B {
inline BlockId air, stone, granite, diorite, andesite, dirt, coarse_dirt, grass_block, sand, red_sand, gravel, clay, snow, ice,
    packed_ice, bedrock, cobblestone, mossy_cobblestone, sandstone, red_sandstone, deepslate, tuff, water, lava, oak_log, birch_log,
    spruce_log, oak_leaves, birch_leaves, spruce_leaves, oak_planks, coal_ore, iron_ore, gold_ore, copper_ore, lapis_ore, redstone_ore,
    diamond_ore, emerald_ore, deepslate_coal_ore, deepslate_iron_ore, deepslate_gold_ore, deepslate_copper_ore, deepslate_lapis_ore,
    deepslate_redstone_ore, deepslate_diamond_ore, short_grass, fern, dandelion, poppy, cactus, dead_bush, sugar_cane, torch, glass,
    obsidian, pumpkin, brown_mushroom, red_mushroom, azure_bluet, oxeye_daisy, cornflower, allium, blue_orchid, red_tulip, pink_tulip,
    lily_of_the_valley, spruce_planks, birch_planks, glowstone;
}

}  // namespace ds
