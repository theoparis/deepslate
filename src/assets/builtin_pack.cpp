// Procedurally generated resource pack that mirrors the official Java-edition layout. It is
// the lowest layer of every PackStack, so the game is playable without any external assets,
// and a user pack only needs to override what it wants to change.
#include <functional>
#include <map>

#include "assets/image.hpp"
#include "assets/resource_pack.hpp"
#include "world/blocks.hpp"

namespace ds {

extern const unsigned char kFallbackFontPng[];  // assets/fallback_font.cpp
extern const unsigned int kFallbackFontPngSize;

namespace {

struct Rgb { float r, g, b; };
Rgb unpack(u32 c) { return {((c >> 16) & 255) / 255.0f, ((c >> 8) & 255) / 255.0f, (c & 255) / 255.0f}; }

class Painter {
 public:
  Painter(u64 seed) : seed_(seed), img_(Image::make(16, 16)) {}
  Image& image() { return img_; }
  float rnd(int x, int y, int salt = 0) const { return hash_unit(hash_coords(seed_, x, y, salt)); }
  void set(int x, int y, Rgb c, float a = 1.0f) {
    if (x < 0 || y < 0 || x > 15 || y > 15) return;
    u8* p = img_.px(x, y);
    p[0] = static_cast<u8>(clampv(c.r, 0.0f, 1.0f) * 255 + 0.5f);
    p[1] = static_cast<u8>(clampv(c.g, 0.0f, 1.0f) * 255 + 0.5f);
    p[2] = static_cast<u8>(clampv(c.b, 0.0f, 1.0f) * 255 + 0.5f);
    p[3] = static_cast<u8>(clampv(a, 0.0f, 1.0f) * 255 + 0.5f);
  }
  static Rgb mul(Rgb c, float f) { return {c.r * f, c.g * f, c.b * f}; }
  static Rgb mix(Rgb a, Rgb b, float t) { return {lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t)}; }
  template <class F> void each(F&& f) { for (int y = 0; y < 16; y++) for (int x = 0; x < 16; x++) f(x, y); }
  void fill_noise(Rgb base, float amp, int salt = 0) {
    each([&](int x, int y) { set(x, y, mul(base, 1.0f + (rnd(x, y, salt) - 0.5f) * 2 * amp)); });
  }

