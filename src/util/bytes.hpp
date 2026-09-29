#pragma once
// Little-endian byte writer/reader used by the NBT and Bedrock chunk codecs.
#include "util/common.hpp"

namespace ds {

class ByteWriter {
 public:
  std::vector<u8> buf;
  void u8_(u8 v) { buf.push_back(v); }
  void u16le(u16 v) { u8_(v & 0xFF); u8_(v >> 8); }
  void u32le(u32 v) { for (int i = 0; i < 4; i++) u8_((v >> (8 * i)) & 0xFF); }
  void u64le(u64 v) { for (int i = 0; i < 8; i++) u8_((v >> (8 * i)) & 0xFF); }
  void i16le(i16 v) { u16le(static_cast<u16>(v)); }
  void i32le(i32 v) { u32le(static_cast<u32>(v)); }
  void i64le(i64 v) { u64le(static_cast<u64>(v)); }
  void f32le(float f) { u32 b; std::memcpy(&b, &f, 4); u32le(b); }
  void f64le(double f) { u64 b; std::memcpy(&b, &f, 8); u64le(b); }
  void bytes(std::span<const u8> s) { buf.insert(buf.end(), s.begin(), s.end()); }
  void str(std::string_view s) { buf.insert(buf.end(), s.begin(), s.end()); }
};

// Bounds-checked reader; once a read runs past the end `ok()` turns false and
// all further reads return zeros.
class ByteReader {
 public:
  ByteReader() = default;
  explicit ByteReader(std::span<const u8> d) : data_(d) {}
  bool ok() const { return ok_; }
  size_t pos() const { return pos_; }
  size_t remaining() const { return data_.size() - pos_; }
  bool eof() const { return pos_ >= data_.size(); }
  u8 u8_() { return take(1) ? data_[pos_ - 1] : 0; }
  u16 u16le() { u16 v = 0; if (take(2)) for (int i = 0; i < 2; i++) v |= static_cast<u16>(data_[pos_ - 2 + i]) << (8 * i); return v; }
  u32 u32le() { u32 v = 0; if (take(4)) for (int i = 0; i < 4; i++) v |= static_cast<u32>(data_[pos_ - 4 + i]) << (8 * i); return v; }
  u64 u64le() { u64 v = 0; if (take(8)) for (int i = 0; i < 8; i++) v |= static_cast<u64>(data_[pos_ - 8 + i]) << (8 * i); return v; }
  i16 i16le() { return static_cast<i16>(u16le()); }
  i32 i32le() { return static_cast<i32>(u32le()); }
  i64 i64le() { return static_cast<i64>(u64le()); }
  float f32le() { u32 b = u32le(); float f; std::memcpy(&f, &b, 4); return f; }
  double f64le() { u64 b = u64le(); double f; std::memcpy(&f, &b, 8); return f; }
  std::span<const u8> bytes(size_t n) {
    if (!take(n)) return {};
    return data_.subspan(pos_ - n, n);
  }
  std::string str(size_t n) {
    auto b = bytes(n);
    return std::string(reinterpret_cast<const char*>(b.data()), b.size());
  }

 private:
  bool take(size_t n) {
    if (!ok_ || data_.size() - pos_ < n) { ok_ = false; return false; }
    pos_ += n;
    return true;
  }
  std::span<const u8> data_;
  size_t pos_ = 0;
  bool ok_ = true;
};

}  // namespace ds
