#include "game/game.hpp"

#include <SDL3/SDL.h>

#include <algorithm>
#include <cctype>
#include <ctime>
#include <filesystem>
#include <sstream>

#include "assets/image.hpp"

namespace ds {

namespace fs = std::filesystem;

namespace {
SDL_Window* win(void* p) { return static_cast<SDL_Window*>(p); }

std::vector<std::string> split(const std::string& s, char sep) {
  std::vector<std::string> out;
  std::string cur;
  for (char c : s) {
    if (c == sep) { out.push_back(cur); cur.clear(); }
    else cur += c;
  }
  out.push_back(cur);
  return out;
}
std::string trim(std::string s) {
  size_t a = s.find_first_not_of(" \t\n"), b = s.find_last_not_of(" \t\n");
  return a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
}
}  // namespace

Game::~Game() { shutdown(); }

// ------------------------------------------------------------------ init

bool Game::init_window(std::string* err) {
  if (!SDL_Init(SDL_INIT_VIDEO)) {
    *err = std::string("SDL_Init: ") + SDL_GetError();
    return false;
  }
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
  SDL_WindowFlags flags = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY;
  if (opt_.fullscreen) flags |= SDL_WINDOW_FULLSCREEN;
  window_ = SDL_CreateWindow("Deepslate Edition", opt_.width, opt_.height, flags);
  if (!window_) {
    *err = std::string("SDL_CreateWindow: ") + SDL_GetError();
    return false;
  }
  gl_context_ = SDL_GL_CreateContext(win(window_));
  if (!gl_context_) {
    *err = std::string("OpenGL 3.3 core context: ") + SDL_GetError();
    return false;
  }
  SDL_GL_SetSwapInterval(opt_.vsync ? 1 : 0);
  std::string missing;
  if (!gl::load(&missing)) {
    *err = "missing OpenGL function " + missing;
    return false;
  }
  SDL_GetWindowSizeInPixels(win(window_), &fb_w_, &fb_h_);
  log_info("OpenGL {} on {}", reinterpret_cast<const char*>(gl::GetString(GL_VERSION)), reinterpret_cast<const char*>(gl::GetString(GL_RENDERER)));
  return true;
}

bool Game::init_content(std::string* err) {
  for (auto& spec : opt_.packs) {
    std::string e;
    if (!packs_.add_spec(spec, &e)) {
      *err = "resource pack '" + spec + "': " + e;
      return false;
    }
  }
  packs_.add_builtin_fallback();
  log_info("resource packs: {}", packs_.describe());

  Blocks& reg = Blocks::get();
  GLint max_layers = 256;
  gl::GetIntegerv(GL_MAX_ARRAY_TEXTURE_LAYERS, &max_layers);
  models_ = std::make_unique<BlockModels>(packs_, max_layers);
  models_->build();
  reg.set_listener([this](BlockId id) { models_->bake(id); });

  // World.
  std::string e;
  i64 seed = opt_.seed ? *opt_.seed : static_cast<i64>(mix64(static_cast<u64>(std::time(nullptr)) ^ 0xDEE951A7E));
  store_ = LevelStore::open(opt_.world_dir, seed, &e);
  if (!store_) {
    *err = "cannot open world '" + opt_.world_dir + "': " + e;
    return false;
  }
  if (store_->is_new()) log_info("creating new world '{}' (seed {})", store_->info().name, store_->info().seed);
  else log_info("loaded world '{}' (seed {})", store_->info().name, store_->info().seed);
  gen_ = std::make_unique<WorldGen>(store_->info().seed);
  unsigned hw = std::thread::hardware_concurrency();
  unsigned threads = opt_.threads > 0 ? static_cast<unsigned>(opt_.threads) : std::max(2u, hw > 1 ? hw - 1 : 1);
  pool_ = std::make_unique<ThreadPool>(threads);
  log_info("worker threads: {}", threads);
  world_ = std::make_unique<World>(*store_, *gen_, *pool_);
  updates_ = std::make_unique<BlockUpdates>(*world_);
  wr_ = std::make_unique<WorldRenderer>(*world_, *models_, *pool_);
  if (!wr_->init(&e)) { *err = "world renderer: " + e; return false; }
  sky_ = std::make_unique<SkyRenderer>();
  if (!sky_->init(packs_, &e)) { *err = "sky renderer: " + e; return false; }
  clouds_ = std::make_unique<Clouds>();
  if (!clouds_->init(packs_, &e)) { *err = "clouds: " + e; return false; }
  particles_ = std::make_unique<Particles>();
  if (!particles_->init(*models_, wr_->atlas_texture(), &e)) { *err = "particles: " + e; return false; }
  ui_ = std::make_unique<Ui>();
  if (!ui_->init(packs_, *models_, wr_->atlas_texture(), &e)) { *err = "ui: " + e; return false; }

  radius_ = clampv(opt_.render_distance, 2, 32);
  world_ticks_ = opt_.start_time ? *opt_.start_time : store_->info().time;
  build_creative_list();

  // Hotbar defaults / saved.
  PlayerData pd;
  have_saved_player_ = store_->load_player(pd);
  const char* defaults[9] = {"grass_block", "dirt", "stone", "cobblestone", "oak_planks", "oak_log", "glass", "torch", "sand"};
  for (int i = 0; i < 9; i++) hotbar_[static_cast<size_t>(i)] = reg.find(defaults[i]);
  if (have_saved_player_ && pd.hotbar.size() == 9) {
    for (int i = 0; i < 9; i++)
      if (!pd.hotbar[static_cast<size_t>(i)].block.empty()) {
        BlockId id = reg.find(pd.hotbar[static_cast<size_t>(i)].block);
        if (id) hotbar_[static_cast<size_t>(i)] = id;
      }
    selected_ = clampv(pd.selected, 0, 8);
  }
  player_.creative = true;  // gameplay is creative-style regardless of the stored GameType

  for (auto& a : split(opt_.script, ';')) {
    std::string t = trim(a);
    if (!t.empty()) script_.push_back(t);
  }
  return true;
}

void Game::build_creative_list() {
  creative_.clear();
  Blocks& reg = Blocks::get();
  for (const BlockDef& d : builtin_defs()) {
    if (d.kind == Kind::Air || !d.creative) continue;
    BlockId id = reg.find(d.name);
    if (id) creative_.push_back(id);
  }
}

void Game::shutdown() {
  if (!window_ && !world_) return;
  if (store_ && world_) save_all(true);
  wr_.reset();
  particles_.reset();
  clouds_.reset();
  updates_.reset();
  ui_.reset();
  sky_.reset();
  world_.reset();
  pool_.reset();
  gen_.reset();
  store_.reset();
  models_.reset();
  if (gl_context_) { SDL_GL_DestroyContext(static_cast<SDL_GLContext>(gl_context_)); gl_context_ = nullptr; }
  if (window_) { SDL_DestroyWindow(win(window_)); window_ = nullptr; }
  SDL_Quit();
}

// ------------------------------------------------------------------ saving

void Game::save_all(bool wait) {
  if (opt_.no_save) return;
  world_->save_dirty(wait);
  PlayerData pd;
  pd.pos[0] = player_.pos.x(); pd.pos[1] = player_.pos.y(); pd.pos[2] = player_.pos.z();
  pd.yaw = player_.yaw * 180.0f / 3.14159265f;
  pd.pitch = player_.pitch * 180.0f / 3.14159265f;
  pd.flying = player_.flying;
  pd.selected = selected_;
  for (BlockId id : hotbar_) pd.hotbar.push_back({id ? Blocks::get().info(id).name : std::string(), id ? 1 : 0});
  if (!spawn_pending_) store_->save_player(pd);
  store_->info().time = world_ticks_;
  store_->write_level_dat();
}

// ------------------------------------------------------------------ player placement

void Game::place_player_at_spawn() {
  PlayerData pd;
  if (have_saved_player_ && store_->load_player(pd)) {
    player_.pos = {pd.pos[0], pd.pos[1], pd.pos[2]};
    player_.yaw = pd.yaw * 3.14159265f / 180.0f;
    player_.pitch = pd.pitch * 3.14159265f / 180.0f;
    player_.flying = pd.flying;
  } else {
    LevelInfo& li = store_->info();
    int sx = 0, sz = 0;
    if (li.spawn_set) { sx = li.spawn_x; sz = li.spawn_z; }
    else {
      // Look for dry land near the origin.
      bool found = false;
      for (int r = 0; r < 60 && !found; r++)
        for (int k = 0; k < std::max(1, r * 8) && !found; k++) {
          double a = k * 6.2831853 / std::max(1, r * 8);
          int x = static_cast<int>(std::cos(a) * r * 8), z = static_cast<int>(std::sin(a) * r * 8);
          if (gen_->surface_height(x, z) > WorldGen::SEA_LEVEL + 1 && gen_->surface_height(x, z) < 110) { sx = x; sz = z; found = true; }
        }
      li.spawn_x = sx; li.spawn_z = sz; li.spawn_y = gen_->surface_height(sx, sz) + 1;
      li.spawn_set = true;
    }
    player_.pos = {sx + 0.5, static_cast<double>(li.spawn_y) + 0.01, sz + 0.5};
    player_.yaw = 0;
    player_.pitch = 0.2f;
  }
  if (opt_.start_pos) player_.pos = *opt_.start_pos;
  if (opt_.start_yaw_deg) player_.yaw = *opt_.start_yaw_deg * 3.14159265f / 180.0f;
  if (opt_.start_pitch_deg) player_.pitch = *opt_.start_pitch_deg * 3.14159265f / 180.0f;
  player_.vel.setZero();
}

// ------------------------------------------------------------------ main loop

int Game::run() {
  std::string err;
  if (!init_window(&err) || !init_content(&err)) {
    log_error("{}", err);
    return 1;
  }
  place_player_at_spawn();
  set_screen(Screen::Loading);

  double prev = now_seconds();
  int exit_code = 0;
  while (running_) {
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) handle_event(&ev);
    double t = now_seconds();
    double dt = std::min(t - prev, 0.1);
    prev = t;
    update(dt);
    render();
    SDL_GL_SwapWindow(win(window_));
    frame_no_++;
    frame_ms_ = (now_seconds() - t) * 1000.0;
    fps_frames_++;
    fps_timer_ += dt;
    if (fps_timer_ >= 0.5) { fps_ = fps_frames_ / fps_timer_; fps_frames_ = 0; fps_timer_ = 0; }
    if (opt_.max_frames >= 0 && static_cast<int>(frame_no_) >= opt_.max_frames) running_ = false;
  }
  log_info("chunks: {} generated, {} loaded from disk, {} written", world_->chunks_generated(), world_->chunks_loaded_from_disk(), world_->writer_written());
  extern int g_script_failures;
  exit_code = g_script_failures ? 1 : 0;
  return exit_code;
}

