#pragma once
// Immediate-mode 2D drawing: coloured rects, sprites, bitmap-font text (vanilla ascii.png
// layout) and isometric block icons drawn from the block texture atlas.
#include "assets/block_models.hpp"
#include "render/gl.hpp"

namespace ds {

struct UiTexture {
  GLuint id = 0;
  int w = 0, h = 0;
  bool valid() const { return id != 0; }
};

class Ui {
 public:
  ~Ui();
  bool init(const PackStack& packs, BlockModels& models, GLuint atlas, std::string* err);
  void begin(int fb_w, int fb_h);  // GUI units = framebuffer pixels / scale
  void end();

  float scale() const { return scale_; }
  float width() const { return w_ / scale_; }
  float height() const { return h_ / scale_; }

  void rect(float x, float y, float w, float h, u32 argb);
  void outline(float x, float y, float w, float h, u32 argb, float t = 1);
  void sprite(const UiTexture& t, float x, float y, float w, float h, u32 argb = 0xFFFFFFFF, float u0 = 0, float v0 = 0, float u1 = 1, float v1 = 1);
  void text(std::string_view s, float x, float y, u32 argb = 0xFFFFFFFF, bool shadow = true, float size = 1.0f);
  float text_width(std::string_view s, float size = 1.0f) const;
  void block_icon(BlockId id, float x, float y, float size);

  UiTexture load_texture(const PackStack& packs, const std::string& path) const;
  UiTexture hotbar, hotbar_selection, crosshair;

 private:
  struct V { float x, y, u, v, layer; u8 r, g, b, a; };
  enum Mode { None, Tex2D, Array };
  void flush();
  void bind(Mode m, GLuint tex);
  void quad(const float p[4][2], const float uv[4][2], u32 argb, float layer = 0);
  UiTexture make_texture(const Image& img) const;

  GLuint program_ = 0, vao_ = 0, vbo_ = 0, white_ = 0, atlas_ = 0;
  GLint u_size_ = -1, u_mode_ = -1, u_tex_ = -1, u_arr_ = -1;
  std::vector<V> verts_;
  Mode mode_ = None;
  GLuint cur_tex_ = 0;
  float scale_ = 2, w_ = 1, h_ = 1;
  BlockModels* models_ = nullptr;

  UiTexture font_;
  int cell_ = 8;
  float glyph_w_[256] = {};  // advance in font units (8px = 1 unit of size)
};

}  // namespace ds
