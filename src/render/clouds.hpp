#pragma once
#include "assets/resource_pack.hpp"
#include "render/camera.hpp"
#include "render/gl.hpp"
#include "render/world_renderer.hpp"

namespace ds {

// Scrolling cloud layer built from a 256x256 alpha mask (textures/environment/clouds.png, or a
// procedural mask when the pack has none). Cells are 12x12 blocks, 4 blocks thick.
class Clouds {
 public:
  ~Clouds();
  bool init(const PackStack& packs, std::string* err);
  void draw(const Camera& cam, const SkyState& sky, double seconds);

  static constexpr float HEIGHT = 192.0f;
  static constexpr int CELL = 12;

 private:
  void rebuild(int ci, int cj);
  bool cell(int i, int j) const { return mask_[static_cast<size_t>(((j % N) + N) % N) * N + static_cast<size_t>(((i % N) + N) % N)]; }
  static constexpr int N = 256;
  static constexpr int R = 22;  // radius in cells

  struct V { float x, y, z, shade; };
  GLuint prog_ = 0, vao_ = 0, vbo_ = 0;
  std::vector<bool> mask_;
  std::vector<V> verts_;
  int built_i_ = INT32_MIN, built_j_ = INT32_MIN;
  int vert_count_ = 0;
};

}  // namespace ds