 private:
  u64 seed_;
  Image img_;
};

u64 name_seed(const std::string& n) { return std::hash<std::string>{}(n); }

Image paint(const TexRecipe& r, int frame = 0) {
  Painter p(name_seed(r.name));
  const float phase = static_cast<float>(frame) * 0.7854f;  // 8 frames per cycle
  Rgb c1 = unpack(r.c1), c2 = unpack(r.c2);
  switch (r.style) {
    case TexStyle::Noise: p.fill_noise(c1, r.c2 == 1 ? 0.10f : 0.05f); break;
    case TexStyle::Stone: case TexStyle::Tuff: case TexStyle::Deepslate: case TexStyle::Bedrock: {
      float amp = r.style == TexStyle::Bedrock ? 0.35f : 0.12f;
      p.fill_noise(c1, amp);
      p.each([&](int x, int y) {
        float b = p.rnd(x / 3, y / 3, 9);
        if (b > 0.7f) p.set(x, y, Painter::mix(Painter::mul(c1, 0.8f + p.rnd(x, y) * 0.2f), r.c2 ? c2 : Painter::mul(c1, 1.15f), 0.6f));
        if (r.style == TexStyle::Deepslate && (x + (y / 4)) % 5 == 0) p.set(x, y, Painter::mul(c1, 0.8f));
      });
      break;
    }
    case TexStyle::Ore: {
      p.fill_noise(c1, 0.10f);
      static const int pts[][2] = {{3, 3}, {10, 2}, {6, 8}, {12, 10}, {3, 12}, {9, 13}};
      for (auto& pt : pts)
        for (int dx = 0; dx < 2 + (pt[0] + pt[1]) % 2; dx++)
          for (int dy = 0; dy < 2; dy++) p.set(pt[0] + dx, pt[1] + dy, Painter::mul(c2, 0.85f + p.rnd(pt[0] + dx, pt[1] + dy) * 0.3f));
      break;
    }
    case TexStyle::Planks:
      p.fill_noise(c1, 0.05f);
      p.each([&](int x, int y) {
        if (y % 4 == 3) p.set(x, y, Painter::mul(c1, 0.72f));
        else if (x == ((y / 4) % 2 ? 4 : 11) ) p.set(x, y, Painter::mul(c1, 0.8f));
      });
      break;
    case TexStyle::LogSide:
      p.each([&](int x, int y) { p.set(x, y, Painter::mul(c1, 0.75f + 0.35f * p.rnd(x, 0, 3) + (p.rnd(x, y, 4) - 0.5f) * 0.1f)); });
      break;
    case TexStyle::LogTop:
      p.each([&](int x, int y) {
        float dx = x - 7.5f, dy = y - 7.5f;
        float d = std::max(std::abs(dx), std::abs(dy));
        Rgb wood = c2.r || c2.g || c2.b ? c2 : Painter::mul(c1, 1.6f);
        if (d > 6.5f) p.set(x, y, Painter::mul(c1, 0.9f + p.rnd(x, y) * 0.2f));
        else p.set(x, y, Painter::mul(wood, 0.85f + 0.15f * std::sin(std::sqrt(dx * dx + dy * dy) * 1.9f) + p.rnd(x, y) * 0.05f));
      });
      break;
    case TexStyle::Leaves:
      p.each([&](int x, int y) {
        float v = p.rnd(x, y, 5);
        if (v < 0.18f) p.set(x, y, {0, 0, 0}, 0.0f);
        else p.set(x, y, Painter::mul({0.85f, 0.85f, 0.85f}, 0.55f + 0.5f * p.rnd(x / 2, y / 2, 6) + (v - 0.5f) * 0.2f));
      });
      break;
    case TexStyle::Bricks:
      p.fill_noise(c1, 0.07f);
      p.each([&](int x, int y) {
        int row = y / 4;
        if (y % 4 == 3 || (x + (row % 2 ? 4 : 0)) % 8 == 7) p.set(x, y, Painter::mul(c2, 0.9f + p.rnd(x, y) * 0.1f));
      });
      break;
    case TexStyle::StoneBricks:
      p.fill_noise(c1, 0.08f);
      p.each([&](int x, int y) {
        int row = y / 8;
        if (y % 8 == 7 || (x + (row % 2 ? 8 : 0)) % 16 == 15) p.set(x, y, Painter::mul(c2, 0.9f));
      });
      break;
    case TexStyle::Plant: case TexStyle::Fern: {
      p.each([&](int, int) {});
      bool fern = r.style == TexStyle::Fern;
      for (int x = 1; x < 15; x += fern ? 2 : 1) {
        float hgt = fern ? 6 + p.rnd(x, 0, 1) * 8 : 3 + p.rnd(x, 0, 1) * 10;
        if (!fern && p.rnd(x, 1, 2) < 0.35f) continue;
        for (int y = 15; y > 15 - hgt; y--) {
          float shade = 0.55f + 0.45f * (15 - y) / 15.0f + p.rnd(x, y) * 0.1f;
          int xx = x + (fern ? static_cast<int>(std::sin(y * 0.8f + x) * 1.5f) : 0);
          p.set(xx, y, Painter::mul({0.9f, 0.9f, 0.9f}, shade));
        }
      }
      break;
    }
    case TexStyle::DeadBush:
      for (int i = 0; i < 4; i++) {
        int x = 3 + i * 3;
        for (int y = 15; y > 5 + i; y--) p.set(x + (15 - y) / 4 * (i % 2 ? 1 : -1), y, Painter::mul(c1, 0.8f + p.rnd(x, y) * 0.3f));
      }
      break;
    case TexStyle::Flower: case TexStyle::Mushroom:
      if (r.style == TexStyle::Flower) {
        for (int y = 15; y >= 6; y--) p.set(7, y, {0.20f, 0.55f, 0.15f});
        p.set(8, 12, {0.20f, 0.55f, 0.15f}); p.set(6, 10, {0.20f, 0.55f, 0.15f});
        for (int dx = -2; dx <= 2; dx++)
          for (int dy = -2; dy <= 2; dy++)
            if (std::abs(dx) + std::abs(dy) <= 3) p.set(7 + dx, 4 + dy, (dx == 0 && dy == 0) ? Rgb{1, 0.85f, 0.2f} : Painter::mul(c2, 0.85f + p.rnd(dx + 9, dy + 9) * 0.3f));
      } else {
        for (int y = 15; y >= 9; y--) for (int x = 7; x <= 8; x++) p.set(x, y, {0.85f, 0.8f, 0.7f});
        for (int y = 5; y < 9; y++) for (int x = 4; x < 12; x++) if (y > 5 || (x > 5 && x < 10)) p.set(x, y, Painter::mul(c1, 0.85f + p.rnd(x, y) * 0.3f));
      }
      break;
    case TexStyle::Reeds:
      for (int x : {3, 8, 12})
        for (int y = 0; y < 16; y++) p.set(x, y, Painter::mul({0.55f, 0.75f, 0.35f}, (y % 5 == 0) ? 0.7f : 1.0f - p.rnd(x, y) * 0.15f));
      for (int y = 0; y < 16; y++) p.set(4, y, {0.4f, 0.6f, 0.25f});
      break;
    case TexStyle::Glass:
      p.each([&](int x, int y) {
        bool edge = x == 0 || y == 0 || x == 15 || y == 15;
        if (edge) p.set(x, y, Painter::mul(c1, 0.9f), 0.9f);
        else if ((x + y) % 9 == 0 && x < 8) p.set(x, y, c1, 0.5f);
        else p.set(x, y, c1, 0.0f);
      });
      break;
    case TexStyle::Sand:
      p.fill_noise(c1, 0.05f);
      p.each([&](int x, int y) { if (p.rnd(x, y, 8) > 0.9f) p.set(x, y, Painter::mul(c1, 0.88f)); });
      break;
    case TexStyle::Sandstone:
      p.fill_noise(c1, 0.04f);
      p.each([&](int x, int y) { if (y == 3 || y == 4 || y == 11) p.set(x, y, Painter::mul(c1, 0.88f)); });
      break;
    case TexStyle::Dirt:
      p.fill_noise(c1, 0.10f);
      p.each([&](int x, int y) { if (p.rnd(x, y, 8) > 0.85f) p.set(x, y, Painter::mul(c1, 0.75f)); });
      break;
    case TexStyle::Gravel:
      p.each([&](int x, int y) {
        float b = p.rnd(x / 3, y / 2, 12);
        Rgb base = b > 0.5f ? c1 : (r.c2 ? c2 : Painter::mul(c1, 1.2f));
        p.set(x, y, Painter::mul(base, 0.85f + p.rnd(x, y) * 0.3f));
      });
      break;
    case TexStyle::GrassTop: p.fill_noise({0.78f, 0.78f, 0.78f}, 0.10f); break;
    case TexStyle::GrassSide: p.fill_noise(c1, 0.10f); break;
    case TexStyle::GrassOverlay:
      p.each([&](int x, int y) {
        int depth = 2 + static_cast<int>(p.rnd(x, 0, 21) * 3);
        if (y < depth) p.set(x, y, Painter::mul({0.78f, 0.78f, 0.78f}, 0.9f + p.rnd(x, y) * 0.2f));
      });
      break;
    case TexStyle::Cactus:
      p.each([&](int x, int y) {
        bool edge = x == 0 || x == 15;
        Rgb g = Painter::mul(c1, edge ? 0.7f : 0.9f + p.rnd(x, y) * 0.2f);
        if (r.c2 == 1) { if (std::max(std::abs(x - 7.5f), std::abs(y - 7.5f)) > 6.5f) g = Painter::mul(c1, 0.75f); }
        else if ((x % 4 == 2) && (y % 4 == 1)) g = {0.85f, 0.9f, 0.7f};
        p.set(x, y, g);
      });
      break;
    case TexStyle::Torch:
      for (int y = 6; y < 16; y++) for (int x = 7; x <= 8; x++) p.set(x, y, Painter::mul({0.55f, 0.4f, 0.2f}, 0.8f + p.rnd(x, y) * 0.3f));
      for (int y = 3; y < 7; y++) for (int x = 7; x <= 8; x++) p.set(x, y, y < 5 ? Rgb{1, 0.9f, 0.4f} : Rgb{1, 0.6f, 0.15f});
      break;
    case TexStyle::Bookshelf:
      p.each([&](int x, int y) {
        if (y < 2 || y > 13 || (y > 5 && y < 8)) { p.set(x, y, {0.62f, 0.48f, 0.26f}); return; }
        static const Rgb cols[] = {{0.6f, 0.15f, 0.1f}, {0.2f, 0.3f, 0.6f}, {0.2f, 0.5f, 0.2f}, {0.6f, 0.5f, 0.15f}};
        p.set(x, y, Painter::mul(cols[(x / 2 + (y > 7 ? 2 : 0)) % 4], 0.7f + p.rnd(x, y) * 0.3f));
      });
      break;
    case TexStyle::Crafting:
      p.fill_noise({0.62f, 0.47f, 0.26f}, 0.05f);
      p.each([&](int x, int y) { if ((x % 5 == 2 && y > 2 && y < 13) || (y % 5 == 2 && x > 2 && x < 13)) p.set(x, y, {0.35f, 0.24f, 0.12f}); });
      break;
    case TexStyle::Tnt:
      p.fill_noise(c1, 0.05f);
      p.each([&](int x, int y) { if (y >= 6 && y <= 9) p.set(x, y, {0.9f, 0.9f, 0.88f}); });
      break;
    case TexStyle::Hay:
      p.each([&](int x, int y) { p.set(x, y, Painter::mul(c1, 0.75f + 0.35f * p.rnd(x, 0, 30) + (p.rnd(x, y) - 0.5f) * 0.1f)); });
      p.each([&](int x, int y) { if (y == 5 || y == 6 || y == 10 || y == 11) p.set(x, y, {0.5f, 0.35f, 0.15f}); });
      break;
    case TexStyle::Pumpkin:
      p.each([&](int x, int y) { p.set(x, y, Painter::mul(c1, (x % 4 == 0 ? 0.8f : 1.0f) + (p.rnd(x, y) - 0.5f) * 0.1f)); });
      break;
    case TexStyle::Snow: p.fill_noise({0.98f, 0.99f, 1.0f}, 0.02f); break;
    case TexStyle::Ice:
      p.each([&](int x, int y) { p.set(x, y, Painter::mul(c1, 0.95f + p.rnd(x, y) * 0.1f), r.c1 == 0x9FBFFF ? 0.75f : 1.0f); });
      break;
    case TexStyle::Water:
      p.each([&](int x, int y) { p.set(x, y, Painter::mul({0.75f, 0.85f, 1.0f}, 0.85f + 0.15f * std::sin((x + y * 0.5f) * 0.9f - phase) + p.rnd(x, y) * 0.03f)); });
      break;
    case TexStyle::Lava:
      p.each([&](int x, int y) {
        float v = 0.5f + 0.5f * std::sin(x * 0.7f + std::sin(y * 0.5f + phase) * 2) * std::cos(y * 0.6f + x * 0.2f - phase * 0.5f);
        p.set(x, y, {1.0f, 0.35f + 0.5f * v, 0.05f + 0.15f * p.rnd(x, y)});
      });
      break;
    case TexStyle::Glowstone:
      p.each([&](int x, int y) { p.set(x, y, Painter::mul(c1, 0.75f + 0.35f * p.rnd(x / 3, y / 3, 40) + p.rnd(x, y) * 0.1f)); });
      break;
    case TexStyle::Obsidian:
      p.fill_noise(c1, 0.25f);
      break;
  }
  return std::move(p.image());
}

// Built-in 256x256 grass/foliage colour maps (temperature on x, downfall on y).
Image make_colormap(bool foliage) {
  Image img = Image::make(256, 256);
  Rgb cold = foliage ? Rgb{0.38f, 0.60f, 0.35f} : Rgb{0.55f, 0.72f, 0.55f};
  Rgb warm = foliage ? Rgb{0.55f, 0.65f, 0.17f} : Rgb{0.75f, 0.72f, 0.33f};
  Rgb lush = foliage ? Rgb{0.19f, 0.73f, 0.09f} : Rgb{0.35f, 0.79f, 0.24f};
  for (int y = 0; y < 256; y++)
    for (int x = 0; x < 256; x++) {
      float t = 1.0f - x / 255.0f;       // x = 255 is coldest... vanilla indexes (1-temp)
      float w = 1.0f - y / 255.0f;       // y ~ (1 - downfall*temp)
      Rgb dry = Painter::mix(cold, warm, t);
      Rgb c = Painter::mix(dry, lush, w * (0.4f + 0.6f * t));
      c = Painter::mix(c, cold, (1 - t) * 0.5f);
      u8* p = img.px(x, y);
      p[0] = static_cast<u8>(clampv(c.r, 0.0f, 1.0f) * 255);
      p[1] = static_cast<u8>(clampv(c.g, 0.0f, 1.0f) * 255);
      p[2] = static_cast<u8>(clampv(c.b, 0.0f, 1.0f) * 255);
      p[3] = 255;
    }
  return img;
}

// ---------------------------------------------------------------- JSON
const char* kCube = R"({"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{
"down":{"texture":"#down","cullface":"down"},"up":{"texture":"#up","cullface":"up"},
"north":{"texture":"#north","cullface":"north"},"south":{"texture":"#south","cullface":"south"},
"west":{"texture":"#west","cullface":"west"},"east":{"texture":"#east","cullface":"east"}}}]})";
const char* kCubeAll = R"({"parent":"minecraft:block/cube","textures":{"particle":"#all","down":"#all","up":"#all","north":"#all","east":"#all","south":"#all","west":"#all"}})";
const char* kCubeColumn = R"({"parent":"minecraft:block/cube","textures":{"particle":"#side","down":"#end","up":"#end","north":"#side","east":"#side","south":"#side","west":"#side"}})";
const char* kCubeBottomTop = R"({"parent":"minecraft:block/cube","textures":{"particle":"#side","down":"#bottom","up":"#top","north":"#side","east":"#side","south":"#side","west":"#side"}})";
const char* kLeaves = R"({"parent":"minecraft:block/cube_all","elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{
"down":{"texture":"#all","cullface":"down","tintindex":0},"up":{"texture":"#all","cullface":"up","tintindex":0},
"north":{"texture":"#all","cullface":"north","tintindex":0},"south":{"texture":"#all","cullface":"south","tintindex":0},
"west":{"texture":"#all","cullface":"west","tintindex":0},"east":{"texture":"#all","cullface":"east","tintindex":0}}}]})";
const char* kCross = R"({"ambientocclusion":false,"textures":{"particle":"#cross"},"elements":[
{"from":[0.8,0,8],"to":[15.2,16,8],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"north":{"uv":[0,0,16,16],"texture":"#cross"},"south":{"uv":[0,0,16,16],"texture":"#cross"}}},
{"from":[8,0,0.8],"to":[8,16,15.2],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"west":{"uv":[0,0,16,16],"texture":"#cross"},"east":{"uv":[0,0,16,16],"texture":"#cross"}}}]})";
const char* kTintedCross = R"({"ambientocclusion":false,"textures":{"particle":"#cross"},"elements":[
{"from":[0.8,0,8],"to":[15.2,16,8],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"north":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0},"south":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0}}},
{"from":[8,0,0.8],"to":[8,16,15.2],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"west":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0},"east":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0}}}]})";
const char* kSlab = R"({"textures":{"particle":"#side"},"elements":[{"from":[0,0,0],"to":[16,8,16],"faces":{
"down":{"texture":"#bottom","cullface":"down"},"up":{"texture":"#top"},"north":{"texture":"#side","cullface":"north"},
"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side","cullface":"west"},"east":{"texture":"#side","cullface":"east"}}}]})";
const char* kSlabTop = R"({"textures":{"particle":"#side"},"elements":[{"from":[0,8,0],"to":[16,16,16],"faces":{
"down":{"texture":"#bottom"},"up":{"texture":"#top","cullface":"up"},"north":{"texture":"#side","cullface":"north"},
"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side","cullface":"west"},"east":{"texture":"#side","cullface":"east"}}}]})";
const char* kStairs = R"({"textures":{"particle":"#side"},"elements":[
{"from":[0,0,0],"to":[16,8,16],"faces":{"down":{"texture":"#bottom","cullface":"down"},"up":{"texture":"#top"},
"north":{"texture":"#side","cullface":"north"},"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side","cullface":"west"},"east":{"texture":"#side","cullface":"east"}}},
{"from":[8,8,0],"to":[16,16,16],"faces":{"up":{"texture":"#top","cullface":"up"},"north":{"texture":"#side","cullface":"north"},
"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side"},"east":{"texture":"#side","cullface":"east"}}}]})";
const char* kTorch = R"({"textures":{"particle":"#torch"},"elements":[{"from":[7,0,7],"to":[9,10,9],"shade":false,"faces":{
"down":{"uv":[7,13,9,15],"texture":"#torch"},"up":{"uv":[7,6,9,8],"texture":"#torch"},
"north":{"uv":[7,6,9,16],"texture":"#torch"},"south":{"uv":[7,6,9,16],"texture":"#torch"},
"west":{"uv":[7,6,9,16],"texture":"#torch"},"east":{"uv":[7,6,9,16],"texture":"#torch"}}}]})";
const char* kCactus = R"({"textures":{"particle":"#side"},"elements":[{"from":[1,0,1],"to":[15,16,15],"faces":{
"down":{"texture":"#bottom","cullface":"down"},"up":{"texture":"#top","cullface":"up"},"north":{"texture":"#side"},
"south":{"texture":"#side"},"west":{"texture":"#side"},"east":{"texture":"#side"}}}]})";

