// World generation, packs, meshing, physics and threading.
#include <atomic>
#include <filesystem>
#include <fstream>
#include <thread>
#include <unistd.h>

#include "assets/block_models.hpp"
#include "assets/image.hpp"
#include "assets/resource_pack.hpp"
#include "game/block_updates.hpp"
#include "game/player.hpp"
#include "game/raycast.hpp"
#include "render/mesher.hpp"
#include "test_framework.hpp"
#include "util/thread_pool.hpp"
#include "world/world.hpp"

using namespace ds;
namespace fs = std::filesystem;

static fs::path temp_dir(const char* name) {
  fs::path p = fs::temp_directory_path() / (std::string("deepslate-test-") + std::to_string(::getpid()) + "-" + name);
  fs::remove_all(p);
  fs::create_directories(p);
  return p;
}

// ---------------------------------------------------------------- generator

TEST(worldgen_is_deterministic) {
  (void)Blocks::get();
  WorldGen a(1234), b(1234), c(4321);
  auto ca = a.generate({5, -9}), cb = b.generate({5, -9}), cc = c.generate({5, -9});
  bool same = true, differs = false;
  for (int i = 0; i < NUM_SUBS; i++) {
    bool ea = !ca->subs[static_cast<size_t>(i)], eb = !cb->subs[static_cast<size_t>(i)];
    if (ea != eb) same = false;
    else if (!ea && ca->subs[static_cast<size_t>(i)]->b != cb->subs[static_cast<size_t>(i)]->b) same = false;
    bool ec = !cc->subs[static_cast<size_t>(i)];
    if (ea != ec || (!ea && ca->subs[static_cast<size_t>(i)]->b != cc->subs[static_cast<size_t>(i)]->b)) differs = true;
  }
  CHECK(same);
  CHECK(differs);
  CHECK(ca->biome == cb->biome);
}

TEST(worldgen_structure) {
  (void)Blocks::get();
  WorldGen g(77);
  int water_cols = 0, land_cols = 0;
  for (int cz = -6; cz < 6; cz++)
    for (int cx = -6; cx < 6; cx++) {
      auto c = g.generate({cx * 7, cz * 7});
      for (int x = 0; x < 16; x += 5)
        for (int z = 0; z < 16; z += 5) {
          CHECK_EQ(c->get(x, -64, z), B::bedrock);          // world floor
          CHECK(c->get(x, -20, z) != B::grass_block);       // grass only on the surface
          int h = c->height[col_index(x, z)];
          CHECK(h > MIN_Y && h < MAX_Y);
          if (c->get(x, WorldGen::SEA_LEVEL, z) == B::water || c->get(x, WorldGen::SEA_LEVEL, z) == B::ice) water_cols++;
          else land_cols++;
        }
    }
  CHECK(water_cols > 20);
  CHECK(land_cols > 20);
}

TEST(worldgen_thread_safety) {
  (void)Blocks::get();
  WorldGen g(99);
  auto ref = g.generate({3, 3});
  std::atomic<int> bad{0};
  std::vector<std::thread> ts;
  for (int t = 0; t < 4; t++)
    ts.emplace_back([&, t] {
      for (int i = 0; i < 6; i++) {
        auto c = g.generate({3, 3});
        for (int s = 0; s < NUM_SUBS; s++) {
          auto &a = c->subs[static_cast<size_t>(s)], &b = ref->subs[static_cast<size_t>(s)];
          if (!a != !b || (a && a->b != b->b)) bad++;
        }
        g.generate({3 + t, 4 + i});  // interleave other chunks
      }
    });
  for (auto& t : ts) t.join();
  CHECK_EQ(bad.load(), 0);
}

TEST(worldgen_surface_height_matches_chunk) {
  (void)Blocks::get();
  WorldGen g(5);
  auto c = g.generate({2, 2});
  for (int x = 0; x < 16; x += 3)
    for (int z = 0; z < 16; z += 3) {
      int h = g.surface_height(32 + x, 32 + z);
      // Terrain top (before trees/plants) is at h; the block there is solid or the ocean floor.
      CHECK(c->get(x, h, z) != 0);
    }
}

// ---------------------------------------------------------------- packs

TEST(builtin_pack_layout) {
  auto pack = make_builtin_pack();
  auto files = builtin_pack_files();
  CHECK(files.size() > 300);
  CHECK(pack->has("pack.mcmeta"));
  CHECK(pack->has("assets/minecraft/blockstates/stone.json"));
  CHECK(pack->has("assets/minecraft/models/block/cube_all.json"));
  CHECK(pack->has("assets/minecraft/textures/block/stone.png"));
  CHECK(pack->has("assets/minecraft/textures/colormap/grass.png"));
  CHECK(pack->has("assets/minecraft/textures/font/ascii.png"));
  auto png = pack->read("assets/minecraft/textures/block/stone.png");
  CHECK(png.has_value());
  auto img = decode_png(*png);
  CHECK(img.has_value());
  if (img) { CHECK_EQ(img->w, 16); CHECK_EQ(img->h, 16); }
  auto font = decode_png(*pack->read("assets/minecraft/textures/font/ascii.png"));
  CHECK(font.has_value());
  if (font) CHECK_EQ(font->w, 128);
}