void Game::capture_mouse(bool on) {
  mouse_captured_ = on;
  SDL_SetWindowRelativeMouseMode(win(window_), on);
}

void Game::set_screen(Screen s) {
  screen_ = s;
  capture_mouse(s == Screen::Playing);
  if (s == Screen::Inventory || s == Screen::Pause) SDL_WarpMouseInWindow(win(window_), 0, 0);
}

void Game::select_slot(int i) {
  selected_ = ((i % 9) + 9) % 9;
  name_timer_ = 2.0;
}

std::string Game::block_display(BlockId id) const { return id ? Blocks::get().info(id).display : std::string(); }

// ------------------------------------------------------------------ events

void Game::handle_event(const void* pe) {
  const SDL_Event& e = *static_cast<const SDL_Event*>(pe);
  switch (e.type) {
    case SDL_EVENT_QUIT: running_ = false; break;
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: SDL_GetWindowSizeInPixels(win(window_), &fb_w_, &fb_h_); break;
    case SDL_EVENT_WINDOW_FOCUS_LOST:
      if (screen_ == Screen::Playing) set_screen(Screen::Pause);
      break;
    case SDL_EVENT_MOUSE_MOTION:
      if (mouse_captured_) { mouse_dx_ += e.motion.xrel; mouse_dy_ += e.motion.yrel; }
      break;
    case SDL_EVENT_MOUSE_WHEEL:
      if (screen_ == Screen::Playing) select_slot(selected_ - (e.wheel.y > 0 ? 1 : (e.wheel.y < 0 ? -1 : 0)));
      else if (screen_ == Screen::Inventory) inv_scroll_ = std::max(0, inv_scroll_ - static_cast<int>(e.wheel.y));
      break;
    case SDL_EVENT_MOUSE_BUTTON_DOWN: {
      if (screen_ == Screen::Playing) {
        if (e.button.button == SDL_BUTTON_LEFT) { lmb_ = true; break_cd_ = 0; }
        if (e.button.button == SDL_BUTTON_RIGHT) { rmb_ = true; place_cd_ = 0; }
        if (e.button.button == SDL_BUTTON_MIDDLE) pick_block();
      } else if (screen_ == Screen::Inventory || screen_ == Screen::Pause) {
        float density = SDL_GetWindowPixelDensity(win(window_));
        float gx = e.button.x * density / ui_->scale(), gy = e.button.y * density / ui_->scale();
        const float W = ui_->width(), H = ui_->height();
        if (screen_ == Screen::Inventory) {
          const float px = std::floor((W - 176) / 2), py = std::floor((H - 166) / 2);
          for (int r = 0; r < 5; r++)
            for (int c = 0; c < 9; c++) {
              size_t idx = static_cast<size_t>((r + inv_scroll_) * 9 + c);
              float x = px + 8 + c * 18, y = py + 18 + r * 18;
              if (idx < creative_.size() && gx >= x && gx < x + 18 && gy >= y && gy < y + 18) {
                hotbar_[static_cast<size_t>(selected_)] = creative_[idx];
                name_timer_ = 2.0;
              }
            }
          for (int i = 0; i < 9; i++) {
            float x = px + 8 + i * 18, y = py + 142;
            if (gx >= x && gx < x + 18 && gy >= y && gy < y + 18) {
              if (e.button.button == SDL_BUTTON_RIGHT) hotbar_[static_cast<size_t>(i)] = 0;
              else select_slot(i);
            }
          }
        } else {
          float bx = std::floor((W - 200) / 2);
          if (gx >= bx && gx < bx + 200) {
            if (gy >= H / 2 - 24 && gy < H / 2 - 4) set_screen(Screen::Playing);
            else if (gy >= H / 2 + 4 && gy < H / 2 + 24) running_ = false;
          }
        }
      }
      break;
    }
    case SDL_EVENT_MOUSE_BUTTON_UP:
      if (e.button.button == SDL_BUTTON_LEFT) lmb_ = false;
      if (e.button.button == SDL_BUTTON_RIGHT) rmb_ = false;
      break;
    case SDL_EVENT_KEY_DOWN: {
      if (e.key.repeat) break;
      SDL_Keycode k = e.key.key;
      if (k == SDLK_ESCAPE) {
        if (screen_ == Screen::Playing) set_screen(Screen::Pause);
        else if (screen_ == Screen::Inventory || screen_ == Screen::Pause) set_screen(Screen::Playing);
      } else if (k == SDLK_E && (screen_ == Screen::Playing || screen_ == Screen::Inventory)) {
        set_screen(screen_ == Screen::Playing ? Screen::Inventory : Screen::Playing);
      } else if (k == SDLK_F3) show_debug_ = !show_debug_;
      else if (k == SDLK_F1) show_hud_ = !show_hud_;
      else if (k == SDLK_F2) {
        fs::create_directories("screenshots");
        std::time_t tt = std::time(nullptr);
        char buf[64];
        std::strftime(buf, sizeof buf, "screenshots/%Y-%m-%d_%H.%M.%S.png", std::localtime(&tt));
        take_screenshot(buf);
        toast_ = std::string("Saved ") + buf;
        toast_timer_ = 3;
      } else if (k == SDLK_F11) {
        bool fs_now = SDL_GetWindowFlags(win(window_)) & SDL_WINDOW_FULLSCREEN;
        SDL_SetWindowFullscreen(win(window_), !fs_now);
      } else if (screen_ == Screen::Playing) {
        if (k >= SDLK_1 && k <= SDLK_9) select_slot(static_cast<int>(k - SDLK_1));
        else if (k == SDLK_MINUS) { radius_ = std::max(2, radius_ - 1); toast_ = std::format("Render distance: {}", radius_); toast_timer_ = 2; }
        else if (k == SDLK_EQUALS) { radius_ = std::min(32, radius_ + 1); toast_ = std::format("Render distance: {}", radius_); toast_timer_ = 2; }
        else if (k == SDLK_PAGEUP) world_ticks_ += 1000;
        else if (k == SDLK_PAGEDOWN) world_ticks_ -= 1000;
        else if (k == SDLK_T) { time_frozen_ = !time_frozen_; toast_ = time_frozen_ ? "Time frozen" : "Time running"; toast_timer_ = 2; }
      }
      break;
    }
    default: break;
  }
}

