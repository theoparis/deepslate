#include "nbt/nbt.hpp"

namespace ds::nbt {

void write_payload(ByteWriter& w, const Tag& t) {
  switch (t.type) {
    case Type::End: break;
    case Type::Byte: w.u8_(static_cast<u8>(t.i)); break;
    case Type::Short: w.i16le(static_cast<i16>(t.i)); break;
    case Type::Int: w.i32le(static_cast<i32>(t.i)); break;
    case Type::Long: w.i64le(t.i); break;
    case Type::Float: w.f32le(static_cast<float>(t.d)); break;
    case Type::Double: w.f64le(t.d); break;
    case Type::ByteArray: w.i32le(static_cast<i32>(t.bytes.size())); w.bytes(t.bytes); break;
    case Type::String: w.u16le(static_cast<u16>(t.s.size())); w.str(t.s); break;
    case Type::List:
      w.u8_(static_cast<u8>(t.list.empty() ? Type::End : t.list_type));
      w.i32le(static_cast<i32>(t.list.size()));
      for (auto& e : t.list) write_payload(w, e);
      break;
    case Type::Compound:
      for (auto& [k, v] : t.compound) {
        w.u8_(static_cast<u8>(v.type));
        w.u16le(static_cast<u16>(k.size()));
        w.str(k);
        write_payload(w, v);
      }
      w.u8_(0);
      break;
    case Type::IntArray:
      w.i32le(static_cast<i32>(t.ints.size()));
      for (i32 v : t.ints) w.i32le(v);
      break;
    case Type::LongArray:
      w.i32le(static_cast<i32>(t.longs.size()));
      for (i64 v : t.longs) w.i64le(v);
      break;
  }
}

void write_root(ByteWriter& w, std::string_view name, const Tag& t) {
  w.u8_(static_cast<u8>(t.type));
  w.u16le(static_cast<u16>(name.size()));
  w.str(name);
  write_payload(w, t);
}

bool read_payload(ByteReader& r, Type type, Tag& out, int depth) {
  if (depth > 64) return false;
  out = Tag{};
  out.type = type;
  switch (type) {
    case Type::End: return true;
    case Type::Byte: out.i = static_cast<i8>(r.u8_()); break;
    case Type::Short: out.i = r.i16le(); break;
    case Type::Int: out.i = r.i32le(); break;
    case Type::Long: out.i = r.i64le(); break;
    case Type::Float: out.d = r.f32le(); break;
    case Type::Double: out.d = r.f64le(); break;
    case Type::ByteArray: {
      i32 n = r.i32le();
      if (n < 0 || static_cast<size_t>(n) > r.remaining()) return false;
      auto b = r.bytes(static_cast<size_t>(n));
      out.bytes.assign(b.begin(), b.end());
      break;
    }
    case Type::String: {
      u16 n = r.u16le();
      out.s = r.str(n);
      break;
    }
    case Type::List: {
      auto et = static_cast<Type>(r.u8_());
      i32 n = r.i32le();
      if (n < 0 || static_cast<size_t>(n) > r.remaining() + 1) return false;
      out.list_type = et;
      out.list.resize(static_cast<size_t>(n));
      for (auto& e : out.list)
        if (!read_payload(r, et, e, depth + 1)) return false;
      break;
    }
    case Type::Compound: {
      for (;;) {
        if (!r.ok()) return false;
        auto t = static_cast<Type>(r.u8_());
        if (t == Type::End) break;
        u16 n = r.u16le();
        std::string name = r.str(n);
        Tag child;
        if (!read_payload(r, t, child, depth + 1)) return false;
        out.compound.push_back(Entry{std::move(name), std::move(child)});
      }
      break;
    }
    case Type::IntArray: {
      i32 n = r.i32le();
      if (n < 0 || static_cast<size_t>(n) * 4 > r.remaining()) return false;
      out.ints.resize(static_cast<size_t>(n));
      for (auto& v : out.ints) v = r.i32le();
      break;
    }
    case Type::LongArray: {
      i32 n = r.i32le();
      if (n < 0 || static_cast<size_t>(n) * 8 > r.remaining()) return false;
      out.longs.resize(static_cast<size_t>(n));
      for (auto& v : out.longs) v = r.i64le();
      break;
    }
    default: return false;
  }
  return r.ok();
}

std::optional<std::pair<std::string, Tag>> read_root(ByteReader& r) {
  auto t = static_cast<Type>(r.u8_());
  if (t == Type::End || !r.ok()) return std::nullopt;
  u16 n = r.u16le();
  std::string name = r.str(n);
  Tag tag;
  if (!read_payload(r, t, tag)) return std::nullopt;
  return std::make_pair(std::move(name), std::move(tag));
}

}  // namespace ds::nbt
