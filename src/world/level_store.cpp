#include "world/level_store.hpp"

#include <fstream>
#include <unordered_map>

#include <leveldb/cache.h>
#include <leveldb/db.h>
#include <leveldb/filter_policy.h>
#include <leveldb/options.h>
#include <leveldb/write_batch.h>

#include "nbt/nbt.hpp"

namespace ds {

namespace {

constexpr u8 TAG_DATA3D = 0x2B;
constexpr u8 TAG_VERSION = 0x2C;
constexpr u8 TAG_SUBCHUNK = 0x2F;
constexpr u8 TAG_FINALIZED = 0x36;
constexpr u8 CHUNK_VERSION = 40;
constexpr i32 LEVEL_STORAGE_VERSION = 10;

int pick_bits(size_t palette_size) {
  static constexpr int allowed[] = {1, 2, 3, 4, 5, 6, 8, 16};
  for (int b : allowed)
    if (palette_size <= (size_t{1} << b)) return b;
  return 16;
}

// Writes a paletted 4096-entry storage (blocks or biomes share the same word packing).
void pack_words(ByteWriter& w, const std::array<u16, 4096>& idx, int bits) {
  const int per_word = 32 / bits;
  const int n_words = (4096 + per_word - 1) / per_word;
  for (int wi = 0; wi < n_words; wi++) {
    u32 word = 0;
    for (int k = 0; k < per_word; k++) {
      int i = wi * per_word + k;
      if (i >= 4096) break;
      word |= static_cast<u32>(idx[i]) << (k * bits);
    }
    w.u32le(word);
  }
}

bool unpack_words(ByteReader& r, int bits, std::array<u16, 4096>& idx) {
  if (bits < 1 || bits > 16) return false;
  const int per_word = 32 / bits;
  const int n_words = (4096 + per_word - 1) / per_word;
  const u32 mask = (1u << bits) - 1;
  for (int wi = 0; wi < n_words; wi++) {
    u32 word = r.u32le();
    if (!r.ok()) return false;
    for (int k = 0; k < per_word; k++) {
      int i = wi * per_word + k;
      if (i >= 4096) break;
      idx[i] = static_cast<u16>((word >> (k * bits)) & mask);
    }
  }
  return true;
}

}  // namespace

// ------------------------------------------------------------------ codecs

std::string LevelStore::chunk_key(ChunkPos pos, u8 tag, std::optional<i8> sub) {
  ByteWriter w;
  w.i32le(pos.x);
  w.i32le(pos.z);
  w.u8_(tag);
  if (sub) w.u8_(static_cast<u8>(*sub));
  return std::string(reinterpret_cast<const char*>(w.buf.data()), w.buf.size());
}

std::vector<u8> LevelStore::encode_subchunk(const SubChunk& s, int index) {
  Blocks& reg = Blocks::get();
  std::unordered_map<BlockId, u16> lookup;
  std::vector<BlockId> palette;
  std::array<u16, 4096> idx{};
  for (int i = 0; i < 4096; i++) {
    auto [it, inserted] = lookup.try_emplace(s.b[i], static_cast<u16>(palette.size()));
    if (inserted) palette.push_back(s.b[i]);
    idx[i] = it->second;
  }
  ByteWriter w;
  w.u8_(9);   // sub-chunk format version
  w.u8_(1);   // storage layers
  w.u8_(static_cast<u8>(static_cast<i8>(index)));
  int bits = pick_bits(palette.size());
  w.u8_(static_cast<u8>(bits << 1));  // persistent (not runtime) palette
  pack_words(w, idx, bits);
  w.i32le(static_cast<i32>(palette.size()));
  for (BlockId id : palette) nbt::write_root(w, "", reg.to_palette_entry(id));
  return std::move(w.buf);
}

bool LevelStore::decode_subchunk(std::span<const u8> data, SubChunk& out, int* index_out) {
  ByteReader r(data);
  int version = r.u8_();
  int layers = 1;
  int index = 0;
  if (version == 8 || version == 9) {
    layers = r.u8_();
    if (version == 9) index = static_cast<i8>(r.u8_());
  } else if (version != 1) {
    return false;
  }
  if (index_out) *index_out = index;
  Blocks& reg = Blocks::get();
  for (int layer = 0; layer < layers; layer++) {
    int flag = r.u8_();
    if (!r.ok()) return false;
    int bits = flag >> 1;
    if (flag & 1) return false;  // runtime palettes only appear on the network
    std::array<u16, 4096> idx{};
    if (!unpack_words(r, bits, idx)) return false;
    i32 n = r.i32le();
    if (n < 0 || n > 65536 || !r.ok()) return false;
    std::vector<BlockId> palette(static_cast<size_t>(n));
    for (auto& p : palette) {
      auto root = nbt::read_root(r);
      if (!root) return false;
      p = reg.from_palette_entry(root->second);
    }
    if (layer == 0) {
      for (int i = 0; i < 4096; i++) out.b[i] = idx[i] < palette.size() ? palette[idx[i]] : BlockId(0);
    }
    // Layer 1 holds waterlogged liquids; not modelled.
  }
  return true;
}

std::vector<u8> LevelStore::encode_data3d(const ChunkSnapshot& snap) {
  ByteWriter w;
  // Height map: 256 x i16, stored relative to the world floor. Index = z*16+x.
  for (int z = 0; z < 16; z++)
    for (int x = 0; x < 16; x++) w.i16le(static_cast<i16>(snap.height[col_index(x, z)] - MIN_Y));
  // One biome palette per sub-chunk (24), column biomes replicated over y.
  for (int s = 0; s < NUM_SUBS; s++) {
    std::vector<u8> pal;
    std::array<u16, 4096> idx{};
    for (int x = 0; x < 16; x++)
      for (int z = 0; z < 16; z++) {
        u8 b = snap.biome[col_index(x, z)];
        auto it = std::find(pal.begin(), pal.end(), b);
        u16 pi = static_cast<u16>(it - pal.begin());
        if (it == pal.end()) pal.push_back(b);
        for (int y = 0; y < 16; y++) idx[sub_index(x, y, z)] = pi;
      }
    if (pal.size() == 1) {
      w.u8_(1);  // zero bits per entry, runtime flag set (as Mojang writes biome storages)
      w.i32le(pal[0]);
    } else {
      int bits = pick_bits(pal.size());
      w.u8_(static_cast<u8>((bits << 1) | 1));
      pack_words(w, idx, bits);
      w.i32le(static_cast<i32>(pal.size()));
      for (u8 b : pal) w.i32le(b);
    }
  }
  return std::move(w.buf);
}

void LevelStore::decode_data3d(std::span<const u8> data, Chunk& c) {
  ByteReader r(data);
  for (int z = 0; z < 16; z++)
    for (int x = 0; x < 16; x++) c.height[col_index(x, z)] = static_cast<i16>(r.i16le() + MIN_Y);
  // Decode the biome palette of the section that contains each column's surface.
  struct Store { std::array<u16, 4096> idx{}; std::vector<i32> pal; bool valid = false; };
  std::array<Store, 32> stores;
  int n = 0;
  while (!r.eof() && r.ok() && n < 32) {
    int flag = r.u8_();
    Store& st = stores[n];
    if (flag == 0xFF) {  // "same as previous section"
      if (n > 0) st = stores[n - 1];
    } else {
      int bits = flag >> 1;
      if (bits == 0) {
        st.pal = {r.i32le()};
        st.idx.fill(0);
      } else {
        if (!unpack_words(r, bits, st.idx)) break;
        i32 cnt = r.i32le();
        if (cnt < 0 || cnt > 4096) break;
        st.pal.resize(static_cast<size_t>(cnt));
        for (auto& p : st.pal) p = r.i32le();
      }
      st.valid = r.ok();
    }
    n++;
  }
  for (int x = 0; x < 16; x++)
    for (int z = 0; z < 16; z++) {
      int y = std::max(c.height[col_index(x, z)] - 1, MIN_Y);
      int si = clampv((y >> 4) - MIN_SUB, 0, std::max(0, n - 1));
      if (n == 0) { c.biome[col_index(x, z)] = Biome::Plains; continue; }
      Store& st = stores[static_cast<size_t>(si)];
      u8 b = Biome::Plains;
      if (st.valid) {
        u16 pi = st.idx[sub_index(x, y & 15, z)];
        if (pi < st.pal.size()) b = static_cast<u8>(st.pal[pi]);
      }
      c.biome[col_index(x, z)] = b;
    }
}

// ------------------------------------------------------------------ level.dat

bool LevelStore::write_level_dat() {
  nbt::Tag t = nbt::Tag::make_compound();
  using nbt::Tag;
  t.set("StorageVersion", Tag::make_int(LEVEL_STORAGE_VERSION));
  t.set("NetworkVersion", Tag::make_int(898));
  {
    Tag v = Tag::make_list(nbt::Type::Int);
    for (int x : {1, 21, 50, 0, 0}) v.list.push_back(Tag::make_int(x));
    t.set("lastOpenedWithVersion", v);
    Tag m = Tag::make_list(nbt::Type::Int);
    for (int x : {1, 21, 0, 0, 0}) m.list.push_back(Tag::make_int(x));
    t.set("MinimumCompatibleClientVersion", m);
  }
  t.set("LevelName", Tag::make_string(info_.name));
  t.set("RandomSeed", Tag::make_long(info_.seed));
  t.set("GameType", Tag::make_int(info_.game_type));
  t.set("Generator", Tag::make_int(1));  // infinite
  t.set("Difficulty", Tag::make_int(2));
  t.set("SpawnX", Tag::make_int(info_.spawn_x));
  t.set("SpawnY", Tag::make_int(info_.spawn_y));
  t.set("SpawnZ", Tag::make_int(info_.spawn_z));
  t.set("Time", Tag::make_long(info_.time));
  t.set("currentTick", Tag::make_long(info_.time));
  info_.last_played = static_cast<i64>(std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count());
  t.set("LastPlayed", Tag::make_long(info_.last_played));
  t.set("baseGameVersion", Tag::make_string("*"));
  t.set("commandsEnabled", Tag::make_byte(1));
  t.set("dodaylightcycle", Tag::make_byte(1));
  t.set("immutableWorld", Tag::make_byte(0));
  t.set("spawnMobs", Tag::make_byte(0));
  t.set("hasBeenLoadedInCreative", Tag::make_byte(info_.game_type == 1));
  t.set("eduLevel", Tag::make_byte(0));
  t.set("rainLevel", Tag::make_float(0));
  t.set("rainTime", Tag::make_int(100000));
  t.set("lightningLevel", Tag::make_float(0));
  t.set("lightningTime", Tag::make_int(100000));
  t.set("FlatWorldLayers", Tag::make_string(""));

  ByteWriter body;
  nbt::write_root(body, "", t);
  ByteWriter file;
  file.i32le(LEVEL_STORAGE_VERSION);
  file.i32le(static_cast<i32>(body.buf.size()));
  file.bytes(body.buf);

  auto tmp = dir_ / "level.dat.tmp";
  {
    std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
    if (!f) return false;
    f.write(reinterpret_cast<const char*>(file.buf.data()), static_cast<std::streamsize>(file.buf.size()));
    if (!f) return false;
  }
  std::error_code ec;
  std::filesystem::rename(tmp, dir_ / "level.dat", ec);
  if (ec) return false;
  {
    std::ofstream n(dir_ / "levelname.txt", std::ios::trunc);
    n << info_.name;
  }
  return true;
}

bool LevelStore::read_level_dat() {
  std::ifstream f(dir_ / "level.dat", std::ios::binary);
  if (!f) return false;
  std::vector<u8> data((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  ByteReader r(data);
  r.i32le();  // storage version
  i32 len = r.i32le();
  if (!r.ok() || len < 0 || static_cast<size_t>(len) > r.remaining()) return false;
  auto root = nbt::read_root(r);
  if (!root || root->second.type != nbt::Type::Compound) return false;
  const nbt::Tag& t = root->second;
  info_.name = t.get_string("LevelName", info_.name);
  info_.seed = t.get_int("RandomSeed", 0);
  info_.game_type = static_cast<i32>(t.get_int("GameType", 1));
  info_.spawn_x = static_cast<i32>(t.get_int("SpawnX", 0));
  info_.spawn_y = static_cast<i32>(t.get_int("SpawnY", 100));
  info_.spawn_z = static_cast<i32>(t.get_int("SpawnZ", 0));
  info_.time = t.get_int("Time", 1000);
  info_.last_played = t.get_int("LastPlayed", 0);
  info_.spawn_set = true;
  return true;
}

// ------------------------------------------------------------------ open / close

std::unique_ptr<LevelStore> LevelStore::open(const std::filesystem::path& dir, i64 seed, std::string* err) {
  auto fail = [&](std::string m) -> std::unique_ptr<LevelStore> {
    if (err) *err = std::move(m);
    return nullptr;
  };
  std::error_code ec;
  std::filesystem::create_directories(dir / "db", ec);
  if (ec) return fail("cannot create " + dir.string() + ": " + ec.message());

  std::unique_ptr<LevelStore> s(new LevelStore());
  s->dir_ = dir;
  if (!s->read_level_dat()) {
    s->new_world_ = true;
    s->info_.seed = seed;
    s->info_.name = dir.filename().string();
    if (s->info_.name.empty()) s->info_.name = "Deepslate World";
  }

  leveldb::Options opt;
  opt.create_if_missing = true;
  opt.compression = leveldb::kZlibRawCompression;  // Bedrock's on-disk block compression
  s->cache_ = leveldb::NewLRUCache(16 * 1024 * 1024);
  s->filter_ = leveldb::NewBloomFilterPolicy(10);
  opt.block_cache = s->cache_;
  opt.filter_policy = s->filter_;
  opt.write_buffer_size = 4 * 1024 * 1024;
  opt.max_open_files = 128;
  leveldb::Status st = leveldb::DB::Open(opt, (dir / "db").string(), &s->db_);
  if (!st.ok()) return fail("leveldb: " + st.ToString());
  return s;
}

LevelStore::~LevelStore() {
  delete db_;
  delete cache_;
  delete filter_;
}

// ------------------------------------------------------------------ chunks

bool LevelStore::has_chunk(ChunkPos pos) {
  std::string v;
  return db_->Get(leveldb::ReadOptions(), chunk_key(pos, TAG_VERSION), &v).ok();
}

std::unique_ptr<Chunk> LevelStore::load_chunk(ChunkPos pos) {
  leveldb::ReadOptions ro;
  std::string v;
  if (!db_->Get(ro, chunk_key(pos, TAG_VERSION), &v).ok()) return nullptr;
  auto c = std::make_unique<Chunk>();
  c->pos = pos;
  for (int si = 0; si < NUM_SUBS; si++) {
    std::string data;
    if (!db_->Get(ro, chunk_key(pos, TAG_SUBCHUNK, static_cast<i8>(si + MIN_SUB)), &data).ok()) continue;
    auto sub = std::make_shared<SubChunk>();
    int idx = si + MIN_SUB;
    if (!decode_subchunk({reinterpret_cast<const u8*>(data.data()), data.size()}, *sub, &idx)) {
      log_warn("chunk ({},{}) sub {}: undecodable sub-chunk, dropping", pos.x, pos.z, si + MIN_SUB);
      continue;
    }
    // Version-1/8 sub-chunks carry no index: the key is authoritative.
    c->subs[static_cast<size_t>(si)] = std::move(sub);
  }
  std::string d3;
  bool have_biomes = false;
  if (db_->Get(ro, chunk_key(pos, TAG_DATA3D), &d3).ok()) {
    decode_data3d({reinterpret_cast<const u8*>(d3.data()), d3.size()}, *c);
    have_biomes = true;
  }
  c->recompute_heights();  // authoritative: also covers worlds written by other tools
  if (!have_biomes) c->biome.fill(Biome::Plains);
  return c;
}

bool LevelStore::save_chunk(const ChunkSnapshot& snap) {
  leveldb::WriteBatch batch;
  auto put = [&](const std::string& k, const std::vector<u8>& v) {
    batch.Put(k, leveldb::Slice(reinterpret_cast<const char*>(v.data()), v.size()));
  };
  put(chunk_key(snap.pos, TAG_VERSION), {CHUNK_VERSION});
  put(chunk_key(snap.pos, TAG_DATA3D), encode_data3d(snap));
  ByteWriter fin;
  fin.i32le(2);  // FinalizedState: done
  put(chunk_key(snap.pos, TAG_FINALIZED), fin.buf);
  for (int si = 0; si < NUM_SUBS; si++) {
    std::string key = chunk_key(snap.pos, TAG_SUBCHUNK, static_cast<i8>(si + MIN_SUB));
    bool empty = true;
    if (snap.subs[static_cast<size_t>(si)]) {
      for (BlockId b : snap.subs[static_cast<size_t>(si)]->b)
        if (b != 0) { empty = false; break; }
    }
    if (empty) batch.Delete(key);
    else put(key, encode_subchunk(*snap.subs[static_cast<size_t>(si)], si + MIN_SUB));
  }
  return db_->Write(leveldb::WriteOptions(), &batch).ok();
}

// ------------------------------------------------------------------ player

bool LevelStore::save_player(const PlayerData& p) {
  using nbt::Tag;
  Tag t = Tag::make_compound();
  Tag pos = Tag::make_list(nbt::Type::Float);
  for (double d : p.pos) pos.list.push_back(Tag::make_float(d));
  t.set("Pos", pos);
  Tag rot = Tag::make_list(nbt::Type::Float);
  rot.list.push_back(Tag::make_float(p.yaw));
  rot.list.push_back(Tag::make_float(p.pitch));
  t.set("Rotation", rot);
  Tag mot = Tag::make_list(nbt::Type::Float);
  for (int i = 0; i < 3; i++) mot.list.push_back(Tag::make_float(0));
  t.set("Motion", mot);
  t.set("OnGround", Tag::make_byte(0));
  t.set("Health", Tag::make_short(20));
  t.set("DimensionId", Tag::make_int(0));
  t.set("UniqueID", Tag::make_long(1));
  Tag ab = Tag::make_compound();
  ab.set("flying", Tag::make_byte(p.flying));
  ab.set("mayfly", Tag::make_byte(1));
  t.set("abilities", ab);
  t.set("SelectedInventorySlot", Tag::make_int(p.selected));
  Tag inv = Tag::make_list(nbt::Type::Compound);
  for (size_t i = 0; i < p.hotbar.size(); i++) {
    const auto& s = p.hotbar[i];
    Tag e = Tag::make_compound();
    e.set("Slot", Tag::make_byte(static_cast<i64>(i)));
    e.set("Count", Tag::make_byte(s.block.empty() ? 0 : s.count));
    e.set("Damage", Tag::make_short(0));
    e.set("Name", Tag::make_string(s.block));
    inv.list.push_back(std::move(e));
  }
  t.set("Inventory", inv);
  ByteWriter w;
  nbt::write_root(w, "", t);
  return db_->Put(leveldb::WriteOptions(), "~local_player", leveldb::Slice(reinterpret_cast<const char*>(w.buf.data()), w.buf.size())).ok();
}

bool LevelStore::load_player(PlayerData& out) {
  std::string v;
  if (!db_->Get(leveldb::ReadOptions(), "~local_player", &v).ok()) return false;
  ByteReader r({reinterpret_cast<const u8*>(v.data()), v.size()});
  auto root = nbt::read_root(r);
  if (!root) return false;
  const nbt::Tag& t = root->second;
  const nbt::Tag* pos = t.find("Pos");
  if (!pos || pos->list.size() < 3) return false;
  for (int i = 0; i < 3; i++) out.pos[i] = pos->list_num(static_cast<size_t>(i));
  if (const nbt::Tag* rot = t.find("Rotation")) {
    out.yaw = static_cast<float>(rot->list_num(0));
    out.pitch = static_cast<float>(rot->list_num(1));
  }
  if (const nbt::Tag* ab = t.find("abilities")) out.flying = ab->get_int("flying") != 0;
  out.selected = static_cast<int>(t.get_int("SelectedInventorySlot", 0));
  out.hotbar.assign(9, {});
  if (const nbt::Tag* inv = t.find("Inventory")) {
    for (const nbt::Tag& e : inv->list) {
      int slot = static_cast<int>(e.get_int("Slot", -1));
      if (slot < 0 || slot >= 9) continue;
      out.hotbar[static_cast<size_t>(slot)] = {e.get_string("Name"), static_cast<int>(e.get_int("Count"))};
    }
  }
  return true;
}

}  // namespace ds