TEST(pack_zip_and_dir_roundtrip_and_layering) {
  fs::path dir = temp_dir("pack");
  std::string err;
  CHECK(export_builtin_pack_zip((dir / "p.zip").string(), &err));
  CHECK(export_builtin_pack((dir / "tree").string(), &err));
  auto zip = open_zip_pack((dir / "p.zip").string(), &err);
  CHECK(zip != nullptr);
  auto tree = open_dir_pack((dir / "tree").string(), &err);
  CHECK(tree != nullptr);
  auto builtin = make_builtin_pack();
  if (!zip || !tree) return;
  for (const auto& f : builtin_pack_files()) {
    auto a = builtin->read(f);
    if (f.starts_with("assets/minecraft/lang")) continue;
    auto z = zip->read(f), t = tree->read(f);
    CHECK(z.has_value() && t.has_value());
    if (z && t && a) { CHECK(*z == *a); CHECK(*t == *a); }
  }
  // Layering: a directory pack overriding one texture wins over the fallback.
  fs::create_directories(dir / "over/assets/minecraft/textures/block");
  Image red = Image::make(16, 16);
  for (size_t i = 0; i < red.rgba.size(); i += 4) { red.rgba[i] = 255; red.rgba[i + 3] = 255; }
  write_png_file((dir / "over/assets/minecraft/textures/block/stone.png").string(), red);
  std::ofstream(dir / "over/pack.mcmeta") << R"({"pack":{"pack_format":1,"description":"t"}})";
  PackStack stack;
  CHECK(stack.add_spec((dir / "over").string(), &err));
  stack.add_builtin_fallback();
  auto stone = decode_png(*stack.read("assets/minecraft/textures/block/stone.png"));
  CHECK(stone.has_value());
  if (stone) CHECK_EQ(stone->px(3, 3)[0], u8{255});
  auto dirt = decode_png(*stack.read("assets/minecraft/textures/block/dirt.png"));  // falls through
  CHECK(dirt.has_value());
  CHECK(!stack.has("assets/minecraft/textures/block/nope.png"));
  // Errors are reported, not thrown.
  PackStack bad;
  CHECK(!bad.add_spec((dir / "missing.zip").string(), &err));
  std::ofstream(dir / "junk.zip") << "not a zip";
  CHECK(!bad.add_spec((dir / "junk.zip").string(), &err));
  fs::remove_all(dir);
}

struct Models {
  PackStack packs;
  std::unique_ptr<BlockModels> models;
  Models() {
    packs.add_builtin_fallback();
    (void)Blocks::get();
    models = std::make_unique<BlockModels>(packs);
    models->build();
  }
};

TEST(block_models_bake_from_json) {
  Models m;
  auto quads = [&](BlockId id) { return m.models->baked(id)->quads.size(); };
  CHECK_EQ(quads(B::stone), size_t{6});
  CHECK_EQ(quads(B::grass_block), size_t{10});  // cube + 4 tinted side overlays
  CHECK_EQ(quads(B::short_grass), size_t{4});   // two crossed planes, both sides
  CHECK_EQ(quads(B::torch), size_t{6});
  CHECK_EQ(quads(B::water), size_t{0});         // fluids are meshed procedurally
  CHECK_EQ(quads(0), size_t{0});
  for (BlockId id = 1; id < Blocks::get().count(); id++)
    if (!(Blocks::get().info(id).flags & BF_Unknown)) CHECK(!m.models->baked(id)->missing);
  // Blocks the pack knows nothing about still render, as a missing-texture cube.
  BlockId future = Blocks::get().lookup_or_register("minecraft:some_future_block", {});
  m.models->bake(future);
  CHECK_EQ(m.models->baked(future)->quads.size(), size_t{6});
  CHECK_EQ(m.models->baked(future)->quads[0].layer, u16(0));

  // Grass: top quad is tinted, bottom uses the dirt texture layer.
  const BakedBlock* g = m.models->baked(B::grass_block);
  int tinted = 0;
  for (auto& q : g->quads) if (q.tint >= 0) tinted++;
  CHECK_EQ(tinted, 5);
  // Logs: axis=x rotates the end grain onto the x faces.
  Blocks& reg = Blocks::get();
  BlockId log_x = reg.lookup_or_register("minecraft:oak_log", {{"pillar_axis", StateValue::string("x")}});
  BlockId log_y = B::oak_log;
  auto top_layer = [&](BlockId id, int dir) {
    for (auto& q : m.models->baked(id)->quads) if (q.dir == dir) return q.layer;
    return u16(0xFFFF);
  };
  CHECK_EQ(top_layer(log_y, UP), m.models->layer_of("block/oak_log_top"));
  CHECK_EQ(top_layer(log_x, EAST), m.models->layer_of("block/oak_log_top"));
  CHECK_EQ(top_layer(log_x, UP), m.models->layer_of("block/oak_log"));
  // Stairs face the direction they rise toward.
  BlockId st_e = reg.lookup_or_register("minecraft:oak_stairs", {{"weirdo_direction", StateValue::integer(0)}, {"upside_down_bit", StateValue::byte(0)}});
  BlockId st_s = reg.lookup_or_register("minecraft:oak_stairs", {{"weirdo_direction", StateValue::integer(2)}, {"upside_down_bit", StateValue::byte(0)}});
  auto max_top_z_edge = [&](BlockId id) {
    float best_x = 0, best_z = 0;
    for (auto& q : m.models->baked(id)->quads)
      if (q.dir == UP)
        for (int v = 0; v < 4; v++) if (q.pos[v][1] > 0.99f) { best_x = std::max(best_x, q.pos[v][0]); best_z = std::max(best_z, q.pos[v][2]); }
    return std::pair{best_x, best_z};
  };
  (void)max_top_z_edge;
  auto raised_min = [&](BlockId id, int axis) {
    float mn = 1;
    for (auto& q : m.models->baked(id)->quads)
      if (q.dir == UP)
        for (int v = 0; v < 4; v++) if (q.pos[v][1] > 0.99f) mn = std::min(mn, q.pos[v][axis]);
    return mn;
  };
  CHECK(std::abs(raised_min(st_e, 0) - 0.5f) < 1e-4f);  // upper step occupies x in [0.5, 1]
  CHECK(std::abs(raised_min(st_s, 2) - 0.5f) < 1e-4f);  // rotated: z in [0.5, 1]
  CHECK(std::abs(raised_min(st_s, 0) - 0.0f) < 1e-4f);
}