// ------------------------------------------------------------------ gameplay

BlockId Game::placement_state(BlockId base, const RayHit& hit) const {
  const BlockInfo& bi = Blocks::get().info(base);
  if (!bi.def) return base;
  StateMap st = bi.states;
  auto set_state = [&](const char* key, StateValue v) {
    for (auto& [k, val] : st)
      if (k == key) { val = v; return; }
    st.emplace_back(key, v);
  };
  const double frac_y = hit.point.y() - std::floor(hit.point.y());
  switch (bi.def->kind) {
    case Kind::Column: {
      const char* ax = (hit.face <= 1) ? "y" : (hit.face <= 3 ? "z" : "x");
      set_state("pillar_axis", StateValue::string(ax));
      break;
    }
    case Kind::Slab: {
      bool top = hit.face == DOWN || (hit.face >= NORTH && frac_y > 0.5);
      set_state("minecraft:vertical_half", StateValue::string(top ? "top" : "bottom"));
      break;
    }
    case Kind::Stairs: {
      bool top = hit.face == DOWN || (hit.face >= NORTH && frac_y > 0.5);
      Eigen::Vector3f f = cam_.forward();
      int dir = std::abs(f.x()) > std::abs(f.z()) ? (f.x() > 0 ? 0 : 1) : (f.z() > 0 ? 2 : 3);
      set_state("upside_down_bit", StateValue::byte(top ? 1 : 0));
      set_state("weirdo_direction", StateValue::integer(dir));
      break;
    }
    case Kind::Torch: {
      // Attach to the clicked face: standing on top, or hanging on a wall facing away from it.
      static const char* names[6] = {"top", "top", "north", "south", "west", "east"};
      set_state("torch_facing_direction", StateValue::string(names[hit.face]));
      break;
    }
    default: return base;
  }
  return Blocks::get().lookup_or_register(bi.name, std::move(st));
}

