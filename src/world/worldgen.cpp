#include "world/worldgen.hpp"

namespace ds {

namespace {

float smoothstep(float a, float b, float x) {
  float t = clampv((x - a) / (b - a), 0.0f, 1.0f);
  return t * t * (3 - 2 * t);
}

// Fractal noise whose largest features are `scale` blocks across (FastNoise2 works in world units).
FastNoise::SmartNode<> make_fbm(int octaves, float scale, float gain = 0.5f, bool ridged = false) {
  auto src = FastNoise::New<FastNoise::Simplex>();
  src->SetScale(scale);
  if (ridged) {
    auto f = FastNoise::New<FastNoise::FractalRidged>();
    f->SetSource(src);
    f->SetOctaveCount(octaves);
    f->SetGain(gain);
    return f;
  }
  auto f = FastNoise::New<FastNoise::FractalFBm>();
  f->SetSource(src);
  f->SetOctaveCount(octaves);
  f->SetGain(gain);
  return f;
}

// Sample a 2D grid at world coordinates (x0.., z0..), one sample per block.
void grid2(const FastNoise::SmartNode<>& n, std::vector<float>& out, int x0, int z0, int nx, int nz, int seed) {
  out.resize(static_cast<size_t>(nx) * nz);
  n->GenUniformGrid2D(out.data(), static_cast<float>(x0), static_cast<float>(z0), nx, nz, 1.0f, 1.0f, seed);
}

struct OreSpec {
  const char* name;
  const char* deep;
  int tries, min_y, max_y, size;
};

}  // namespace

WorldGen::WorldGen(i64 seed) : seed_(seed), s32_(static_cast<int>(mix64(static_cast<u64>(seed)) & 0x7FFFFFFF)) {
  continental_ = make_fbm(5, 1100.0f);
  hills_ = make_fbm(4, 170.0f);
  ridged_ = make_fbm(4, 420.0f, 0.5f, true);
  temperature_ = make_fbm(2, 1500.0f);
  humidity_ = make_fbm(2, 1200.0f);
  cave_a_ = make_fbm(2, 48.0f, 0.3f);
  cave_b_ = make_fbm(2, 48.0f, 0.3f);
  cheese_ = make_fbm(2, 90.0f);
  detail_ = make_fbm(2, 22.0f);
}

void WorldGen::compute_columns(ChunkPos pos, ColumnGrid& out) const {
  thread_local std::vector<float> cont, hill, ridge, temp, hum, detail;
  const int x0 = pos.x * 16 - PAD, z0 = pos.z * 16 - PAD;
  // grid2 is indexed [z * EXT + x].
  grid2(continental_, cont, x0, z0, EXT, EXT, s32_);
  grid2(hills_, hill, x0, z0, EXT, EXT, s32_ + 101);
  grid2(ridged_, ridge, x0, z0, EXT, EXT, s32_ + 202);
  grid2(temperature_, temp, x0, z0, EXT, EXT, s32_ + 303);
  grid2(humidity_, hum, x0, z0, EXT, EXT, s32_ + 404);
  grid2(detail_, detail, x0, z0, EXT, EXT, s32_ + 505);

  for (int z = 0; z < EXT; z++) {
    for (int x = 0; x < EXT; x++) {
      size_t i = static_cast<size_t>(z) * EXT + x;
      float c = clampv(cont[i] * 0.85f + 0.12f, -1.0f, 1.0f);
      float land = smoothstep(-0.30f, 0.02f, c);
      float seafloor = clampv(50.0f + (c + 0.55f) * 55.0f, 14.0f, 58.0f);
      float base = lerp(seafloor, 65.0f + c * 14.0f, land);
      const float hv = clampv(hill[i] * 0.6f, -1.2f, 1.2f);
      float rough = 3.0f + 11.0f * land * (0.4f + 0.6f * clampv(hv * 0.5f + 0.5f, 0.0f, 1.0f));
      float h = base + hv * rough + detail[i] * 1.2f;
      float mountain = std::max(0.0f, ridge[i] - 0.85f) * 110.0f * smoothstep(0.0f, 0.5f, c);
      h += mountain;
      h = clampv(h, 8.0f, 300.0f);
      Column& col = out[i];
      col.height = static_cast<int>(h);
      col.temp = temp[i];
      col.hum = hum[i];
      // Cool down with altitude.
      float t = col.temp - std::max(0.0f, h - 100.0f) * 0.012f;
      u8 b;
      if (col.height < SEA_LEVEL - 1) {
        b = col.height < 38 ? Biome::DeepOcean : Biome::Ocean;
        if (t < -0.45f) b = Biome::FrozenOcean;
      } else if (col.height <= SEA_LEVEL + 1 && c < 0.1f) {
        b = Biome::Beach;
      } else if (h > 120.0f) {
        b = Biome::Hills;
      } else if (t < -0.45f) {
        b = col.hum > 0.0f ? Biome::ColdTaiga : Biome::SnowyPlains;
      } else if (t < -0.1f) {
        b = Biome::Taiga;
      } else if (t > 0.5f) {
        b = col.hum < -0.05f ? Biome::Desert : (col.hum < 0.25f ? Biome::Savanna : Biome::Plains);
      } else if (col.hum > 0.3f) {
        b = t < 0.15f ? Biome::BirchForest : Biome::Forest;
      } else if (col.hum > 0.05f) {
        b = Biome::Forest;
      } else {
        b = Biome::Plains;
      }
      col.biome = b;
    }
  }
}

int WorldGen::surface_height(int wx, int wz) const {
  ColumnGrid g;
  ChunkPos cp{floor_div(wx, 16), floor_div(wz, 16)};
  compute_columns(cp, g);
  int lx = floor_mod(wx, 16) + PAD, lz = floor_mod(wz, 16) + PAD;
  return g[static_cast<size_t>(lz) * EXT + lx].height;
}

std::unique_ptr<Chunk> WorldGen::generate(ChunkPos pos) const {
  auto chunk = std::make_unique<Chunk>();
  chunk->pos = pos;
  ColumnGrid cols;
  compute_columns(pos, cols);
  for (int x = 0; x < 16; x++)
    for (int z = 0; z < 16; z++) chunk->biome[col_index(x, z)] = cols[static_cast<size_t>(z + PAD) * EXT + x + PAD].biome;
  carve_and_fill(*chunk, cols);
  place_ores(*chunk);
  place_features(*chunk, cols);
  chunk->recompute_heights();
  chunk->dirty = true;
  return chunk;
}

void WorldGen::carve_and_fill(Chunk& c, const ColumnGrid& cols) const {
  int max_h = 0;
  for (int x = 0; x < 16; x++)
    for (int z = 0; z < 16; z++) max_h = std::max(max_h, cols[static_cast<size_t>(z + PAD) * EXT + x + PAD].height);

  // 3D cave noise over [-60, max_h). Grid layout: x fastest, then z, then y.
  const int y_lo = -60;
  const int ny = std::max(1, std::min(max_h, 200) - y_lo + 1);
  thread_local std::vector<float> ca, cb, ch;
  ca.resize(16u * 16u * ny);
  cb.resize(ca.size());
  ch.resize(ca.size());
  const int wx = c.pos.x * 16, wz = c.pos.z * 16;
  // Grid layout is x, then "y" (used for z), then "z" (used for world y); stretch y so caves run flat.
  const float ys = 1.4f;
  cave_a_->GenUniformGrid3D(ca.data(), static_cast<float>(wx), static_cast<float>(wz), y_lo * ys, 16, 16, ny, 1.0f, 1.0f, ys, s32_ + 11);
  cave_b_->GenUniformGrid3D(cb.data(), static_cast<float>(wx), static_cast<float>(wz), y_lo * ys, 16, 16, ny, 1.0f, 1.0f, ys, s32_ + 12);
  cheese_->GenUniformGrid3D(ch.data(), static_cast<float>(wx), static_cast<float>(wz), y_lo * 1.7f, 16, 16, ny, 1.0f, 1.0f, 1.7f, s32_ + 13);

  const BlockId stone = B::stone, deepslate = B::deepslate;
  for (int lx = 0; lx < 16; lx++) {
    for (int lz = 0; lz < 16; lz++) {
      const Column& col = cols[static_cast<size_t>(lz + PAD) * EXT + lx + PAD];
      const int h = col.height;
      const u64 rh = hash_coords(static_cast<u64>(seed_), wx + lx, 7, wz + lz);
      const float rnd = hash_unit(rh);
      const int top = std::max(h, SEA_LEVEL);

      // Surface materials by biome.
      BlockId top_block = B::grass_block, filler = B::dirt;
      int filler_depth = 3 + static_cast<int>(rnd * 2);
      switch (col.biome) {
        case Biome::Desert: top_block = filler = B::sand; filler_depth = 4; break;
        case Biome::Beach: top_block = filler = B::sand; filler_depth = 3; break;
        case Biome::Ocean: case Biome::DeepOcean: case Biome::FrozenOcean: {
          float k = hash_unit(hash_coords(static_cast<u64>(seed_), (wx + lx) >> 3, 3, (wz + lz) >> 3));
          top_block = filler = k < 0.15f ? B::gravel : (k < 0.25f ? B::clay : B::sand);
          if (col.height > 56) top_block = filler = B::sand;
          break;
        }
        case Biome::SnowyPlains: case Biome::ColdTaiga: top_block = B::snow; break;
        case Biome::Hills:
          if (h > 150) { top_block = filler = B::snow; filler_depth = 1; }
          else if (h > 118) { top_block = filler = B::stone; filler_depth = 1; }
          break;
        default: break;
      }
      if (col.biome == Biome::Savanna && rnd < 0.05f) top_block = B::coarse_dirt;

      for (int y = MIN_Y; y <= top; y++) {
        BlockId id = 0;
        if (y <= h) {
          if (y < MIN_Y + 1) id = B::bedrock;
          else if (y < MIN_Y + 5 && rnd * 5.0f > (y - MIN_Y)) id = B::bedrock;
          else if (y == h) id = top_block;
          else if (y > h - filler_depth) id = filler;
          else if (y < 0) id = deepslate;
          else if (y < 8 && hash_unit(hash_coords(static_cast<u64>(seed_), wx + lx, y, wz + lz)) < (8 - y) / 8.0f) id = deepslate;
          else id = stone;
          if (id == B::sand && y <= h - 4 && col.biome == Biome::Desert) id = B::sandstone;
          if (id == B::snow && y == h && col.biome == Biome::Hills && h > 150) id = B::snow;

          // Caves.
          if (y > MIN_Y + 4 && y <= h - 1 && id != B::bedrock) {
            int yi = y - y_lo;
            if (yi >= 0 && yi < ny) {
              size_t gi = static_cast<size_t>(yi) * 256 + static_cast<size_t>(lz) * 16 + lx;
              float a = ca[gi], b2 = cb[gi];
              bool tunnel = std::abs(a) < 0.07f && std::abs(b2) < 0.07f;
              bool cavern = ch[gi] > 1.1f && y < 48;
              int roof = h - y;
              if ((tunnel || cavern) && (roof > 4 || (tunnel && roof > 1 && h > SEA_LEVEL + 2))) {
                id = y < -54 ? B::lava : 0;
              }
            }
          }
        } else if (y <= SEA_LEVEL) {
          id = (col.biome == Biome::FrozenOcean && y == SEA_LEVEL) ? B::ice : B::water;
        }
        if (id) c.set(lx, y, lz, id);
      }
      (void)stone;
    }
  }
}

void WorldGen::place_ores(Chunk& c) const {
  static const OreSpec ores[] = {
      {"coal_ore", "deepslate_coal_ore", 18, 0, 128, 8},   {"iron_ore", "deepslate_iron_ore", 16, -60, 72, 6},
      {"copper_ore", "deepslate_copper_ore", 12, -16, 112, 8}, {"gold_ore", "deepslate_gold_ore", 4, -60, 32, 6},
      {"redstone_ore", "deepslate_redstone_ore", 6, -60, 16, 6}, {"lapis_ore", "deepslate_lapis_ore", 2, -60, 32, 5},
      {"diamond_ore", "deepslate_diamond_ore", 4, -60, 14, 4}, {"emerald_ore", "emerald_ore", 2, 4, 100, 1},
      {"granite", "granite", 3, 0, 80, 24},  {"diorite", "diorite", 3, 0, 80, 24}, {"andesite", "andesite", 3, 0, 80, 24},
      {"tuff", "tuff", 4, -60, 0, 24},       {"gravel", "gravel", 3, -60, 80, 20},  {"dirt", "dirt", 3, 0, 120, 20},
  };
  int idx = 0;
  Blocks& reg = Blocks::get();
  for (const OreSpec& o : ores) {
    BlockId normal = reg.find(o.name), deep = reg.find(o.deep);
    bool is_ore = std::string_view(o.name).ends_with("_ore");
    for (int t = 0; t < o.tries; t++) {
      Rng rng(hash_coords(static_cast<u64>(seed_), c.pos.x, 1000 + idx * 31 + t, c.pos.z));
      int cx = rng.range(0, 15), cz = rng.range(0, 15), cy = rng.range(o.min_y, o.max_y);
      // Ore veins are rarer at the extremes of their range.
      if (is_ore && rng.chance(0.35f) && std::abs(cy - (o.min_y + o.max_y) / 2) > (o.max_y - o.min_y) / 3) continue;
      int n = is_ore ? std::max(1, o.size - rng.range(0, o.size / 2)) : o.size;
      float radius = std::cbrt(static_cast<float>(n)) * (is_ore ? 0.75f : 1.1f);
      float rx = radius * (0.7f + rng.unit() * 0.6f), ry = radius * (0.6f + rng.unit() * 0.5f), rz = radius * (0.7f + rng.unit() * 0.6f);
      int ir = static_cast<int>(std::ceil(std::max({rx, ry, rz})));
      for (int dx = -ir; dx <= ir; dx++)
        for (int dy = -ir; dy <= ir; dy++)
          for (int dz = -ir; dz <= ir; dz++) {
            int x = cx + dx, y = cy + dy, z = cz + dz;
            if (x < 0 || x > 15 || z < 0 || z > 15) continue;
            float d = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) + (dz * dz) / (rz * rz);
            if (d > 1.0f || rng.unit() < 0.25f) continue;
            BlockId cur = c.get(x, y, z);
            bool host = cur == B::stone || cur == B::deepslate || (!is_ore && (cur == B::dirt || cur == B::tuff));
            if (!host) continue;
            if (!is_ore && cur == B::dirt && normal != B::gravel && normal != B::dirt) continue;
            c.set(x, y, z, (cur == B::deepslate) ? deep : normal);
          }
    }
    idx++;
  }
}