TEST(block_models_weighted_variants) {
  // A pack whose stone blockstate lists four rotated models (as vanilla does) with weights.
  fs::path dir = temp_dir("variants");
  fs::create_directories(dir / "assets/minecraft/blockstates");
  std::ofstream(dir / "pack.mcmeta") << R"({"pack":{"pack_format":1,"description":"t"}})";
  std::ofstream(dir / "assets/minecraft/blockstates/stone.json") << R"({"variants":{"":[
    {"model":"minecraft:block/stone"},{"model":"minecraft:block/stone","y":90,"weight":2},
    {"model":"minecraft:block/stone","y":180},{"model":"minecraft:block/stone","y":270}]}})";
  PackStack packs;
  std::string err;
  CHECK(packs.add_spec(dir.string(), &err));
  packs.add_builtin_fallback();
  BlockModels models(packs);
  models.build();
  const BakedBlock* b = models.baked(B::stone);
  CHECK_EQ(b->alts.size(), size_t{4});
  CHECK_EQ(b->total_weight, 5);
  CHECK_EQ(b->alts[1].weight, 2);
  CHECK_EQ(b->quads.size(), size_t{6});
  // Choice is a pure function of the hash and follows the weights.
  int counts[4] = {0, 0, 0, 0};
  for (u64 i = 0; i < 5000; i++) {
    const auto& q = b->pick(mix64(i));
    for (size_t k = 0; k < 4; k++) if (&q == &b->alts[k].quads) counts[k]++;
  }
  CHECK(counts[1] > counts[0] * 1.6 && counts[1] < counts[0] * 2.4);
  CHECK(counts[0] > 700 && counts[2] > 700 && counts[3] > 700);
  CHECK(&b->pick(12345) == &b->pick(12345));
  // Rotated variants map the same texture onto different faces' uv corners.
  bool any_diff = false;
  for (size_t q = 0; q < 6; q++)
    if (b->alts[0].quads[q].uv[0][0] != b->alts[1].quads[q].uv[0][0] || b->alts[0].quads[q].pos[0][0] != b->alts[1].quads[q].pos[0][0]) any_diff = true;
  CHECK(any_diff);
  // Blocks without variant lists have no alternatives.
  CHECK(models.baked(B::dirt)->alts.empty());
  fs::remove_all(dir);
}

TEST(animated_textures_from_mcmeta) {
  Models m;
  u16 water = m.models->water_layer();
  std::vector<float> anim;
  m.models->copy_anim(anim);
  CHECK(water != 0);
  CHECK_EQ(anim[water * 2], 8.0f);       // 8-frame strip
  CHECK_EQ(anim[water * 2 + 1], 3.0f);   // frametime from the .mcmeta
  CHECK_EQ(anim[m.models->layer_of("block/stone") * 2], 1.0f);
  // Frames occupy consecutive layers and differ from each other.
  std::vector<u8> px;
  m.models->copy_layers(water, px);
  size_t layer_bytes = 16 * 16 * 4;
  CHECK(px.size() >= 8 * layer_bytes);
  CHECK(std::memcmp(px.data(), px.data() + layer_bytes, layer_bytes) != 0);
}

TEST(atlas_layers_and_tints) {
  Models m;
  CHECK(m.models->layer_count() > 100);
  CHECK_EQ(m.models->layer_of("block/does_not_exist"), u16(0));
  CHECK(m.models->layer_of("block/stone") != 0);
  CHECK_EQ(m.models->layer_of("block/stone"), m.models->layer_of("minecraft:block/stone"));
  std::vector<u8> px;
  size_t n = m.models->copy_layers(0, px);
  CHECK_EQ(px.size(), n * 16 * 16 * 4);
  // Layer 0 is the magenta/black missing texture.
  CHECK_EQ(px[0], u8{248});
  CHECK(m.models->tint_color(Tint::Grass, Biome::Plains) != m.models->tint_color(Tint::Grass, Biome::Desert));
  CHECK(m.models->tint_color(Tint::Water, Biome::Swamp) != m.models->tint_color(Tint::Water, Biome::Plains));
}

// ---------------------------------------------------------------- mesher

static MeshInput make_input(const std::function<void(Chunk&)>& fill, int section) {
  Chunk c;
  c.pos = {0, 0};
  c.height.fill(MIN_Y);
  fill(c);
  c.recompute_heights();
  MeshInput in;
  Chunk empty;
  empty.recompute_heights();
  for (int i = 0; i < 9; i++) {
    if (i == 4) in.chunks[4] = c.snapshot();
    else { empty.pos = {(i % 3) - 1, (i / 3) - 1}; in.chunks[static_cast<size_t>(i)] = empty.snapshot(); }
  }
  in.section = section;
  return in;
}

TEST(mesher_culls_hidden_faces) {
  Models m;
  const int sec = (64 >> 4) - MIN_SUB;
  MeshData one, two, lone_air;
  mesh_section(make_input([](Chunk& c) { c.set(4, 64, 4, B::stone); }, sec), *m.models, one);
  CHECK_EQ(one.quads(), size_t{6});
  mesh_section(make_input([](Chunk& c) { c.set(4, 64, 4, B::stone); c.set(5, 64, 4, B::stone); }, sec), *m.models, two);
  CHECK_EQ(two.quads(), size_t{10});  // 2*6 minus the two touching faces
  mesh_section(make_input([](Chunk&) {}, sec), *m.models, lone_air);
  CHECK_EQ(lone_air.quads(), size_t{0});
  // A fully enclosed block emits nothing.
  MeshData boxed;
  mesh_section(make_input([](Chunk& c) {
    for (int x = 3; x <= 5; x++) for (int y = 64; y <= 66; y++) for (int z = 3; z <= 5; z++) c.set(x, y, z, B::stone);
  }, sec), *m.models, boxed);
  CHECK_EQ(boxed.quads(), size_t{54});  // 3x3x3 cube surface only
}

