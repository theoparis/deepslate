#pragma once
#include <vector>

#include "assets/block_models.hpp"
#include "render/camera.hpp"
#include "render/gl.hpp"
#include "render/world_renderer.hpp"
#include "world/world.hpp"

namespace ds {

// Small textured billboards: block-break debris.
class Particles {
 public:
  ~Particles();
  bool init(BlockModels& models, GLuint atlas, std::string* err);
  void emit_break(BlockId id, int x, int y, int z, Rng& rng);
  void update(double dt, const World& world);
  void draw(const Camera& cam, const SkyState& sky);
  size_t count() const { return list_.size(); }

 private:
  struct P {
    Eigen::Vector3d pos, vel;
    float life, size;
    float u0, v0, du;
    u16 layer;
    float r, g, b;
  };
  struct V { float x, y, z, u, v, layer, r, g, b, a; };
  BlockModels* models_ = nullptr;
  GLuint atlas_ = 0, prog_ = 0, vao_ = 0, vbo_ = 0;
  std::vector<P> list_;
  std::vector<V> verts_;
};

}  // namespace ds