void Game::break_block() {
  if (!target_.hit) return;
  const BlockInfo& bi = Blocks::get().info(world_->get_block(target_.x, target_.y, target_.z));
  if (bi.flags & BF_Unbreakable && !player_.creative) return;
  particles_->emit_break(world_->get_block(target_.x, target_.y, target_.z), target_.x, target_.y, target_.z, fx_rng_);
  world_->set_block(target_.x, target_.y, target_.z, 0);
  updates_->notify(target_.x, target_.y, target_.z);
  // Dependent blocks (plants, torches) notice the missing support on the next update tick.
}

void Game::place_block() {
  if (!target_.hit) return;
  BlockId held = hotbar_[static_cast<size_t>(selected_)];
  if (!held) return;
  static const int dv[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};
  int x = target_.x, y = target_.y, z = target_.z;
  // Replaceable targets (tall grass...) are replaced in place.
  const BlockInfo& tinfo = Blocks::get().info(world_->get_block(x, y, z));
  if (!tinfo.replaceable()) { x += dv[target_.face][0]; y += dv[target_.face][1]; z += dv[target_.face][2]; }
  if (y < MIN_Y || y >= MAX_Y) return;
  if (!Blocks::get().info(world_->get_block(x, y, z)).replaceable()) return;
  if (Blocks::get().info(held).def && Blocks::get().info(held).def->kind == Kind::Torch && target_.face == DOWN) return;  // no ceiling torches
  BlockId id = placement_state(held, target_);
  if (!BlockUpdates::supported(*world_, id, x, y, z)) return;
  const BlockInfo& bi = Blocks::get().info(id);
  if (bi.nbox > 0 && bi.solid()) {
    AABB pb = player_.box();
    for (int i = 0; i < bi.nbox; i++) {
      AABB b{{x + bi.boxes[i].min[0], y + bi.boxes[i].min[1], z + bi.boxes[i].min[2]}, {x + bi.boxes[i].max[0], y + bi.boxes[i].max[1], z + bi.boxes[i].max[2]}};
      if (b.overlaps(pb)) return;
    }
  }
  world_->set_block(x, y, z, id);
  updates_->notify(x, y, z);
}

void Game::pick_block() {
  if (!target_.hit) return;
  BlockId id = world_->get_block(target_.x, target_.y, target_.z);
  const BlockInfo& bi = Blocks::get().info(id);
  BlockId base = Blocks::get().find(bi.name);
  if (!base) base = id;
  for (int i = 0; i < 9; i++)
    if (hotbar_[static_cast<size_t>(i)] == base) { select_slot(i); return; }
  hotbar_[static_cast<size_t>(selected_)] = base;
  name_timer_ = 2.0;
}

bool Game::world_settled() const {
  ChunkPos pc{floor_div(ifloor(player_.pos.x()), 16), floor_div(ifloor(player_.pos.z()), 16)};
  return world_->all_loaded_around(pc, radius_ + 1) && world_->inflight_count() == 0 && wr_->idle();
}

int g_script_failures = 0;

