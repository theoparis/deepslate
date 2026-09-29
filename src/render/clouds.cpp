#include "render/clouds.hpp"

#include "assets/image.hpp"

namespace ds {

namespace {

const char* kVS = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in float aShade;
uniform mat4 uVP;
uniform vec3 uOffset;
out float vShade; out float vDist;
void main() {
  vec3 p = aPos + uOffset;
  gl_Position = uVP * vec4(p, 1.0);
  vShade = aShade; vDist = length(p);
}
)";
const char* kFS = R"(#version 330 core
in float vShade; in float vDist;
uniform vec3 uColor, uFogColor;
uniform float uFogStart, uFogEnd, uAlpha;
out vec4 oColor;
void main() {
  float f = clamp((vDist - uFogStart) / max(uFogEnd - uFogStart, 0.001), 0.0, 1.0);
  oColor = vec4(mix(uColor * vShade, uFogColor, f), uAlpha * (1.0 - f * 0.9));
}
)";

}  // namespace

Clouds::~Clouds() {
  if (prog_) gl::DeleteProgram(prog_);
  if (vao_) gl::DeleteVertexArrays(1, &vao_);
  if (vbo_) gl::DeleteBuffers(1, &vbo_);
}

bool Clouds::init(const PackStack& packs, std::string* err) {
  prog_ = gl::make_program(kVS, kFS, err);
  if (!prog_) return false;
  gl::GenVertexArrays(1, &vao_);
  gl::GenBuffers(1, &vbo_);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::EnableVertexAttribArray(0);
  gl::VertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, x)));
  gl::EnableVertexAttribArray(1);
  gl::VertexAttribPointer(1, 1, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, shade)));
  gl::BindVertexArray(0);

  mask_.assign(static_cast<size_t>(N) * N, false);
  bool from_pack = false;
  if (auto data = packs.read("assets/minecraft/textures/environment/clouds.png")) {
    if (auto img = decode_png(*data); img && img->w > 0 && img->h > 0) {
      for (int y = 0; y < N; y++)
        for (int x = 0; x < N; x++) mask_[static_cast<size_t>(y) * N + x] = img->px(x * img->w / N, y * img->h / N)[3] > 127;
      from_pack = true;
    }
  }
  if (!from_pack) {
    // Procedural fallback: thresholded 2-octave value noise (wraps at the mask size).
    auto vn = [](int x, int y, int period, int salt) {
      return hash_unit(hash_coords(0xC10D, ((x % period) + period) % period, salt, ((y % period) + period) % period));
    };
    auto smooth = [&](float fx, float fy, int period, int salt) {
      int x0 = static_cast<int>(std::floor(fx)), y0 = static_cast<int>(std::floor(fy));
      float tx = fx - x0, ty = fy - y0;
      tx = tx * tx * (3 - 2 * tx);
      ty = ty * ty * (3 - 2 * ty);
      float a = lerp(vn(x0, y0, period, salt), vn(x0 + 1, y0, period, salt), tx);
      float b = lerp(vn(x0, y0 + 1, period, salt), vn(x0 + 1, y0 + 1, period, salt), tx);
      return lerp(a, b, ty);
    };
    for (int y = 0; y < N; y++)
      for (int x = 0; x < N; x++) {
        float v = 0.6f * smooth(x / 32.0f, y / 32.0f, 8, 1) + 0.4f * smooth(x / 12.0f, y / 12.0f, 22, 2);
        mask_[static_cast<size_t>(y) * N + x] = v > 0.6f;
      }
  }
  return true;
}

