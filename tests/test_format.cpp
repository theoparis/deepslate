// NBT, block registry and Bedrock chunk/level codecs.
#include <filesystem>
#include <fstream>
#include <unistd.h>
#include <random>

#include "nbt/nbt.hpp"
#include "test_framework.hpp"
#include "world/level_store.hpp"

using namespace ds;
namespace fs = std::filesystem;

static fs::path temp_dir(const char* name) {
  fs::path p = fs::temp_directory_path() / (std::string("deepslate-test-") + std::to_string(::getpid()) + "-" + name);
  fs::remove_all(p);
  fs::create_directories(p);
  return p;
}

TEST(nbt_roundtrip) {
  using namespace nbt;
  Tag root = Tag::make_compound();
  root.set("b", Tag::make_byte(-5));
  root.set("s", Tag::make_short(-1234));
  root.set("i", Tag::make_int(123456789));
  root.set("l", Tag::make_long(-9876543210123LL));
  root.set("f", Tag::make_float(1.5));
  root.set("d", Tag::make_double(-2.25));
  root.set("str", Tag::make_string("héllo"));
  Tag list = Tag::make_list(Type::Int);
  for (int i = 0; i < 4; i++) list.list.push_back(Tag::make_int(i * i));
  root.set("list", list);
  Tag nested = Tag::make_compound();
  nested.set("x", Tag::make_int(7));
  root.set("nested", nested);
  Tag ba;
  ba.type = Type::ByteArray;
  ba.bytes = {1, 2, 3, 250};
  root.set("ba", ba);
  Tag ia;
  ia.type = Type::IntArray;
  ia.ints = {-1, 0, 65536};
  root.set("ia", ia);

  ByteWriter w;
  write_root(w, "root", root);
  ByteReader r(w.buf);
  auto got = read_root(r);
  CHECK(got.has_value());
  CHECK_EQ(got->first, std::string("root"));
  const Tag& t = got->second;
  CHECK_EQ(t.get_int("b"), -5);
  CHECK_EQ(t.get_int("s"), -1234);
  CHECK_EQ(t.get_int("i"), 123456789);
  CHECK_EQ(t.get_int("l"), -9876543210123LL);
  CHECK_EQ(t.get_num("f"), 1.5);
  CHECK_EQ(t.get_num("d"), -2.25);
  CHECK_EQ(t.get_string("str"), std::string("héllo"));
  CHECK_EQ(t.find("list")->list.size(), size_t{4});
  CHECK_EQ(t.find("list")->list_num(3), 9.0);
  CHECK_EQ(t.find("nested")->get_int("x"), 7);
  CHECK_EQ(t.find("ba")->bytes.size(), size_t{4});
  CHECK_EQ(t.find("ia")->ints[2], 65536);
  CHECK(r.eof());
}

TEST(nbt_is_little_endian) {
  nbt::Tag t = nbt::Tag::make_compound();
  t.set("v", nbt::Tag::make_int(0x01020304));
  ByteWriter w;
  nbt::write_root(w, "", t);
  // 0x0A (compound) 0x0000 (empty name) 0x03 (int) 0x0001 'v' then 04 03 02 01
  const std::vector<u8> expect = {0x0A, 0, 0, 0x03, 1, 0, 'v', 4, 3, 2, 1, 0};
  CHECK(w.buf == expect);
}

TEST(nbt_rejects_truncated_and_garbage) {
  nbt::Tag t = nbt::Tag::make_compound();
  t.set("name", nbt::Tag::make_string("a fairly long string value"));
  ByteWriter w;
  nbt::write_root(w, "x", t);
  for (size_t cut = 0; cut + 1 < w.buf.size(); cut++) {
    std::vector<u8> part(w.buf.begin(), w.buf.begin() + static_cast<std::ptrdiff_t>(cut));
    ByteReader r(part);
    CHECK(!nbt::read_root(r).has_value());
  }
  std::mt19937 rng(1);
  for (int i = 0; i < 200; i++) {
    std::vector<u8> junk(64);
    for (auto& b : junk) b = static_cast<u8>(rng());
    ByteReader r(junk);
    (void)nbt::read_root(r);  // must not crash or hang
  }
}

