#include "render/ui.hpp"
#include "world/chunk.hpp"

namespace ds {

namespace {

const char* kVS = R"(#version 330 core
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aUV;
layout(location=2) in float aLayer;
layout(location=3) in vec4 aCol;
uniform vec2 uSize;
out vec2 vUV; out float vLayer; out vec4 vCol;
void main() {
  gl_Position = vec4(aPos.x / uSize.x * 2.0 - 1.0, 1.0 - aPos.y / uSize.y * 2.0, 0.0, 1.0);
  vUV = aUV; vLayer = aLayer; vCol = aCol;
}
)";
const char* kFS = R"(#version 330 core
in vec2 vUV; in float vLayer; in vec4 vCol;
uniform int uMode;
uniform sampler2D uTex;
uniform sampler2DArray uArr;
out vec4 oColor;
void main() {
  vec4 t = uMode == 2 ? texture(uArr, vec3(vUV, vLayer)) : texture(uTex, vUV);
  if (t.a < 0.05) discard;
  oColor = t * vCol;
}
)";

}  // namespace

Ui::~Ui() {
  if (vbo_) gl::DeleteBuffers(1, &vbo_);
  if (vao_) gl::DeleteVertexArrays(1, &vao_);
  if (program_) gl::DeleteProgram(program_);
  if (white_) gl::DeleteTextures(1, &white_);
  for (UiTexture* t : {&hotbar, &hotbar_selection, &crosshair, &font_})
    if (t->id) gl::DeleteTextures(1, &t->id);
}

UiTexture Ui::make_texture(const Image& img) const {
  UiTexture t;
  gl::GenTextures(1, &t.id);
  gl::BindTexture(GL_TEXTURE_2D, t.id);
  gl::PixelStorei(GL_UNPACK_ALIGNMENT, 1);
  gl::TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, img.w, img.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, img.rgba.data());
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  gl::TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  t.w = img.w;
  t.h = img.h;
  return t;
}

UiTexture Ui::load_texture(const PackStack& packs, const std::string& path) const {
  auto data = packs.read("assets/minecraft/textures/" + path + ".png");
  if (!data) return {};
  auto img = decode_png(*data);
  if (!img) return {};
  return make_texture(*img);
}

bool Ui::init(const PackStack& packs, BlockModels& models, GLuint atlas, std::string* err) {
  models_ = &models;
  atlas_ = atlas;
  program_ = gl::make_program(kVS, kFS, err);
  if (!program_) return false;
  u_size_ = gl::GetUniformLocation(program_, "uSize");
  u_mode_ = gl::GetUniformLocation(program_, "uMode");
  u_tex_ = gl::GetUniformLocation(program_, "uTex");
  u_arr_ = gl::GetUniformLocation(program_, "uArr");
  gl::GenVertexArrays(1, &vao_);
  gl::GenBuffers(1, &vbo_);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::EnableVertexAttribArray(0);
  gl::VertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, x)));
  gl::EnableVertexAttribArray(1);
  gl::VertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, u)));
  gl::EnableVertexAttribArray(2);
  gl::VertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, sizeof(V), reinterpret_cast<void*>(offsetof(V, layer)));
  gl::EnableVertexAttribArray(3);
  gl::VertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(V), reinterpret_cast<void*>(offsetof(V, r)));
  gl::BindVertexArray(0);

  Image white = Image::make(1, 1);
  std::fill(white.rgba.begin(), white.rgba.end(), 255);
  white_ = make_texture(white).id;

  hotbar = load_texture(packs, "gui/sprites/hud/hotbar");
  hotbar_selection = load_texture(packs, "gui/sprites/hud/hotbar_selection");
  crosshair = load_texture(packs, "gui/sprites/hud/crosshair");

  // Bitmap font: 16x16 grid of square cells, width from the rightmost opaque column.
  if (auto data = packs.read("assets/minecraft/textures/font/ascii.png")) {
    if (auto img = decode_png(*data); img && img->w >= 16 && img->w == img->h) {
      cell_ = img->w / 16;
      for (int c = 0; c < 256; c++) {
        int cx = (c % 16) * cell_, cy = (c / 16) * cell_;
        int last = -1;
        for (int x = 0; x < cell_; x++)
          for (int y = 0; y < cell_; y++)
            if (img->px(cx + x, cy + y)[3] > 0) last = x;
        glyph_w_[c] = c == ' ' ? 4.0f : (last < 0 ? 0.0f : (last + 1) * 8.0f / cell_);
      }
      font_ = make_texture(*img);
    }
  }
  if (!font_.valid()) log_warn("no usable font texture; text disabled");
  return true;
}