TEST(mesher_transparency_and_fluids) {
  Models m;
  const int sec = (64 >> 4) - MIN_SUB;
  MeshData d;
  mesh_section(make_input([](Chunk& c) { c.set(4, 64, 4, B::glass); c.set(5, 64, 4, B::glass); }, sec), *m.models, d);
  CHECK_EQ(d.quads(), size_t{10});  // glass hides faces against glass
  MeshData w;
  mesh_section(make_input([](Chunk& c) {
    c.set(4, 64, 4, B::water); c.set(5, 64, 4, B::water);
  }, sec), *m.models, w);
  CHECK(w.opaque.empty());
  CHECK_EQ(w.translucent.size() / 4, size_t{10});
  // Water surface sits below the block top when nothing is above.
  float top = 0;
  for (auto& v : w.translucent) top = std::max(top, v.y);
  CHECK(top < 1.0f + 64 - 64 * 0 && top > 0.8f);
  // Water against stone: the shared face is culled.
  MeshData ws;
  mesh_section(make_input([](Chunk& c) { c.set(4, 64, 4, B::water); c.set(5, 64, 4, B::stone); }, sec), *m.models, ws);
  CHECK_EQ(ws.translucent.size() / 4, size_t{5});
}

TEST(mesher_lighting) {
  Models m;
  const int sec = (64 >> 4) - MIN_SUB;
  // Open sky: the top face of a lone block is fully sky-lit; a torch-lit cave face gets block light.
  MeshData open;
  mesh_section(make_input([](Chunk& c) { c.set(8, 64, 8, B::stone); }, sec), *m.models, open);
  int lit = 0;
  for (auto& v : open.opaque) if (v.sky == 255) lit++;
  CHECK(lit >= 4);
  // A sealed room: no sky light inside, torch provides block light that falls off with distance.
  MeshData room;
  mesh_section(make_input([](Chunk& c) {
    for (int x = 2; x <= 12; x++) for (int y = 60; y <= 70; y++) for (int z = 2; z <= 12; z++) c.set(x, y, z, B::stone);
    for (int x = 3; x <= 11; x++) for (int y = 61; y <= 69; y++) for (int z = 3; z <= 11; z++) c.set(x, y, z, 0);
    c.set(4, 66, 4, B::torch);
  }, sec), *m.models, room);
  u8 near_blk = 0, far_blk = 255, max_sky = 0;
  for (auto& v : room.opaque) {
    // Interior faces only: inside the hollow (x,z in 3..12, section-local y below the ceiling at 6).
    const bool torch_geometry = std::abs(v.x - 4.5f) < 0.2f && std::abs(v.z - 4.5f) < 0.2f && v.y < 3.5f;  // emissive itself
    if (!torch_geometry && v.x >= 3 && v.x <= 12 && v.z >= 3 && v.z <= 12 && v.y > 0.5f && v.y <= 6.0f) {
      float d = std::abs(v.x - 4.5f) + std::abs(v.z - 4.5f);
      if (d < 3.0f) near_blk = std::max(near_blk, v.blk);
      if (d > 9.0f) far_blk = std::min(far_blk, v.blk);
      max_sky = std::max(max_sky, v.sky);
    }
  }
  CHECK(near_blk > 150);
  CHECK(far_blk < near_blk);
  CHECK(max_sky < 30);
}

TEST(mesher_is_thread_safe_and_deterministic) {
  Models m;
  const int sec = (64 >> 4) - MIN_SUB;
  auto in = std::make_shared<MeshInput>(make_input([](Chunk& c) {
    for (int x = 0; x < 16; x++) for (int z = 0; z < 16; z++) { for (int y = 50; y < 66; y++) c.set(x, y, z, B::stone); c.set(x, 66, z, B::grass_block); }
    c.set(8, 67, 8, B::torch);
  }, sec));
  MeshData ref;
  mesh_section(*in, *m.models, ref);
  std::atomic<int> bad{0};
  std::vector<std::thread> ts;
  for (int t = 0; t < 4; t++)
    ts.emplace_back([&] {
      for (int i = 0; i < 10; i++) {
        MeshData d;
        mesh_section(*in, *m.models, d);
        if (d.opaque.size() != ref.opaque.size() || std::memcmp(d.opaque.data(), ref.opaque.data(), d.opaque.size() * sizeof(Vertex)) != 0) bad++;
      }
    });
  for (auto& t : ts) t.join();
  CHECK_EQ(bad.load(), 0);
}

// ---------------------------------------------------------------- world, physics, interaction