TEST(block_registry_basics) {
  Blocks& reg = Blocks::get();
  CHECK_EQ(reg.info(0).name, std::string("minecraft:air"));
  CHECK_EQ(B::air, BlockId(0));
  CHECK(reg.info(B::stone).opaque());
  CHECK(reg.info(B::water).liquid());
  CHECK(reg.info(B::glass).solid() && !reg.info(B::glass).opaque());
  CHECK(reg.info(B::short_grass).replaceable());
  CHECK(reg.info(B::torch).emit == 14);
  CHECK(reg.find("oak_log") == B::oak_log);
  CHECK(reg.find("minecraft:oak_log") == B::oak_log);
  CHECK_EQ(reg.find("does_not_exist"), BlockId(0));
  // Different states are different ids; same states are the same id.
  BlockId ax = reg.lookup_or_register("minecraft:oak_log", {{"pillar_axis", StateValue::string("x")}});
  BlockId ay = reg.lookup_or_register("minecraft:oak_log", {{"pillar_axis", StateValue::string("y")}});
  CHECK(ax != ay);
  CHECK(ay == B::oak_log);
  CHECK(ax == reg.lookup_or_register("minecraft:oak_log", {{"pillar_axis", StateValue::string("x")}}));
}

TEST(block_registry_unknown_blocks) {
  Blocks& reg = Blocks::get();
  BlockId u = reg.lookup_or_register("minecraft:some_future_block", {{"foo", StateValue::byte(1)}});
  CHECK(u != 0);
  CHECK(reg.info(u).flags & BF_Unknown);
  CHECK(reg.info(u).opaque());
  CHECK_EQ(reg.lookup_or_register("minecraft:some_future_block", {{"foo", StateValue::byte(1)}}), u);
}

TEST(block_shapes) {
  Blocks& reg = Blocks::get();
  CHECK_EQ(reg.info(B::stone).nbox, 1);
  CHECK_EQ(reg.info(B::short_grass).nbox, 0);
  BlockId slab_top = reg.lookup_or_register("minecraft:oak_slab", {{"minecraft:vertical_half", StateValue::string("top")}});
  BlockId slab_bot = reg.lookup_or_register("minecraft:oak_slab", {{"minecraft:vertical_half", StateValue::string("bottom")}});
  CHECK_EQ(reg.info(slab_top).boxes[0].min[1], 0.5f);
  CHECK_EQ(reg.info(slab_bot).boxes[0].max[1], 0.5f);
  BlockId stairs = reg.lookup_or_register("minecraft:oak_stairs", {{"weirdo_direction", StateValue::integer(0)}, {"upside_down_bit", StateValue::byte(0)}});
  CHECK_EQ(reg.info(stairs).nbox, 2);
  CHECK_EQ(reg.info(stairs).boxes[1].min[0], 0.5f);  // rises toward +x (east)
}

TEST(palette_entry_roundtrip) {
  Blocks& reg = Blocks::get();
  for (BlockId id : {B::stone, B::oak_log, B::grass_block, B::water, B::oak_leaves}) {
    nbt::Tag t = reg.to_palette_entry(id);
    CHECK_EQ(t.get_string("name"), reg.info(id).name);
    CHECK(t.find("states") != nullptr);
    CHECK(t.find("version") != nullptr);
    CHECK_EQ(reg.from_palette_entry(t), id);
  }
  // Legacy name aliases resolve.
  nbt::Tag legacy = nbt::Tag::make_compound();
  legacy.set("name", nbt::Tag::make_string("minecraft:grass"));
  legacy.set("states", nbt::Tag::make_compound());
  CHECK_EQ(reg.from_palette_entry(legacy), B::grass_block);
}