void WorldGen::place_features(Chunk& c, const ColumnGrid& cols) const {
  const int wx0 = c.pos.x * 16, wz0 = c.pos.z * 16;
  auto col_at = [&](int lx, int lz) -> const Column& { return cols[static_cast<size_t>(lz + PAD) * EXT + lx + PAD]; };
  auto ground_ok = [&](const Column& col) { return col.height >= SEA_LEVEL; };

  // ---- trees: candidates from the extended region so canopies cross chunk borders.
  for (int lz = -3; lz < 16 + 3; lz++) {
    for (int lx = -3; lx < 16 + 3; lx++) {
      const Column& col = col_at(lx, lz);
      float density = 0;
      switch (col.biome) {
        case Biome::Forest: density = 0.030f; break;
        case Biome::BirchForest: density = 0.030f; break;
        case Biome::Taiga: case Biome::ColdTaiga: density = 0.028f; break;
        case Biome::Plains: density = 0.0015f; break;
        case Biome::Savanna: density = 0.004f; break;
        case Biome::SnowyPlains: density = 0.002f; break;
        case Biome::Hills: density = col.height < 110 ? 0.006f : 0.0f; break;
        default: break;
      }
      if (density <= 0 || !ground_ok(col) || col.height < SEA_LEVEL + 1) continue;
      int wx = wx0 + lx, wz = wz0 + lz;
      u64 hv = hash_coords(static_cast<u64>(seed_), wx, 55, wz);
      float v = hash_unit(hv);
      if (v >= density) continue;
      // Spacing: this must be the smallest roll within radius 2.
      bool best = true;
      for (int dz = -2; dz <= 2 && best; dz++)
        for (int dx = -2; dx <= 2; dx++) {
          if (!dx && !dz) continue;
          if (hash_unit(hash_coords(static_cast<u64>(seed_), wx + dx, 55, wz + dz)) < v) { best = false; break; }
        }
      if (!best) continue;

      Rng rng(hv ^ 0x1234);
      BlockId log = B::oak_log, leaves = B::oak_leaves;
      int trunk = rng.range(4, 6);
      enum { Round, Conifer } shape = Round;
      if (col.biome == Biome::BirchForest || (col.biome == Biome::Forest && rng.chance(0.2f))) { log = B::birch_log; leaves = B::birch_leaves; trunk = rng.range(5, 7); }
      if (col.biome == Biome::Taiga || col.biome == Biome::ColdTaiga || col.biome == Biome::SnowyPlains ||
          (col.biome == Biome::Hills)) { log = B::spruce_log; leaves = B::spruce_leaves; trunk = rng.range(6, 9); shape = Conifer; }
      const int base = col.height + 1;

      auto put = [&](int x, int y, int z, BlockId id, bool only_air) {
        if (x < 0 || x > 15 || z < 0 || z > 15) return;
        BlockId cur = c.get(x, y, z);
        if (only_air && cur != 0 && !(Blocks::get().info(cur).flags & BF_Plant)) return;
        c.set(x, y, z, id);
      };
      for (int y = 0; y < trunk; y++) put(lx, base + y, lz, log, false);
      if (shape == Round) {
        int top = base + trunk;
        for (int dy = -2; dy <= 1; dy++) {
          int r = dy >= 0 ? (dy == 0 ? 1 : 1) : 2;
          for (int dx = -r; dx <= r; dx++)
            for (int dz = -r; dz <= r; dz++) {
              if (std::abs(dx) == r && std::abs(dz) == r && (dy >= 0 || rng.chance(0.4f))) continue;
              if (dx == 0 && dz == 0 && dy < 0) continue;
              put(lx + dx, top + dy, lz + dz, leaves, true);
            }
        }
        put(lx, top + 1, lz, leaves, true);
      } else {
        int top = base + trunk;
        int r = 0;
        for (int y = top + 1; y >= base + 2; y--) {
          for (int dx = -r; dx <= r; dx++)
            for (int dz = -r; dz <= r; dz++) {
              if (std::abs(dx) + std::abs(dz) > r + (r > 1 ? 1 : 0)) continue;
              if (dx == 0 && dz == 0 && y <= top) continue;
              put(lx + dx, y, lz + dz, leaves, true);
            }
          r = (r + 1) % 3 + ((top + 1 - y) > 4 ? 1 : 0);
          if (r > 3) r = 1;
        }
      }
    }
  }

  // ---- ground cover
  for (int lx = 0; lx < 16; lx++) {
    for (int lz = 0; lz < 16; lz++) {
      const Column& col = col_at(lx, lz);
      const int h = col.height;
      if (h < SEA_LEVEL - 1 || h >= MAX_Y - 8) continue;
      int wx = wx0 + lx, wz = wz0 + lz;
      u64 hv = hash_coords(static_cast<u64>(seed_), wx, 77, wz);
      float v = hash_unit(hv);
      BlockId ground = c.get(lx, h, lz);
      if (c.get(lx, h + 1, lz) != 0) continue;
      if (ground == B::grass_block) {
        switch (col.biome) {
          case Biome::Plains: case Biome::Forest: case Biome::BirchForest: case Biome::Savanna:
            if (v < 0.16f) c.set(lx, h + 1, lz, B::short_grass);
            else if (v < 0.175f) {
              static const BlockId flowers[] = {B::dandelion, B::poppy, B::azure_bluet, B::oxeye_daisy, B::cornflower, B::allium, B::red_tulip, B::pink_tulip, B::lily_of_the_valley};
              c.set(lx, h + 1, lz, flowers[(hv >> 20) % 9]);
            } else if (v > 0.9995f) c.set(lx, h + 1, lz, B::pumpkin);
            break;
          case Biome::Taiga: case Biome::ColdTaiga:
            if (v < 0.08f) c.set(lx, h + 1, lz, B::fern);
            else if (v < 0.12f) c.set(lx, h + 1, lz, B::short_grass);
            break;
          default: break;
        }
      } else if (ground == B::sand && col.biome == Biome::Desert) {
        if (v < 0.004f) {
          int hh = 1 + static_cast<int>((hv >> 24) % 3);
          for (int i = 0; i < hh; i++) c.set(lx, h + 1 + i, lz, B::cactus);
        } else if (v < 0.02f) c.set(lx, h + 1, lz, B::dead_bush);
      } else if ((ground == B::sand || ground == B::dirt || ground == B::grass_block) && h == SEA_LEVEL && v < 0.05f) {
        // Sugar cane next to water.
        bool water = false;
        for (auto [dx, dz] : {std::pair{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
          int nx = lx + dx, nz = lz + dz;
          if (nx < 0 || nx > 15 || nz < 0 || nz > 15) continue;
          if (c.get(nx, h, nz) == B::water) water = true;
        }
        if (water) {
          int hh = 1 + static_cast<int>((hv >> 24) % 3);
          for (int i = 0; i < hh; i++) c.set(lx, h + 1 + i, lz, B::sugar_cane);
        }
      }
    }
  }
}

}  // namespace ds