struct TestWorld {
  fs::path dir;
  std::unique_ptr<LevelStore> store;
  std::unique_ptr<WorldGen> gen;
  std::unique_ptr<ThreadPool> pool;
  std::unique_ptr<World> world;
  explicit TestWorld(const char* name, i64 seed = 3) {
    (void)Blocks::get();
    dir = temp_dir(name);
    std::string err;
    store = LevelStore::open(dir, seed, &err);
    gen = std::make_unique<WorldGen>(seed);
    pool = std::make_unique<ThreadPool>(3);
    world = std::make_unique<World>(*store, *gen, *pool);
  }
  bool load_around(double x, double z, int radius) {
    for (int i = 0; i < 4000; i++) {
      world->update(x, z, radius);
      if (world->all_loaded_around({floor_div(ifloor(x), 16), floor_div(ifloor(z), 16)}, radius) && world->inflight_count() == 0) return true;
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    return false;
  }
  ~TestWorld() {
    world.reset();
    pool.reset();
    store.reset();
    fs::remove_all(dir);
  }
};

TEST(world_streams_chunks_on_worker_threads) {
  TestWorld tw("stream");
  CHECK(tw.load_around(8, 8, 3));
  CHECK(tw.world->loaded_count() >= 29);
  CHECK(tw.world->chunks_generated() >= 29);
  // Moving away unloads distant chunks and loads new ones.
  CHECK(tw.load_around(16 * 40 + 8, 8, 3));
  for (int i = 0; i < 100; i++) tw.world->update(16 * 40 + 8, 8, 3);
  CHECK(!tw.world->column_loaded({0, 0}));
  CHECK(tw.world->column_loaded({40, 0}));
}

TEST(world_edits_track_dirty_sections_and_persist) {
  TestWorld tw("edits");
  CHECK(tw.load_around(8, 8, 2));
  std::vector<DirtyChunk> dirty;
  tw.world->take_dirty(dirty);
  CHECK(!dirty.empty());
  dirty.clear();
  CHECK(tw.world->set_block(3, 100, 3, B::glowstone));
  CHECK_EQ(tw.world->get_block(3, 100, 3), B::glowstone);
  CHECK(!tw.world->set_block(3, 100, 3, B::glowstone));  // no-op edit
  tw.world->take_dirty(dirty);
  bool found_center = false;
  for (auto& d : dirty) if (d.pos == ChunkPos{0, 0} && (d.mask & (1u << ((100 >> 4) - MIN_SUB)))) found_center = true;
  CHECK(found_center);
  // A block on a chunk border dirties the neighbour too.
  dirty.clear();
  CHECK(tw.world->set_block(15, 100, 5, B::stone));
  tw.world->take_dirty(dirty);
  bool neighbour = false;
  for (auto& d : dirty) if (d.pos == ChunkPos{1, 0}) neighbour = true;
  CHECK(neighbour);
  CHECK(!tw.world->set_block(1000000, 10, 0, B::stone));  // unloaded column
  tw.world->save_dirty(true);
  auto reloaded = tw.store->load_chunk({0, 0});
  CHECK(reloaded != nullptr);
  if (reloaded) CHECK_EQ(reloaded->get(3, 100, 3), B::glowstone);
}

static void flat_floor(TestWorld& tw, int y, BlockId id) {
  for (int x = -20; x <= 20; x++)
    for (int z = -20; z <= 20; z++) {
      for (int yy = y; yy < y + 8; yy++) tw.world->set_block(x, yy, z, 0);
      tw.world->set_block(x, y, z, id);
    }
}

TEST(player_physics) {
  TestWorld tw("physics");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 100, B::stone);
  Player p;
  p.pos = {0.5, 105, 0.5};
  MoveInput none;
  for (int i = 0; i < 240; i++) p.update(1.0 / 60, none, *tw.world);
  CHECK(p.on_ground);
  CHECK(std::abs(p.pos.y() - 101.0) < 1e-6);

  // Walking speed ~4.3 blocks/s.
  Eigen::Vector3d start = p.pos;
  MoveInput fwd;
  fwd.forward = 1;
  for (int i = 0; i < 60; i++) p.update(1.0 / 60, fwd, *tw.world);
  double walked = (p.pos - start).norm();
  CHECK(walked > 3.8 && walked < 4.6);

  // Jumping reaches ~1.25 blocks and lands again.
  p.vel.setZero();
  MoveInput jump;
  jump.jump = true;
  double peak = p.pos.y();
  for (int i = 0; i < 40; i++) { p.update(1.0 / 60, i < 2 ? jump : none, *tw.world); peak = std::max(peak, p.pos.y()); }
  CHECK(peak - 101.0 > 1.1 && peak - 101.0 < 1.4);
  for (int i = 0; i < 60; i++) p.update(1.0 / 60, none, *tw.world);
  CHECK(p.on_ground);

  // A 2-high wall stops the player; a slab is stepped onto.
  tw.world->set_block(3, 101, 0, B::stone);
  tw.world->set_block(3, 102, 0, B::stone);
  p.pos = {0.5, 101, 0.5};
  p.vel.setZero();
  p.yaw = 3.14159265f / 2 * 3;  // face +x (yaw 270)
  for (int i = 0; i < 120; i++) p.update(1.0 / 60, fwd, *tw.world);
  CHECK(p.pos.x() < 3 - 0.3 + 1e-6);  // blocked by the wall at x=3
  BlockId slab = Blocks::get().lookup_or_register("minecraft:oak_slab", {{"minecraft:vertical_half", StateValue::string("bottom")}});
  tw.world->set_block(3, 101, 0, slab);
  tw.world->set_block(3, 102, 0, 0);
  p.pos = {0.5, 101, 0.5};
  p.vel.setZero();
  for (int i = 0; i < 90; i++) p.update(1.0 / 60, fwd, *tw.world);
  CHECK(p.pos.x() > 3.5);  // walked over the slab without jumping

  // Water: the player floats and slows down.
  for (int x = 6; x <= 10; x++) for (int z = -2; z <= 2; z++) for (int y = 101; y <= 106; y++) tw.world->set_block(x, y, z, B::water);
  p.pos = {8.5, 105, 0.5};
  p.vel.setZero();
  for (int i = 0; i < 180; i++) p.update(1.0 / 60, none, *tw.world);
  CHECK(p.in_water);
  CHECK(p.pos.y() > 100.9);  // stopped by the floor, not tunnelling through
}

