#include "render/mesher.hpp"

namespace ds {

namespace {

constexpr int R = 12;            // light window margin around the section
constexpr int W = 16 + 2 * R;    // window edge length
constexpr int WV = W * W * W;

constexpr float kDirShade[6] = {0.5f, 1.0f, 0.8f, 0.8f, 0.6f, 0.6f};
constexpr float kAo[4] = {0.55f, 0.72f, 0.87f, 1.0f};
const int kDir[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};

struct Scratch {
  std::vector<BlockId> blk = std::vector<BlockId>(WV);
  std::vector<u8> opq = std::vector<u8>(WV);
  std::vector<u8> sky = std::vector<u8>(WV);
  std::vector<u8> bl = std::vector<u8>(WV);
  std::vector<u32> queue;
};

constexpr int idx(int x, int y, int z) { return (y * W + z) * W + x; }

inline u8 to_u8(float v) { return static_cast<u8>(clampv(v, 0.0f, 1.0f) * 255.0f + 0.5f); }

// Flood fill of light levels through non-opaque cells.
void flood(std::vector<u8>& level, const std::vector<u8>& opq, std::vector<u32>& q) {
  size_t head = 0;
  while (head < q.size()) {
    u32 i = q[head++];
    int L = level[i];
    if (L <= 1) continue;
    int x = i % W, z = (i / W) % W, y = i / (W * W);
    auto try_nb = [&](int nx, int ny, int nz) {
      if (nx < 0 || ny < 0 || nz < 0 || nx >= W || ny >= W || nz >= W) return;
      u32 j = static_cast<u32>(idx(nx, ny, nz));
      if (opq[j] || level[j] >= L - 1) return;
      level[j] = static_cast<u8>(L - 1);
      q.push_back(j);
    };
    try_nb(x - 1, y, z); try_nb(x + 1, y, z);
    try_nb(x, y - 1, z); try_nb(x, y + 1, z);
    try_nb(x, y, z - 1); try_nb(x, y, z + 1);
  }
}

}  // namespace

void mesh_section(const MeshInput& in, const BlockModels& models, MeshData& out) {
  thread_local Scratch S;
  Blocks& reg = Blocks::get();
  const ChunkSnapshot& center = in.chunks[4];
  const int ox = center.pos.x * 16;
  const int oz = center.pos.z * 16;
  const int oy = (in.section + MIN_SUB) * 16;

  // ---- fill the block window and sky seeds
  std::fill(S.sky.begin(), S.sky.end(), 0);
  std::fill(S.bl.begin(), S.bl.end(), 0);
  S.queue.clear();
  std::vector<u32> block_seeds;
  for (int zi = 0; zi < W; zi++) {
    const int lzw = zi - R;                          // section-relative z
    const int cdz = lzw < 0 ? -1 : (lzw > 15 ? 1 : 0);
    const int lz = lzw - cdz * 16;
    for (int xi = 0; xi < W; xi++) {
      const int lxw = xi - R;
      const int cdx = lxw < 0 ? -1 : (lxw > 15 ? 1 : 0);
      const int lx = lxw - cdx * 16;
      const ChunkSnapshot& snap = in.chunks[static_cast<size_t>((cdz + 1) * 3 + (cdx + 1))];
      const int h = snap.height[col_index(lx, lz)];
      const int lh = snap.light_height[col_index(lx, lz)];
      for (int yi = 0; yi < W; yi++) {
        const int wy = oy - R + yi;
        BlockId id = snap.get(lx, wy, lz);
        const int i = idx(xi, yi, zi);
        S.blk[static_cast<size_t>(i)] = id;
        const BlockInfo& bi = reg.info(id);
        const bool opq = bi.opaque();
        S.opq[static_cast<size_t>(i)] = opq;
        if (opq) continue;
        int sk = 0;
        if (wy >= MAX_Y || wy >= h) sk = 15;
        else if (wy >= lh) sk = std::max(15 - (h - wy), 6);
        if (sk) { S.sky[static_cast<size_t>(i)] = static_cast<u8>(sk); S.queue.push_back(static_cast<u32>(i)); }
        if (bi.emit) { S.bl[static_cast<size_t>(i)] = bi.emit; block_seeds.push_back(static_cast<u32>(i)); }
      }
    }
  }
  flood(S.sky, S.opq, S.queue);
  if (!block_seeds.empty()) {
    S.queue = std::move(block_seeds);
    flood(S.bl, S.opq, S.queue);
  }

  auto blk_at = [&](int x, int y, int z) -> BlockId { return S.blk[static_cast<size_t>(idx(x + R, y + R, z + R))]; };
  auto opq_at = [&](int x, int y, int z) -> bool { return S.opq[static_cast<size_t>(idx(x + R, y + R, z + R))]; };

  // ---- mesh
  for (int y = 0; y < 16; y++) {
    for (int z = 0; z < 16; z++) {
      for (int x = 0; x < 16; x++) {
        const BlockId id = blk_at(x, y, z);
        if (id == 0) continue;
        const BlockInfo& bi = reg.info(id);
        if (bi.opaque() && opq_at(x - 1, y, z) && opq_at(x + 1, y, z) && opq_at(x, y - 1, z) && opq_at(x, y + 1, z) &&
            opq_at(x, y, z - 1) && opq_at(x, y, z + 1))
          continue;

        const u8 biome = center.biome[col_index(x, z)];
        auto light_of = [&](int cx, int cy, int cz, float& sk, float& bk) {
          size_t i = static_cast<size_t>(idx(cx + R, cy + R, cz + R));
          sk = S.sky[i];
          bk = S.bl[i];
        };

        if (bi.liquid()) {
          const bool lava = bi.name.ends_with("lava");
          const u16 layer = lava ? models.lava_layer() : models.water_layer();
          std::vector<Vertex>& dst = lava ? out.opaque : out.translucent;
          const u32 tint = lava ? 0xFFFFFF : models.tint_color(Tint::Water, biome);
          const float tr = ((tint >> 16) & 255) / 255.0f, tg = ((tint >> 8) & 255) / 255.0f, tb = (tint & 255) / 255.0f;
          auto same_fluid = [&](BlockId other) { return other != 0 && reg.info(other).def == bi.def; };
          // Surface height: sources sit just below the block top, flowing levels step down, falling is full.
          auto level_height = [&](BlockId fid) {
            const BlockInfo& fi = reg.info(fid);
            return fi.fluid_depth >= 8 ? 1.0f : 0.889f - 0.111f * static_cast<float>(fi.fluid_depth);
          };
          const bool above_same = same_fluid(blk_at(x, y + 1, z));
          const float top = above_same ? 1.0f : level_height(id);
          for (int d = 0; d < 6; d++) {
            const int nx = x + kDir[d][0], ny = y + kDir[d][1], nz = z + kDir[d][2];
            const BlockId nid = blk_at(nx, ny, nz);
            if (opq_at(nx, ny, nz)) continue;
            float bottom = 0.0f, ytop = top;
            if (same_fluid(nid)) {
              if (d == UP || d == DOWN) continue;
              // Side faces only show the part rising above the neighbouring fluid.
              float nh = same_fluid(blk_at(nx, ny + 1, nz)) ? 1.0f : level_height(nid);
              if (nh >= top) continue;
              bottom = nh;
            }
            float sk, bk;
            light_of(nx, ny, nz, sk, bk);
            const float shade = lava ? 1.0f : kDirShade[d];
            Vertex v{};
            v.r = to_u8(tr * shade); v.g = to_u8(tg * shade); v.b = to_u8(tb * shade);
            v.a = lava ? 255 : 200;
            v.sky = lava ? 255 : to_u8(sk / 15.0f);
            v.blk = lava ? 255 : to_u8(bk / 15.0f);
            v.layer = layer;
            float p[4][3];
            const float x0 = static_cast<float>(x), x1 = x0 + 1, z0 = static_cast<float>(z), z1 = z0 + 1;
            const float yb = y + bottom, yt = y + ytop;
            switch (d) {
              case DOWN: { float q[4][3] = {{x0, y + 0.0f, z1}, {x0, y + 0.0f, z0}, {x1, y + 0.0f, z0}, {x1, y + 0.0f, z1}}; std::memcpy(p, q, sizeof p); break; }
              case UP: { float q[4][3] = {{x0, yt, z0}, {x0, yt, z1}, {x1, yt, z1}, {x1, yt, z0}}; std::memcpy(p, q, sizeof p); break; }
              case NORTH: { float q[4][3] = {{x1, yt, z0}, {x1, yb, z0}, {x0, yb, z0}, {x0, yt, z0}}; std::memcpy(p, q, sizeof p); break; }
              case SOUTH: { float q[4][3] = {{x0, yt, z1}, {x0, yb, z1}, {x1, yb, z1}, {x1, yt, z1}}; std::memcpy(p, q, sizeof p); break; }
              case WEST: { float q[4][3] = {{x0, yt, z0}, {x0, yb, z0}, {x0, yb, z1}, {x0, yt, z1}}; std::memcpy(p, q, sizeof p); break; }
              default: { float q[4][3] = {{x1, yt, z1}, {x1, yb, z1}, {x1, yb, z0}, {x1, yt, z0}}; std::memcpy(p, q, sizeof p); break; }
            }
            const float vt = (d >= NORTH) ? (1.0f - ytop) : 0.0f, vb = (d >= NORTH) ? (1.0f - bottom) : 1.0f;
            const float uvs[4][2] = {{0, vt}, {0, vb}, {1, vb}, {1, vt}};
            for (int k = 0; k < 4; k++) {
              v.x = p[k][0]; v.y = p[k][1]; v.z = p[k][2];
              v.u = uvs[k][0]; v.v = uvs[k][1];
              dst.push_back(v);
            }
          }
          continue;
        }

        const BakedBlock* baked = models.baked(id);
        if (!baked) continue;
        std::vector<Vertex>& dst = (bi.flags & BF_Translucent) ? out.translucent : out.opaque;
        const bool emissive = bi.flags & BF_Emissive;
        const u32 tint_rgb = bi.tint != Tint::None ? models.tint_color(bi.tint, biome) : 0xFFFFFF;

        const std::vector<BakedQuad>& quads = baked->pick(hash_coords(0xA17, ox + x, oy + y, oz + z));
        for (const BakedQuad& q : quads) {
          if (q.cull >= 0) {
            const int nx = x + kDir[q.cull][0], ny = y + kDir[q.cull][1], nz = z + kDir[q.cull][2];
            if (opq_at(nx, ny, nz)) continue;
            if ((bi.flags & BF_Translucent) && blk_at(nx, ny, nz) == id) continue;
            if ((bi.flags & BF_Cutout) && !(bi.flags & (BF_Leaves | BF_Plant)) && blk_at(nx, ny, nz) == id) continue;  // glass
          }
          float tr = 1, tg = 1, tb = 1;
          if (q.tint >= 0 && bi.tint != Tint::None) {
            tr = ((tint_rgb >> 16) & 255) / 255.0f;
            tg = ((tint_rgb >> 8) & 255) / 255.0f;
            tb = (tint_rgb & 255) / 255.0f;
          }
          const float shade = q.shade ? kDirShade[q.dir] : 1.0f;
          for (int v = 0; v < 4; v++) {
            float ao = 1.0f, sk = 0, bk = 0;
            if (q.boundary) {
              static const int kAxisOfDir[6] = {1, 1, 2, 2, 0, 0};
              const int a = kAxisOfDir[q.dir], sgn = (q.dir % 2) ? 1 : -1;
              const int t1 = (a + 1) % 3, t2 = (a + 2) % 3;
              const int s1 = q.pos[v][t1] > 0.5f ? 1 : -1, s2 = q.pos[v][t2] > 0.5f ? 1 : -1;
              int base[3] = {x, y, z};
              base[a] += sgn;
              auto cell = [&](int d1, int d2, int* c) { c[0] = base[0]; c[1] = base[1]; c[2] = base[2]; c[t1] += d1; c[t2] += d2; };
              int c0[3], c1[3], c2[3], c3[3];
              cell(0, 0, c0); cell(s1, 0, c1); cell(0, s2, c2); cell(s1, s2, c3);
              const bool o1 = opq_at(c1[0], c1[1], c1[2]), o2 = opq_at(c2[0], c2[1], c2[2]), o3 = opq_at(c3[0], c3[1], c3[2]);
              ao = kAo[(o1 && o2) ? 0 : 3 - (o1 + o2 + o3)];
              float ssum = 0, bsum = 0;
              int n = 0;
              int* cs[4] = {c0, c1, c2, c3};
              for (int* c : cs) {
                if (opq_at(c[0], c[1], c[2])) continue;
                float s, b;
                light_of(c[0], c[1], c[2], s, b);
                ssum += s; bsum += b; n++;
              }
              if (n) { sk = ssum / n; bk = bsum / n; }
            } else {
              light_of(x, y, z, sk, bk);
            }
            const float f = shade * ao;
            Vertex vx{};
            vx.x = x + q.pos[v][0]; vx.y = y + q.pos[v][1]; vx.z = z + q.pos[v][2];
            vx.u = q.uv[v][0]; vx.v = q.uv[v][1];
            vx.layer = q.layer;
            vx.r = to_u8(tr * f); vx.g = to_u8(tg * f); vx.b = to_u8(tb * f);
            vx.a = 255;
            vx.sky = emissive ? 255 : to_u8(sk / 15.0f);
            vx.blk = emissive ? 255 : to_u8(bk / 15.0f);
            dst.push_back(vx);
          }
        }
      }
    }
  }
}

}  // namespace ds
