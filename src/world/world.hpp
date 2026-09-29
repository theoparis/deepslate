#pragma once
// Loaded-world manager. All mutation happens on the main thread; worker threads only see
// immutable ChunkSnapshots. Chunk loading/generation runs on the thread pool, saving on a
// dedicated writer thread.
#include <condition_variable>
#include <deque>
#include <functional>
#include <thread>
#include <unordered_map>

#include "util/thread_pool.hpp"
#include "world/level_store.hpp"
#include "world/worldgen.hpp"

namespace ds {

struct DirtyChunk {
  ChunkPos pos;
  u32 mask;  // bit i = section index i (sub-chunk MIN_SUB + i) needs remeshing
};

class ChunkWriter {
 public:
  explicit ChunkWriter(LevelStore& store);
  ~ChunkWriter();
  void push(ChunkSnapshot snap);
  void flush();  // blocks until everything queued so far is on disk
  size_t queued() const;
  u64 written() const { return written_.load(); }

 private:
  void run();
  LevelStore& store_;
  mutable std::mutex m_;
  std::condition_variable cv_, done_cv_;
  std::deque<ChunkSnapshot> q_;
  bool busy_ = false, stop_ = false;
  std::atomic<u64> written_{0};
  std::thread th_;
};

class World {
 public:
  World(LevelStore& store, const WorldGen& gen, ThreadPool& pool);
  ~World();

  // Streams chunks around (px, pz) in world coordinates. `radius` is in chunks.
  void update(double px, double pz, int radius);

  BlockId get_block(int x, int y, int z) const;
  bool set_block(int x, int y, int z, BlockId id);
  bool column_loaded(ChunkPos p) const { return chunks_.contains(pack_chunk(p)); }
  const Chunk* chunk(ChunkPos p) const {
    auto it = chunks_.find(pack_chunk(p));
    return it == chunks_.end() ? nullptr : it->second.get();
  }
  // Loaded height of the column above (x, z): y of the first sky-blocking block + 1.
  int column_height(int x, int z) const;

  // True (and fills `out`, ordered by dz then dx) when the 3x3 neighbourhood is fully loaded.
  bool snapshot3x3(ChunkPos c, std::array<ChunkSnapshot, 9>& out) const;
  bool neighbourhood_loaded(ChunkPos c) const;
  // True when every chunk within `radius` (circular) of `c` is resident.
  bool all_loaded_around(ChunkPos c, int radius) const;

  void take_dirty(std::vector<DirtyChunk>& out);

  // Persist every modified chunk (synchronously when wait is true).
  void save_dirty(bool wait);
  void shutdown();

  size_t loaded_count() const { return chunks_.size(); }
  size_t inflight_count() const { return inflight_.size(); }
  size_t writer_queue() const { return writer_.queued(); }
  u64 writer_written() const { return writer_.written(); }
  u64 chunks_generated() const { return generated_.load(); }
  u64 chunks_loaded_from_disk() const { return from_disk_.load(); }
  LevelStore& store() { return store_; }

 private:
  struct Ready {
    ChunkPos pos;
    std::unique_ptr<Chunk> chunk;
  };
  void mark_dirty(ChunkPos p, u32 mask);
  void mark_dirty_around(int lx, int y, int lz, ChunkPos p, bool height_changed, bool light_changed);
  void unload_far(double px, double pz, int radius);

  LevelStore& store_;
  const WorldGen& gen_;
  ThreadPool& pool_;
  ChunkWriter writer_;

  std::unordered_map<u64, std::unique_ptr<Chunk>> chunks_;
  std::unordered_map<u64, bool> inflight_;
  std::unordered_map<u64, u32> dirty_;
  std::mutex ready_m_;
  std::vector<Ready> ready_;
  std::atomic<int> outstanding_{0};
  std::atomic<u64> generated_{0}, from_disk_{0};

  std::vector<std::pair<int, int>> offsets_;
  int offsets_radius_ = -1;
  int frame_ = 0;
  mutable ChunkPos cache_pos_{INT32_MIN, INT32_MIN};
  mutable Chunk* cache_chunk_ = nullptr;
};

}  // namespace ds
