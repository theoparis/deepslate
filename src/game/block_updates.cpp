#include "game/block_updates.hpp"

namespace ds {

namespace {
constexpr int kMaxPerTick = 600;
const int kSide[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};

bool is_fluid(const BlockInfo& bi) { return bi.def && bi.def->kind == Kind::Liquid; }
}  // namespace

void BlockUpdates::schedule(int x, int y, int z, int delay) {
  if (y < MIN_Y || y >= MAX_Y) return;
  u64 k = key(x, y, z);
  if (!queued_.insert(k).second) return;
  queue_.push_back({x, y, z, tick_ + delay});
}

void BlockUpdates::notify(int x, int y, int z, int delay) {
  schedule(x, y, z, delay);
  static const int d[6][3] = {{0, -1, 0}, {0, 1, 0}, {1, 0, 0}, {-1, 0, 0}, {0, 0, 1}, {0, 0, -1}};
  for (auto& o : d) schedule(x + o[0], y + o[1], z + o[2], delay);
}

void BlockUpdates::tick() {
  tick_++;
  int budget = kMaxPerTick;
  // Updates were pushed in due order per delay class; scan the queue once per tick.
  size_t n = queue_.size();
  for (size_t i = 0; i < n && budget > 0; i++) {
    Update u = queue_.front();
    queue_.pop_front();
    if (u.due > tick_) { queue_.push_back(u); continue; }
    queued_.erase(key(u.x, u.y, u.z));
    run(u.x, u.y, u.z);
    budget--;
  }
}

void BlockUpdates::run(int x, int y, int z) {
  if (!world_.column_loaded({floor_div(x, 16), floor_div(z, 16)})) return;
  BlockId id = world_.get_block(x, y, z);
  if (!id) return;
  const BlockInfo& bi = Blocks::get().info(id);
  if (is_fluid(bi)) fluid(x, y, z, id);
  else gravity(x, y, z, id);
}

bool BlockUpdates::gravity(int x, int y, int z, BlockId id) {
  const BlockInfo& bi = Blocks::get().info(id);
  if (!bi.def) return false;
  const std::string& n = bi.def->name;
  if (n != "sand" && n != "red_sand" && n != "gravel") return false;
  BlockId below = world_.get_block(x, y - 1, z);
  if (y <= MIN_Y || !Blocks::get().info(below).replaceable()) return false;
  // Falls one cell per tick pair; landing on fluid or plants replaces them.
  world_.set_block(x, y, z, 0);
  world_.set_block(x, y - 1, z, id);
  notify(x, y, z);
  schedule(x, y - 1, z, 2);
  return true;
}

BlockId BlockUpdates::fluid_state(BlockId like, int depth) const {
  const BlockInfo& bi = Blocks::get().info(like);
  return Blocks::get().lookup_or_register(bi.name, {{"liquid_depth", StateValue::integer(depth)}});
}

void BlockUpdates::fluid(int x, int y, int z, BlockId id) {
  Blocks& reg = Blocks::get();
  const BlockInfo& me = reg.info(id);
  const bool lava = me.name.ends_with("lava");
  const int delay = lava ? 30 : 5;
  const int max_flow = lava ? 3 : 7;  // how far flowing fluid reaches from a source
  int depth = me.fluid_depth;
  auto same = [&](BlockId o) { return o && reg.info(o).def == me.def; };
  // Fluid rests on solid ground or on a pool of itself (source/flowing, not a falling column).
  auto rests = [&](int bx, int by, int bz) {
    BlockId b = world_.get_block(bx, by, bz);
    if (!b) return false;
    const BlockInfo& i = reg.info(b);
    if (!i.replaceable()) return true;
    return same(b) && i.fluid_depth < 8;
  };

  // 1. Flowing fluid needs a feeder, otherwise it drains away.
  if (depth > 0) {
    int best = 99;
    const bool fed_from_above = same(world_.get_block(x, y + 1, z));
    if (fed_from_above) best = 8;  // fluid with fluid above is always a falling column
    for (auto& s : kSide) {
      if (fed_from_above) break;
      BlockId nb = world_.get_block(x + s[0], y, z + s[1]);
      if (!same(nb)) continue;
      int nd = reg.info(nb).fluid_depth;
      if (nd >= 8) {
        if (rests(x + s[0], y - 1, z + s[1])) best = std::min(best, 1);  // a falling column that landed spreads out
      } else if (nd < max_flow) {
        best = std::min(best, nd + 1);
      }
    }
    if (best == 99) {  // unsupported: drain
      world_.set_block(x, y, z, 0);
      notify(x, y, z, delay);
      return;
    }
    if (best != depth) {
      depth = best;
      id = fluid_state(id, depth);
      world_.set_block(x, y, z, id);
      notify(x, y, z, delay);
    }
  }

  // 2. Flow down first.
  if (y > MIN_Y && !rests(x, y - 1, z)) {
    BlockId below = world_.get_block(x, y - 1, z);
    const BlockInfo& bel = reg.info(below);
    if (below == 0 || (bel.replaceable() && (!is_fluid(bel) || same(below)))) {
      if (!(same(below) && bel.fluid_depth >= 8)) {
        world_.set_block(x, y - 1, z, fluid_state(id, 8));
        notify(x, y - 1, z, delay);
      }
    }
    return;
  }
  // 3. Resting on something: spread sideways (a landed falling column restarts at depth 1).
  const int nd = depth >= 8 ? 1 : depth + 1;
  if (nd > max_flow) return;
  for (auto& s : kSide) {
    int nx = x + s[0], nz = z + s[1];
    BlockId nb = world_.get_block(nx, y, nz);
    const BlockInfo& ni = reg.info(nb);
    bool place = false;
    if (nb == 0 || (ni.replaceable() && !is_fluid(ni))) place = true;
    else if (same(nb) && ni.fluid_depth > nd && ni.fluid_depth < 8) place = true;
    if (!place) continue;
    world_.set_block(nx, y, nz, fluid_state(id, nd));
    notify(nx, y, nz, delay);
  }
}

}  // namespace ds
