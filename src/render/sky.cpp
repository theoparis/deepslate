#include "render/sky.hpp"

#include "assets/image.hpp"

namespace ds {

namespace {

const char* kDomeVS = R"(#version 330 core
out vec2 vNdc;
void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  vNdc = p * 2.0 - 1.0;
  gl_Position = vec4(vNdc, 0.999, 1.0);
}
)";
const char* kDomeFS = R"(#version 330 core
in vec2 vNdc;
uniform vec3 uFwd, uRight, uUp;
uniform float uTanHalf, uAspect;
uniform vec3 uZenith, uHorizon, uGlowColor, uSunDir;
uniform float uGlow;
out vec4 oColor;
void main() {
  vec3 d = normalize(uFwd + uRight * (vNdc.x * uTanHalf * uAspect) + uUp * (vNdc.y * uTanHalf));
  float h = clamp(d.y, -1.0, 1.0);
  vec3 c = mix(uHorizon, uZenith, pow(clamp(h, 0.0, 1.0), 0.55));
  if (h < 0.0) c = mix(uHorizon, uHorizon * 0.85, clamp(-h * 3.0, 0.0, 1.0));
  float g = pow(max(dot(d, uSunDir), 0.0), 6.0) * uGlow * (1.0 - clamp(abs(h) * 1.2, 0.0, 1.0));
  c = mix(c, uGlowColor, clamp(g, 0.0, 0.85));
  oColor = vec4(c, 1.0);
}
)";
const char* kQuadVS = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec2 aUV;
layout(location=2) in vec4 aCol;
uniform mat4 uVP;
out vec2 vUV; out vec4 vCol;
void main() { gl_Position = uVP * vec4(aPos, 1.0); vUV = aUV; vCol = aCol; }
)";
const char* kQuadFS = R"(#version 330 core
in vec2 vUV; in vec4 vCol;
uniform sampler2D uTex;
uniform int uTextured;
out vec4 oColor;
void main() {
  vec4 t = uTextured != 0 ? texture(uTex, vUV) : vec4(1.0);
  oColor = t * vCol;
}
)";

float smoothstepf(float a, float b, float x) {
  float t = clampv((x - a) / (b - a), 0.0f, 1.0f);
  return t * t * (3 - 2 * t);
}

}  // namespace

SkyRenderer::~SkyRenderer() {
  if (dome_prog_) gl::DeleteProgram(dome_prog_);
  if (quad_prog_) gl::DeleteProgram(quad_prog_);
  if (vao_) gl::DeleteVertexArrays(1, &vao_);
  if (empty_vao_) gl::DeleteVertexArrays(1, &empty_vao_);
  if (vbo_) gl::DeleteBuffers(1, &vbo_);
  if (sun_tex_) gl::DeleteTextures(1, &sun_tex_);
  for (GLuint t : moon_tex_) if (t) gl::DeleteTextures(1, &t);
  if (moon_sheet_) gl::DeleteTextures(1, &moon_sheet_);
}

GLuint SkyRenderer::make_tex(const std::string& path, const PackStack& packs, int* w, int* h) {
  auto data = packs.read("assets/minecraft/textures/" + path + ".png");
  if (!data) return 0;
  auto img = decode_png(*data);
  if (!img) return 0;
  GLuint t;
  gl::GenTextures(1, &t);
  gl::BindTexture(GL_TEXTURE_2D, t);
  gl::PixelStorei(GL_UNPACK_ALIGNMENT, 1);
  gl::TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, img->w, img->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, img->rgba.data());
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  *w = img->w;
  *h = img->h;
  return t;
}

bool SkyRenderer::init(const PackStack& packs, std::string* err) {
  dome_prog_ = gl::make_program(kDomeVS, kDomeFS, err);
  if (!dome_prog_) return false;
  quad_prog_ = gl::make_program(kQuadVS, kQuadFS, err);
  if (!quad_prog_) return false;
  gl::GenVertexArrays(1, &empty_vao_);
  gl::GenVertexArrays(1, &vao_);
  gl::GenBuffers(1, &vbo_);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::EnableVertexAttribArray(0);
  gl::VertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, x)));
  gl::EnableVertexAttribArray(1);
  gl::VertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, u)));
  gl::EnableVertexAttribArray(2);
  gl::VertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, r)));
  gl::BindVertexArray(0);

  for (const char* p : {"environment/sun", "environment/celestial/sun"})
    if (!sun_tex_) sun_tex_ = make_tex(p, packs, &sun_w_, &moon_h_);
  // Moon: eight per-phase files (26.x) in the order the game cycles them, else the legacy 4x2 sheet.
  static const char* phases[8] = {"full_moon", "waning_gibbous", "third_quarter", "waning_crescent", "new_moon", "waxing_crescent", "first_quarter", "waxing_gibbous"};
  for (int i = 0; i < 8; i++) moon_tex_[i] = make_tex(std::string("environment/celestial/moon/") + phases[i], packs, &moon_w_, &moon_h_);
  if (!moon_tex_[0]) moon_sheet_ = make_tex("environment/moon_phases", packs, &moon_w_, &moon_h_);

  Rng rng(0xC0FFEE);
  for (int i = 0; i < 400; i++) {
    float z = rng.unit() * 2 - 1, a = rng.unit() * 6.2831853f;
    float r = std::sqrt(1 - z * z);
    stars_.emplace_back(r * std::cos(a), z, r * std::sin(a));
  }
  return true;
}