void Ui::begin(int fb_w, int fb_h) {
  w_ = static_cast<float>(fb_w);
  h_ = static_cast<float>(fb_h);
  scale_ = std::max(1.0f, std::floor(std::min(w_ / 320.0f, h_ / 240.0f)));
  scale_ = std::min(scale_, 4.0f);
  gl::Disable(GL_DEPTH_TEST);
  gl::Disable(GL_CULL_FACE);
  gl::Enable(GL_BLEND);
  gl::BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  gl::UseProgram(program_);
  gl::Uniform2f(u_size_, w_ / scale_, h_ / scale_);
  gl::Uniform1i(u_tex_, 0);
  gl::Uniform1i(u_arr_, 1);
  mode_ = None;
  cur_tex_ = 0;
  verts_.clear();
}

void Ui::end() {
  flush();
  gl::Disable(GL_BLEND);
  gl::Enable(GL_DEPTH_TEST);
}

void Ui::flush() {
  if (verts_.empty()) return;
  gl::UseProgram(program_);
  gl::BindVertexArray(vao_);
  gl::BindBuffer(GL_ARRAY_BUFFER, vbo_);
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(verts_.size() * sizeof(V)), verts_.data(), GL_STREAM_DRAW);
  gl::Uniform1i(u_mode_, mode_ == Array ? 2 : 1);
  gl::ActiveTexture(GL_TEXTURE0);
  gl::BindTexture(GL_TEXTURE_2D, mode_ == Tex2D ? cur_tex_ : white_);
  gl::ActiveTexture(GL_TEXTURE1);
  gl::BindTexture(GL_TEXTURE_2D_ARRAY, mode_ == Array ? cur_tex_ : 0);
  gl::ActiveTexture(GL_TEXTURE0);
  // Quads as two triangles.
  static std::vector<V> tri;
  tri.clear();
  for (size_t i = 0; i + 3 < verts_.size(); i += 4) {
    for (int k : {0, 1, 2, 2, 3, 0}) tri.push_back(verts_[i + static_cast<size_t>(k)]);
  }
  gl::BufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(tri.size() * sizeof(V)), tri.data(), GL_STREAM_DRAW);
  gl::DrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(tri.size()));
  gl::BindVertexArray(0);
  verts_.clear();
}

void Ui::bind(Mode m, GLuint tex) {
  if (m != mode_ || (m != None && tex != cur_tex_)) {
    flush();
    mode_ = m;
    cur_tex_ = tex;
  }
}

void Ui::quad(const float p[4][2], const float uv[4][2], u32 argb, float layer) {
  V v{};
  v.a = static_cast<u8>(argb >> 24);
  v.r = static_cast<u8>(argb >> 16);
  v.g = static_cast<u8>(argb >> 8);
  v.b = static_cast<u8>(argb);
  v.layer = layer;
  for (int i = 0; i < 4; i++) {
    v.x = p[i][0]; v.y = p[i][1];
    v.u = uv[i][0]; v.v = uv[i][1];
    verts_.push_back(v);
  }
}

void Ui::rect(float x, float y, float w, float h, u32 argb) {
  bind(None, 0);
  const float p[4][2] = {{x, y}, {x, y + h}, {x + w, y + h}, {x + w, y}};
  const float uv[4][2] = {{0, 0}, {0, 1}, {1, 1}, {1, 0}};
  quad(p, uv, argb);
}

void Ui::outline(float x, float y, float w, float h, u32 argb, float t) {
  rect(x, y, w, t, argb);
  rect(x, y + h - t, w, t, argb);
  rect(x, y + t, t, h - 2 * t, argb);
  rect(x + w - t, y + t, t, h - 2 * t, argb);
}

