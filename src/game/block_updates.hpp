#pragma once
// Scheduled block updates (20 Hz): gravity blocks fall, fluids flow and drain.
// Runs on the main thread and only ever touches the world through World::set_block.
#include <deque>
#include <unordered_set>

#include "world/world.hpp"

namespace ds {

class BlockUpdates {
 public:
  explicit BlockUpdates(World& w) : world_(w) {}

  // The block at (x,y,z) changed: schedule it and its neighbours.
  void notify(int x, int y, int z, int delay = 1);
  // Advances one game tick (call at 20 Hz).
  void tick();
  size_t pending() const { return queue_.size(); }
  i64 now() const { return tick_; }

 private:
  struct Update { int x, y, z; i64 due; };
  void schedule(int x, int y, int z, int delay);
  void run(int x, int y, int z);
  bool gravity(int x, int y, int z, BlockId id);
  void fluid(int x, int y, int z, BlockId id);
  BlockId fluid_state(BlockId like, int depth) const;

  World& world_;
  std::deque<Update> queue_;
  std::unordered_set<u64> queued_;
  i64 tick_ = 0;
  static u64 key(int x, int y, int z) {
    return (static_cast<u64>(static_cast<u32>(x) & 0x3FFFFFF) << 38) | (static_cast<u64>(static_cast<u32>(z) & 0x3FFFFFF) << 12) |
           static_cast<u64>(static_cast<u32>(y + 64) & 0xFFF);
  }
};

}  // namespace ds