bool Game::run_script_action() {
  // Returns true when the action finished and the next one may start.
  if (!pending_shot_.empty()) return false;  // wait for the frame that will be captured
  if (script_wait_ > 0) { script_wait_--; return false; }
  if (script_idle_) {
    if (world_settled() || now_seconds() > idle_deadline_) {
      if (now_seconds() > idle_deadline_) log_warn("script: idle timeout");
      script_idle_ = false;
      script_wait_ = 2;  // let the last uploads reach the screen
    }
    return false;
  }
  if (forced_frames_ > 0) return false;
  if (script_ground_) {
    if (player_.on_ground || now_seconds() > ground_deadline_) { script_ground_ = false; script_wait_ = 2; }
    return false;
  }
  if (script_.empty()) return false;
  std::string line = script_.front();
  script_.pop_front();
  std::istringstream is(line);
  std::string cmd;
  is >> cmd;
  auto num = [&](double def = 0) { double v = def; is >> v; return v; };
  if (cmd == "wait") script_wait_ = static_cast<int>(num(1));
  else if (cmd == "ground") { script_ground_ = true; ground_deadline_ = now_seconds() + 30; }
  else if (cmd == "idle") { script_idle_ = true; idle_deadline_ = now_seconds() + 180; }
  else if (cmd == "shot") { is >> pending_shot_; }  // captured after the next frame is drawn
  else if (cmd == "tp") { double x = num(), y = num(), z = num(); player_.pos = {x, y, z}; player_.vel.setZero(); }
  else if (cmd == "setblock") {
    // setblock X Y Z name [key=value ...]  (values: integers, *_bit as bytes, otherwise strings)
    int x = static_cast<int>(num()), y = static_cast<int>(num()), z = static_cast<int>(num());
    std::string name;
    is >> name;
    StateMap st;
    std::string kv;
    while (is >> kv) {
      auto eq = kv.find('=');
      if (eq == std::string::npos) continue;
      std::string k = kv.substr(0, eq), v = kv.substr(eq + 1);
      bool numeric = !v.empty() && std::all_of(v.begin(), v.end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); });
      if (numeric) st.emplace_back(k, k.ends_with("_bit") ? StateValue::byte(std::stoi(v)) : StateValue::integer(std::stoi(v)));
      else st.emplace_back(k, StateValue::string(v));
    }
    BlockId id = 0;
    if (name != "air") {
      if (name.find(':') == std::string::npos) name = "minecraft:" + name;
      id = st.empty() ? Blocks::get().find(name) : Blocks::get().lookup_or_register(name, st);
    }
    if (world_->set_block(x, y, z, id)) updates_->notify(x, y, z);
    else if (!world_->column_loaded({floor_div(x, 16), floor_div(z, 16)})) log_warn("script: setblock outside loaded area");
  }
  else if (cmd == "nudge") { double x = num(), y = num(), z = num(); player_.pos += Eigen::Vector3d(x, y, z); player_.vel.setZero(); }
  else if (cmd == "mark") {
    if (!target_.hit) { log_info("script: mark FAIL (no target)"); g_script_failures++; }
    else { mark_[0] = target_.x; mark_[1] = target_.y; mark_[2] = target_.z; log_info("script: MARK {} {} {}", target_.x, target_.y, target_.z); }
  } else if (cmd == "assert_marked") {
    std::string want;
    is >> want;
    std::string got = Blocks::get().info(world_->get_block(mark_[0], mark_[1], mark_[2])).name;
    if (got.starts_with("minecraft:")) got.erase(0, 10);
    bool ok = got == want;
    log_info("script: assert_marked {} : {}", want, ok ? "PASS" : std::format("FAIL (got {})", got));
    if (!ok) g_script_failures++;
  }
  else if (cmd == "look") { double y = num(), p = num(); player_.yaw = static_cast<float>(y * 3.14159265 / 180); player_.pitch = static_cast<float>(p * 3.14159265 / 180); }
  else if (cmd == "break") break_block();
  else if (cmd == "place") place_block();
  else if (cmd == "select") select_slot(static_cast<int>(num()));
  else if (cmd == "time") world_ticks_ = static_cast<i64>(num());
  else if (cmd == "freeze") time_frozen_ = true;
  else if (cmd == "fly") { std::string v; is >> v; player_.flying = v == "on"; }
  else if (cmd == "walk") { MoveInput m; m.forward = static_cast<float>(num()); m.strafe = static_cast<float>(num()); forced_frames_ = static_cast<int>(num(1)); forced_input_ = m; }
  else if (cmd == "jump") { MoveInput m; m.jump = true; forced_frames_ = static_cast<int>(num(1)); forced_input_ = m; }
  else if (cmd == "inv") set_screen(screen_ == Screen::Inventory ? Screen::Playing : Screen::Inventory);
  else if (cmd == "radius") radius_ = clampv(static_cast<int>(num()), 2, 32);
  else if (cmd == "save") { save_all(true); }
  else if (cmd == "debug") show_debug_ = true;
  else if (cmd == "where") {
    log_info("script: pos {:.3f} {:.3f} {:.3f} yaw {:.1f} pitch {:.1f} ground {}", player_.pos.x(), player_.pos.y(), player_.pos.z(),
             player_.yaw * 57.29578f, player_.pitch * 57.29578f, player_.on_ground);
    if (target_.hit)
      log_info("script: target {} {} {} face {} = {}", target_.x, target_.y, target_.z, target_.face,
               Blocks::get().info(world_->get_block(target_.x, target_.y, target_.z)).name);
    else log_info("script: no target");
  } else if (cmd == "assert_hit") {
    log_info("script: assert_hit : {}", target_.hit ? "PASS" : "FAIL");
    if (!target_.hit) g_script_failures++;
  }
  else if (cmd == "quit") running_ = false;
  else if (cmd == "log") { std::string rest; std::getline(is, rest); log_info("script: {}", trim(rest)); }
  else if (cmd == "assert_block") {
    int x = static_cast<int>(num()), y = static_cast<int>(num()), z = static_cast<int>(num());
    std::string want;
    is >> want;
    BlockId id = world_->get_block(x, y, z);
    std::string got = Blocks::get().info(id).name;
    if (got.starts_with("minecraft:")) got.erase(0, 10);
    bool ok = got == want;
    log_info("script: assert_block {} {} {} == {} : {}", x, y, z, want, ok ? "PASS" : std::format("FAIL (got {})", got));
    if (!ok) g_script_failures++;
  } else if (cmd == "assert_target") {
    std::string want;
    is >> want;
    std::string got = target_.hit ? Blocks::get().info(world_->get_block(target_.x, target_.y, target_.z)).name : "none";
    if (got.starts_with("minecraft:")) got.erase(0, 10);
    bool ok = got == want;
    log_info("script: assert_target {} : {}", want, ok ? "PASS" : std::format("FAIL (got {})", got));
    if (!ok) g_script_failures++;
  } else if (cmd == "assert_ground") {
    log_info("script: assert_ground : {}", player_.on_ground ? "PASS" : "FAIL");
    if (!player_.on_ground) g_script_failures++;
  } else log_warn("script: unknown action '{}'", line);
  return true;
}

