#include <cstdlib>
#include <cstring>
#include <iostream>

#include "assets/resource_pack.hpp"
#include "game/game.hpp"

namespace {

void usage() {
  std::cout << R"(Deepslate Edition - single-player Bedrock-style voxel game (C++26)

Usage: deepslate [options]
  --resource-pack <zip|dir|url>  Resource pack in Java/official layout (assets/minecraft/...).
                                 May be given several times; earlier packs win. A built-in
                                 procedural pack is always used as the lowest layer.
  --world <dir>                  Bedrock world directory (level.dat + db/). Created if missing.
                                 Default: worlds/DeepslateWorld
  --seed <n>                     Seed for a new world
  --render-distance <chunks>     2..32 (default 10)
  --threads <n>                  Worker threads (default: cores - 1)
  --size <w>x<h>                 Window size (default 1280x720)
  --fullscreen                   Start fullscreen
  --no-vsync                     Disable vsync
  --pos <x> <y> <z>              Start position
  --yaw <deg> --pitch <deg>      Start orientation
  --time <ticks>                 Start time of day (0 sunrise, 6000 noon, 12000 sunset, 18000 midnight)
  --script "<a;b;c>"             Scripted actions (for automated tests), e.g.
                                   "idle;shot a.png;look 90 20;break;idle;shot b.png;quit"
                                 actions: wait N | idle | ground | setblock X Y Z NAME [k=v..] | nudge DX DY DZ | mark | assert_marked NAME | shot FILE | tp X Y Z | look YAW PITCH | break | place |
                                 select N | time T | freeze | fly on|off | walk FWD STRAFE FRAMES | jump FRAMES |
                                 inv | radius N | save | debug | log MSG | assert_block X Y Z NAME |
                                 assert_target NAME | assert_ground | quit
  --frames <n>                   Exit after n frames
  --no-save                      Do not write anything to the world
  --write-builtin-pack <zip>     Write the built-in resource pack as a .zip and exit
  --verbose                      Debug logging
  --help

Controls: WASD move, Space jump (double-tap: toggle flight), Shift sneak/descend, Ctrl or double-tap W sprint,
mouse look, LMB break, RMB place, MMB pick block, 1-9 / wheel hotbar, E inventory, F3 debug, F1 hide HUD,
F2 screenshot, F11 fullscreen, -/= render distance, PgUp/PgDn time of day, T freeze time, Esc menu.
)";
}

}  // namespace

int main(int argc, char** argv) {
  ds::Options opt;
  std::string export_pack;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&](const char* what) -> const char* {
      if (i + 1 >= argc) { std::cerr << "missing value for " << what << "\n"; std::exit(2); }
      return argv[++i];
    };
    if (a == "--help" || a == "-h") { usage(); return 0; }
    else if (a == "--resource-pack" || a == "--pack") opt.packs.push_back(next("--resource-pack"));
    else if (a == "--world") opt.world_dir = next("--world");
    else if (a == "--seed") opt.seed = std::strtoll(next("--seed"), nullptr, 10);
    else if (a == "--render-distance") opt.render_distance = std::atoi(next("--render-distance"));
    else if (a == "--threads") opt.threads = std::atoi(next("--threads"));
    else if (a == "--size") {
      if (std::sscanf(next("--size"), "%dx%d", &opt.width, &opt.height) != 2) { std::cerr << "bad --size\n"; return 2; }
    } else if (a == "--fullscreen") opt.fullscreen = true;
    else if (a == "--no-vsync") opt.vsync = false;
    else if (a == "--pos") {
      double x = std::atof(next("--pos")), y = std::atof(next("--pos")), z = std::atof(next("--pos"));
      opt.start_pos = Eigen::Vector3d(x, y, z);
    } else if (a == "--yaw") opt.start_yaw_deg = static_cast<float>(std::atof(next("--yaw")));
    else if (a == "--pitch") opt.start_pitch_deg = static_cast<float>(std::atof(next("--pitch")));
    else if (a == "--time") opt.start_time = std::strtoll(next("--time"), nullptr, 10);
    else if (a == "--script") opt.script = next("--script");
    else if (a == "--frames") opt.max_frames = std::atoi(next("--frames"));
    else if (a == "--no-save") opt.no_save = true;
    else if (a == "--write-builtin-pack") export_pack = next("--write-builtin-pack");
    else if (a == "--verbose") { opt.verbose = true; ds::log_threshold() = ds::LogLevel::Debug; }
    else { std::cerr << "unknown option " << a << " (see --help)\n"; return 2; }
  }
  if (!export_pack.empty()) {
    std::string err;
    if (!ds::export_builtin_pack_zip(export_pack, &err)) { std::cerr << "error: " << err << "\n"; return 1; }
    std::cout << "wrote " << export_pack << "\n";
    return 0;
  }
  ds::Game game(std::move(opt));
  return game.run();
}
