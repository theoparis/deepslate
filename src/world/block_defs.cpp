// Built-in block set. Names follow Bedrock's flattened block identifiers; texture
// and blockstate names follow the Java resource-pack layout (assets/minecraft/...).
#include <unordered_map>

#include "world/blocks.hpp"

namespace ds {
namespace {

constexpr u32 SOLID = BF_Solid | BF_Opaque;

struct Table {
  std::vector<BlockDef> v;

  BlockDef& add(std::string name, std::string display, Kind k, u32 flags, u32 color) {
    BlockDef d;
    d.name = std::move(name);
    d.display = std::move(display);
    d.kind = k;
    d.flags = flags;
    d.color = color;
    v.push_back(std::move(d));
    return v.back();
  }

  BlockDef& cube(const std::string& name, const std::string& display, u32 color, TexStyle st = TexStyle::Noise, u32 c2 = 0,
                 u32 flags = SOLID) {
    auto& d = add(name, display, Kind::CubeAll, flags, color);
    d.tex[0] = d.tex[1] = d.tex[2] = name;
    d.recipes.push_back({name, st, color, c2});
    return d;
  }
  BlockDef& cube_tex(const std::string& name, const std::string& display, const std::string& tex, u32 color, TexStyle st,
                     u32 c2 = 0, u32 flags = SOLID) {
    auto& d = add(name, display, Kind::CubeAll, flags, color);
    d.tex[0] = d.tex[1] = d.tex[2] = tex;
    d.recipes.push_back({tex, st, color, c2});
    return d;
  }
  BlockDef& column(const std::string& name, const std::string& display, const std::string& end, const std::string& side, u32 color,
                   TexStyle end_style, TexStyle side_style, u32 c2 = 0, u32 flags = SOLID) {
    auto& d = add(name, display, Kind::Column, flags, color);
    d.tex[0] = d.tex[2] = end;
    d.tex[1] = side;
    d.recipes.push_back({end, end_style, color, c2});
    d.recipes.push_back({side, side_style, color, c2});
    return d;
  }
  BlockDef& bottom_top(const std::string& name, const std::string& display, const std::string& top, const std::string& side,
                       const std::string& bottom, u32 color, TexStyle top_style, TexStyle side_style, TexStyle bottom_style,
                       u32 c2 = 0) {
    auto& d = add(name, display, Kind::BottomTop, SOLID, color);
    d.tex[0] = top;
    d.tex[1] = side;
    d.tex[2] = bottom;
    d.recipes.push_back({top, top_style, color, c2});
    if (side != top) d.recipes.push_back({side, side_style, color, c2});
    if (bottom != top && bottom != side) d.recipes.push_back({bottom, bottom_style, color, c2});
    return d;
  }
  BlockDef& plant(const std::string& name, const std::string& display, u32 color, TexStyle st, u32 c2 = 0, Tint tint = Tint::None,
                  const std::string& java = {}, const std::string& tex = {}) {
    auto& d = add(name, display, Kind::Cross, BF_Plant | BF_Cutout | BF_Replaceable * (st == TexStyle::Plant || st == TexStyle::Fern), color);
    d.tint = tint;
    d.java = java;
    std::string t = tex.empty() ? (java.empty() ? name : java) : tex;
    d.tex[0] = d.tex[1] = d.tex[2] = t;
    d.recipes.push_back({t, st, color, c2});
    return d;
  }
  void slab_stairs(const std::string& base, const std::string& display, const std::string& top, const std::string& side,
                   const std::string& bottom, u32 color, TexStyle st, const std::string& stairs_name = {},
                   const std::string& java_stairs = {}) {
    std::string sl = base + "_slab";
    auto& s = add(sl, display + " Slab", Kind::Slab, BF_Solid, color);
    s.tex[0] = top;
    s.tex[1] = side;
    s.tex[2] = bottom;
    std::string st_name = stairs_name.empty() ? base + "_stairs" : stairs_name;
    auto& t = add(st_name, display + " Stairs", Kind::Stairs, BF_Solid, color);
    t.java = java_stairs;
    t.tex[0] = top;
    t.tex[1] = side;
    t.tex[2] = bottom;
    (void)st;
  }
};

struct Rgb { const char* name; const char* display; u32 c; };

std::vector<BlockDef> build() {
  Table T;
  T.add("air", "Air", Kind::Air, BF_Replaceable | BF_NoTarget, 0);

  // ---- terrain
  T.cube("stone", "Stone", 0x7D7D7D, TexStyle::Stone);
  T.cube("granite", "Granite", 0x9A6B56, TexStyle::Stone, 0xB08070);
  T.cube("diorite", "Diorite", 0xBDBDBD, TexStyle::Stone, 0xE0E0E0);
  T.cube("andesite", "Andesite", 0x888888, TexStyle::Stone, 0x9A9A9A);
  T.cube("dirt", "Dirt", 0x866043, TexStyle::Dirt);
  T.cube("coarse_dirt", "Coarse Dirt", 0x77553A, TexStyle::Gravel, 0x866043);
  {
    auto& g = T.add("grass_block", "Grass Block", Kind::Grass, SOLID, 0x79C05A);
    g.tint = Tint::Grass;
    g.tex[0] = "grass_block_top";
    g.tex[1] = "grass_block_side";
    g.tex[2] = "dirt";
    g.overlay = "grass_block_side_overlay";
    g.recipes.push_back({"grass_block_top", TexStyle::GrassTop, 0x8CBF5A, 0});
    g.recipes.push_back({"grass_block_side", TexStyle::GrassSide, 0x866043, 0});
    g.recipes.push_back({"grass_block_side_overlay", TexStyle::GrassOverlay, 0x8CBF5A, 0});
    g.recipes.push_back({"dirt", TexStyle::Dirt, 0x866043, 0});
  }
  T.cube("sand", "Sand", 0xDBCFA3, TexStyle::Sand);
  T.cube("red_sand", "Red Sand", 0xBF6A2E, TexStyle::Sand);
  T.cube("gravel", "Gravel", 0x837F7E, TexStyle::Gravel, 0x9C9896);
  T.cube("clay", "Clay", 0xA0A6B5, TexStyle::Noise);
  T.cube("snow", "Snow", 0xFAFAFA, TexStyle::Snow);
  T.cube("ice", "Ice", 0x9FBFFF, TexStyle::Ice, 0, BF_Solid | BF_Translucent);
  T.cube("packed_ice", "Packed Ice", 0x8DB4F0, TexStyle::Ice);
  T.cube("bedrock", "Bedrock", 0x3A3A3A, TexStyle::Bedrock, 0, SOLID | BF_Unbreakable);
  T.cube("cobblestone", "Cobblestone", 0x7A7A7A, TexStyle::Gravel, 0x999999);
  T.cube("mossy_cobblestone", "Mossy Cobblestone", 0x6A7F60, TexStyle::Gravel, 0x709060);
  T.bottom_top("sandstone", "Sandstone", "sandstone_top", "sandstone", "sandstone_bottom", 0xDCD0A0, TexStyle::Sand, TexStyle::Sandstone,
               TexStyle::Sand);
  T.bottom_top("red_sandstone", "Red Sandstone", "red_sandstone_top", "red_sandstone", "red_sandstone_bottom", 0xB8622A, TexStyle::Sand,
               TexStyle::Sandstone, TexStyle::Sand);
  T.column("deepslate", "Deepslate", "deepslate_top", "deepslate", 0x505055, TexStyle::Deepslate, TexStyle::Deepslate);
  T.cube("tuff", "Tuff", 0x6C6D63, TexStyle::Tuff);
  T.cube("obsidian", "Obsidian", 0x150F26, TexStyle::Obsidian);
  T.cube("glowstone", "Glowstone", 0xF0C060, TexStyle::Glowstone, 0, SOLID | BF_Emissive).emit = 15;

  // ---- ores
  struct Ore { const char* n; const char* d; u32 c; };
  for (Ore o : {Ore{"coal", "Coal", 0x282828}, {"iron", "Iron", 0xD8AF93}, {"gold", "Gold", 0xFCEE4B}, {"copper", "Copper", 0xE0885A},
                {"lapis", "Lapis Lazuli", 0x2050C0}, {"redstone", "Redstone", 0xD01010}, {"diamond", "Diamond", 0x5DECF5},
                {"emerald", "Emerald", 0x17DD62}}) {
    std::string n = std::string(o.n) + "_ore";
    T.cube(n, std::string(o.d) + " Ore", 0x7D7D7D, TexStyle::Ore, o.c);
    if (std::string(o.n) != "emerald") T.cube("deepslate_" + n, "Deepslate " + std::string(o.d) + " Ore", 0x505055, TexStyle::Ore, o.c);
  }
  // deepslate ores use a darker base: patch recipes.
  for (auto& d : T.v)
    if (d.name.starts_with("deepslate_") && d.name.ends_with("_ore")) d.recipes[0].c1 = 0x4A4A50;

  // ---- storage/decoration blocks
  T.cube("coal_block", "Block of Coal", 0x101010, TexStyle::Noise);
  T.cube("iron_block", "Block of Iron", 0xDCDCDC, TexStyle::Noise);
  T.cube("gold_block", "Block of Gold", 0xF6D33E, TexStyle::Noise);
  T.cube("diamond_block", "Block of Diamond", 0x62EDE4, TexStyle::Noise);
  T.cube("emerald_block", "Block of Emerald", 0x2ACB58, TexStyle::Noise);
  T.cube("lapis_block", "Block of Lapis Lazuli", 0x1F4CA6, TexStyle::Noise);
  T.cube("redstone_block", "Block of Redstone", 0xAB1A0A, TexStyle::Noise);
  T.cube("copper_block", "Block of Copper", 0xC26B4E, TexStyle::Noise);
  T.cube("bricks", "Bricks", 0x96604F, TexStyle::Bricks, 0xB0A8A0);
  T.cube("stone_bricks", "Stone Bricks", 0x7A7A7A, TexStyle::StoneBricks, 0x666666);
  T.cube("mossy_stone_bricks", "Mossy Stone Bricks", 0x6E7E66, TexStyle::StoneBricks, 0x557744);
  T.cube("sponge", "Sponge", 0xC7C74A, TexStyle::Noise);
  T.cube("glass", "Glass", 0xC0F0F0, TexStyle::Glass, 0, BF_Solid | BF_Cutout);
  T.column("bookshelf", "Bookshelf", "oak_planks", "bookshelf", 0x8A6B3A, TexStyle::Planks, TexStyle::Bookshelf);
  T.bottom_top("crafting_table", "Crafting Table", "crafting_table_top", "crafting_table_side", "oak_planks", 0x9A7040,
               TexStyle::Crafting, TexStyle::Crafting, TexStyle::Planks);
  T.bottom_top("tnt", "TNT", "tnt_top", "tnt_side", "tnt_bottom", 0xC03028, TexStyle::Tnt, TexStyle::Tnt, TexStyle::Tnt);
  T.column("pumpkin", "Pumpkin", "pumpkin_top", "pumpkin_side", 0xC77619, TexStyle::Pumpkin, TexStyle::Pumpkin);
  T.column("hay_block", "Hay Bale", "hay_block_top", "hay_block_side", 0xC9A21A, TexStyle::Hay, TexStyle::Hay);

  static const Rgb colors[] = {
      {"white", "White", 0xE9ECEC},      {"orange", "Orange", 0xF07613},   {"magenta", "Magenta", 0xBD44B3}, {"light_blue", "Light Blue", 0x3AAFD9},
      {"yellow", "Yellow", 0xF8C527},    {"lime", "Lime", 0x70B919},       {"pink", "Pink", 0xED8DAC},       {"gray", "Gray", 0x3E4447},
      {"light_gray", "Light Gray", 0x8E8E86}, {"cyan", "Cyan", 0x158991},  {"purple", "Purple", 0x792AAC},  {"blue", "Blue", 0x35399D},
      {"brown", "Brown", 0x724728},      {"green", "Green", 0x546D1B},     {"red", "Red", 0xA12722},         {"black", "Black", 0x141519}};
  for (auto& c : colors) T.cube(std::string(c.name) + "_wool", std::string(c.display) + " Wool", c.c, TexStyle::Noise, 1);
  for (auto& c : colors) T.cube(std::string(c.name) + "_concrete", std::string(c.display) + " Concrete", c.c, TexStyle::Noise, 0);

  // ---- wood
  struct Wood { const char* n; const char* d; u32 plank; u32 bark; u32 leaf; };
  static const Wood woods[] = {
      {"oak", "Oak", 0xA2824D, 0x6B5230, 0x48B518},   {"spruce", "Spruce", 0x735530, 0x3B2912, 0x619961}, {"birch", "Birch", 0xC4B47A, 0xD8D5CD, 0x80A755},
      {"jungle", "Jungle", 0xA5764F, 0x564419, 0x30BB0B}, {"acacia", "Acacia", 0xA85632, 0x6B665E, 0x4CAA2C}, {"dark_oak", "Dark Oak", 0x42290F, 0x2D2213, 0x2F7818}};
  for (auto& w : woods) {
    std::string n = w.n, d = w.d;
    T.cube(n + "_planks", d + " Planks", w.plank, TexStyle::Planks);
    T.column(n + "_log", d + " Log", n + "_log_top", n + "_log", w.bark, TexStyle::LogTop, TexStyle::LogSide, w.plank);
    auto& lf = T.cube(n + "_leaves", d + " Leaves", w.leaf, TexStyle::Leaves, 0, BF_Solid | BF_Cutout | BF_Leaves);
    lf.tint = n == "birch" ? Tint::Birch : n == "spruce" ? Tint::Spruce : Tint::Foliage;
    T.slab_stairs(n, d, n + "_planks", n + "_planks", n + "_planks", w.plank, TexStyle::Planks);
    // slabs/stairs share the plank recipe (already registered by the planks block).
  }
  // Keep the wood slabs/stairs to a small set to keep the palette sane.
  std::erase_if(T.v, [](const BlockDef& d) {
    return (d.name.ends_with("_slab") || d.name.ends_with("_stairs")) &&
           (d.name.starts_with("jungle") || d.name.starts_with("acacia") || d.name.starts_with("dark_oak"));
  });
  T.slab_stairs("cobblestone", "Cobblestone", "cobblestone", "cobblestone", "cobblestone", 0x7A7A7A, TexStyle::Gravel, "stone_stairs", "cobblestone_stairs");
  T.slab_stairs("stone_brick", "Stone Brick", "stone_bricks", "stone_bricks", "stone_bricks", 0x7A7A7A, TexStyle::StoneBricks);
  T.slab_stairs("brick", "Brick", "bricks", "bricks", "bricks", 0x96604F, TexStyle::Bricks);
  T.slab_stairs("sandstone", "Sandstone", "sandstone_top", "sandstone", "sandstone_bottom", 0xDCD0A0, TexStyle::Sandstone);

  // ---- plants
  T.plant("short_grass", "Short Grass", 0x7BBB4A, TexStyle::Plant, 0, Tint::Grass);
  T.plant("fern", "Fern", 0x6BAA4A, TexStyle::Fern, 0, Tint::Grass);
  T.plant("dead_bush", "Dead Bush", 0x8A6A3A, TexStyle::DeadBush);
  T.plant("dandelion", "Dandelion", 0xF0E020, TexStyle::Flower, 0xF0E020);
  T.plant("poppy", "Poppy", 0xD02020, TexStyle::Flower, 0xD02020);
  T.plant("blue_orchid", "Blue Orchid", 0x30B0F0, TexStyle::Flower, 0x30B0F0);
  T.plant("allium", "Allium", 0xB060E0, TexStyle::Flower, 0xB060E0);
  T.plant("azure_bluet", "Azure Bluet", 0xE8E8E0, TexStyle::Flower, 0xE8E8E0);
  T.plant("red_tulip", "Red Tulip", 0xE04030, TexStyle::Flower, 0xE04030);
  T.plant("pink_tulip", "Pink Tulip", 0xF0A0C0, TexStyle::Flower, 0xF0A0C0);
  T.plant("oxeye_daisy", "Oxeye Daisy", 0xF4F4F0, TexStyle::Flower, 0xF4F4F0);
  T.plant("cornflower", "Cornflower", 0x4060E0, TexStyle::Flower, 0x4060E0);
  T.plant("lily_of_the_valley", "Lily of the Valley", 0xF8F8F8, TexStyle::Flower, 0xF8F8F8);
  T.plant("brown_mushroom", "Brown Mushroom", 0x8A6A4A, TexStyle::Mushroom, 0x8A6A4A);
  T.plant("red_mushroom", "Red Mushroom", 0xD03030, TexStyle::Mushroom, 0xD03030);
  T.plant("oak_sapling", "Oak Sapling", 0x4CA030, TexStyle::Plant);
  T.plant("reeds", "Sugar Cane", 0x90C060, TexStyle::Reeds, 0, Tint::Grass, "sugar_cane");
  {
    auto& c = T.add("cactus", "Cactus", Kind::Cactus, BF_Solid | BF_Cutout, 0x2E7D32);
    c.tex[0] = "cactus_top";
    c.tex[1] = "cactus_side";
    c.tex[2] = "cactus_bottom";
    c.recipes.push_back({"cactus_top", TexStyle::Cactus, 0x2E7D32, 1});
    c.recipes.push_back({"cactus_side", TexStyle::Cactus, 0x2E7D32, 0});
    c.recipes.push_back({"cactus_bottom", TexStyle::Cactus, 0x2E7D32, 1});
  }
  {
    auto& t = T.add("torch", "Torch", Kind::Torch, BF_Cutout | BF_Emissive, 0xFFC040);
    t.emit = 14;
    t.tex[0] = t.tex[1] = t.tex[2] = "torch";
    t.recipes.push_back({"torch", TexStyle::Torch, 0xFFC040, 0});
  }

  // ---- fluids
  {
    auto& w = T.add("water", "Water", Kind::Liquid, BF_Liquid | BF_Translucent | BF_Replaceable | BF_NoTarget, 0x3F76E4);
    w.tint = Tint::Water;
    w.creative = false;
    w.tex[0] = w.tex[1] = w.tex[2] = "water_still";
    w.recipes.push_back({"water_still", TexStyle::Water, 0x3F76E4, 0});
    auto& l = T.add("lava", "Lava", Kind::Liquid, BF_Liquid | BF_Replaceable | BF_Emissive | BF_NoTarget, 0xE06010);
    l.emit = 15;
    l.creative = false;
    l.tex[0] = l.tex[1] = l.tex[2] = "lava_still";
    l.recipes.push_back({"lava_still", TexStyle::Lava, 0xE06010, 0});
  }
  return std::move(T.v);
}

}  // namespace

const std::vector<BlockDef>& builtin_defs() {
  static const std::vector<BlockDef> defs = build();
  return defs;
}

const BlockDef* find_def(std::string_view short_name) {
  static const std::unordered_map<std::string, const BlockDef*> idx = [] {
    std::unordered_map<std::string, const BlockDef*> m;
    for (auto& d : builtin_defs()) m.emplace(d.name, &d);
    return m;
  }();
  auto it = idx.find(std::string(short_name));
  return it == idx.end() ? nullptr : it->second;
}

}  // namespace ds