void Game::update(double dt) {
  // ---- loading screen
  if (screen_ == Screen::Loading) {
    world_->update(player_.pos.x(), player_.pos.z(), radius_);
    ChunkPos pc{floor_div(ifloor(player_.pos.x()), 16), floor_div(ifloor(player_.pos.z()), 16)};
    Camera c = cam_;
    c.pos = player_.eye();
    wr_->update(c, radius_);
    if (world_->neighbourhood_loaded(pc) && spawn_pending_) {
      if (!have_saved_player_ && !opt_.start_pos) {
        // Stand on the actual surface (trees/caves may differ from the height estimate).
        int x = ifloor(player_.pos.x()), z = ifloor(player_.pos.z());
        for (int y = MAX_Y - 1; y > MIN_Y; y--) {
          const BlockInfo& bi = Blocks::get().info(world_->get_block(x, y, z));
          if (bi.solid() && !(bi.flags & BF_Leaves)) { player_.pos.y() = y + 1.001; break; }
        }
      }
      spawn_pending_ = false;
      set_screen(Screen::Playing);
    }
    return;
  }

  // ---- script driver
  MoveInput scripted;
  bool use_script_input = false;
  if (!script_.empty() || script_wait_ > 0 || script_idle_ || script_ground_ || forced_frames_ > 0) {
    if (forced_frames_ > 0 && forced_input_) {
      scripted = *forced_input_;
      use_script_input = true;
      if (--forced_frames_ == 0) forced_input_.reset();
    } else {
      while (run_script_action()) {}
    }
  }

  const bool* keys = SDL_GetKeyboardState(nullptr);
  const bool playing = screen_ == Screen::Playing;

  if (playing) {
    const float sens = 0.0022f;
    player_.yaw += mouse_dx_ * sens;
    player_.pitch = clampv(player_.pitch + mouse_dy_ * sens, -1.553f, 1.553f);
  }
  mouse_dx_ = mouse_dy_ = 0;

  MoveInput in;
  if (playing) {
    in.forward = (keys[SDL_SCANCODE_W] ? 1.f : 0.f) - (keys[SDL_SCANCODE_S] ? 1.f : 0.f);
    in.strafe = (keys[SDL_SCANCODE_D] ? 1.f : 0.f) - (keys[SDL_SCANCODE_A] ? 1.f : 0.f);
    in.jump = keys[SDL_SCANCODE_SPACE];
    in.sneak = keys[SDL_SCANCODE_LSHIFT] || keys[SDL_SCANCODE_RSHIFT];
    bool w = keys[SDL_SCANCODE_W];
    double t = now_seconds();
    if (w && !prev_w_) { if (t - last_w_ < 0.3) sprint_latch_ = true; last_w_ = t; }
    if (!w) sprint_latch_ = false;
    prev_w_ = w;
    in.sprint = keys[SDL_SCANCODE_LCTRL] || sprint_latch_;
    bool sp = keys[SDL_SCANCODE_SPACE];
    if (sp && !prev_space_ && player_.creative) {
      if (t - last_space_ < 0.3) { player_.flying = !player_.flying; player_.vel.y() = 0; }
      last_space_ = t;
    }
    prev_space_ = sp;
  }
  if (use_script_input) in = scripted;

  // ---- fixed-step physics
  static double accum = 0;
  accum += dt;
  int steps = 0;
  while (accum >= 1.0 / 60.0 && steps < 6) {
    player_.update(1.0 / 60.0, in, *world_);
    accum -= 1.0 / 60.0;
    steps++;
  }
  if (steps == 6) accum = 0;
  if (player_.pos.y() < MIN_Y - 64) { player_.pos.y() = 200; player_.vel.setZero(); }

  // ---- 20 Hz game tick: block updates
  update_accum_ += dt;
  for (int i = 0; i < 4 && update_accum_ >= 0.05; i++) { updates_->tick(); update_accum_ -= 0.05; }
  if (update_accum_ > 0.2) update_accum_ = 0;

  // ---- time
  if (!time_frozen_) {
    tick_accum_ += dt * 20.0;
    i64 whole = static_cast<i64>(tick_accum_);
    world_ticks_ += whole;
    tick_accum_ -= static_cast<double>(whole);
  }

  // ---- camera & targeting
  cam_.pos = player_.eye();
  cam_.yaw = player_.yaw;
  cam_.pitch = player_.pitch;
  cam_.aspect = static_cast<float>(fb_w_) / static_cast<float>(std::max(fb_h_, 1));
  cam_.fovy = (fov_deg_ + (player_.sprinting ? 6.0f : 0.0f)) * 3.14159265f / 180.0f;
  cam_.zfar = std::max(160.0f, radius_ * 16.0f * 2.0f);
  {
    Eigen::Vector3f f = cam_.forward();
    target_ = raycast(*world_, cam_.pos, Eigen::Vector3d(f.x(), f.y(), f.z()), player_.creative ? 8.0 : 5.0);
  }

  // ---- interaction
  break_cd_ = std::max(0.0, break_cd_ - dt);
  place_cd_ = std::max(0.0, place_cd_ - dt);
  if (playing) {
    if (lmb_ && break_cd_ <= 0) { break_block(); break_cd_ = 0.2; }
    if (rmb_ && place_cd_ <= 0) { place_block(); place_cd_ = 0.2; }
  }
  name_timer_ = std::max(0.0, name_timer_ - dt);
  toast_timer_ = std::max(0.0, toast_timer_ - dt);

  particles_->update(dt, *world_);

  // ---- streaming
  world_->update(player_.pos.x(), player_.pos.z(), radius_);
  wr_->update(cam_, radius_);

  autosave_timer_ += dt;
  if (autosave_timer_ > 30.0) {
    autosave_timer_ = 0;
    save_all(false);
  }
}

// ------------------------------------------------------------------ rendering

