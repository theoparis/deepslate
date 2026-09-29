#include "world/world.hpp"

#include <thread>

namespace ds {

// ------------------------------------------------------------------ writer

ChunkWriter::ChunkWriter(LevelStore& store) : store_(store), th_([this] { run(); }) {}

ChunkWriter::~ChunkWriter() {
  {
    std::lock_guard lk(m_);
    stop_ = true;
  }
  cv_.notify_all();
  th_.join();
}

void ChunkWriter::push(ChunkSnapshot snap) {
  {
    std::lock_guard lk(m_);
    q_.push_back(std::move(snap));
  }
  cv_.notify_one();
}

size_t ChunkWriter::queued() const {
  std::lock_guard lk(m_);
  return q_.size() + (busy_ ? 1 : 0);
}

void ChunkWriter::flush() {
  std::unique_lock lk(m_);
  done_cv_.wait(lk, [&] { return q_.empty() && !busy_; });
}

void ChunkWriter::run() {
  for (;;) {
    ChunkSnapshot s;
    {
      std::unique_lock lk(m_);
      cv_.wait(lk, [&] { return stop_ || !q_.empty(); });
      if (q_.empty()) return;  // stop_ set and drained
      s = std::move(q_.front());
      q_.pop_front();
      busy_ = true;
    }
    if (!store_.save_chunk(s)) log_error("failed to write chunk ({},{})", s.pos.x, s.pos.z);
    written_++;
    {
      std::lock_guard lk(m_);
      busy_ = false;
    }
    done_cv_.notify_all();
  }
}

// ------------------------------------------------------------------ world

World::World(LevelStore& store, const WorldGen& gen, ThreadPool& pool) : store_(store), gen_(gen), pool_(pool), writer_(store) {}

World::~World() { shutdown(); }

void World::shutdown() {
  while (outstanding_.load() > 0) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  save_dirty(true);
}

int World::column_height(int x, int z) const {
  const Chunk* c = chunk({floor_div(x, 16), floor_div(z, 16)});
  return c ? c->height[col_index(floor_mod(x, 16), floor_mod(z, 16))] : MIN_Y;
}

BlockId World::get_block(int x, int y, int z) const {
  if (y < MIN_Y || y >= MAX_Y) return 0;
  ChunkPos p{floor_div(x, 16), floor_div(z, 16)};
  if (p != cache_pos_) {
    auto it = chunks_.find(pack_chunk(p));
    cache_chunk_ = it == chunks_.end() ? nullptr : it->second.get();
    cache_pos_ = p;
  }
  return cache_chunk_ ? cache_chunk_->get(floor_mod(x, 16), y, floor_mod(z, 16)) : BlockId(0);
}

void World::mark_dirty(ChunkPos p, u32 mask) {
  if (!column_loaded(p)) return;
  dirty_[pack_chunk(p)] |= mask;
}

void World::mark_dirty_around(int lx, int y, int lz, ChunkPos p, bool height_changed, bool light_changed) {
  const int sec = (y >> 4) - MIN_SUB;
  const int ly = y & 15;
  // Light spreads up to 14 blocks, i.e. into the adjacent sections/chunks.
  const bool wide = light_changed || height_changed;
  for (int dz = ((lz == 0 || wide) ? -1 : 0); dz <= ((lz == 15 || wide) ? 1 : 0); dz++)
    for (int dx = ((lx == 0 || wide) ? -1 : 0); dx <= ((lx == 15 || wide) ? 1 : 0); dx++) {
      u32 mask = 0;
      for (int ds_ = ((ly == 0 || wide) ? -1 : 0); ds_ <= ((ly == 15 || wide) ? 1 : 0); ds_++) {
        int s = sec + ds_;
        if (s >= 0 && s < NUM_SUBS) mask |= 1u << s;
      }
      if (height_changed) mask = 0xFFFFFFu;  // skylight of the whole column may have changed
      mark_dirty({p.x + dx, p.z + dz}, mask);
    }
}

bool World::set_block(int x, int y, int z, BlockId id) {
  if (y < MIN_Y || y >= MAX_Y) return false;
  ChunkPos p{floor_div(x, 16), floor_div(z, 16)};
  auto it = chunks_.find(pack_chunk(p));
  if (it == chunks_.end()) return false;
  Chunk& c = *it->second;
  const int lx = floor_mod(x, 16), lz = floor_mod(z, 16);
  const BlockId old = c.get(lx, y, lz);
  if (!c.set(lx, y, lz, id)) return false;
  c.dirty = true;
  const int old_h = c.height[col_index(lx, lz)], old_lh = c.light_height[col_index(lx, lz)];
  if (blocks_sky(old) != blocks_sky(id) || blocks_light(old) != blocks_light(id)) c.recompute_column_height(lx, lz);
  const bool changed = c.height[col_index(lx, lz)] != old_h || c.light_height[col_index(lx, lz)] != old_lh;
  const BlockInfo &oi = Blocks::get().info(old), &ni = Blocks::get().info(id);
  const bool light_changed = oi.emit != ni.emit || oi.opaque() != ni.opaque();
  mark_dirty_around(lx, y, lz, p, changed, light_changed);
  return true;
}

bool World::neighbourhood_loaded(ChunkPos c) const {
  for (int dz = -1; dz <= 1; dz++)
    for (int dx = -1; dx <= 1; dx++)
      if (!column_loaded({c.x + dx, c.z + dz})) return false;
  return true;
}

bool World::all_loaded_around(ChunkPos c, int r) const {
  for (int dz = -r; dz <= r; dz++)
    for (int dx = -r; dx <= r; dx++)
      if (dx * dx + dz * dz <= r * r && !column_loaded({c.x + dx, c.z + dz})) return false;
  return true;
}

bool World::snapshot3x3(ChunkPos c, std::array<ChunkSnapshot, 9>& out) const {
  int i = 0;
  for (int dz = -1; dz <= 1; dz++)
    for (int dx = -1; dx <= 1; dx++, i++) {
      const Chunk* ch = chunk({c.x + dx, c.z + dz});
      if (!ch) return false;
      out[static_cast<size_t>(i)] = ch->snapshot();
    }
  return true;
}

void World::take_dirty(std::vector<DirtyChunk>& out) {
  for (auto& [k, mask] : dirty_) out.push_back({{static_cast<i32>(k >> 32), static_cast<i32>(k & 0xFFFFFFFFu)}, mask});
  dirty_.clear();
}

void World::save_dirty(bool wait) {
  for (auto& [k, c] : chunks_) {
    if (!c->dirty) continue;
    writer_.push(c->snapshot());
    c->dirty = false;
  }
  if (wait) writer_.flush();
}

void World::unload_far(double px, double pz, int radius) {
  const int pcx = floor_div(static_cast<int>(std::floor(px)), 16), pcz = floor_div(static_cast<int>(std::floor(pz)), 16);
  const int keep = radius + 2;
  for (auto it = chunks_.begin(); it != chunks_.end();) {
    int dx = it->second->pos.x - pcx, dz = it->second->pos.z - pcz;
    if (dx * dx + dz * dz > keep * keep) {
      if (it->second->dirty) writer_.push(it->second->snapshot());
      dirty_.erase(it->first);
      cache_pos_ = {INT32_MIN, INT32_MIN};
      it = chunks_.erase(it);
    } else {
      ++it;
    }
  }
}

void World::update(double px, double pz, int radius) {
  frame_++;
  // 1. Integrate finished chunks.
  std::vector<Ready> done;
  {
    std::lock_guard lk(ready_m_);
    done.swap(ready_);
  }
  const int pcx = floor_div(static_cast<int>(std::floor(px)), 16), pcz = floor_div(static_cast<int>(std::floor(pz)), 16);
  const int load_r = radius + 1;
  for (auto& r : done) {
    u64 key = pack_chunk(r.pos);
    inflight_.erase(key);
    int dx = r.pos.x - pcx, dz = r.pos.z - pcz;
    if (dx * dx + dz * dz > (load_r + 1) * (load_r + 1)) continue;  // player moved away meanwhile
    chunks_[key] = std::move(r.chunk);
    dirty_[key] |= 0xFFFFFFu;
  }

  // 2. Unload chunks that are far behind us.
  if (frame_ % 20 == 0) unload_far(px, pz, load_r);

  // 3. Request missing chunks, nearest first, bounded by the number of in-flight jobs.
  if (offsets_radius_ != load_r) {
    offsets_.clear();
    for (int dz = -load_r; dz <= load_r; dz++)
      for (int dx = -load_r; dx <= load_r; dx++)
        if (dx * dx + dz * dz <= load_r * load_r) offsets_.emplace_back(dx, dz);
    std::sort(offsets_.begin(), offsets_.end(), [](auto& a, auto& b) { return a.first * a.first + a.second * a.second < b.first * b.first + b.second * b.second; });
    offsets_radius_ = load_r;
  }
  const size_t max_inflight = pool_.size() * 2 + 2;
  for (auto [dx, dz] : offsets_) {
    if (inflight_.size() >= max_inflight) break;
    ChunkPos p{pcx + dx, pcz + dz};
    u64 key = pack_chunk(p);
    if (chunks_.contains(key) || inflight_.contains(key)) continue;
    inflight_[key] = true;
    outstanding_++;
    pool_.submit(dx * dx + dz * dz, [this, p] {
      std::unique_ptr<Chunk> c = store_.load_chunk(p);
      if (c) from_disk_++;
      else {
        c = gen_.generate(p);
        generated_++;
      }
      {
        std::lock_guard lk(ready_m_);
        ready_.push_back({p, std::move(c)});
      }
      outstanding_--;
    });
  }
}

}  // namespace ds