static SubChunk random_subchunk(int palette_size, unsigned seed) {
  Blocks& reg = Blocks::get();
  std::vector<BlockId> pal;
  for (int i = 0; i < palette_size; i++) pal.push_back(static_cast<BlockId>(1 + i % (reg.count() - 1)));  // distinct ids
  std::mt19937 rng(seed);
  SubChunk s;
  for (auto& b : s.b) b = pal[rng() % pal.size()];
  return s;
}

TEST(subchunk_codec_all_palette_sizes) {
  // Palette sizes chosen to hit every bits-per-block width Bedrock allows (1,2,3,4,5,6,8,16).
  for (int n : {1, 2, 3, 4, 7, 8, 9, 16, 17, 32, 33, 64, 65, 200}) {
    SubChunk s = random_subchunk(n, static_cast<unsigned>(n));
    auto bytes = LevelStore::encode_subchunk(s, -3);
    CHECK_EQ(bytes[0], u8{9});   // format version
    CHECK_EQ(bytes[1], u8{1});   // one storage layer
    CHECK_EQ(bytes[2], u8{0xFD}); // y index -3 as a signed byte
    SubChunk d;
    int idx = 99;
    CHECK(LevelStore::decode_subchunk(bytes, d, &idx));
    CHECK_EQ(idx, -3);
    CHECK(d.b == s.b);
  }
}

TEST(subchunk_bits_per_block_header) {
  auto header_bits = [](int palette) {
    SubChunk s = random_subchunk(palette, 5);
    auto bytes = LevelStore::encode_subchunk(s, 0);
    return bytes[3] >> 1;
  };
  CHECK_EQ(header_bits(1), 1);
  CHECK_EQ(header_bits(2), 1);
  CHECK_EQ(header_bits(3), 2);
  CHECK_EQ(header_bits(5), 3);
  CHECK_EQ(header_bits(9), 4);
  CHECK_EQ(header_bits(17), 5);
  CHECK_EQ(header_bits(33), 6);
  CHECK_EQ(header_bits(65), 8);
  CHECK_EQ(header_bits(200), 8);
}

TEST(subchunk_word_packing_matches_bedrock_layout) {
  // Bedrock packs blocks in x,z,y order, 32/bits entries per little-endian 32-bit word.
  SubChunk s;  // all air except a marker
  s.b[sub_index(0, 0, 0)] = B::stone;
  s.b[sub_index(0, 1, 0)] = B::dirt;  // y is the fastest-moving coordinate
  auto bytes = LevelStore::encode_subchunk(s, 0);
  // 3 palette entries -> 2 bits per block -> 16 blocks per word. Palette order = first use: stone, dirt, air.
  CHECK_EQ(bytes[3] >> 1, 2);
  u32 word0 = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (u32(bytes[7]) << 24);
  CHECK_EQ(word0 & 3u, 0u);         // (0,0,0) -> palette index 0 (stone)
  CHECK_EQ((word0 >> 2) & 3u, 1u);  // (0,1,0) -> palette index 1 (dirt)
  CHECK_EQ((word0 >> 4) & 3u, 2u);  // (0,2,0) -> air
}

TEST(subchunk_decode_legacy_versions) {
  // Version 8 header (no y index) and version 1 (single layer, no layer count).
  SubChunk s = random_subchunk(5, 3);
  auto v9 = LevelStore::encode_subchunk(s, 2);
  std::vector<u8> v8 = {8, 1};
  v8.insert(v8.end(), v9.begin() + 3, v9.end());
  SubChunk d8;
  CHECK(LevelStore::decode_subchunk(v8, d8, nullptr));
  CHECK(d8.b == s.b);
  std::vector<u8> v1 = {1};
  v1.insert(v1.end(), v9.begin() + 3, v9.end());
  SubChunk d1;
  CHECK(LevelStore::decode_subchunk(v1, d1, nullptr));
  CHECK(d1.b == s.b);
  // Truncated / runtime-palette data is rejected, not misread.
  SubChunk bad;
  CHECK(!LevelStore::decode_subchunk(std::span<const u8>(v9.data(), 40), bad, nullptr));
  std::vector<u8> runtime = v9;
  runtime[3] |= 1;
  CHECK(!LevelStore::decode_subchunk(runtime, bad, nullptr));
}