void Game::take_screenshot(const std::string& path) {
  Image img = Image::make(fb_w_, fb_h_);
  gl::Finish();
  gl::PixelStorei(GL_PACK_ALIGNMENT, 1);
  gl::ReadPixels(0, 0, fb_w_, fb_h_, GL_RGBA, GL_UNSIGNED_BYTE, img.rgba.data());
  // Flip vertically and force opaque alpha.
  Image flipped = Image::make(fb_w_, fb_h_);
  for (int y = 0; y < fb_h_; y++) std::memcpy(flipped.px(0, y), img.px(0, fb_h_ - 1 - y), static_cast<size_t>(fb_w_) * 4);
  for (size_t i = 3; i < flipped.rgba.size(); i += 4) flipped.rgba[i] = 255;
  write_png_file(path, flipped);
}

void Game::render() {
  const TimeOfDay tod(world_ticks_);
  SkyState sky = SkyRenderer::make_state(tod, radius_ * 16.0f);
  sky.anim_tick = static_cast<float>(now_seconds() * 20.0);
  if (player_.eyes_in_water) {
    float l = 0.25f + 0.75f * sky.sky_light;
    sky.fog_color[0] = 0.05f * l; sky.fog_color[1] = 0.18f * l; sky.fog_color[2] = 0.45f * l;
    sky.fog_start = 0.0f;
    sky.fog_end = 28.0f;
  }
  gl::Viewport(0, 0, fb_w_, fb_h_);
  gl::ClearColor(sky.fog_color[0], sky.fog_color[1], sky.fog_color[2], 1.0f);
  gl::Clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
  gl::DepthMask(GL_TRUE);

  if (screen_ != Screen::Loading) {
    if (!player_.eyes_in_water) sky_->draw(cam_, tod, sky);
    wr_->draw_opaque(cam_, sky);
    if (target_.hit && screen_ == Screen::Playing)
      sky_->draw_box_outline(cam_, {target_.box_min[0], target_.box_min[1], target_.box_min[2]}, {target_.box_max[0], target_.box_max[1], target_.box_max[2]});
    wr_->draw_translucent(cam_, sky);
    particles_->draw(cam_, sky);
    if (!player_.eyes_in_water) clouds_->draw(cam_, sky, now_seconds());
  }

  ui_->begin(fb_w_, fb_h_);
  const float W = ui_->width(), H = ui_->height();
  if (screen_ == Screen::Loading) {
    std::string msg = "Generating terrain...";
    ui_->text(msg, std::floor((W - ui_->text_width(msg)) / 2), std::floor(H / 2 - 4));
    std::string sub = std::format("{} chunks loaded", world_->loaded_count());
    ui_->text(sub, std::floor((W - ui_->text_width(sub)) / 2), std::floor(H / 2 + 8), 0xFFAAAAAA);
  } else {
    if (player_.eyes_in_water) ui_->rect(0, 0, W, H, 0x502040C0);
    if (show_hud_) draw_hud(static_cast<int>(W), static_cast<int>(H));
    if (screen_ == Screen::Inventory) draw_inventory();
    if (screen_ == Screen::Pause) draw_pause();
  }
  ui_->end();
  if (!pending_shot_.empty()) {
    take_screenshot(pending_shot_);
    log_info("script: saved {}", pending_shot_);
    pending_shot_.clear();
  }
}

void Game::draw_hud(int w, int h) {
  Ui& ui = *ui_;
  const float cx = std::floor(w / 2.0f), cy = std::floor(h / 2.0f);
  if (screen_ == Screen::Playing) {
    if (ui.crosshair.valid()) ui.sprite(ui.crosshair, cx - 7, cy - 7, 15, 15, 0xFFFFFFFF);
    else { ui.rect(cx - 5, cy - 1, 11, 1, 0xC0FFFFFF); ui.rect(cx, cy - 6, 1, 11, 0xC0FFFFFF); }
  }
  // Hotbar
  const float hx = std::floor((w - 182) / 2.0f), hy = static_cast<float>(h - 22 - 1);
  if (ui.hotbar.valid()) ui.sprite(ui.hotbar, hx, hy, 182, 22);
  else {
    ui.rect(hx, hy, 182, 22, 0xA0000000);
    ui.outline(hx, hy, 182, 22, 0xFF555555);
    for (int i = 1; i < 9; i++) ui.rect(hx + i * 20, hy + 2, 1, 18, 0x60FFFFFF);
  }
  for (int i = 0; i < 9; i++) {
    BlockId id = hotbar_[static_cast<size_t>(i)];
    if (id) ui.block_icon(id, hx + 3 + i * 20, hy + 3, 16);
  }
  if (ui.hotbar_selection.valid()) ui.sprite(ui.hotbar_selection, hx - 1 + selected_ * 20, hy - 1, 24, 23);
  else ui.outline(hx + selected_ * 20, hy - 1, 24, 24, 0xFFFFFFFF, 2);

  if (name_timer_ > 0) {
    std::string n = block_display(hotbar_[static_cast<size_t>(selected_)]);
    u32 a = static_cast<u32>(clampv(name_timer_ / 0.5, 0.0, 1.0) * 255);
    ui.text(n, std::floor((w - ui.text_width(n)) / 2), hy - 14, (a << 24) | 0xFFFFFF);
  }
  if (toast_timer_ > 0) ui.text(toast_, 4, h - 12, 0xFFFFFF55);

  if (show_debug_) {
    const BlockInfo* tb = target_.hit ? &Blocks::get().info(world_->get_block(target_.x, target_.y, target_.z)) : nullptr;
    int bx = ifloor(player_.pos.x()), by = ifloor(player_.pos.y()), bz = ifloor(player_.pos.z());
    const Chunk* ch = world_->chunk({floor_div(bx, 16), floor_div(bz, 16)});
    u8 biome = ch ? ch->biome[col_index(floor_mod(bx, 16), floor_mod(bz, 16))] : 0;
    static const char* dirs[] = {"south (+Z)", "west (-X)", "north (-Z)", "east (+X)"};
    int di = static_cast<int>(std::floor(std::fmod(player_.yaw * 180.0f / 3.14159265f + 45.0f + 3600.0f, 360.0f) / 90.0f)) & 3;
    i64 dayt = world_ticks_ % 24000;
    std::vector<std::string> lines = {
        std::format("Deepslate Edition 0.1 ({:.0f} fps, {:.1f} ms)", fps_, frame_ms_),
        std::format("XYZ: {:.3f} / {:.3f} / {:.3f}", player_.pos.x(), player_.pos.y(), player_.pos.z()),
        std::format("Block: {} {} {}  Chunk: {} {} in {} {}", bx, by, bz, floor_mod(bx, 16), floor_mod(bz, 16), floor_div(bx, 16), floor_div(bz, 16)),
        std::format("Facing: {}  Biome id: {}", dirs[di], biome),
        std::format("Chunks: {} loaded, {} in flight, gen {} / disk {}, write queue {}", world_->loaded_count(), world_->inflight_count(),
                    world_->chunks_generated(), world_->chunks_loaded_from_disk(), world_->writer_queue()),
        std::format("Sections: {} ({} drawn, {}k quads), meshing {} / pending {}", wr_->stats.sections, wr_->stats.drawn, wr_->stats.quads / 1000,
                    wr_->stats.in_flight, wr_->stats.pending),
        std::format("Render distance: {}  Threads: {}  Time: {} ({})", radius_, pool_->size(), dayt, time_frozen_ ? "frozen" : "running"),
        std::format("Seed: {}  {}{}", store_->info().seed, player_.flying ? "flying " : "", player_.on_ground ? "on ground" : "airborne"),
    };
    if (tb) lines.push_back(std::format("Targeting: {} ({} {} {})", tb->name, target_.x, target_.y, target_.z));
    float y = 3;
    for (auto& l : lines) {
      float tw = ui.text_width(l);
      ui.rect(2, y - 1, tw + 3, 10, 0x60000000);
      ui.text(l, 3, y, 0xFFE0E0E0);
      y += 10;
    }
  }
}

