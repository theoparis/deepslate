#pragma once
// Bedrock Edition world persistence (minimal):
//   <world>/level.dat      8-byte header (storage version, length) + little-endian NBT
//   <world>/db/            LevelDB (raw-deflate block compression) holding chunk data
//   chunk key   = x:i32le z:i32le [dimension:i32le if != overworld] tag:u8 [subchunk index:i8]
//   tags used   = 0x2B Data3D, 0x2C Version, 0x2F SubChunkPrefix, 0x36 FinalizedState
//   player      = "~local_player" NBT
#include <filesystem>
#include <memory>

#include "world/chunk.hpp"

namespace leveldb { class DB; class Cache; class FilterPolicy; }

namespace ds {

struct LevelInfo {
  std::string name = "Deepslate World";
  i64 seed = 0;
  i32 game_type = 1;  // 0 survival, 1 creative
  i32 spawn_x = 0, spawn_y = 100, spawn_z = 0;
  i64 time = 1000;
  i64 last_played = 0;
  bool spawn_set = false;
};

struct InventorySlot {
  std::string block;  // full block name, empty = empty slot
  int count = 0;
};

struct PlayerData {
  double pos[3] = {0, 0, 0};
  float yaw = 0, pitch = 0;
  bool flying = false;
  int selected = 0;
  std::vector<InventorySlot> hotbar;  // 9 entries
};

class LevelStore {
 public:
  // Opens (or creates) a world directory. Returns null and fills `err` on failure.
  static std::unique_ptr<LevelStore> open(const std::filesystem::path& dir, i64 seed_for_new_world, std::string* err);
  ~LevelStore();

  bool is_new() const { return new_world_; }
  LevelInfo& info() { return info_; }
  bool write_level_dat();

  // Thread-safe.
  std::unique_ptr<Chunk> load_chunk(ChunkPos pos);
  bool save_chunk(const ChunkSnapshot& snap);
  bool has_chunk(ChunkPos pos);

  bool load_player(PlayerData& out);
  bool save_player(const PlayerData& p);

  const std::filesystem::path& dir() const { return dir_; }

  // Exposed for tests.
  static std::vector<u8> encode_subchunk(const SubChunk& s, int index);
  static bool decode_subchunk(std::span<const u8> data, SubChunk& out, int* index_out);
  static std::vector<u8> encode_data3d(const ChunkSnapshot& snap);
  static void decode_data3d(std::span<const u8> data, Chunk& c);
  static std::string chunk_key(ChunkPos pos, u8 tag, std::optional<i8> sub = std::nullopt);

 private:
  LevelStore() = default;
  bool read_level_dat();
  std::filesystem::path dir_;
  LevelInfo info_;
  bool new_world_ = false;
  leveldb::DB* db_ = nullptr;
  leveldb::Cache* cache_ = nullptr;
  const leveldb::FilterPolicy* filter_ = nullptr;
};

}  // namespace ds
