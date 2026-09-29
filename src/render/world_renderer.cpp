#include "render/world_renderer.hpp"

#include <thread>

namespace ds {

namespace {

const char* kVS = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec2 aUV;
layout(location=2) in float aLayer;
layout(location=3) in vec4 aCol;
layout(location=4) in vec2 aLight;
uniform mat4 uViewProj;
uniform vec3 uOffset;
out vec2 vUV;
flat out float vLayer;
out vec4 vCol;
out vec2 vLight;
out float vDist;
void main() {
  vec3 p = aPos + uOffset;
  gl_Position = uViewProj * vec4(p, 1.0);
  vUV = aUV; vLayer = aLayer; vCol = aCol; vLight = aLight;
  vDist = length(p);
}
)";

const char* kFS = R"(#version 330 core
in vec2 vUV;
flat in float vLayer;
in vec4 vCol;
in vec2 vLight;
in float vDist;
uniform sampler2DArray uTex;
uniform vec3 uFogColor;
uniform float uFogStart;
uniform float uFogEnd;
uniform float uSky;
uniform float uCut;
out vec4 oColor;
void main() {
  vec4 t = texture(uTex, vec3(vUV, vLayer));
  if (t.a < uCut) discard;
  float l = max(vLight.x * uSky, vLight.y);
  float b = mix(0.035, 1.0, l * l * (0.35 + 0.65 * l));
  vec3 c = t.rgb * vCol.rgb * b;
  float f = clamp((vDist - uFogStart) / max(uFogEnd - uFogStart, 0.001), 0.0, 1.0);
  oColor = vec4(mix(c, uFogColor, f), t.a * vCol.a);
#ifdef DEBUG_LIGHT
  oColor = vec4(vLight.x, vLight.y, 0.0, 1.0);
#endif
#ifdef DEBUG_COL
  oColor = vec4(vCol.rgb, 1.0);
#endif
}
)";

}  // namespace

WorldRenderer::WorldRenderer(World& world, BlockModels& models, ThreadPool& pool) : world_(world), models_(models), pool_(pool) {}

WorldRenderer::~WorldRenderer() {
  while (jobs_.load() > 0) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  for (auto& [k, s] : sections_) { free_mesh(s.opaque); free_mesh(s.trans); }
  if (ibo_) gl::DeleteBuffers(1, &ibo_);
  if (atlas_) gl::DeleteTextures(1, &atlas_);
  if (program_) gl::DeleteProgram(program_);
}

bool WorldRenderer::init(std::string* err) {
  program_ = gl::make_program(kVS, kFS, err);
  if (!program_) return false;
  u_viewproj_ = gl::GetUniformLocation(program_, "uViewProj");
  u_offset_ = gl::GetUniformLocation(program_, "uOffset");
  u_fog_color_ = gl::GetUniformLocation(program_, "uFogColor");
  u_fog_start_ = gl::GetUniformLocation(program_, "uFogStart");
  u_fog_end_ = gl::GetUniformLocation(program_, "uFogEnd");
  u_sky_ = gl::GetUniformLocation(program_, "uSky");
  u_cut_ = gl::GetUniformLocation(program_, "uCut");
  u_tex_ = gl::GetUniformLocation(program_, "uTex");

  gl::GenTextures(1, &atlas_);
  gl::BindTexture(GL_TEXTURE_2D_ARRAY, atlas_);
  const int T = models_.tile_size();
  gl::TexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA8, T, T, models_.capacity(), 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  int levels = 0;
  for (int s = T; s > 1 && levels < 4; s >>= 1) levels++;
  gl::TexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAX_LEVEL, levels);
  gl::TexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_LINEAR);
  gl::TexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  gl::TexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT);
  gl::TexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT);
  upload_atlas();
  ensure_index_buffer(8192);
  return true;
}