TEST(data3d_codec) {
  ChunkSnapshot snap;
  for (int x = 0; x < 16; x++)
    for (int z = 0; z < 16; z++) {
      snap.height[col_index(x, z)] = static_cast<i16>(60 + x + z);
      snap.biome[col_index(x, z)] = static_cast<u8>((x / 4 + z / 8) % 3 == 0 ? Biome::Plains : ((x + z) % 2 ? Biome::Forest : Biome::Desert));
    }
  auto bytes = LevelStore::encode_data3d(snap);
  CHECK(bytes.size() > 512);
  Chunk c;
  LevelStore::decode_data3d(bytes, c);
  for (int x = 0; x < 16; x++)
    for (int z = 0; z < 16; z++) {
      CHECK_EQ(c.height[col_index(x, z)], snap.height[col_index(x, z)]);
      CHECK_EQ(c.biome[col_index(x, z)], snap.biome[col_index(x, z)]);
    }
  // Uniform biome uses the compact single-value form.
  ChunkSnapshot uni;
  uni.biome.fill(Biome::Taiga);
  auto ub = LevelStore::encode_data3d(uni);
  CHECK_EQ(ub.size(), size_t{512 + 24 * 5});
  Chunk c2;
  LevelStore::decode_data3d(ub, c2);
  CHECK_EQ(c2.biome[37], u8(Biome::Taiga));
}

TEST(chunk_key_layout) {
  // x:i32le z:i32le tag [sub]  -- overworld keys carry no dimension id.
  auto k = LevelStore::chunk_key({-2, 3}, 0x2F, static_cast<i8>(-4));
  const std::string expect = std::string("\xFE\xFF\xFF\xFF\x03\x00\x00\x00\x2F\xFC", 10);
  CHECK(k == expect);
  auto k2 = LevelStore::chunk_key({1, 1}, 0x2C);
  CHECK_EQ(k2.size(), size_t{9});
}

TEST(level_store_roundtrip) {
  fs::path dir = temp_dir("store");
  std::string err;
  {
    auto st = LevelStore::open(dir, 12345, &err);
    CHECK(st != nullptr);
    if (!st) return;
    CHECK(st->is_new());
    st->info().name = "Round Trip";
    st->info().spawn_x = 5; st->info().spawn_y = 70; st->info().spawn_z = -9;
    st->info().time = 4242;
    CHECK(st->write_level_dat());

    Chunk c;
    c.pos = {-3, 7};
    for (int x = 0; x < 16; x++)
      for (int z = 0; z < 16; z++) {
        for (int y = -64; y < 60; y++) c.set(x, y, z, y < 0 ? B::deepslate : B::stone);
        c.set(x, 60, z, B::grass_block);
        c.biome[col_index(x, z)] = Biome::Forest;
      }
    c.set(4, 61, 4, B::oak_log);
    c.set(4, 62, 4, B::torch);
    c.recompute_heights();
    CHECK(st->save_chunk(c.snapshot()));
    CHECK(st->has_chunk({-3, 7}));
    CHECK(!st->has_chunk({0, 0}));

    PlayerData p;
    p.pos[0] = 1.5; p.pos[1] = 70.25; p.pos[2] = -3.75;
    p.yaw = 33; p.pitch = -12; p.flying = true; p.selected = 4;
    p.hotbar.assign(9, {});
    p.hotbar[2] = {"minecraft:stone", 1};
    CHECK(st->save_player(p));
  }
  {
    auto st = LevelStore::open(dir, 999, &err);
    CHECK(st != nullptr);
    if (!st) return;
    CHECK(!st->is_new());
    CHECK_EQ(st->info().name, std::string("Round Trip"));
    CHECK_EQ(st->info().seed, i64{12345});  // seed comes from level.dat, not the argument
    CHECK_EQ(st->info().spawn_x, 5);
    CHECK_EQ(st->info().spawn_y, 70);
    CHECK_EQ(st->info().spawn_z, -9);
    CHECK_EQ(st->info().time, i64{4242});
    auto c = st->load_chunk({-3, 7});
    CHECK(c != nullptr);
    if (c) {
      CHECK_EQ(c->get(3, -64, 3), B::deepslate);
      CHECK_EQ(c->get(3, -1, 3), B::deepslate);
      CHECK_EQ(c->get(3, 0, 3), B::stone);
      CHECK_EQ(c->get(3, 60, 3), B::grass_block);
      CHECK_EQ(c->get(4, 61, 4), B::oak_log);
      CHECK_EQ(c->get(4, 62, 4), B::torch);
      CHECK_EQ(c->get(3, 100, 3), BlockId(0));
      CHECK_EQ(c->biome[col_index(9, 9)], u8(Biome::Forest));
      CHECK_EQ(c->height[col_index(3, 3)], i16(61));
      CHECK_EQ(c->height[col_index(4, 4)], i16(62));  // the log; the torch does not block sky
    }
    CHECK(st->load_chunk({0, 0}) == nullptr);
    PlayerData p;
    CHECK(st->load_player(p));
    CHECK_EQ(p.pos[1], 70.25);
    CHECK_EQ(p.yaw, 33.0f);
    CHECK(p.flying);
    CHECK_EQ(p.selected, 4);
    CHECK_EQ(p.hotbar[2].block, std::string("minecraft:stone"));
  }
  fs::remove_all(dir);
}

