// Renders a top-down biome/height map of the generator output.
//   worldmap <seed> <center_x> <center_z> <size_in_blocks> <out.png> [step]
#include <cstdlib>
#include <iostream>

#include "assets/image.hpp"
#include "world/worldgen.hpp"

using namespace ds;

int main(int argc, char** argv) {
  if (argc < 6) { std::cerr << "usage: worldmap seed cx cz size out.png [step]\n"; return 2; }
  i64 seed = std::atoll(argv[1]);
  int cx = std::atoi(argv[2]), cz = std::atoi(argv[3]), size = std::atoi(argv[4]);
  int step = argc > 6 ? std::atoi(argv[6]) : 4;
  (void)Blocks::get();
  WorldGen gen(seed);
  int n = size / step;
  Image img = Image::make(n, n);
  const int x0 = cx - size / 2, z0 = cz - size / 2;
  // Generate whole chunks and sample them so the map shows real block data.
  std::unordered_map<u64, std::unique_ptr<Chunk>> cache;
  for (int j = 0; j < n; j++)
    for (int i = 0; i < n; i++) {
      int wx = x0 + i * step, wz = z0 + j * step;
      ChunkPos cp{floor_div(wx, 16), floor_div(wz, 16)};
      auto& c = cache[pack_chunk(cp)];
      if (!c) c = gen.generate(cp);
      int lx = floor_mod(wx, 16), lz = floor_mod(wz, 16);
      int h = c->height[col_index(lx, lz)] - 1;
      // Top block colour.
      BlockId top = 0;
      for (int y = h; y >= MIN_Y; y--) { top = c->get(lx, y, lz); if (top && !(Blocks::get().info(top).flags & BF_Plant)) break; }
      u32 col = Blocks::get().info(top).color;
      float shade = 0.7f + 0.3f * clampv((h - 40) / 120.0f, 0.0f, 1.0f);
      if (Blocks::get().info(top).flags & BF_Liquid) shade = 0.55f + 0.45f * clampv((h + 20) / 80.0f, 0.0f, 1.0f);
      u8* p = img.px(i, j);
      p[0] = static_cast<u8>(((col >> 16) & 255) * shade);
      p[1] = static_cast<u8>(((col >> 8) & 255) * shade);
      p[2] = static_cast<u8>((col & 255) * shade);
      p[3] = 255;
      if (top == B::grass_block) {  // tint by biome
        u8 b = c->biome[col_index(lx, lz)];
        static const u32 tint[] = {0, 0x7CBD6B, 0, 0, 0x4F9A3E, 0x4B7F50};
        if (b < 6 && tint[b]) { p[0] = static_cast<u8>(((tint[b] >> 16) & 255) * shade); p[1] = static_cast<u8>(((tint[b] >> 8) & 255) * shade); p[2] = static_cast<u8>((tint[b] & 255) * shade); }
      }
    }
  write_png_file(argv[5], img);
  std::cout << "wrote " << argv[5] << " (" << n << "x" << n << ")\n";
}
