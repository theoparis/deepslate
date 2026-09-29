#include "render/particles.hpp"

namespace ds {

namespace {
const char* kVS = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aUVL;
layout(location=2) in vec4 aCol;
uniform mat4 uVP;
out vec3 vUVL; out vec4 vCol; out float vDist;
void main() { gl_Position = uVP * vec4(aPos, 1.0); vUVL = aUVL; vCol = aCol; vDist = length(aPos); }
)";
const char* kFS = R"(#version 330 core
in vec3 vUVL; in vec4 vCol; in float vDist;
uniform sampler2DArray uTex;
uniform vec3 uFogColor;
uniform float uFogStart, uFogEnd;
out vec4 oColor;
void main() {
  vec4 t = texture(uTex, vUVL);
  if (t.a < 0.3) discard;
  float f = clamp((vDist - uFogStart) / max(uFogEnd - uFogStart, 0.001), 0.0, 1.0);
  oColor = vec4(mix(t.rgb * vCol.rgb, uFogColor, f), 1.0);
}
)";
}  // namespace

Particles::~Particles() {
  if (prog_) gl::DeleteProgram(prog_);
  if (vao_) gl::DeleteVertexArrays(1, &vao_);
  if (vbo_) gl::DeleteBuffers(1, &vbo_);
}

bool Particles::init(BlockModels& models, GLuint atlas, std::string* err) {
  models_ = &models;
  atlas_ = atlas;
  prog_ = gl::make_program(kVS, kFS, err);
  if (!prog_) return false;
  gl::GenVertexArrays(1, &vao_);
  gl::GenBuffers(1, &vbo_);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::EnableVertexAttribArray(0);
  gl::VertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, x)));
  gl::EnableVertexAttribArray(1);
  gl::VertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, u)));
  gl::EnableVertexAttribArray(2);
  gl::VertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, r)));
  gl::BindVertexArray(0);
  return true;
}

void Particles::emit_break(BlockId id, int x, int y, int z, Rng& rng) {
  const BlockInfo& bi = Blocks::get().info(id);
  BlockModels::Icon ic = models_->icon(id);
  u16 layer = ic.left ? ic.left : ic.top;
  if (bi.liquid()) return;
  u32 tint = bi.tint != Tint::None ? models_->tint_color(bi.tint, Biome::Plains) : 0xFFFFFF;
  // Grass debris is dirt-coloured.
  if (bi.def && bi.def->kind == Kind::Grass) tint = 0xFFFFFF;
  for (int i = 0; i < 24 && list_.size() < 4000; i++) {
    P p;
    p.pos = {x + 0.1 + rng.unit() * 0.8, y + 0.1 + rng.unit() * 0.8, z + 0.1 + rng.unit() * 0.8};
    p.vel = {(rng.unit() - 0.5) * 3.2, rng.unit() * 2.6 + 0.4, (rng.unit() - 0.5) * 3.2};
    p.life = 0.5f + rng.unit() * 0.7f;
    p.size = 0.07f + rng.unit() * 0.06f;
    p.du = 0.25f;
    p.u0 = static_cast<float>(rng.range(0, 3)) * 0.25f;
    p.v0 = static_cast<float>(rng.range(0, 3)) * 0.25f;
    p.layer = layer;
    const float sh = 0.75f + rng.unit() * 0.25f;
    p.r = ((tint >> 16) & 255) / 255.0f * sh;
    p.g = ((tint >> 8) & 255) / 255.0f * sh;
    p.b = (tint & 255) / 255.0f * sh;
    list_.push_back(p);
  }
}

void Particles::update(double dt, const World& world) {
  for (size_t i = 0; i < list_.size();) {
    P& p = list_[i];
    p.life -= static_cast<float>(dt);
    if (p.life <= 0) { list_[i] = list_.back(); list_.pop_back(); continue; }
    p.vel.y() -= 22.0 * dt;
    Eigen::Vector3d np = p.pos + p.vel * dt;
    BlockId b = world.get_block(ifloor(np.x()), ifloor(np.y()), ifloor(np.z()));
    if (b && Blocks::get().info(b).solid()) {
      // Bounce/slide on the way out: cancel velocity on the axis that entered the block.
      if (world.get_block(ifloor(np.x()), ifloor(p.pos.y()), ifloor(p.pos.z())) && Blocks::get().info(world.get_block(ifloor(np.x()), ifloor(p.pos.y()), ifloor(p.pos.z()))).solid()) p.vel.x() = 0;
      else if (world.get_block(ifloor(p.pos.x()), ifloor(p.pos.y()), ifloor(np.z())) && Blocks::get().info(world.get_block(ifloor(p.pos.x()), ifloor(p.pos.y()), ifloor(np.z()))).solid()) p.vel.z() = 0;
      else { p.vel.y() = 0; p.vel.x() *= 0.6; p.vel.z() *= 0.6; }
      np = p.pos + p.vel * dt;
    }
    p.pos = np;
    ++i;
  }
}

void Particles::draw(const Camera& cam, const SkyState& sky) {
  if (list_.empty()) return;
  Eigen::Vector3f f = cam.forward();
  Eigen::Vector3f right = f.cross(Eigen::Vector3f::UnitY()).normalized();
  Eigen::Vector3f up = right.cross(f);
  verts_.clear();
  const float br = 0.25f + 0.75f * sky.sky_light;
  for (const P& p : list_) {
    Eigen::Vector3f c = (p.pos - cam.pos).cast<float>();
    Eigen::Vector3f a = right * p.size, b = up * p.size;
    Eigen::Vector3f v[4] = {c - a - b, c + a - b, c + a + b, c - a + b};
    const float uv[4][2] = {{p.u0, p.v0 + p.du}, {p.u0 + p.du, p.v0 + p.du}, {p.u0 + p.du, p.v0}, {p.u0, p.v0}};
    for (int k : {0, 1, 2, 0, 2, 3})
      verts_.push_back({v[k].x(), v[k].y(), v[k].z(), uv[k][0], uv[k][1], static_cast<float>(p.layer), p.r * br, p.g * br, p.b * br, 1.0f});
  }
  gl::Enable(GL_DEPTH_TEST);
  gl::DepthFunc(GL_LEQUAL);
  gl::Disable(GL_CULL_FACE);
  gl::Disable(GL_BLEND);
  gl::UseProgram(prog_);
  Eigen::Matrix4f vp = cam.view_proj();
  auto U = [&](const char* n) { return gl::GetUniformLocation(prog_, n); };
  gl::UniformMatrix4fv(U("uVP"), 1, GL_FALSE, vp.data());
  gl::Uniform1i(U("uTex"), 0);
  gl::Uniform3f(U("uFogColor"), sky.fog_color[0], sky.fog_color[1], sky.fog_color[2]);
  gl::Uniform1f(U("uFogStart"), sky.fog_start);
  gl::Uniform1f(U("uFogEnd"), sky.fog_end);
  gl::ActiveTexture(GL_TEXTURE0);
  gl::BindTexture(GL_TEXTURE_2D_ARRAY, atlas_);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(verts_.size() * sizeof(V)), verts_.data(), GL_STREAM_DRAW);
  gl::DrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(verts_.size()));
  gl::BindVertexArray(0);
}

}  // namespace ds
