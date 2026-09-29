#pragma once
// Small shared helpers: integer types, hashing, logging.
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <format>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace ds {

using u8 = std::uint8_t;
using u16 = std::uint16_t;
using u32 = std::uint32_t;
using u64 = std::uint64_t;
using i8 = std::int8_t;
using i16 = std::int16_t;
using i32 = std::int32_t;
using i64 = std::int64_t;

// ---------------------------------------------------------------- logging
enum class LogLevel { Debug, Info, Warn, Error };

inline std::mutex& log_mutex() {
  static std::mutex m;
  return m;
}

inline LogLevel& log_threshold() {
  static LogLevel l = LogLevel::Info;
  return l;
}

template <class... A>
void log(LogLevel lvl, std::format_string<A...> fmt, A&&... args) {
  if (lvl < log_threshold()) return;
  static constexpr const char* names[] = {"debug", "info", "warn", "error"};
  std::string msg = std::format(fmt, std::forward<A>(args)...);
  std::lock_guard lk(log_mutex());
  std::fprintf(stderr, "[%s] %s\n", names[static_cast<int>(lvl)], msg.c_str());
}
template <class... A> void log_info(std::format_string<A...> f, A&&... a) { log(LogLevel::Info, f, std::forward<A>(a)...); }
template <class... A> void log_warn(std::format_string<A...> f, A&&... a) { log(LogLevel::Warn, f, std::forward<A>(a)...); }
template <class... A> void log_error(std::format_string<A...> f, A&&... a) { log(LogLevel::Error, f, std::forward<A>(a)...); }
template <class... A> void log_debug(std::format_string<A...> f, A&&... a) { log(LogLevel::Debug, f, std::forward<A>(a)...); }

// ---------------------------------------------------------------- math
constexpr int floor_div(int a, int b) { int q = a / b; return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q; }
constexpr int floor_mod(int a, int b) { int r = a % b; return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r; }
inline int ifloor(float f) { return static_cast<int>(std::floor(f)); }
inline int ifloor(double f) { return static_cast<int>(std::floor(f)); }
template <class T> constexpr T clampv(T v, T lo, T hi) { return v < lo ? lo : (v > hi ? hi : v); }
constexpr float lerp(float a, float b, float t) { return a + (b - a) * t; }

// ---------------------------------------------------------------- hashing
constexpr u64 mix64(u64 z) {
  z += 0x9E3779B97F4A7C15ull;
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
  return z ^ (z >> 31);
}
constexpr u64 hash_coords(u64 seed, i64 x, i64 y, i64 z) {
  u64 h = mix64(seed ^ 0xA0761D6478BD642Full);
  h = mix64(h ^ static_cast<u64>(x) * 0xE7037ED1A0B428DBull);
  h = mix64(h ^ static_cast<u64>(y) * 0x8EBC6AF09C88C6E3ull);
  h = mix64(h ^ static_cast<u64>(z) * 0x589965CC75374CC3ull);
  return h;
}
// [0,1) float from a hash.
constexpr float hash_unit(u64 h) { return static_cast<float>(h >> 40) * (1.0f / 16777216.0f); }

// Tiny deterministic PRNG (xoshiro-ish via splitmix state).
struct Rng {
  u64 s;
  explicit constexpr Rng(u64 seed) : s(seed) {}
  constexpr u64 next() { return mix64(s += 0x9E3779B97F4A7C15ull); }
  constexpr float unit() { return hash_unit(next()); }
  constexpr int range(int lo, int hi) { return lo + static_cast<int>(next() % static_cast<u64>(hi - lo + 1)); }
  constexpr bool chance(float p) { return unit() < p; }
};

inline double now_seconds() {
  using clk = std::chrono::steady_clock;
  static const auto t0 = clk::now();
  return std::chrono::duration<double>(clk::now() - t0).count();
}

// Packs a chunk column position into a single key.
struct ChunkPos {
  i32 x = 0, z = 0;
  constexpr bool operator==(const ChunkPos&) const = default;
};
constexpr u64 pack_chunk(ChunkPos p) { return (static_cast<u64>(static_cast<u32>(p.x)) << 32) | static_cast<u32>(p.z); }
struct ChunkPosHash { size_t operator()(ChunkPos p) const noexcept { return mix64(pack_chunk(p)); } };

}  // namespace ds