void Game::draw_inventory() {
  Ui& ui = *ui_;
  const float W = ui.width(), H = ui.height();
  ui.rect(0, 0, W, H, 0x90000000);
  const float px = std::floor((W - 176) / 2), py = std::floor((H - 166) / 2);
  ui.rect(px, py, 176, 166, 0xFFC6C6C6);
  ui.outline(px, py, 176, 166, 0xFF000000);
  ui.text("Creative Inventory", px + 8, py + 6, 0xFF404040, false);
  float mx, my;
  SDL_GetMouseState(&mx, &my);
  const float density = SDL_GetWindowPixelDensity(win(window_));
  const float gx = mx * density / ui.scale(), gy = my * density / ui.scale();
  BlockId hovered = 0;
  for (int r = 0; r < 5; r++)
    for (int c = 0; c < 9; c++) {
      size_t idx = static_cast<size_t>((r + inv_scroll_) * 9 + c);
      float x = px + 8 + c * 18, y = py + 18 + r * 18;
      ui.rect(x, y, 18, 18, 0xFF8B8B8B);
      ui.rect(x + 1, y + 1, 17, 17, 0xFFDBDBDB);
      ui.rect(x + 1, y + 1, 16, 16, 0xFF8B8B8B);
      if (idx < creative_.size()) {
        ui.block_icon(creative_[idx], x + 1, y + 1, 16);
        if (gx >= x && gx < x + 18 && gy >= y && gy < y + 18) { ui.rect(x + 1, y + 1, 16, 16, 0x80FFFFFF); hovered = creative_[idx]; }
      }
    }
  int max_scroll = std::max(0, static_cast<int>((creative_.size() + 8) / 9) - 5);
  inv_scroll_ = std::min(inv_scroll_, max_scroll);
  if (max_scroll > 0) {
    float track = 90, thumb = std::max(8.0f, track * 5 / (max_scroll + 5));
    float ty = py + 18 + (track - thumb) * inv_scroll_ / max_scroll;
    ui.rect(px + 8 + 9 * 18 + 3, py + 18, 4, track, 0xFF8B8B8B);
    ui.rect(px + 8 + 9 * 18 + 3, ty, 4, thumb, 0xFF404040);
  }
  for (int i = 0; i < 9; i++) {
    float x = px + 8 + i * 18, y = py + 142;
    ui.rect(x, y, 18, 18, i == selected_ ? 0xFFFFFFFF : 0xFF373737);
    ui.rect(x + 1, y + 1, 16, 16, 0xFF8B8B8B);
    if (hotbar_[static_cast<size_t>(i)]) ui.block_icon(hotbar_[static_cast<size_t>(i)], x + 1, y + 1, 16);
  }
  ui.text("Click: set selected slot", px + 8, py + 112, 0xFF404040, false);
  ui.text("Right-click a slot: clear it", px + 8, py + 124, 0xFF404040, false);
  if (hovered) {
    std::string n = block_display(hovered);
    float tw = ui.text_width(n);
    ui.rect(gx + 6, gy - 14, tw + 6, 12, 0xF0100010);
    ui.text(n, gx + 9, gy - 12);
  }
}

void Game::draw_pause() {
  Ui& ui = *ui_;
  const float W = ui.width(), H = ui.height();
  ui.rect(0, 0, W, H, 0xA0000000);
  const float bx = std::floor((W - 200) / 2);
  std::string t = "Game Menu";
  ui.text(t, std::floor((W - ui.text_width(t)) / 2), H / 2 - 50);
  auto button = [&](float y, const char* label) {
    ui.rect(bx, y, 200, 20, 0xFF000000);
    ui.rect(bx + 1, y + 1, 198, 18, 0xFF6F6F6F);
    ui.rect(bx + 1, y + 1, 198, 1, 0xFFA0A0A0);
    ui.text(label, std::floor(bx + (200 - ui.text_width(label)) / 2), y + 6);
  };
  button(H / 2 - 24, "Back to Game");
  button(H / 2 + 4, "Save and Quit");
}

}  // namespace ds
