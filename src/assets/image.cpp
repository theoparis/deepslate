#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "assets/image.hpp"

#include <stb_image.h>
#include <stb_image_write.h>

namespace ds {

std::optional<Image> decode_png(std::span<const u8> bytes) {
  int w, h, n;
  u8* data = stbi_load_from_memory(bytes.data(), static_cast<int>(bytes.size()), &w, &h, &n, 4);
  if (!data) return std::nullopt;
  Image img;
  img.w = w;
  img.h = h;
  img.rgba.assign(data, data + static_cast<size_t>(w) * h * 4);
  stbi_image_free(data);
  return img;
}

std::vector<u8> encode_png(const Image& img) {
  int len = 0;
  u8* p = stbi_write_png_to_mem(img.rgba.data(), img.w * 4, img.w, img.h, 4, &len);
  if (!p) return {};
  std::vector<u8> out(p, p + len);
  STBIW_FREE(p);
  return out;
}

bool write_png_file(const std::string& path, const Image& img) {
  return stbi_write_png(path.c_str(), img.w, img.h, 4, img.rgba.data(), img.w * 4) != 0;
}

}  // namespace ds