void Clouds::rebuild(int ci, int cj) {
  verts_.clear();
  auto quad = [&](float x0, float y0, float z0, float x1, float y1, float z1, float x2, float y2, float z2, float x3, float y3, float z3, float s) {
    verts_.push_back({x0, y0, z0, s});
    verts_.push_back({x1, y1, z1, s});
    verts_.push_back({x2, y2, z2, s});
    verts_.push_back({x0, y0, z0, s});
    verts_.push_back({x2, y2, z2, s});
    verts_.push_back({x3, y3, z3, s});
  };
  const float y0 = 0.0f, y1 = 4.0f, C = static_cast<float>(CELL);
  for (int j = cj - R; j <= cj + R; j++)
    for (int i = ci - R; i <= ci + R; i++) {
      if (!cell(i, j)) continue;
      float x0 = static_cast<float>(i) * C, x1 = x0 + C, z0 = static_cast<float>(j) * C, z1 = z0 + C;
      quad(x0, y1, z0, x0, y1, z1, x1, y1, z1, x1, y1, z0, 1.0f);   // top
      quad(x0, y0, z0, x1, y0, z0, x1, y0, z1, x0, y0, z1, 0.62f);  // bottom
      if (!cell(i - 1, j)) quad(x0, y0, z0, x0, y0, z1, x0, y1, z1, x0, y1, z0, 0.78f);
      if (!cell(i + 1, j)) quad(x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1, 0.78f);
      if (!cell(i, j - 1)) quad(x0, y0, z0, x0, y1, z0, x1, y1, z0, x1, y0, z0, 0.86f);
      if (!cell(i, j + 1)) quad(x0, y0, z1, x1, y0, z1, x1, y1, z1, x0, y1, z1, 0.86f);
    }
  vert_count_ = static_cast<int>(verts_.size());
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(verts_.size() * sizeof(V)), verts_.data(), GL_DYNAMIC_DRAW);
  built_i_ = ci;
  built_j_ = cj;
}

void Clouds::draw(const Camera& cam, const SkyState& sky, double seconds) {
  const float scroll = static_cast<float>(std::fmod(seconds * 1.6, static_cast<double>(N) * CELL));
  const int ci = static_cast<int>(std::floor((cam.pos.x() - scroll) / CELL));
  const int cj = static_cast<int>(std::floor(cam.pos.z() / CELL));
  if (ci != built_i_ || cj != built_j_) rebuild(ci, cj);
  if (vert_count_ == 0) return;

  gl::Enable(GL_DEPTH_TEST);
  gl::DepthFunc(GL_LEQUAL);
  gl::Disable(GL_CULL_FACE);
  gl::Enable(GL_BLEND);
  gl::BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  gl::UseProgram(prog_);
  Eigen::Matrix4f vp = cam.view_proj();
  auto U = [&](const char* n) { return gl::GetUniformLocation(prog_, n); };
  gl::UniformMatrix4fv(U("uVP"), 1, GL_FALSE, vp.data());
  gl::Uniform3f(U("uOffset"), scroll - static_cast<float>(cam.pos.x()), HEIGHT - static_cast<float>(cam.pos.y()), -static_cast<float>(cam.pos.z()));
  const float l = 0.12f + 0.88f * sky.sky_light;
  const float warm = 0.35f;
  gl::Uniform3f(U("uColor"), (1.0f + (sky.fog_color[0] - 1.0f) * warm) * l, (1.0f + (sky.fog_color[1] - 1.0f) * warm) * l,
                (1.0f + (sky.fog_color[2] - 1.0f) * warm) * l);
  gl::Uniform3f(U("uFogColor"), sky.fog_color[0], sky.fog_color[1], sky.fog_color[2]);
  gl::Uniform1f(U("uFogStart"), std::max(sky.fog_start, 60.0f));
  gl::Uniform1f(U("uFogEnd"), std::max(sky.fog_end * 1.9f, 200.0f));
  gl::Uniform1f(U("uAlpha"), 0.82f);
  gl::BindVertexArray(vao_);
  // Depth pre-pass so overlapping faces of the translucent volume do not stack up.
  gl::ColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  gl::DepthMask(GL_TRUE);
  gl::DrawArrays(GL_TRIANGLES, 0, vert_count_);
  gl::ColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  gl::DepthMask(GL_FALSE);
  gl::DepthFunc(GL_EQUAL);
  gl::DrawArrays(GL_TRIANGLES, 0, vert_count_);
  gl::DepthFunc(GL_LEQUAL);
  gl::BindVertexArray(0);
  gl::DepthMask(GL_TRUE);
  gl::Disable(GL_BLEND);
}

}  // namespace ds