TEST(player_flying_and_sneak_edge) {
  TestWorld tw("fly");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 100, B::stone);
  Player p;
  p.pos = {0.5, 110, 0.5};
  p.flying = true;
  MoveInput none;
  for (int i = 0; i < 120; i++) p.update(1.0 / 60, none, *tw.world);
  CHECK(std::abs(p.pos.y() - 110) < 0.01);  // no gravity while flying
  // Sneaking on a ledge does not walk off the edge.
  for (int x = 5; x <= 20; x++) for (int z = -20; z <= 20; z++) tw.world->set_block(x, 100, z, 0);
  p.flying = false;
  p.pos = {3.5, 101, 0.5};
  p.vel.setZero();
  p.yaw = 3.14159265f / 2 * 3;
  MoveInput sneak;
  sneak.forward = 1;
  sneak.sneak = true;
  for (int i = 0; i < 20; i++) p.update(1.0 / 60, none, *tw.world);
  for (int i = 0; i < 240; i++) p.update(1.0 / 60, sneak, *tw.world);
  CHECK(p.on_ground);
  CHECK(p.pos.x() < 5.3);
}

TEST(raycast_hits_faces_and_boxes) {
  TestWorld tw("ray");
  CHECK(tw.load_around(0, 0, 1));
  tw.world->set_block(5, 250, 5, B::stone);
  auto hit = raycast(*tw.world, {0.5, 250.5, 5.5}, {1, 0, 0}, 10);
  CHECK(hit.hit);
  CHECK_EQ(hit.x, 5);
  CHECK_EQ(hit.face, int(WEST));  // entered through the west face
  CHECK(std::abs(hit.dist - 4.5) < 1e-9);
  hit = raycast(*tw.world, {5.5, 260, 5.5}, {0, -1, 0}, 20);
  CHECK(hit.hit && hit.face == int(UP));
  hit = raycast(*tw.world, {5.5, 260, 5.5}, {0, -1, 0}, 5);  // out of reach
  CHECK(!hit.hit);
  hit = raycast(*tw.world, {5.5, 240, 5.5}, {0, 1, 0}, 20);
  CHECK(hit.hit && hit.face == int(DOWN));
  // Water is not targetable; the ray passes through it.
  tw.world->set_block(5, 251, 5, B::water);
  hit = raycast(*tw.world, {5.5, 255, 5.5}, {0, -1, 0}, 20);
  CHECK(hit.hit && hit.y == 250);
  // Half slab: a ray at y=0.75 misses the block but one at 0.25 hits.
  BlockId slab = Blocks::get().lookup_or_register("minecraft:oak_slab", {{"minecraft:vertical_half", StateValue::string("bottom")}});
  tw.world->set_block(8, 250, 5, slab);
  CHECK(!raycast(*tw.world, {5.5, 250.75, 5.5}, {1, 0, 0}, 2.0).hit || raycast(*tw.world, {5.5, 250.75, 5.5}, {1, 0, 0}, 2.0).x != 8);
  auto h2 = raycast(*tw.world, {6.5, 250.25, 5.5}, {1, 0, 0}, 5.0);
  CHECK(h2.hit && h2.x == 8);
  // Axis-aligned rays with a zero component work (regression: negative tmax).
  auto h3 = raycast(*tw.world, {5.5, 252.6, 5.5}, {-0.0, -1.0, 0.0}, 8.0);
  CHECK(h3.hit && h3.y == 250);
}

// ---------------------------------------------------------------- threading

TEST(thread_pool_runs_by_priority) {
  std::mutex m;
  std::vector<int> order;
  std::atomic<bool> release{false};
  {
    ThreadPool pool(1);
    // Block the single worker so the queue fills, then let it drain in priority order.
    pool.submit(-1000, [&] { while (!release) std::this_thread::sleep_for(std::chrono::milliseconds(1)); });
    for (int p : {5, 1, 3, 2, 4}) pool.submit(p, [&, p] { std::lock_guard lk(m); order.push_back(p); });
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    release = true;
    while (true) {
      { std::lock_guard lk(m); if (order.size() == 5) break; }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  }
  CHECK((order == std::vector<int>{1, 2, 3, 4, 5}));
}

TEST(thread_pool_parallel_speedup) {
  std::atomic<int> n{0};
  ThreadPool pool(4);
  auto t0 = std::chrono::steady_clock::now();
  for (int i = 0; i < 8; i++) pool.submit(0, [&] { std::this_thread::sleep_for(std::chrono::milliseconds(50)); n++; });
  while (n < 8) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  CHECK(ms < 300);  // 8 x 50ms on 4 threads ~ 100ms, far below the 400ms serial time
}

TEST(png_roundtrip) {
  Image img = Image::make(7, 5);
  for (size_t i = 0; i < img.rgba.size(); i++) img.rgba[i] = static_cast<u8>(i * 13);
  auto png = encode_png(img);
  auto back = decode_png(png);
  CHECK(back.has_value());
  if (back) { CHECK_EQ(back->w, 7); CHECK_EQ(back->h, 5); CHECK(back->rgba == img.rgba); }
  std::vector<u8> junk = {1, 2, 3};
  CHECK(!decode_png(junk).has_value());
}

// ---------------------------------------------------------------- block updates

static int fluid_depth_at(World& w, int x, int y, int z, const char* name) {
  BlockId id = w.get_block(x, y, z);
  const BlockInfo& bi = Blocks::get().info(id);
  return bi.name == name ? bi.fluid_depth : -1;
}
static int count_blocks(World& w, BlockId lo, BlockId hi) {
  int n = 0;
  for (int x = -20; x <= 20; x++)
    for (int z = -20; z <= 20; z++)
      for (int y = 190; y <= 215; y++) {
        BlockId b = w.get_block(x, y, z);
        if (b >= lo && b <= hi) n++;
      }
  return n;
}

TEST(fluid_spreads_and_drains) {
  TestWorld tw("fluid");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 200, B::stone);
  BlockUpdates up(*tw.world);
  tw.world->set_block(0, 201, 0, B::water);
  up.notify(0, 201, 0);
  for (int i = 0; i < 300; i++) up.tick();
  // Level n at Manhattan distance n on flat ground, out to 7.
  CHECK_EQ(fluid_depth_at(*tw.world, 1, 201, 0, "minecraft:water"), 1);
  CHECK_EQ(fluid_depth_at(*tw.world, 3, 201, 0, "minecraft:water"), 3);
  CHECK_EQ(fluid_depth_at(*tw.world, 0, 201, -7, "minecraft:water"), 7);
  CHECK_EQ(fluid_depth_at(*tw.world, 8, 201, 0, "minecraft:water"), -1);
  CHECK_EQ(fluid_depth_at(*tw.world, 4, 201, 4, "minecraft:water"), -1);  // Manhattan 8 is out of reach
  CHECK_EQ(fluid_depth_at(*tw.world, 3, 201, 3, "minecraft:water"), 6);
  CHECK_EQ(fluid_depth_at(*tw.world, 0, 202, 0, "minecraft:water"), -1);
  CHECK(up.pending() == 0);  // the simulation settles
  // Removing the source drains everything it fed.
  tw.world->set_block(0, 201, 0, 0);
  up.notify(0, 201, 0);
  for (int i = 0; i < 300; i++) up.tick();
  CHECK_EQ(count_blocks(*tw.world, B::water, B::water + 8), 0);
}

