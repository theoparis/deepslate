#pragma once
#include "assets/resource_pack.hpp"
#include "render/camera.hpp"
#include "render/gl.hpp"
#include "render/world_renderer.hpp"

namespace ds {

// World time helpers (Bedrock day length: 24000 ticks, 0 = sunrise, 6000 = noon).
struct TimeOfDay {
  explicit TimeOfDay(i64 ticks) : ticks(ticks) {}
  i64 ticks;
  float sun_angle() const { return 2.0f * 3.14159265f * (static_cast<float>(ticks % 24000) - 6000.0f) / 24000.0f; }
  Eigen::Vector3f sun_dir() const { float a = sun_angle(); return {-std::sin(a), std::cos(a), 0.0f}; }
};

class SkyRenderer {
 public:
  ~SkyRenderer();
  bool init(const PackStack& packs, std::string* err);
  // Fills fog/sky-light fields for this time of day.
  static SkyState make_state(const TimeOfDay& t, float render_distance_blocks);
  void draw(const Camera& cam, const TimeOfDay& t, const SkyState& sky);
  void draw_box_outline(const Camera& cam, const Eigen::Vector3d& mn, const Eigen::Vector3d& mx, float alpha = 0.9f);

 private:
  struct V { float x, y, z, u, v; float r, g, b, a; };
  void flush_quads(const Camera& cam, GLuint tex, bool textured);
  void draw_lines(const Camera& cam);
  GLuint make_tex(const std::string& path, const PackStack& packs, int* w, int* h);

  GLuint dome_prog_ = 0, quad_prog_ = 0, vao_ = 0, vbo_ = 0, sun_tex_ = 0, moon_tex_ = 0, empty_vao_ = 0;
  int sun_w_ = 0, moon_w_ = 0, moon_h_ = 0;
  std::vector<V> verts_;
  std::vector<V> lines_;
  std::vector<Eigen::Vector3f> stars_;
};

}  // namespace ds
