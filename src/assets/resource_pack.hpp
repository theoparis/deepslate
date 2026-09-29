#pragma once
// Resource packs in the official Java-edition layout (assets/minecraft/...), read from a
// .zip/.jar, a directory, or an http(s) URL. Packs are layered; the procedurally generated
// built-in pack is always the lowest layer so a partial pack still renders.
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>

#include "util/common.hpp"

namespace ds {

class PackSource {
 public:
  virtual ~PackSource() = default;
  virtual std::optional<std::vector<u8>> read(const std::string& path) const = 0;
  virtual bool has(const std::string& path) const = 0;
  virtual std::string name() const = 0;
};

class PackStack {
 public:
  // Adds a pack on top of the stack (highest priority first-added-last). Returns false on error.
  bool add_spec(const std::string& spec, std::string* err);
  void add_builtin_fallback();
  void add(std::unique_ptr<PackSource> s) { layers_.push_back(std::move(s)); }  // appended = lower priority

  std::optional<std::vector<u8>> read(const std::string& path) const;
  bool has(const std::string& path) const;
  std::string describe() const;
  size_t layer_count() const { return layers_.size(); }

 private:
  std::vector<std::unique_ptr<PackSource>> layers_;  // index 0 = highest priority
};

std::unique_ptr<PackSource> open_zip_pack(const std::string& path, std::string* err);
std::unique_ptr<PackSource> open_dir_pack(const std::string& path, std::string* err);
std::unique_ptr<PackSource> make_builtin_pack();
// Downloads with libcurl into the cache directory; returns the local path.
std::optional<std::string> download_pack(const std::string& url, std::string* err);
// Writes the built-in pack as a directory tree (used by --write-builtin-pack and tests).
bool export_builtin_pack(const std::string& dir, std::string* err);
// Writes the built-in pack as a .zip file.
bool export_builtin_pack_zip(const std::string& zip_path, std::string* err);
std::vector<std::string> builtin_pack_files();

}  // namespace ds
