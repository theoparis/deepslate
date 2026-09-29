#pragma once
#include <deque>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "assets/block_models.hpp"
#include "game/player.hpp"
#include "game/block_updates.hpp"
#include "game/raycast.hpp"
#include "render/clouds.hpp"
#include "render/particles.hpp"
#include "render/sky.hpp"
#include "render/ui.hpp"
#include "render/world_renderer.hpp"

namespace ds {

struct Options {
  std::vector<std::string> packs;   // resource packs, highest priority first
  std::string world_dir = "worlds/DeepslateWorld";
  std::optional<i64> seed;
  int render_distance = 10;
  int threads = 0;                  // 0 = auto
  int width = 1280, height = 720;
  bool fullscreen = false;
  bool vsync = true;
  // Automation / testing
  std::string script;               // ";"-separated actions, see Game::run_script_action
  std::optional<Eigen::Vector3d> start_pos;
  std::optional<float> start_yaw_deg, start_pitch_deg;
  std::optional<i64> start_time;
  int max_frames = -1;
  bool no_save = false;
  bool verbose = false;
};

class Game {
 public:
  explicit Game(Options o) : opt_(std::move(o)) {}
  ~Game();
  int run();

 private:
  enum class Screen { Loading, Playing, Inventory, Pause };

  bool init_window(std::string* err);
  bool init_content(std::string* err);
  void shutdown();
  void handle_event(const void* sdl_event);
  void update(double dt);
  void render();
  void draw_hud(int w, int h);
  void draw_inventory();
  void draw_pause();
  void set_screen(Screen s);
  void capture_mouse(bool on);

  void break_block();
  void place_block();
  void pick_block();
  BlockId placement_state(BlockId base, const RayHit& hit) const;
  void select_slot(int i);
  std::string block_display(BlockId id) const;
  void save_all(bool wait);
  void take_screenshot(const std::string& path);
  void place_player_at_spawn();
  bool run_script_action();
  bool world_settled() const;
  void build_creative_list();

  Options opt_;
  void* window_ = nullptr;       // SDL_Window*
  void* gl_context_ = nullptr;   // SDL_GLContext
  int fb_w_ = 1280, fb_h_ = 720;
  bool running_ = true;

  PackStack packs_;
  std::unique_ptr<BlockModels> models_;
  std::unique_ptr<LevelStore> store_;
  std::unique_ptr<WorldGen> gen_;
  std::unique_ptr<ThreadPool> pool_;
  std::unique_ptr<World> world_;
  std::unique_ptr<BlockUpdates> updates_;
  std::unique_ptr<WorldRenderer> wr_;
  std::unique_ptr<SkyRenderer> sky_;
  std::unique_ptr<Clouds> clouds_;
  std::unique_ptr<Particles> particles_;
  Rng fx_rng_{0xFEED};
  std::unique_ptr<Ui> ui_;

  Player player_;
  Camera cam_;
  Screen screen_ = Screen::Loading;
  bool mouse_captured_ = false;
  bool spawn_pending_ = true;
  bool have_saved_player_ = false;

  // input
  float mouse_dx_ = 0, mouse_dy_ = 0;
  double last_space_ = -10, last_w_ = -10;
  bool sprint_latch_ = false;
  bool prev_w_ = false, prev_space_ = false;
  double break_cd_ = 0, place_cd_ = 0;
  bool lmb_ = false, rmb_ = false;
  std::optional<MoveInput> forced_input_;
  int forced_frames_ = 0;

  // gameplay
  RayHit target_;
  std::array<BlockId, 9> hotbar_{};
  int selected_ = 0;
  std::vector<BlockId> creative_;
  int inv_scroll_ = 0;
  double name_timer_ = 0;
  i64 world_ticks_ = 1000;
  double tick_accum_ = 0, update_accum_ = 0;
  bool time_frozen_ = false;
  double autosave_timer_ = 0;
  int radius_ = 10;
  float fov_deg_ = 70;

  // HUD / debug
  bool show_debug_ = false, show_hud_ = true;
  double fps_ = 0, fps_timer_ = 0;
  int fps_frames_ = 0;
  double frame_ms_ = 0;
  u64 frame_no_ = 0;
  std::string toast_;
  double toast_timer_ = 0;

  // script
  std::deque<std::string> script_;
  int script_wait_ = 0;
  int mark_[3] = {0, 0, 0};
  bool script_idle_ = false, script_ground_ = false;
  double ground_deadline_ = 0;
  double idle_deadline_ = 0;
};

}  // namespace ds