TEST(level_dat_header) {
  fs::path dir = temp_dir("leveldat");
  std::string err;
  auto st = LevelStore::open(dir, 1, &err);
  CHECK(st != nullptr);
  if (!st) return;
  CHECK(st->write_level_dat());
  std::ifstream f(dir / "level.dat", std::ios::binary);
  std::vector<u8> data((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  ByteReader r(data);
  CHECK_EQ(r.i32le(), 10);  // storage version
  i32 len = r.i32le();
  CHECK_EQ(static_cast<size_t>(len), data.size() - 8);
  auto root = nbt::read_root(r);
  CHECK(root.has_value());
  if (root) {
    CHECK(root->first.empty());
    CHECK(root->second.find("LevelName") != nullptr);
    CHECK(root->second.find("RandomSeed") != nullptr);
    CHECK_EQ(root->second.get_int("StorageVersion"), 10);
    CHECK_EQ(root->second.get_int("Generator"), 1);
  }
  st.reset();
  fs::remove_all(dir);
}

TEST(chunk_snapshots_are_isolated_copy_on_write) {
  Chunk c;
  c.set(1, 10, 1, B::stone);
  ChunkSnapshot snap = c.snapshot();
  c.set(1, 10, 1, B::dirt);
  c.set(2, 10, 2, B::sand);
  CHECK_EQ(snap.get(1, 10, 1), B::stone);
  CHECK_EQ(snap.get(2, 10, 2), BlockId(0));
  CHECK_EQ(c.get(1, 10, 1), B::dirt);
  CHECK_EQ(c.get(2, 10, 2), B::sand);
}

TEST(heightmap_counts_light_blockers) {
  Chunk c;
  c.set(0, 10, 0, B::stone);
  c.set(0, 11, 0, B::oak_leaves);
  c.set(0, 12, 0, B::short_grass);
  c.set(5, 20, 5, B::water);
  c.recompute_heights();
  CHECK_EQ(c.height[col_index(0, 0)], i16(12));        // leaves block sky
  CHECK_EQ(c.light_height[col_index(0, 0)], i16(11));  // but only opaque blocks count for light
  CHECK_EQ(c.height[col_index(5, 5)], i16(21));
  CHECK_EQ(c.light_height[col_index(5, 5)], i16(MIN_Y));
}