void WorldRenderer::upload_atlas() {
  size_t n = models_.layer_count();
  if (n == uploaded_layers_) return;
  std::vector<u8> px;
  models_.copy_layers(uploaded_layers_, px);
  const int T = models_.tile_size();
  n = uploaded_layers_ + px.size() / (static_cast<size_t>(T) * T * 4);
  gl::BindTexture(GL_TEXTURE_2D_ARRAY, atlas_);
  gl::PixelStorei(GL_UNPACK_ALIGNMENT, 1);
  gl::TexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, static_cast<GLint>(uploaded_layers_), T, T, static_cast<GLsizei>(n - uploaded_layers_),
                    GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  gl::GenerateMipmap(GL_TEXTURE_2D_ARRAY);
  uploaded_layers_ = n;
}

void WorldRenderer::ensure_index_buffer(size_t quads) {
  if (quads <= ibo_quads_) return;
  size_t cap = std::max<size_t>(quads, ibo_quads_ * 2);
  std::vector<u32> idx(cap * 6);
  for (size_t q = 0; q < cap; q++) {
    u32 b = static_cast<u32>(q * 4);
    u32* p = &idx[q * 6];
    p[0] = b; p[1] = b + 1; p[2] = b + 2; p[3] = b + 2; p[4] = b + 3; p[5] = b;
  }
  if (!ibo_) gl::GenBuffers(1, &ibo_);
  gl::BindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo_);
  gl::BufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(idx.size() * sizeof(u32)), idx.data(), GL_STATIC_DRAW);
  ibo_quads_ = cap;
}

void WorldRenderer::free_mesh(GpuMesh& m) {
  if (m.vao) gl::DeleteVertexArrays(1, &m.vao);
  if (m.vbo) gl::DeleteBuffers(1, &m.vbo);
  m = {};
}

void WorldRenderer::upload_mesh(GpuMesh& m, const std::vector<Vertex>& v) {
  if (v.empty()) { free_mesh(m); return; }
  size_t quads = v.size() / 4;
  ensure_index_buffer(quads);
  if (!m.vao) {
    gl::GenVertexArrays(1, &m.vao);
    gl::GenBuffers(1, &m.vbo);
    gl::BindVertexArray(m.vao);
    gl::BindBuffer(GL_ARRAY_BUFFER, m.vbo);
    gl::BindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo_);
    const GLsizei stride = sizeof(Vertex);
    gl::EnableVertexAttribArray(0);
    gl::VertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(offsetof(Vertex, x)));
    gl::EnableVertexAttribArray(1);
    gl::VertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(offsetof(Vertex, u)));
    gl::EnableVertexAttribArray(2);
    gl::VertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(offsetof(Vertex, layer)));
    gl::EnableVertexAttribArray(3);
    gl::VertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE, stride, reinterpret_cast<void*>(offsetof(Vertex, r)));
    gl::EnableVertexAttribArray(4);
    gl::VertexAttribPointer(4, 2, GL_UNSIGNED_BYTE, GL_TRUE, stride, reinterpret_cast<void*>(offsetof(Vertex, sky)));
  }
  gl::BindBuffer(GL_ARRAY_BUFFER, m.vbo);
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(v.size() * sizeof(Vertex)), v.data(), GL_STATIC_DRAW);
  m.quads = static_cast<int>(quads);
}