SkyState SkyRenderer::make_state(const TimeOfDay& t, float dist) {
  SkyState s;
  Eigen::Vector3f sun = t.sun_dir();
  float day = smoothstepf(-0.18f, 0.22f, sun.y());
  s.sky_light = lerp(0.13f, 1.0f, day);
  const Eigen::Vector3f hd(0.72f, 0.83f, 1.0f), hn(0.03f, 0.04f, 0.09f);
  Eigen::Vector3f h = hn + (hd - hn) * day;
  // Sunrise/sunset tint on the horizon.
  float twilight = std::max(0.0f, 1.0f - std::abs(sun.y()) * 4.5f);
  Eigen::Vector3f warm(0.95f, 0.55f, 0.35f);
  h = h + (warm - h) * (twilight * 0.55f);
  s.fog_color[0] = h.x(); s.fog_color[1] = h.y(); s.fog_color[2] = h.z();
  s.fog_start = dist * 0.55f;
  s.fog_end = dist * 0.98f;
  return s;
}

void SkyRenderer::flush_quads(const Camera& cam, GLuint tex, bool textured) {
  if (verts_.empty()) return;
  gl::UseProgram(quad_prog_);
  Eigen::Matrix4f vp = cam.view_proj();
  gl::UniformMatrix4fv(gl::GetUniformLocation(quad_prog_, "uVP"), 1, GL_FALSE, vp.data());
  gl::Uniform1i(gl::GetUniformLocation(quad_prog_, "uTextured"), textured && tex ? 1 : 0);
  gl::Uniform1i(gl::GetUniformLocation(quad_prog_, "uTex"), 0);
  gl::ActiveTexture(GL_TEXTURE0);
  gl::BindTexture(GL_TEXTURE_2D, tex);
  static std::vector<V> tri;
  tri.clear();
  for (size_t i = 0; i + 3 < verts_.size(); i += 4)
    for (int k : {0, 1, 2, 2, 3, 0}) tri.push_back(verts_[i + static_cast<size_t>(k)]);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(tri.size() * sizeof(V)), tri.data(), GL_STREAM_DRAW);
  gl::DrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(tri.size()));
  gl::BindVertexArray(0);
  verts_.clear();
}

