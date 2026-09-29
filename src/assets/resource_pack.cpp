#include "assets/resource_pack.hpp"

#include <archive.h>
#include <archive_entry.h>
#include <curl/curl.h>

#include <filesystem>
#include <fstream>

namespace ds {

namespace fs = std::filesystem;

namespace {

// Only these parts of a pack are needed; skipping the rest keeps loading a full client jar fast.
bool wanted(const std::string& p) {
  static constexpr std::string_view prefixes[] = {
      "assets/minecraft/blockstates/",     "assets/minecraft/models/block/",     "assets/minecraft/textures/block/",
      "assets/minecraft/textures/colormap/", "assets/minecraft/textures/font/",   "assets/minecraft/textures/gui/",
      "assets/minecraft/textures/environment/", "assets/minecraft/textures/item/", "pack.mcmeta", "pack.png"};
  for (auto pre : prefixes)
    if (p.starts_with(pre)) return true;
  return false;
}

class ZipPack : public PackSource {
 public:
  std::string label;
  std::unordered_map<std::string, std::vector<u8>> files;
  std::optional<std::vector<u8>> read(const std::string& path) const override {
    auto it = files.find(path);
    if (it == files.end()) return std::nullopt;
    return it->second;
  }
  bool has(const std::string& path) const override { return files.contains(path); }
  std::string name() const override { return label; }
  std::vector<std::string> list(const std::string& prefix) const override {
    std::vector<std::string> v;
    for (auto& [k, _] : files)
      if (k.starts_with(prefix)) v.push_back(k);
    return v;
  }
};

class DirPack : public PackSource {
 public:
  fs::path root;
  std::optional<std::vector<u8>> read(const std::string& path) const override {
    std::ifstream f(root / path, std::ios::binary);
    if (!f) return std::nullopt;
    return std::vector<u8>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  }
  bool has(const std::string& path) const override {
    std::error_code ec;
    return fs::is_regular_file(root / path, ec);
  }
  std::string name() const override { return root.string(); }
  std::vector<std::string> list(const std::string& prefix) const override {
    std::vector<std::string> v;
    std::error_code ec;
    for (auto it = fs::recursive_directory_iterator(root, ec); !ec && it != fs::recursive_directory_iterator(); it.increment(ec)) {
      if (!it->is_regular_file()) continue;
      std::string rel = fs::relative(it->path(), root).generic_string();
      if (rel.starts_with(prefix)) v.push_back(rel);
    }
    return v;
  }
};

size_t curl_write(char* p, size_t sz, size_t n, void* ud) {
  auto* out = static_cast<std::vector<u8>*>(ud);
  out->insert(out->end(), reinterpret_cast<u8*>(p), reinterpret_cast<u8*>(p) + sz * n);
  return sz * n;
}

}  // namespace

std::unique_ptr<PackSource> open_zip_pack(const std::string& path, std::string* err) {
  archive* a = archive_read_new();
  archive_read_support_format_zip(a);
  if (archive_read_open_filename(a, path.c_str(), 1 << 20) != ARCHIVE_OK) {
    if (err) *err = std::string("cannot open archive: ") + archive_error_string(a);
    archive_read_free(a);
    return nullptr;
  }
  auto pack = std::make_unique<ZipPack>();
  pack->label = path;
  archive_entry* e;
  std::vector<u8> buf;
  while (archive_read_next_header(a, &e) == ARCHIVE_OK) {
    std::string name = archive_entry_pathname(e);
    if (name.ends_with('/') || !wanted(name)) {
      archive_read_data_skip(a);
      continue;
    }
    buf.clear();
    u8 tmp[65536];
    la_ssize_t n;
    while ((n = archive_read_data(a, tmp, sizeof tmp)) > 0) buf.insert(buf.end(), tmp, tmp + n);
    if (n < 0) {
      log_warn("{}: error reading '{}': {}", path, name, archive_error_string(a));
      continue;
    }
    pack->files.emplace(std::move(name), buf);
  }
  archive_read_free(a);
  if (pack->files.empty()) {
    if (err) *err = "archive contains no resource pack assets";
    return nullptr;
  }
  return pack;
}

std::unique_ptr<PackSource> open_dir_pack(const std::string& path, std::string* err) {
  auto p = std::make_unique<DirPack>();
  p->root = path;
  if (!p->has("pack.mcmeta") && !fs::is_directory(fs::path(path) / "assets")) {
    if (err) *err = "directory does not look like a resource pack (no pack.mcmeta or assets/)";
    return nullptr;
  }
  return p;
}

std::optional<std::string> download_pack(const std::string& url, std::string* err) {
  fs::path cache;
  if (const char* x = std::getenv("XDG_CACHE_HOME")) cache = x;
  else if (const char* h = std::getenv("HOME")) cache = fs::path(h) / ".cache";
  else cache = fs::temp_directory_path();
  cache /= "deepslate-edition/packs";
  std::error_code ec;
  fs::create_directories(cache, ec);
  fs::path target = cache / (std::format("{:016x}", mix64(std::hash<std::string>{}(url))) + ".zip");
  if (fs::exists(target)) {
    log_info("using cached download {}", target.string());
    return target.string();
  }
  CURL* c = curl_easy_init();
  if (!c) { if (err) *err = "curl init failed"; return std::nullopt; }
  std::vector<u8> body;
  curl_easy_setopt(c, CURLOPT_URL, url.c_str());
  curl_easy_setopt(c, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, curl_write);
  curl_easy_setopt(c, CURLOPT_WRITEDATA, &body);
  curl_easy_setopt(c, CURLOPT_FAILONERROR, 1L);
  curl_easy_setopt(c, CURLOPT_USERAGENT, "deepslate-edition/0.1");
  if (const char* ca = std::getenv("CURL_CA_BUNDLE")) curl_easy_setopt(c, CURLOPT_CAINFO, ca);
  else if (const char* ca2 = std::getenv("SSL_CERT_FILE")) curl_easy_setopt(c, CURLOPT_CAINFO, ca2);
  log_info("downloading resource pack {}", url);
  CURLcode rc = curl_easy_perform(c);
  curl_easy_cleanup(c);
  if (rc != CURLE_OK) {
    if (err) *err = std::string("download failed: ") + curl_easy_strerror(rc);
    return std::nullopt;
  }
  fs::path tmp = target;
  tmp += ".part";
  {
    std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
    f.write(reinterpret_cast<const char*>(body.data()), static_cast<std::streamsize>(body.size()));
  }
  fs::rename(tmp, target, ec);
  if (ec) { if (err) *err = "cannot write cache: " + ec.message(); return std::nullopt; }
  return target.string();
}

bool PackStack::add_spec(const std::string& spec, std::string* err) {
  std::string path = spec;
  if (spec.starts_with("http://") || spec.starts_with("https://")) {
    auto p = download_pack(spec, err);
    if (!p) return false;
    path = *p;
  }
  std::error_code ec;
  std::unique_ptr<PackSource> src;
  if (fs::is_directory(path, ec)) src = open_dir_pack(path, err);
  else if (fs::is_regular_file(path, ec)) src = open_zip_pack(path, err);
  else { if (err) *err = "no such file or directory: " + path; return false; }
  if (!src) return false;
  log_info("resource pack: {}", src->name());
  layers_.push_back(std::move(src));
  return true;
}

void PackStack::add_builtin_fallback() { layers_.push_back(make_builtin_pack()); }

std::optional<std::vector<u8>> PackStack::read(const std::string& path) const {
  for (auto& l : layers_)
    if (auto d = l->read(path)) return d;
  return std::nullopt;
}

bool PackStack::has(const std::string& path) const {
  for (auto& l : layers_)
    if (l->has(path)) return true;
  return false;
}

std::vector<std::string> PackStack::list(const std::string& prefix) const {
  std::vector<std::string> v;
  for (auto& l : layers_) {
    auto part = l->list(prefix);
    v.insert(v.end(), part.begin(), part.end());
  }
  std::sort(v.begin(), v.end());
  v.erase(std::unique(v.begin(), v.end()), v.end());
  return v;
}

std::string PackStack::describe() const {
  std::string s;
  for (auto& l : layers_) {
    if (!s.empty()) s += " > ";
    s += l->name();
  }
  return s;
}

bool export_builtin_pack(const std::string& dir, std::string* err) {
  auto pack = make_builtin_pack();
  for (const std::string& f : builtin_pack_files()) {
    auto data = pack->read(f);
    if (!data) continue;
    fs::path p = fs::path(dir) / f;
    std::error_code ec;
    fs::create_directories(p.parent_path(), ec);
    std::ofstream o(p, std::ios::binary | std::ios::trunc);
    if (!o) { if (err) *err = "cannot write " + p.string(); return false; }
    o.write(reinterpret_cast<const char*>(data->data()), static_cast<std::streamsize>(data->size()));
  }
  return true;
}

bool export_builtin_pack_zip(const std::string& zip_path, std::string* err) {
  archive* a = archive_write_new();
  archive_write_set_format_zip(a);
  if (archive_write_open_filename(a, zip_path.c_str()) != ARCHIVE_OK) {
    if (err) *err = archive_error_string(a);
    archive_write_free(a);
    return false;
  }
  auto pack = make_builtin_pack();
  for (const std::string& f : builtin_pack_files()) {
    auto data = pack->read(f);
    if (!data) continue;
    archive_entry* e = archive_entry_new();
    archive_entry_set_pathname(e, f.c_str());
    archive_entry_set_size(e, static_cast<la_int64_t>(data->size()));
    archive_entry_set_filetype(e, AE_IFREG);
    archive_entry_set_perm(e, 0644);
    archive_write_header(a, e);
    archive_write_data(a, data->data(), data->size());
    archive_entry_free(e);
  }
  archive_write_close(a);
  archive_write_free(a);
  return true;
}

}  // namespace ds