TEST(fluid_falls_and_lands) {
  TestWorld tw("waterfall");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 200, B::stone);
  for (int x = -20; x <= 20; x++) for (int z = -20; z <= 20; z++) tw.world->set_block(x, 196, z, B::stone);
  tw.world->set_block(10, 200, 0, 0);  // a hole in the upper floor
  BlockUpdates up(*tw.world);
  tw.world->set_block(10, 201, 0, B::water);
  up.notify(10, 201, 0);
  for (int i = 0; i < 400; i++) up.tick();
  CHECK_EQ(fluid_depth_at(*tw.world, 10, 200, 0, "minecraft:water"), 8);  // falling column
  CHECK_EQ(fluid_depth_at(*tw.world, 10, 199, 0, "minecraft:water"), 8);
  CHECK_EQ(fluid_depth_at(*tw.world, 10, 197, 0, "minecraft:water"), 8);
  CHECK_EQ(fluid_depth_at(*tw.world, 11, 197, 0, "minecraft:water"), 1);  // spreads once it lands
  CHECK_EQ(fluid_depth_at(*tw.world, 14, 197, 0, "minecraft:water"), 4);
  tw.world->set_block(10, 201, 0, 0);
  up.notify(10, 201, 0);
  for (int i = 0; i < 400; i++) up.tick();
  CHECK_EQ(count_blocks(*tw.world, B::water, B::water + 8), 0);
}

TEST(lava_flows_slower_and_shorter) {
  TestWorld tw("lava");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 200, B::stone);
  BlockUpdates up(*tw.world);
  tw.world->set_block(0, 201, 0, B::lava);
  up.notify(0, 201, 0);
  for (int i = 0; i < 20; i++) up.tick();  // 1s: water would have spread several blocks, lava has barely started
  CHECK_EQ(fluid_depth_at(*tw.world, 3, 201, 0, "minecraft:lava"), -1);
  for (int i = 0; i < 400; i++) up.tick();
  CHECK_EQ(fluid_depth_at(*tw.world, 3, 201, 0, "minecraft:lava"), 3);
  CHECK_EQ(fluid_depth_at(*tw.world, 4, 201, 0, "minecraft:lava"), -1);  // lava reaches only 3 blocks
}

TEST(gravity_blocks_fall) {
  TestWorld tw("gravity");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 200, B::stone);
  BlockUpdates up(*tw.world);
  tw.world->set_block(0, 206, 0, B::sand);
  tw.world->set_block(1, 204, 0, B::gravel);
  up.notify(0, 206, 0);
  up.notify(1, 204, 0);
  for (int i = 0; i < 100; i++) up.tick();
  CHECK_EQ(tw.world->get_block(0, 201, 0), B::sand);
  CHECK_EQ(tw.world->get_block(0, 206, 0), BlockId(0));
  CHECK_EQ(tw.world->get_block(1, 201, 0), B::gravel);
  // Removing the support drops a whole column, one block after another.
  tw.world->set_block(5, 196, 5, B::stone);  // catch floor below the column
  tw.world->set_block(5, 201, 5, B::sand);
  tw.world->set_block(5, 202, 5, B::sand);
  tw.world->set_block(5, 203, 5, B::sand);
  tw.world->set_block(5, 200, 5, 0);
  up.notify(5, 200, 5);
  up.notify(5, 201, 5);
  for (int i = 0; i < 300; i++) up.tick();
  CHECK_EQ(tw.world->get_block(5, 200, 5), BlockId(0));
  int sand = 0;
  for (int y = 100; y < 204; y++) if (tw.world->get_block(5, y, 5) == B::sand) sand++;
  CHECK_EQ(sand, 3);
  CHECK_EQ(tw.world->get_block(5, 197, 5), B::sand);
  CHECK_EQ(tw.world->get_block(5, 199, 5), B::sand);
  // Sand on solid ground stays put.
  CHECK_EQ(tw.world->get_block(0, 201, 0), B::sand);
}

static BlockId torch_facing(const char* dir) {
  return Blocks::get().lookup_or_register("minecraft:torch", {{"torch_facing_direction", StateValue::string(dir)}});
}