void SkyRenderer::draw(const Camera& cam, const TimeOfDay& t, const SkyState& sky) {
  Eigen::Vector3f sun = t.sun_dir();
  float day = smoothstepf(-0.18f, 0.22f, sun.y());
  gl::Disable(GL_DEPTH_TEST);
  gl::Disable(GL_CULL_FACE);
  gl::Disable(GL_BLEND);

  // ---- gradient dome
  {
    Eigen::Vector3f f = cam.forward();
    Eigen::Vector3f r = f.cross(Eigen::Vector3f::UnitY()).normalized();
    Eigen::Vector3f u = r.cross(f);
    Eigen::Vector3f zen_d(0.39f, 0.60f, 0.98f), zen_n(0.01f, 0.015f, 0.05f);
    Eigen::Vector3f zen = zen_n + (zen_d - zen_n) * day;
    float twilight = std::max(0.0f, 1.0f - std::abs(sun.y()) * 4.5f);
    gl::UseProgram(dome_prog_);
    auto U = [&](const char* n) { return gl::GetUniformLocation(dome_prog_, n); };
    gl::Uniform3f(U("uFwd"), f.x(), f.y(), f.z());
    gl::Uniform3f(U("uRight"), r.x(), r.y(), r.z());
    gl::Uniform3f(U("uUp"), u.x(), u.y(), u.z());
    gl::Uniform1f(U("uTanHalf"), std::tan(cam.fovy * 0.5f));
    gl::Uniform1f(U("uAspect"), cam.aspect);
    gl::Uniform3f(U("uZenith"), zen.x(), zen.y(), zen.z());
    gl::Uniform3f(U("uHorizon"), sky.fog_color[0], sky.fog_color[1], sky.fog_color[2]);
    gl::Uniform3f(U("uGlowColor"), 1.0f, 0.6f, 0.3f);
    gl::Uniform3f(U("uSunDir"), sun.x(), sun.y(), sun.z());
    gl::Uniform1f(U("uGlow"), twilight * 1.2f);
    gl::BindVertexArray(empty_vao_);
    gl::DrawArrays(GL_TRIANGLES, 0, 3);
    gl::BindVertexArray(0);
  }

  gl::Enable(GL_BLEND);
  gl::BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ONE, GL_ONE);
  auto add_quad = [&](const Eigen::Vector3f& dir, float size, const float col[4]) {
    Eigen::Vector3f n = dir.normalized();
    Eigen::Vector3f right = n.cross(Eigen::Vector3f::UnitZ());
    if (right.norm() < 1e-3f) right = Eigen::Vector3f::UnitX();
    right.normalize();
    Eigen::Vector3f up = right.cross(n);
    const float d = 100.0f;
    Eigen::Vector3f c = n * d;
    Eigen::Vector3f p[4] = {c - right * size - up * size, c + right * size - up * size, c + right * size + up * size, c - right * size + up * size};
    const float uv[4][2] = {{0, 1}, {1, 1}, {1, 0}, {0, 0}};
    for (int i = 0; i < 4; i++) verts_.push_back({p[i].x(), p[i].y(), p[i].z(), uv[i][0], uv[i][1], col[0], col[1], col[2], col[3]});
  };

  // ---- stars
  if (day < 0.95f) {
    float a = t.sun_angle();
    float ca = std::cos(a), sa = std::sin(a);
    float alpha = (1.0f - day) * 0.9f;
    const float col[4] = {1, 1, 1, alpha};
    for (const auto& s : stars_) {
      Eigen::Vector3f p(s.x() * ca - s.y() * sa, s.x() * sa + s.y() * ca, s.z());
      if (p.y() < -0.05f) continue;
      add_quad(p, 0.35f, col);
    }
    flush_quads(cam, 0, false);
  }

  // ---- sun & moon (billboards on the same orbit)
  {
    const float white[4] = {1, 1, 1, 1};
    const float sun_fallback[4] = {1.0f, 0.95f, 0.7f, 1.0f};
    add_quad(sun, sun_tex_ ? 30.0f : 8.0f, sun_tex_ ? white : sun_fallback);  // textures have transparent padding
    flush_quads(cam, sun_tex_, sun_tex_ != 0);
    const float moon_fallback[4] = {0.85f, 0.87f, 0.95f, 1.0f};
    const int phase = static_cast<int>((t.ticks / 24000) % 8 + 8) % 8;
    GLuint mtex = moon_tex_[phase] ? moon_tex_[phase] : moon_sheet_;
    add_quad(-sun, mtex ? 20.0f : 6.0f, mtex ? white : moon_fallback);
    if (mtex && mtex == moon_sheet_) {
      // Legacy sheet: pick the phase cell (4 columns x 2 rows).
      float cu = static_cast<float>(phase % 4) / 4.0f, cv = static_cast<float>(phase / 4) / 2.0f;
      for (auto& v : verts_) { v.u = cu + v.u / 4.0f; v.v = cv + v.v / 2.0f; }
    }
    flush_quads(cam, mtex, mtex != 0);
  }
  gl::Disable(GL_BLEND);
}

void SkyRenderer::draw_box_outline(const Camera& cam, const Eigen::Vector3d& mn, const Eigen::Vector3d& mx, float alpha) {
  const float e = 0.003f;
  Eigen::Vector3f a = (mn - cam.pos).cast<float>() - Eigen::Vector3f(e, e, e);
  Eigen::Vector3f b = (mx - cam.pos).cast<float>() + Eigen::Vector3f(e, e, e);
  Eigen::Vector3f c[8] = {{a.x(), a.y(), a.z()}, {b.x(), a.y(), a.z()}, {b.x(), a.y(), b.z()}, {a.x(), a.y(), b.z()},
                          {a.x(), b.y(), a.z()}, {b.x(), b.y(), a.z()}, {b.x(), b.y(), b.z()}, {a.x(), b.y(), b.z()}};
  static const int edges[12][2] = {{0, 1}, {1, 2}, {2, 3}, {3, 0}, {4, 5}, {5, 6}, {6, 7}, {7, 4}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
  lines_.clear();
  for (auto& e2 : edges)
    for (int k : {0, 1}) {
      const Eigen::Vector3f& p = c[e2[k]];
      lines_.push_back({p.x(), p.y(), p.z(), 0, 0, 0.0f, 0.0f, 0.0f, alpha});
    }
  gl::Enable(GL_DEPTH_TEST);
  gl::DepthFunc(GL_LEQUAL);
  gl::Enable(GL_BLEND);
  gl::BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  gl::LineWidth(2.0f);
  draw_lines(cam);
  gl::Disable(GL_BLEND);
}

void SkyRenderer::draw_lines(const Camera& cam) {
  gl::UseProgram(quad_prog_);
  Eigen::Matrix4f vp = cam.view_proj();
  gl::UniformMatrix4fv(gl::GetUniformLocation(quad_prog_, "uVP"), 1, GL_FALSE, vp.data());
  gl::Uniform1i(gl::GetUniformLocation(quad_prog_, "uTextured"), 0);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(lines_.size() * sizeof(V)), lines_.data(), GL_STREAM_DRAW);
  gl::DrawArrays(GL_LINES, 0, static_cast<GLsizei>(lines_.size()));
  gl::BindVertexArray(0);
  lines_.clear();
}

}  // namespace ds