void WorldRenderer::update(const Camera& cam, int radius) {
  frame_++;
  upload_atlas();

  // 1. Collect world changes.
  {
    std::vector<DirtyChunk> dirty;
    world_.take_dirty(dirty);
    for (auto& d : dirty) pending_[pack_chunk(d.pos)] |= d.mask;
  }

  const int pcx = floor_div(ifloor(cam.pos.x()), 16), pcz = floor_div(ifloor(cam.pos.z()), 16);

  // 2. Upload finished meshes (time-boxed).
  {
    std::vector<Result> done;
    {
      std::lock_guard lk(results_m_);
      done.swap(results_);
    }
    const double t0 = now_seconds();
    size_t i = 0;
    for (; i < done.size(); i++) {
      Result& r = done[i];
      auto it = sections_.find(r.key);
      if (it != sections_.end()) {
        Section& s = it->second;
        s.in_flight = false;
        upload_mesh(s.opaque, r.data->opaque);
        upload_mesh(s.trans, r.data->translucent);
        stats.meshed++;
      }
      if (now_seconds() - t0 > 0.004) { i++; break; }
    }
    if (i < done.size()) {
      std::lock_guard lk(results_m_);
      results_.insert(results_.begin(), std::make_move_iterator(done.begin() + static_cast<std::ptrdiff_t>(i)), std::make_move_iterator(done.end()));
    }
  }

  // 3. Schedule meshing, nearest columns first.
  struct Col { u64 key; ChunkPos pos; int d2; };
  std::vector<Col> cols;
  cols.reserve(pending_.size());
  for (auto& [k, mask] : pending_) {
    ChunkPos p{static_cast<i32>(k >> 32), static_cast<i32>(k & 0xFFFFFFFFu)};
    int dx = p.x - pcx, dz = p.z - pcz;
    cols.push_back({k, p, dx * dx + dz * dz});
  }
  std::sort(cols.begin(), cols.end(), [](const Col& a, const Col& b) { return a.d2 < b.d2; });
  const int max_jobs = static_cast<int>(pool_.size()) * 2 + 2;
  int submitted = 0;
  backlog_ = false;
  for (const Col& c : cols) {
    u32& mask = pending_[c.key];
    if (c.d2 > radius * radius + 2) continue;  // outside view range: keep pending
    if (!world_.neighbourhood_loaded(c.pos)) continue;
    const Chunk* chunk = world_.chunk(c.pos);
    if (!chunk) { pending_.erase(c.key); continue; }
    for (int si = 0; si < NUM_SUBS; si++) {
      if (!(mask & (1u << si))) continue;
      SecKey key{c.pos.x, si, c.pos.z};
      Section& sec = sections_[key];
      if (sec.in_flight) { sec.dirty = true; continue; }  // re-queued when the current job returns
      if (!chunk->subs[static_cast<size_t>(si)]) {
        // Empty sub-chunk: nothing to draw.
        free_mesh(sec.opaque); free_mesh(sec.trans);
        mask &= ~(1u << si);
        continue;
      }
      if (jobs_.load() >= max_jobs || submitted >= 64) { backlog_ = true; goto scheduled_enough; }
      auto in = std::make_shared<MeshInput>();
      world_.snapshot3x3(c.pos, in->chunks);
      in->section = si;
      sec.in_flight = true;
      sec.dirty = false;
      mask &= ~(1u << si);
      jobs_++;
      submitted++;
      pool_.submit(c.d2, [this, in, key] {
        auto data = std::make_shared<MeshData>();
        mesh_section(*in, models_, *data);
        {
          std::lock_guard lk(results_m_);
          results_.push_back({key, std::move(data)});
        }
        jobs_--;
      });
    }
    if (mask == 0) pending_.erase(c.key);
  }
scheduled_enough:

  // 4. Drop sections whose chunks are far away or gone.
  if (frame_ % 30 == 0) {
    const int keep = radius + 3;
    for (auto it = sections_.begin(); it != sections_.end();) {
      int dx = it->first.x - pcx, dz = it->first.z - pcz;
      if ((dx * dx + dz * dz > keep * keep || !world_.column_loaded({it->first.x, it->first.z})) && !it->second.in_flight) {
        free_mesh(it->second.opaque);
        free_mesh(it->second.trans);
        it = sections_.erase(it);
      } else {
        ++it;
      }
    }
    for (auto it = pending_.begin(); it != pending_.end();) {
      ChunkPos p{static_cast<i32>(it->first >> 32), static_cast<i32>(it->first & 0xFFFFFFFFu)};
      if (!world_.column_loaded(p)) it = pending_.erase(it);
      else ++it;
    }
  }
  stats.sections = sections_.size();
  stats.pending = pending_.size();
  stats.in_flight = static_cast<size_t>(jobs_.load());
}

