// Bakes every blockstate found in a resource pack and reports what could not be resolved.
//   packcheck <pack.zip|dir> [--verbose]
// Useful for checking compatibility with a new resource-pack version.
#include <iostream>

#include "assets/block_models.hpp"

using namespace ds;

int main(int argc, char** argv) {
  if (argc < 2) { std::cerr << "usage: packcheck <pack> [--verbose]\n"; return 2; }
  bool verbose = argc > 2 && std::string(argv[2]) == "--verbose";
  PackStack packs;
  std::string err;
  if (!packs.add_spec(argv[1], &err)) { std::cerr << "error: " << err << "\n"; return 1; }
  packs.add_builtin_fallback();
  Blocks& reg = Blocks::get();
  BlockModels models(packs, 2048);

  // Register every blockstate name as a block so the baker resolves it like a foreign block.
  std::vector<std::pair<std::string, BlockId>> ids;
  const std::string prefix = "assets/minecraft/blockstates/";
  for (const std::string& f : packs.list(prefix)) {
    if (!f.ends_with(".json")) continue;
    std::string name = f.substr(prefix.size(), f.size() - prefix.size() - 5);
    if (name.find('/') != std::string::npos) continue;
    ids.emplace_back(name, reg.lookup_or_register("minecraft:" + name, {{"__packcheck", StateValue::byte(1)}}));
  }
  models.build();
  size_t no_model = 0, bad_tex = 0, quads = 0;
  for (auto& [name, id] : ids) {
    const BakedBlock* b = models.baked(id);
    if (!b) continue;
    quads += b->quads.size();
    size_t missing_layers = 0;
    for (auto& q : b->quads) if (q.layer == 0) missing_layers++;
    if (b->missing || b->quads.empty()) {
      no_model++;
      if (verbose) std::cout << "no model:       " << name << "\n";
    } else if (missing_layers) {
      bad_tex++;
      if (verbose) std::cout << "missing texture: " << name << " (" << missing_layers << "/" << b->quads.size() << " quads)\n";
    }
  }
  std::cout << "blockstates: " << ids.size() << ", baked quads: " << quads << ", atlas layers: " << models.layer_count() << " (" << models.tile_size()
            << "px)\n"
            << "  without a usable model: " << no_model << "\n  with unresolved textures: " << bad_tex << "\n";
  return 0;
}
