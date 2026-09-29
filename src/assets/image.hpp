#pragma once
#include <string>
#include <vector>

#include "util/common.hpp"

namespace ds {

struct Image {
  int w = 0, h = 0;
  std::vector<u8> rgba;  // 4 bytes per pixel
  bool empty() const { return w == 0 || h == 0; }
  u8* px(int x, int y) { return &rgba[(static_cast<size_t>(y) * w + x) * 4]; }
  const u8* px(int x, int y) const { return &rgba[(static_cast<size_t>(y) * w + x) * 4]; }
  static Image make(int w, int h) {
    Image i;
    i.w = w;
    i.h = h;
    i.rgba.assign(static_cast<size_t>(w) * h * 4, 0);
    return i;
  }
};

std::optional<Image> decode_png(std::span<const u8> bytes);
std::vector<u8> encode_png(const Image& img);
bool write_png_file(const std::string& path, const Image& img);

}  // namespace ds