std::string q(const std::string& s) { return "\"" + s + "\""; }

std::string simple_state(const std::string& model) { return R"({"variants":{"":{"model":")" + model + R"("}}})"; }

std::string model_json(const std::string& parent, std::initializer_list<std::pair<const char*, std::string>> tex) {
  std::string s = R"({"parent":")" + parent + R"(","textures":{)";
  bool first = true;
  for (auto& [k, v] : tex) {
    if (!first) s += ",";
    first = false;
    s += q(k) + ":" + q(v);
  }
  return s + "}}";
}

}  // namespace

class BuiltinPack : public PackSource {
 public:
  BuiltinPack() {
    const std::string root = "assets/minecraft/";
    auto text = [&](const std::string& path, std::string s) {
      gen_[path] = [s = std::move(s)] { return std::vector<u8>(s.begin(), s.end()); };
    };
    text("pack.mcmeta", R"({"pack":{"pack_format":99,"description":"Deepslate Edition built-in pack"}})");
    text(root + "models/block/cube.json", kCube);
    text(root + "models/block/cube_all.json", kCubeAll);
    text(root + "models/block/cube_column.json", kCubeColumn);
    text(root + "models/block/cube_bottom_top.json", kCubeBottomTop);
    text(root + "models/block/leaves.json", kLeaves);
    text(root + "models/block/cross.json", kCross);
    text(root + "models/block/tinted_cross.json", kTintedCross);
    text(root + "models/block/slab.json", kSlab);
    text(root + "models/block/slab_top.json", kSlabTop);
    text(root + "models/block/stairs.json", kStairs);
    text(root + "models/block/template_torch.json", kTorch);
    text(root + "models/block/template_cactus.json", kCactus);

    std::map<std::string, TexRecipe> recipes;
    for (const BlockDef& d : builtin_defs()) {
      if (d.kind == Kind::Air) continue;
      for (auto& r : d.recipes) recipes.emplace(r.name, r);
      const std::string n = d.java_name();
      const std::string mp = "minecraft:block/";
      switch (d.kind) {
        case Kind::CubeAll:
          if (d.flags & BF_Leaves) text(root + "models/block/" + n + ".json", model_json(mp + "leaves", {{"all", mp + d.tex[0]}}));
          else text(root + "models/block/" + n + ".json", model_json(mp + "cube_all", {{"all", mp + d.tex[0]}}));
          text(root + "blockstates/" + n + ".json", simple_state("minecraft:block/" + n));
          break;
        case Kind::Column:
          text(root + "models/block/" + n + ".json", model_json(mp + "cube_column", {{"end", mp + d.tex[0]}, {"side", mp + d.tex[1]}}));
          text(root + "blockstates/" + n + ".json",
               R"({"variants":{"axis=y":{"model":"minecraft:block/)" + n + R"("},"axis=z":{"model":"minecraft:block/)" + n +
                   R"(","x":90},"axis=x":{"model":"minecraft:block/)" + n + R"(","x":90,"y":90}}})");
          break;
        case Kind::BottomTop:
          text(root + "models/block/" + n + ".json", model_json(mp + "cube_bottom_top", {{"top", mp + d.tex[0]}, {"side", mp + d.tex[1]}, {"bottom", mp + d.tex[2]}}));
          text(root + "blockstates/" + n + ".json", simple_state("minecraft:block/" + n));
          break;
        case Kind::Grass: {
          std::string faces;
          auto face = [&](const char* dir, const char* tex, bool tint) {
            if (!faces.empty()) faces += ",";
            faces += q(dir) + R"(:{"texture":")" + tex + R"(","cullface":")" + dir + "\"" + (tint ? R"(,"tintindex":0)" : "") + "}";
          };
          std::string base, over;
          faces.clear();
          face("down", "#bottom", false); face("up", "#top", true);
          face("north", "#side", false); face("south", "#side", false); face("west", "#side", false); face("east", "#side", false);
          base = faces;
          faces.clear();
          face("north", "#overlay", true); face("south", "#overlay", true); face("west", "#overlay", true); face("east", "#overlay", true);
          over = faces;
          text(root + "models/block/" + n + ".json",
               R"({"textures":{"particle":"#bottom","bottom":"minecraft:block/)" + d.tex[2] + R"(","top":"minecraft:block/)" + d.tex[0] +
                   R"(","side":"minecraft:block/)" + d.tex[1] + R"(","overlay":"minecraft:block/)" + d.overlay +
                   R"("},"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{)" + base +
                   R"(}},{"from":[0,0,0],"to":[16,16,16],"faces":{)" + over + R"(}}]})");
          text(root + "blockstates/" + n + ".json", R"({"variants":{"snowy=false":{"model":"minecraft:block/)" + n + R"("},"snowy=true":{"model":"minecraft:block/)" + n + R"("}}})");
          break;
        }
        case Kind::Cross:
          text(root + "models/block/" + n + ".json",
               model_json(mp + (d.tint != Tint::None ? "tinted_cross" : "cross"), {{"cross", mp + d.tex[0]}}));
          text(root + "blockstates/" + n + ".json", simple_state("minecraft:block/" + n));
          break;
        case Kind::Slab:
          text(root + "models/block/" + n + ".json", model_json(mp + "slab", {{"bottom", mp + d.tex[2]}, {"top", mp + d.tex[0]}, {"side", mp + d.tex[1]}}));
          text(root + "models/block/" + n + "_top.json", model_json(mp + "slab_top", {{"bottom", mp + d.tex[2]}, {"top", mp + d.tex[0]}, {"side", mp + d.tex[1]}}));
          text(root + "blockstates/" + n + ".json",
               R"({"variants":{"type=bottom":{"model":"minecraft:block/)" + n + R"("},"type=top":{"model":"minecraft:block/)" + n +
                   R"(_top"},"type=double":{"model":"minecraft:block/)" + n + R"("}}})");
          break;
        case Kind::Stairs: {
          text(root + "models/block/" + n + ".json", model_json(mp + "stairs", {{"bottom", mp + d.tex[2]}, {"top", mp + d.tex[0]}, {"side", mp + d.tex[1]}}));
          std::string v = R"({"variants":{)";
          static const char* facings[] = {"east", "south", "west", "north"};
          bool first = true;
          for (const char* half : {"bottom", "top"})
            for (int i = 0; i < 4; i++) {
              if (!first) v += ",";
              first = false;
              v += std::format(R"("facing={},half={},shape=straight":{{"model":"minecraft:block/{}","y":{}{}}})", facings[i], half, n, i * 90,
                               std::string(half) == "top" ? R"(,"x":180)" : "");
            }
          v += "}}";
          text(root + "blockstates/" + n + ".json", v);
          break;
        }
        case Kind::Cactus:
          text(root + "models/block/" + n + ".json", model_json(mp + "template_cactus", {{"top", mp + d.tex[0]}, {"side", mp + d.tex[1]}, {"bottom", mp + d.tex[2]}}));
          text(root + "blockstates/" + n + ".json", simple_state("minecraft:block/" + n));
          break;
        case Kind::Torch:
          text(root + "models/block/" + n + ".json", model_json(mp + "template_torch", {{"torch", mp + d.tex[0]}}));
          text(root + "blockstates/" + n + ".json", simple_state("minecraft:block/" + n));
          break;
        default: break;
      }
    }
    for (auto& [name, r] : recipes) {
      TexRecipe rc = r;
      if (rc.style == TexStyle::Water || rc.style == TexStyle::Lava) {
        // Animated like the real thing: a vertical strip of 8 frames plus a .mcmeta.
        gen_[root + "textures/block/" + name + ".png"] = [rc] {
          Image strip = Image::make(16, 16 * 8);
          for (int f = 0; f < 8; f++) {
            Image fr = paint(rc, f);
            std::memcpy(strip.px(0, f * 16), fr.rgba.data(), fr.rgba.size());
          }
          return encode_png(strip);
        };
        text(root + "textures/block/" + name + ".png.mcmeta", R"({"animation":{"frametime":3}})");
      } else {
        gen_[root + "textures/block/" + name + ".png"] = [rc] { return encode_png(paint(rc)); };
      }
    }
    gen_[root + "textures/colormap/grass.png"] = [] { return encode_png(make_colormap(false)); };
    gen_[root + "textures/colormap/foliage.png"] = [] { return encode_png(make_colormap(true)); };
    gen_[root + "textures/font/ascii.png"] = [] { return std::vector<u8>(kFallbackFontPng, kFallbackFontPng + kFallbackFontPngSize); };
  }

  std::optional<std::vector<u8>> read(const std::string& path) const override {
    auto it = gen_.find(path);
    if (it == gen_.end()) return std::nullopt;
    return it->second();
  }
  bool has(const std::string& path) const override { return gen_.contains(path); }
  std::string name() const override { return "builtin"; }
  std::vector<std::string> files() const {
    std::vector<std::string> v;
    for (auto& [k, _] : gen_) v.push_back(k);
    return v;
  }

 private:
  std::map<std::string, std::function<std::vector<u8>()>> gen_;
};

std::unique_ptr<PackSource> make_builtin_pack() { return std::make_unique<BuiltinPack>(); }
std::vector<std::string> builtin_pack_files() { return BuiltinPack().files(); }

}  // namespace ds
