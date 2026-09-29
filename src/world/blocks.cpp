#include "world/blocks.hpp"

#include <mutex>

namespace ds {

void sort_states(StateMap& m) {
  std::sort(m.begin(), m.end(), [](auto& a, auto& b) { return a.first < b.first; });
}

std::string state_key(std::string_view name, const StateMap& m) {
  std::string k(name);
  for (auto& [key, v] : m) {
    k += '|';
    k += key;
    k += '=';
    switch (v.kind) {
      case StateValue::Byte: k += 'b'; k += std::to_string(v.i); break;
      case StateValue::Int: k += 'i'; k += std::to_string(v.i); break;
      case StateValue::String: k += 's'; k += v.s; break;
    }
  }
  return k;
}

const StateValue* find_state(const StateMap& m, std::string_view key) {
  for (auto& [k, v] : m)
    if (k == key) return &v;
  return nullptr;
}

namespace {

std::string full_name_of(std::string_view n) {
  if (n.find(':') != std::string_view::npos) return std::string(n);
  return "minecraft:" + std::string(n);
}

std::string short_name_of(std::string_view n) {
  if (n.starts_with("minecraft:")) n.remove_prefix(10);
  return std::string(n);
}

int state_int(const StateMap& m, std::string_view key, int def = 0) {
  auto* v = find_state(m, key);
  return v ? v->i : def;
}
std::string state_str(const StateMap& m, std::string_view key, std::string def = {}) {
  auto* v = find_state(m, key);
  return (v && v->kind == StateValue::String) ? v->s : def;
}

// Derives collision boxes and the Java blockstate properties from block states.
void derive_shape(BlockInfo& bi) {
  const BlockDef& d = *bi.def;
  auto full = [&] { bi.nbox = 1; bi.boxes[0] = {{0, 0, 0}, {1, 1, 1}}; };
  switch (d.kind) {
    case Kind::Air: case Kind::Liquid: case Kind::Cross: case Kind::Torch: bi.nbox = 0; break;
    case Kind::Cactus: bi.nbox = 1; bi.boxes[0] = {{0.0625f, 0, 0.0625f}, {0.9375f, 0.9375f, 0.9375f}}; break;
    case Kind::Slab: {
      bool top = state_str(bi.states, "minecraft:vertical_half", "bottom") == "top";
      bi.nbox = 1;
      bi.boxes[0] = top ? Box{{0, 0.5f, 0}, {1, 1, 1}} : Box{{0, 0, 0}, {1, 0.5f, 1}};
      bi.java_props = {{"type", top ? "top" : "bottom"}, {"waterlogged", "false"}};
      break;
    }
    case Kind::Stairs: {
      int dir = state_int(bi.states, "weirdo_direction");
      bool up = state_int(bi.states, "upside_down_bit") != 0;
      static const char* facing[] = {"east", "west", "south", "north"};
      bi.java_props = {{"facing", facing[dir & 3]}, {"half", up ? "top" : "bottom"}, {"shape", "straight"}, {"waterlogged", "false"}};
      bi.nbox = 2;
      bi.boxes[0] = up ? Box{{0, 0.5f, 0}, {1, 1, 1}} : Box{{0, 0, 0}, {1, 0.5f, 1}};
      float y0 = up ? 0.0f : 0.5f, y1 = up ? 0.5f : 1.0f;
      switch (dir & 3) {
        case 0: bi.boxes[1] = {{0.5f, y0, 0}, {1, y1, 1}}; break;      // rises toward +x
        case 1: bi.boxes[1] = {{0, y0, 0}, {0.5f, y1, 1}}; break;      // -x
        case 2: bi.boxes[1] = {{0, y0, 0.5f}, {1, y1, 1}}; break;      // +z
        default: bi.boxes[1] = {{0, y0, 0}, {1, y1, 0.5f}}; break;     // -z
      }
      break;
    }
    default: full(); break;
  }
  if (d.kind == Kind::Column || d.kind == Kind::Stairs || d.kind == Kind::Slab) {
    if (d.kind == Kind::Column) bi.java_props = {{"axis", state_str(bi.states, "pillar_axis", "y")}};
  }
  if (d.kind == Kind::Grass) bi.java_props = {{"snowy", "false"}};
}

}  // namespace

Blocks& Blocks::get() {
  static Blocks inst;
  return inst;
}

Blocks::Blocks() {
  infos_ = std::make_unique<std::atomic<const BlockInfo*>[]>(65536);
  for (int i = 0; i < 65536; i++) infos_[i].store(nullptr, std::memory_order_relaxed);
  std::unique_lock lk(m_);
  // Id 0 is always air.
  add_locked("minecraft:air", {});
  for (const BlockDef& d : builtin_defs()) {
    std::string full = full_name_of(d.name);
    if (d.name == "air") continue;
    // Register every state permutation for state-carrying kinds so runtime ids are stable.
    switch (d.kind) {
      case Kind::Column:
        for (const char* ax : {"y", "x", "z"}) add_locked(full, {{"pillar_axis", StateValue::string(ax)}});
        break;
      case Kind::Slab:
        for (const char* h : {"bottom", "top"}) add_locked(full, {{"minecraft:vertical_half", StateValue::string(h)}});
        break;
      case Kind::Stairs:
        for (int up = 0; up < 2; up++)
          for (int dir = 0; dir < 4; dir++) {
            StateMap s{{"upside_down_bit", StateValue::byte(up)}, {"weirdo_direction", StateValue::integer(dir)}};
            add_locked(full, s);
          }
        break;
      case Kind::Liquid: add_locked(full, {{"liquid_depth", StateValue::integer(0)}}); break;
      case Kind::Torch: add_locked(full, {{"torch_facing_direction", StateValue::string("top")}}); break;
      default:
        if (d.flags & BF_Leaves)
          add_locked(full, {{"persistent_bit", StateValue::byte(0)}, {"update_bit", StateValue::byte(0)}});
        else
          add_locked(full, {});
        break;
    }
  }
  auto id = [&](const char* n) { return default_by_name_.at(full_name_of(n)); };
#define ID(n) B::n = id(#n)
  ID(air); ID(stone); ID(granite); ID(diorite); ID(andesite); ID(dirt); ID(coarse_dirt); ID(grass_block); ID(sand); ID(red_sand);
  ID(gravel); ID(clay); ID(snow); ID(ice); ID(packed_ice); ID(bedrock); ID(cobblestone); ID(mossy_cobblestone); ID(sandstone);
  ID(red_sandstone); ID(deepslate); ID(tuff); ID(water); ID(lava); ID(oak_log); ID(birch_log); ID(spruce_log); ID(oak_leaves);
  ID(birch_leaves); ID(spruce_leaves); ID(oak_planks); ID(coal_ore); ID(iron_ore); ID(gold_ore); ID(copper_ore); ID(lapis_ore);
  ID(redstone_ore); ID(diamond_ore); ID(emerald_ore); ID(deepslate_coal_ore); ID(deepslate_iron_ore); ID(deepslate_gold_ore);
  ID(deepslate_copper_ore); ID(deepslate_lapis_ore); ID(deepslate_redstone_ore); ID(deepslate_diamond_ore); ID(short_grass); ID(fern);
  ID(dandelion); ID(poppy); ID(cactus); ID(dead_bush); ID(torch); B::sugar_cane = id("reeds"); ID(glass); ID(obsidian); ID(pumpkin);
  ID(brown_mushroom); ID(red_mushroom); ID(azure_bluet); ID(oxeye_daisy); ID(cornflower); ID(allium); ID(blue_orchid); ID(red_tulip);
  ID(pink_tulip); ID(lily_of_the_valley); ID(spruce_planks); ID(birch_planks); ID(glowstone);
#undef ID
}

BlockId Blocks::add_locked(std::string_view full_name, StateMap states) {
  sort_states(states);
  std::string key = state_key(full_name, states);
  if (auto it = by_key_.find(key); it != by_key_.end()) return it->second;
  u32 n = count_.load(std::memory_order_relaxed);
  if (n >= 65535) return 0;  // registry full; degrade to air

  auto bi = std::make_unique<BlockInfo>();
  bi->name = std::string(full_name);
  bi->states = std::move(states);
  const BlockDef* def = find_def(short_name_of(full_name));
  static const BlockDef unknown_def = [] {
    BlockDef d;
    d.name = "unknown";
    d.display = "Unknown Block";
    d.kind = Kind::CubeAll;
    d.flags = BF_Solid | BF_Opaque | BF_Unknown;
    d.color = 0xC030C0;
    d.creative = false;
    return d;
  }();
  bi->def = def ? def : &unknown_def;
  bi->flags = bi->def->flags;
  bi->emit = bi->def->emit;
  bi->tint = bi->def->tint;
  bi->display = bi->def->display;
  bi->color = bi->def->color;
  derive_shape(*bi);
  if (bi->def == &unknown_def) bi->display = bi->name;

  BlockId id = static_cast<BlockId>(n);
  const BlockInfo* raw = bi.release();
  infos_[id].store(raw, std::memory_order_release);
  count_.store(n + 1, std::memory_order_release);
  by_key_.emplace(std::move(key), id);
  default_by_name_.emplace(std::string(full_name), id);  // first registered state = default
  return id;
}

BlockId Blocks::lookup_or_register(std::string_view full_name, StateMap states) {
  sort_states(states);
  std::string key = state_key(full_name, states);
  {
    std::shared_lock lk(m_);
    if (auto it = by_key_.find(key); it != by_key_.end()) return it->second;
  }
  BlockId id;
  std::function<void(BlockId)> cb;
  u32 before;
  {
    std::unique_lock lk(m_);
    before = count_.load();
    id = add_locked(full_name, std::move(states));
    if (count_.load() != before) cb = listener_;
  }
  if (cb) cb(id);
  return id;
}

BlockId Blocks::find(std::string_view name) const {
  std::shared_lock lk(m_);
  auto it = default_by_name_.find(full_name_of(name));
  return it == default_by_name_.end() ? 0 : it->second;
}

void Blocks::set_listener(std::function<void(BlockId)> fn) {
  std::unique_lock lk(m_);
  listener_ = std::move(fn);
}

nbt::Tag Blocks::to_palette_entry(BlockId id) const {
  const BlockInfo& bi = info(id);
  nbt::Tag t = nbt::Tag::make_compound();
  t.set("name", nbt::Tag::make_string(bi.name));
  nbt::Tag st = nbt::Tag::make_compound();
  for (auto& [k, v] : bi.states) {
    switch (v.kind) {
      case StateValue::Byte: st.set(k, nbt::Tag::make_byte(v.i)); break;
      case StateValue::Int: st.set(k, nbt::Tag::make_int(v.i)); break;
      case StateValue::String: st.set(k, nbt::Tag::make_string(v.s)); break;
    }
  }
  t.set("states", std::move(st));
  t.set("version", nbt::Tag::make_int(18153475));
  return t;
}

BlockId Blocks::from_palette_entry(const nbt::Tag& t) {
  std::string name = t.get_string("name", "minecraft:air");
  StateMap sm;
  if (auto* st = t.find("states"); st && st->type == nbt::Type::Compound) {
    for (auto& [k, v] : st->compound) {
      switch (v.type) {
        case nbt::Type::Byte: sm.emplace_back(k, StateValue::byte(static_cast<int>(v.i))); break;
        case nbt::Type::Int: case nbt::Type::Short: sm.emplace_back(k, StateValue::integer(static_cast<int>(v.i))); break;
        case nbt::Type::String: sm.emplace_back(k, StateValue::string(v.s)); break;
        default: break;
      }
    }
  }
  // Legacy aliases seen in older worlds.
  if (name == "minecraft:grass") name = "minecraft:grass_block";
  if (name == "minecraft:flowing_water" || name == "minecraft:flowing_lava") {
    name = name == "minecraft:flowing_water" ? "minecraft:water" : "minecraft:lava";
  }
  // A named block with a different (e.g. newer) state set than ours collapses onto our
  // default states for kinds whose states we model, so it still renders correctly.
  return lookup_or_register(name, std::move(sm));
}

}  // namespace ds