void Ui::sprite(const UiTexture& t, float x, float y, float w, float h, u32 argb, float u0, float v0, float u1, float v1) {
  if (!t.valid()) return;
  bind(Tex2D, t.id);
  const float p[4][2] = {{x, y}, {x, y + h}, {x + w, y + h}, {x + w, y}};
  const float uv[4][2] = {{u0, v0}, {u0, v1}, {u1, v1}, {u1, v0}};
  quad(p, uv, argb);
}

float Ui::text_width(std::string_view s, float size) const {
  float w = 0;
  for (unsigned char c : s) w += (glyph_w_[c] + 1.0f) * size;
  return w > 0 ? w - size : 0;
}

void Ui::text(std::string_view s, float x, float y, u32 argb, bool shadow, float size) {
  if (!font_.valid()) return;
  auto draw = [&](float ox, float oy, u32 col) {
    float cx = x + ox;
    for (unsigned char c : s) {
      float gw = glyph_w_[c];
      if (gw > 0 && c != ' ') {
        const float u0 = (c % 16) / 16.0f, v0 = (c / 16) / 16.0f;
        const float du = gw * cell_ / 8.0f / (16.0f * cell_);
        sprite(font_, cx, y + oy, gw * size, 8 * size, col, u0, v0, u0 + du, v0 + 1.0f / 16.0f);
      }
      cx += (gw + 1.0f) * size;
    }
  };
  if (shadow) draw(size, size, (argb & 0xFF000000u) | ((argb & 0xFCFCFC) >> 2));
  draw(0, 0, argb);
}

void Ui::block_icon(BlockId id, float x, float y, float s) {
  BlockModels::Icon ic = models_->icon(id);
  const BlockInfo& bi = Blocks::get().info(id);
  auto tint = [&](bool top_face) -> u32 {
    if (bi.tint == Tint::None) return 0xFFFFFF;
    if (bi.def && bi.def->kind == Kind::Grass && !top_face) return 0xFFFFFF;
    return models_->tint_color(bi.tint, Biome::Plains);
  };
  auto mulc = [](u32 rgb, float f) -> u32 {
    auto ch = [&](int sh) { return static_cast<u32>(clampv(((rgb >> sh) & 255) * f, 0.0f, 255.0f)); };
    return 0xFF000000u | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  };
  if (ic.flat) {
    bind(Array, atlas_);
    const float p[4][2] = {{x, y}, {x, y + s}, {x + s, y + s}, {x + s, y}};
    const float uv[4][2] = {{0, 0}, {0, 1}, {1, 1}, {1, 0}};
    quad(p, uv, mulc(tint(true), 1.0f), ic.top);
    return;
  }
  bind(Array, atlas_);
  const float T[2] = {x + s / 2, y}, TL[2] = {x, y + s * 0.25f}, TR[2] = {x + s, y + s * 0.25f}, C[2] = {x + s / 2, y + s * 0.5f},
              BL[2] = {x, y + s * 0.75f}, BR[2] = {x + s, y + s * 0.75f}, B[2] = {x + s / 2, y + s};
  {
    const float p[4][2] = {{T[0], T[1]}, {TL[0], TL[1]}, {C[0], C[1]}, {TR[0], TR[1]}};
    const float uv[4][2] = {{1, 0}, {0, 0}, {0, 1}, {1, 1}};
    quad(p, uv, mulc(tint(true), 1.0f), ic.top);
  }
  {
    const float p[4][2] = {{TL[0], TL[1]}, {BL[0], BL[1]}, {B[0], B[1]}, {C[0], C[1]}};
    const float uv[4][2] = {{0, 0}, {0, 1}, {1, 1}, {1, 0}};
    quad(p, uv, mulc(tint(false), 0.82f), ic.left);
  }
  {
    const float p[4][2] = {{C[0], C[1]}, {B[0], B[1]}, {BR[0], BR[1]}, {TR[0], TR[1]}};
    const float uv[4][2] = {{0, 0}, {0, 1}, {1, 1}, {1, 0}};
    quad(p, uv, mulc(tint(false), 0.62f), ic.right);
  }
}

}  // namespace ds