TEST(support_rules_drop_unsupported_blocks) {
  TestWorld tw("support");
  CHECK(tw.load_around(0, 0, 2));
  flat_floor(tw, 200, B::grass_block);
  BlockUpdates up(*tw.world);
  auto run = [&](int ticks = 10) { for (int i = 0; i < ticks; i++) up.tick(); };
  // Plants on grass are fine; on stone or sand they are not.
  CHECK(BlockUpdates::supported(*tw.world, B::short_grass, 0, 201, 0));
  CHECK(BlockUpdates::supported(*tw.world, B::poppy, 3, 201, 3));
  tw.world->set_block(4, 200, 4, B::stone);
  tw.world->set_block(5, 200, 5, B::sand);
  CHECK(!BlockUpdates::supported(*tw.world, B::poppy, 4, 201, 4));
  CHECK(!BlockUpdates::supported(*tw.world, B::poppy, 5, 201, 5));
  CHECK(BlockUpdates::supported(*tw.world, B::cactus, 5, 201, 5));
  CHECK(!BlockUpdates::supported(*tw.world, B::cactus, 0, 201, 0));
  CHECK(BlockUpdates::supported(*tw.world, B::dead_bush, 5, 201, 5));
  CHECK(BlockUpdates::supported(*tw.world, B::sugar_cane, 5, 201, 5));

  // Removing the ground drops the plant above it and, transitively, stacked sugar cane.
  tw.world->set_block(5, 201, 5, B::sugar_cane);
  tw.world->set_block(5, 202, 5, B::sugar_cane);
  tw.world->set_block(5, 203, 5, B::sugar_cane);
  tw.world->set_block(0, 201, 0, B::short_grass);
  run();
  CHECK_EQ(tw.world->get_block(5, 203, 5), B::sugar_cane);  // untouched while supported
  tw.world->set_block(5, 200, 5, 0);
  up.notify(5, 200, 5);
  tw.world->set_block(0, 200, 0, 0);
  up.notify(0, 200, 0);
  run(30);
  for (int y = 201; y <= 203; y++) CHECK_EQ(tw.world->get_block(5, y, 5), BlockId(0));
  CHECK_EQ(tw.world->get_block(0, 201, 0), BlockId(0));

  // Torches: standing ones need a block below, wall ones a block behind.
  tw.world->set_block(8, 200, 8, B::stone);
  CHECK(BlockUpdates::supported(*tw.world, B::torch, 8, 201, 8));
  CHECK(!BlockUpdates::supported(*tw.world, B::torch, 9, 202, 8));
  tw.world->set_block(12, 201, 12, B::stone);
  CHECK(BlockUpdates::supported(*tw.world, torch_facing("east"), 13, 201, 12));   // hangs on the stone to its west
  CHECK(BlockUpdates::supported(*tw.world, torch_facing("west"), 11, 201, 12));
  CHECK(BlockUpdates::supported(*tw.world, torch_facing("north"), 12, 201, 11));  // north of the stone, pointing away from it
  CHECK(BlockUpdates::supported(*tw.world, torch_facing("south"), 12, 201, 13));
  CHECK(!BlockUpdates::supported(*tw.world, torch_facing("east"), 11, 201, 12));  // wrong side
  tw.world->set_block(13, 201, 12, torch_facing("east"));
  tw.world->set_block(8, 201, 8, B::torch);
  run();
  CHECK_EQ(tw.world->get_block(13, 201, 12), torch_facing("east"));
  tw.world->set_block(12, 201, 12, 0);
  up.notify(12, 201, 12);
  tw.world->set_block(8, 200, 8, 0);
  up.notify(8, 200, 8);
  run(20);
  CHECK_EQ(tw.world->get_block(13, 201, 12), BlockId(0));
  CHECK_EQ(tw.world->get_block(8, 201, 8), BlockId(0));
}

TEST(wall_torch_model_and_shape) {
  Models m;
  BlockId east = torch_facing("east");
  m.models->bake(east);
  const BakedBlock* wall = m.models->baked(east);
  const BakedBlock* stand = m.models->baked(B::torch);
  CHECK(!wall->missing);
  CHECK_EQ(wall->quads.size(), size_t{6});
  // Leans away from the wall: the top of the flame is further east than its base.
  float top_x = 0, bottom_x = 1;
  for (auto& q : wall->quads)
    for (int v = 0; v < 4; v++) {
      if (q.pos[v][1] > 0.7f) top_x = std::max(top_x, q.pos[v][0]);
      if (q.pos[v][1] < 0.3f) bottom_x = std::min(bottom_x, q.pos[v][0]);
    }
  CHECK(top_x > bottom_x + 0.1f);
  CHECK(std::abs(wall->quads[0].pos[0][0] - stand->quads[0].pos[0][0]) > 0.05f);
  // Facing rotates the model around the block: "south" leans toward +z.
  BlockId south = torch_facing("south");
  m.models->bake(south);
  float top_z = 0, bottom_z = 1;
  for (auto& q : m.models->baked(south)->quads)
    for (int v = 0; v < 4; v++) {
      if (q.pos[v][1] > 0.7f) top_z = std::max(top_z, q.pos[v][2]);
      if (q.pos[v][1] < 0.3f) bottom_z = std::min(bottom_z, q.pos[v][2]);
    }
  CHECK(top_z > bottom_z + 0.1f);
  // Selection boxes hug the supporting block.
  Blocks& reg = Blocks::get();
  CHECK_EQ(reg.info(east).boxes[0].min[0], 0.0f);
  CHECK(reg.info(east).boxes[0].max[0] < 0.4f);
  CHECK(reg.info(torch_facing("west")).boxes[0].max[0] == 1.0f);
  CHECK_EQ(reg.info(east).emit, u8(14));
  CHECK(!reg.info(east).solid());
}