bool WorldRenderer::idle() const {
  if (jobs_.load() > 0 || backlog_) return false;
  std::lock_guard lk(const_cast<std::mutex&>(results_m_));
  return results_.empty();
}

void WorldRenderer::draw_pass(const Camera& cam, const SkyState& sky, bool translucent) {
  gl::UseProgram(program_);
  Eigen::Matrix4f vp = cam.view_proj();
  gl::UniformMatrix4fv(u_viewproj_, 1, GL_FALSE, vp.data());
  gl::Uniform3f(u_fog_color_, sky.fog_color[0], sky.fog_color[1], sky.fog_color[2]);
  gl::Uniform1f(u_fog_start_, sky.fog_start);
  gl::Uniform1f(u_fog_end_, sky.fog_end);
  gl::Uniform1f(u_sky_, sky.sky_light);
  gl::Uniform1f(u_cut_, translucent ? 0.02f : 0.12f);
  gl::Uniform1i(u_tex_, 0);
  gl::ActiveTexture(GL_TEXTURE0);
  gl::BindTexture(GL_TEXTURE_2D_ARRAY, atlas_);

  Camera::Frustum fr = cam.frustum();
  struct Item { const GpuMesh* m; Eigen::Vector3f off; float d2; };
  static thread_local std::vector<Item> items;
  items.clear();
  size_t drawn = 0, quads = 0;
  for (auto& [key, sec] : sections_) {
    const GpuMesh& m = translucent ? sec.trans : sec.opaque;
    if (!m.vao) continue;
    Eigen::Vector3f off(static_cast<float>(key.x * 16.0 - cam.pos.x()), static_cast<float>((key.y + MIN_SUB) * 16.0 - cam.pos.y()),
                        static_cast<float>(key.z * 16.0 - cam.pos.z()));
    if (!fr.intersects(off, off + Eigen::Vector3f(16, 16, 16))) continue;
    items.push_back({&m, off, (off + Eigen::Vector3f(8, 8, 8)).squaredNorm()});
  }
  if (translucent) std::sort(items.begin(), items.end(), [](const Item& a, const Item& b) { return a.d2 > b.d2; });
  for (const Item& it : items) {
    gl::Uniform3f(u_offset_, it.off.x(), it.off.y(), it.off.z());
    gl::BindVertexArray(it.m->vao);
    gl::DrawElements(GL_TRIANGLES, it.m->quads * 6, GL_UNSIGNED_INT, nullptr);
    drawn++;
    quads += static_cast<size_t>(it.m->quads);
  }
  if (!translucent) { stats.drawn = drawn; stats.quads = quads; }
  gl::BindVertexArray(0);
}

void WorldRenderer::draw_opaque(const Camera& cam, const SkyState& sky) {
  gl::Enable(GL_DEPTH_TEST);
  gl::DepthFunc(GL_LEQUAL);
  gl::Enable(GL_CULL_FACE);
  gl::CullFace(GL_BACK);
  gl::FrontFace(GL_CCW);
  gl::Disable(GL_BLEND);
  draw_pass(cam, sky, false);
}

void WorldRenderer::draw_translucent(const Camera& cam, const SkyState& sky) {
  gl::Enable(GL_DEPTH_TEST);
  gl::DepthFunc(GL_LEQUAL);
  gl::Disable(GL_CULL_FACE);
  gl::Enable(GL_BLEND);
  gl::BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  gl::DepthMask(GL_FALSE);
  draw_pass(cam, sky, true);
  gl::DepthMask(GL_TRUE);
  gl::Disable(GL_BLEND);
}

}  // namespace ds
