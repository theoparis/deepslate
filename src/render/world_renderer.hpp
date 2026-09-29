#pragma once
#include <unordered_map>
#include <unordered_set>

#include "render/camera.hpp"
#include "render/gl.hpp"
#include "render/mesher.hpp"
#include "util/thread_pool.hpp"
#include "world/world.hpp"

namespace ds {

struct SkyState {
  float sky_light = 1.0f;         // 0 (night) .. 1 (day): scales sky light on world geometry
  float fog_color[3] = {0.7f, 0.8f, 1.0f};
  float fog_start = 100, fog_end = 160;
  bool underwater = false;
};

class WorldRenderer {
 public:
  WorldRenderer(World& world, BlockModels& models, ThreadPool& pool);
  ~WorldRenderer();
  bool init(std::string* err);

  // Schedules meshing jobs and uploads finished meshes. `radius` is in chunks.
  void update(const Camera& cam, int radius);
  void draw_opaque(const Camera& cam, const SkyState& sky);
  void draw_translucent(const Camera& cam, const SkyState& sky);
  GLuint atlas_texture() const { return atlas_; }
  // True when no meshing work is queued, running or waiting to be uploaded.
  bool idle() const;

  struct Stats {
    size_t sections = 0, drawn = 0, quads = 0, pending = 0, in_flight = 0;
    u64 meshed = 0;
  } stats;

 private:
  struct SecKey {
    int x, y, z;
    bool operator==(const SecKey&) const = default;
  };
  struct SecHash {
    size_t operator()(const SecKey& k) const noexcept {
      return static_cast<size_t>(hash_coords(0x5EC, k.x, k.y, k.z));
    }
  };
  struct GpuMesh {
    GLuint vao = 0, vbo = 0;
    int quads = 0;
  };
  struct Section {
    GpuMesh opaque, trans;
    bool in_flight = false;
    bool dirty = false;
  };
  struct Result {
    SecKey key;
    std::shared_ptr<MeshData> data;
  };

  void upload_atlas();
  void upload_mesh(GpuMesh& m, const std::vector<Vertex>& v);
  void free_mesh(GpuMesh& m);
  void draw_pass(const Camera& cam, const SkyState& sky, bool translucent);
  void ensure_index_buffer(size_t quads);

  World& world_;
  BlockModels& models_;
  ThreadPool& pool_;
  GLuint program_ = 0, atlas_ = 0, ibo_ = 0;
  GLint u_viewproj_ = -1, u_offset_ = -1, u_fog_color_ = -1, u_fog_start_ = -1, u_fog_end_ = -1, u_sky_ = -1, u_cut_ = -1, u_tex_ = -1;
  size_t uploaded_layers_ = 0;
  size_t ibo_quads_ = 0;

  std::unordered_map<SecKey, Section, SecHash> sections_;
  std::unordered_map<u64, u32> pending_;  // chunk -> section mask still to be meshed
  std::mutex results_m_;
  std::vector<Result> results_;
  std::atomic<int> jobs_{0};
  int frame_ = 0;
  bool backlog_ = false;
};

}  // namespace ds
