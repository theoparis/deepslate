// Micro-benchmark: world generation and meshing throughput (single thread).
//   bench [seed] [chunks-per-side]
#include <chrono>
#include <cstdlib>
#include <iostream>

#include "assets/block_models.hpp"
#include "render/mesher.hpp"
#include "world/worldgen.hpp"

using namespace ds;
using Clock = std::chrono::steady_clock;
static double ms_since(Clock::time_point t) { return std::chrono::duration<double, std::milli>(Clock::now() - t).count(); }

int main(int argc, char** argv) {
  i64 seed = argc > 1 ? std::atoll(argv[1]) : 42;
  int n = argc > 2 ? std::atoi(argv[2]) : 8;
  (void)Blocks::get();
  PackStack packs;
  packs.add_builtin_fallback();
  BlockModels models(packs);
  models.build();
  WorldGen gen(seed);

  std::vector<std::unique_ptr<Chunk>> chunks(static_cast<size_t>(n) * n);
  auto t = Clock::now();
  for (int z = 0; z < n; z++)
    for (int x = 0; x < n; x++) chunks[static_cast<size_t>(z) * n + x] = gen.generate({x - n / 2, z - n / 2});
  double gen_ms = ms_since(t);
  std::cout << "generate: " << n * n << " chunks in " << gen_ms << " ms  (" << gen_ms / (n * n) << " ms/chunk)\n";

  t = Clock::now();
  size_t sections = 0, quads = 0;
  for (int z = 1; z < n - 1; z++)
    for (int x = 1; x < n - 1; x++) {
      MeshInput in;
      for (int dz = -1; dz <= 1; dz++)
        for (int dx = -1; dx <= 1; dx++)
          in.chunks[static_cast<size_t>((dz + 1) * 3 + dx + 1)] = chunks[static_cast<size_t>(z + dz) * n + x + dx]->snapshot();
      const Chunk& c = *chunks[static_cast<size_t>(z) * n + x];
      for (int s = 0; s < NUM_SUBS; s++) {
        if (!c.subs[static_cast<size_t>(s)]) continue;
        in.section = s;
        MeshData m;
        mesh_section(in, models, m);
        sections++;
        quads += m.quads();
      }
    }
  double mesh_ms = ms_since(t);
  std::cout << "mesh: " << sections << " sections in " << mesh_ms << " ms  (" << mesh_ms / static_cast<double>(sections) << " ms/section, "
            << quads / sections << " quads/section)\n";
}
