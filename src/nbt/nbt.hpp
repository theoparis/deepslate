#pragma once
// Minimal NBT (little-endian, as used by Bedrock Edition on disk).
#include <string>
#include <utility>
#include <vector>

#include "util/bytes.hpp"

namespace ds::nbt {

enum class Type : u8 { End, Byte, Short, Int, Long, Float, Double, ByteArray, String, List, Compound, IntArray, LongArray };

struct Tag;
struct Entry;

struct Tag {
  Type type = Type::End;
  i64 i = 0;                  // Byte/Short/Int/Long
  double d = 0;               // Float/Double
  std::string s;              // String
  std::vector<u8> bytes;      // ByteArray
  std::vector<i32> ints;      // IntArray
  std::vector<i64> longs;     // LongArray
  Type list_type = Type::End; // List element type
  std::vector<Tag> list;      // List items
  std::vector<Entry> compound;

  // Special members are defined after Entry (which holds a Tag) is complete.
  Tag();
  ~Tag();
  Tag(const Tag&);
  Tag(Tag&&) noexcept;
  Tag& operator=(const Tag&);
  Tag& operator=(Tag&&) noexcept;

  static Tag make_byte(i64 v);
  static Tag make_short(i64 v);
  static Tag make_int(i64 v);
  static Tag make_long(i64 v);
  static Tag make_float(double v);
  static Tag make_double(double v);
  static Tag make_string(std::string v);
  static Tag make_compound();
  static Tag make_list(Type elem);

  // Compound helpers (defined below, once Entry is complete).
  Tag& set(std::string name, Tag v);
  const Tag* find(std::string_view name) const;
  i64 get_int(std::string_view name, i64 def = 0) const;
  double get_num(std::string_view name, double def = 0) const;
  std::string get_string(std::string_view name, std::string def = {}) const;
  // List helper: numeric element (float/int) at index.
  double list_num(size_t idx, double def = 0) const;
};

struct Entry {
  std::string first;
  Tag second;
};

inline Tag::Tag() = default;
inline Tag::~Tag() = default;
inline Tag::Tag(const Tag&) = default;
inline Tag::Tag(Tag&&) noexcept = default;
inline Tag& Tag::operator=(const Tag&) = default;
inline Tag& Tag::operator=(Tag&&) noexcept = default;
inline Tag Tag::make_byte(i64 v) { Tag t; t.type = Type::Byte; t.i = v; return t; }
inline Tag Tag::make_short(i64 v) { Tag t; t.type = Type::Short; t.i = v; return t; }
inline Tag Tag::make_int(i64 v) { Tag t; t.type = Type::Int; t.i = v; return t; }
inline Tag Tag::make_long(i64 v) { Tag t; t.type = Type::Long; t.i = v; return t; }
inline Tag Tag::make_float(double v) { Tag t; t.type = Type::Float; t.d = v; return t; }
inline Tag Tag::make_double(double v) { Tag t; t.type = Type::Double; t.d = v; return t; }
inline Tag Tag::make_string(std::string v) { Tag t; t.type = Type::String; t.s = std::move(v); return t; }
inline Tag Tag::make_compound() { Tag t; t.type = Type::Compound; return t; }
inline Tag Tag::make_list(Type elem) { Tag t; t.type = Type::List; t.list_type = elem; return t; }
inline Tag& Tag::set(std::string name, Tag v) {
  for (auto& [k, val] : compound)
    if (k == name) { val = std::move(v); return val; }
  compound.push_back(Entry{std::move(name), std::move(v)});
  return compound.back().second;
}
inline const Tag* Tag::find(std::string_view name) const {
  for (auto& [k, v] : compound)
    if (k == name) return &v;
  return nullptr;
}
inline i64 Tag::get_int(std::string_view name, i64 def) const {
  auto* t = find(name);
  return (t && t->type >= Type::Byte && t->type <= Type::Long) ? t->i : def;
}
inline double Tag::get_num(std::string_view name, double def) const {
  auto* t = find(name);
  if (!t) return def;
  if (t->type == Type::Float || t->type == Type::Double) return t->d;
  if (t->type >= Type::Byte && t->type <= Type::Long) return static_cast<double>(t->i);
  return def;
}
inline std::string Tag::get_string(std::string_view name, std::string def) const {
  auto* t = find(name);
  return (t && t->type == Type::String) ? t->s : def;
}
inline double Tag::list_num(size_t idx, double def) const {
  if (type != Type::List || idx >= list.size()) return def;
  const Tag& t = list[idx];
  return (t.type == Type::Float || t.type == Type::Double) ? t.d : static_cast<double>(t.i);
}

void write_payload(ByteWriter& w, const Tag& t);
// Writes a named root tag (type byte + name + payload).
void write_root(ByteWriter& w, std::string_view name, const Tag& t);
// Reads a payload of the given type. Returns false on malformed data.
bool read_payload(ByteReader& r, Type type, Tag& out, int depth = 0);
// Reads a named root tag. Empty optional on error.
std::optional<std::pair<std::string, Tag>> read_root(ByteReader& r);

}  // namespace ds::nbt
