#include "assets/block_models.hpp"
#include "world/chunk.hpp"

#include <simdjson.h>

#include <numbers>

namespace ds {

namespace {

constexpr int kDirCount = 6;
const int kDirVec[6][3] = {{0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}, {-1, 0, 0}, {1, 0, 0}};

int dir_from_name(std::string_view s) {
  if (s == "down") return DOWN;
  if (s == "up") return UP;
  if (s == "north") return NORTH;
  if (s == "south") return SOUTH;
  if (s == "west") return WEST;
  if (s == "east") return EAST;
  return -1;
}

// Vertex selectors: 0 = min corner, 1 = max corner per axis; last = uv corner index.
struct FaceVert { int sx, sy, sz, uvc; };
const FaceVert kFaceVerts[6][4] = {
    /*down*/ {{0, 0, 1, 0}, {0, 0, 0, 1}, {1, 0, 0, 2}, {1, 0, 1, 3}},
    /*up*/ {{0, 1, 0, 0}, {0, 1, 1, 1}, {1, 1, 1, 2}, {1, 1, 0, 3}},
    /*north*/ {{1, 1, 0, 0}, {1, 0, 0, 1}, {0, 0, 0, 2}, {0, 1, 0, 3}},
    /*south*/ {{0, 1, 1, 0}, {0, 0, 1, 1}, {1, 0, 1, 2}, {1, 1, 1, 3}},
    /*west*/ {{0, 1, 0, 0}, {0, 0, 0, 1}, {0, 0, 1, 2}, {0, 1, 1, 3}},
    /*east*/ {{1, 1, 1, 0}, {1, 0, 1, 1}, {1, 0, 0, 2}, {1, 1, 0, 3}},
};

std::string strip_ns(std::string s) {
  if (s.starts_with("minecraft:")) s.erase(0, 10);
  return s;
}

// Rotates a point (relative to centre) about an axis by angle degrees (multiples of 90 for
// blockstate rotation; arbitrary for element rotation). Axis: 0=x, 1=y, 2=z.
void rotate_axis(float p[3], int axis, float deg, bool clockwise_y = false) {
  float r = deg * std::numbers::pi_v<float> / 180.0f;
  float c = std::cos(r), s = std::sin(r);
  float a, b;
  switch (axis) {
    case 0: a = p[1]; b = p[2]; p[1] = a * c - b * s; p[2] = a * s + b * c; break;   // x: up -> south
    case 1:                                                                          // y: clockwise from above
      a = p[0]; b = p[2];
      if (clockwise_y) { p[0] = a * c - b * s; p[2] = a * s + b * c; }
      else { p[0] = a * c + b * s; p[2] = -a * s + b * c; }
      break;
    default: a = p[0]; b = p[1]; p[0] = a * c - b * s; p[1] = a * s + b * c; break;
  }
}

int dir_of_vec(const float v[3]) {
  int best = UP;
  float bd = -2;
  for (int d = 0; d < kDirCount; d++) {
    float dot = v[0] * kDirVec[d][0] + v[1] * kDirVec[d][1] + v[2] * kDirVec[d][2];
    if (dot > bd) { bd = dot; best = d; }
  }
  return best;
}

}  // namespace

// ------------------------------------------------------------------ data model

struct BlockModels::Element {
  float from[3], to[3];
  bool has_rot = false;
  float origin[3] = {8, 8, 8};
  int axis = 1;
  float angle = 0;
  bool rescale = false;
  bool shade = true;
  struct Face {
    bool present = false;
    bool has_uv = false;
    float uv[4] = {0, 0, 16, 16};
    std::string texture;
    int cull = -1;
    int rotation = 0;
    int tint = -1;
  } faces[6];
};

struct BlockModels::Model {
  std::string parent;
  std::map<std::string, std::string> textures;
  std::vector<Element> elements;
  bool has_elements = false;
  bool ao = true;
  // Resolved:
  bool resolved = false;
  std::map<std::string, std::string> all_textures;
  const std::vector<Element>* final_elements = nullptr;
  std::vector<Element> owned_elements;
};

struct BlockModels::BlockState {
  struct Variant { std::vector<std::pair<std::string, std::string>> key; std::vector<ModelRef> models; };
  struct Part {
    bool has_when = false;
    // OR of ANDs of (prop -> allowed values).
    std::vector<std::vector<std::pair<std::string, std::vector<std::string>>>> when;
    std::vector<ModelRef> models;
  };
  std::vector<Variant> variants;
  std::vector<Part> parts;
  bool valid = false;
};

// ------------------------------------------------------------------ ctor / atlas

BlockModels::~BlockModels() = default;

BlockModels::BlockModels(const PackStack& packs) : packs_(packs) {
  table_ = std::make_unique<std::atomic<const BakedBlock*>[]>(65536);
  for (int i = 0; i < 65536; i++) table_[i].store(nullptr, std::memory_order_relaxed);

  // Tile size = width of the pack's stone texture (usually 16, or 32/64/128... for HD packs).
  for (const char* probe : {"block/stone", "block/dirt", "block/grass_block_top"}) {
    if (auto data = packs_.read(std::string("assets/minecraft/textures/") + probe + ".png"))
      if (auto img = decode_png(*data)) { tile_ = clampv(img->w, 8, 512); break; }
  }
  capacity_ = std::max(256, std::min(2048, (96 * 1024 * 1024) / (tile_ * tile_ * 4)));
  pixels_.reserve(static_cast<size_t>(capacity_) * tile_ * tile_ * 4);

  // Layer 0: the classic magenta/black "missing texture".
  std::vector<u8> missing(static_cast<size_t>(tile_) * tile_ * 4);
  for (int y = 0; y < tile_; y++)
    for (int x = 0; x < tile_; x++) {
      bool m = ((x * 2 / tile_) + (y * 2 / tile_)) % 2 == 0;
      u8* p = &missing[(static_cast<size_t>(y) * tile_ + x) * 4];
      p[0] = m ? 248 : 0; p[1] = 0; p[2] = m ? 248 : 0; p[3] = 255;
    }
  pixels_.insert(pixels_.end(), missing.begin(), missing.end());
  layers_.store(1);
  anim_.assign(2, 1.0f);
  layer_ids_["<missing>"] = 0;
  init_tints();
}

BlockModels::Frames BlockModels::load_frames(const std::string& texture, bool* found) {
  *found = false;
  Frames out;
  auto data = packs_.read("assets/minecraft/textures/" + texture + ".png");
  if (!data) return out;
  auto img = decode_png(*data);
  if (!img || img->empty()) return out;
  *found = true;
  // Animated textures are vertical strips of square frames plus an optional .mcmeta.
  const int fw = img->w;
  int nframes = (img->h > img->w && img->w > 0) ? img->h / img->w : 1;
  std::vector<int> seq;
  if (nframes > 1) {
    if (auto meta = packs_.read("assets/minecraft/textures/" + texture + ".png.mcmeta")) {
      try {
        simdjson::dom::parser parser;
        simdjson::padded_string ps(reinterpret_cast<const char*>(meta->data()), meta->size());
        simdjson::dom::element doc;
        if (!parser.parse(ps).get(doc)) {
          int64_t ft;
          if (!doc["animation"]["frametime"].get(ft)) out.frametime = static_cast<int>(std::max<int64_t>(1, ft));
          simdjson::dom::array frames;
          if (!doc["animation"]["frames"].get(frames)) {
            for (simdjson::dom::element f : frames) {
              int64_t idx, t;
              if (!f.get(idx)) seq.push_back(static_cast<int>(idx));
              else if (!f["index"].get(idx)) {
                int reps = 1;
                if (!f["time"].get(t)) reps = static_cast<int>(std::max<int64_t>(1, t / out.frametime));
                for (int r = 0; r < reps && r < 16; r++) seq.push_back(static_cast<int>(idx));
              }
            }
          }
        }
      } catch (const simdjson::simdjson_error&) {}
    }
    if (seq.empty()) for (int i = 0; i < nframes; i++) seq.push_back(i);
    for (int& i : seq) i = clampv(i, 0, nframes - 1);
    if (seq.size() > 64) seq.resize(64);
  } else {
    seq.push_back(0);
  }
  for (int fi : seq) {
    Image tile = Image::make(tile_, tile_);
    for (int y = 0; y < tile_; y++)
      for (int x = 0; x < tile_; x++)
        std::memcpy(tile.px(x, y), img->px(x * fw / tile_, fi * fw + y * fw / tile_), 4);
    out.images.push_back(std::move(tile));
  }
  return out;
}

u16 BlockModels::add_layer_locked(const std::string& name) {
  std::string n = strip_ns(name);
  if (auto it = layer_ids_.find(n); it != layer_ids_.end()) return it->second;
  bool found = false;
  Frames fr = load_frames(n, &found);
  size_t idx = layers_.load();
  const size_t need = fr.images.size();
  if (!found || static_cast<int>(idx + need) > capacity_) {
    if (!found) log_debug("missing texture: {}", n);
    layer_ids_[n] = 0;
    return 0;
  }
  for (auto& img : fr.images) pixels_.insert(pixels_.end(), img.rgba.begin(), img.rgba.end());
  anim_.resize((idx + need) * 2, 1.0f);
  anim_[idx * 2] = static_cast<float>(need);
  anim_[idx * 2 + 1] = static_cast<float>(fr.frametime);
  layers_.store(idx + need, std::memory_order_release);
  layer_ids_[n] = static_cast<u16>(idx);
  return static_cast<u16>(idx);
}

u16 BlockModels::layer_of(const std::string& texture) {
  std::lock_guard lk(m_);
  return add_layer_locked(texture);
}

size_t BlockModels::layer_count() const { return layers_.load(std::memory_order_acquire); }

size_t BlockModels::copy_anim(std::vector<float>& out) const {
  std::lock_guard lk(m_);
  out = anim_;
  out.resize(layers_.load() * 2, 1.0f);
  return out.size() / 2;
}

size_t BlockModels::copy_layers(size_t from, std::vector<u8>& out) const {
  std::lock_guard lk(m_);
  size_t n = layers_.load();
  size_t bytes = static_cast<size_t>(tile_) * tile_ * 4;
  out.assign(pixels_.begin() + static_cast<std::ptrdiff_t>(from * bytes), pixels_.begin() + static_cast<std::ptrdiff_t>(n * bytes));
  return n;
}

// ------------------------------------------------------------------ tints

void BlockModels::init_tints() {
  auto read_map = [&](const char* name, Image& out) {
    if (auto d = packs_.read(std::string("assets/minecraft/textures/colormap/") + name + ".png"))
      if (auto img = decode_png(*d)) out = std::move(*img);
  };
  read_map("grass", grass_map_);
  read_map("foliage", foliage_map_);
  auto sample = [](const Image& m, float temp, float down, u32 fallback) -> u32 {
    if (m.empty()) return fallback;
    temp = clampv(temp, 0.0f, 1.0f);
    down = clampv(down, 0.0f, 1.0f) * temp;
    int x = clampv(static_cast<int>((1.0f - temp) * (m.w - 1)), 0, m.w - 1);
    int y = clampv(static_cast<int>((1.0f - down) * (m.h - 1)), 0, m.h - 1);
    const u8* p = m.px(x, y);
    return (u32(p[0]) << 16) | (u32(p[1]) << 8) | p[2];
  };
  for (int b = 0; b < 256; b++) {
    auto cl = Biome::climate(static_cast<u8>(b));
    tints_[static_cast<int>(Tint::None)][b] = 0xFFFFFF;
    tints_[static_cast<int>(Tint::Grass)][b] = sample(grass_map_, cl.temperature, cl.downfall, 0x91BD59);
    tints_[static_cast<int>(Tint::Foliage)][b] = sample(foliage_map_, cl.temperature, cl.downfall, 0x77AB2F);
    tints_[static_cast<int>(Tint::Birch)][b] = 0x80A755;
    tints_[static_cast<int>(Tint::Spruce)][b] = 0x619961;
    u32 water = 0x3F76E4;
    switch (b) {
      case Biome::FrozenOcean: water = 0x3938C9; break;
      case Biome::Swamp: water = 0x617B64; break;
      case Biome::Taiga: case Biome::ColdTaiga: case Biome::SnowyPlains: water = 0x3D57D6; break;
      default: break;
    }
    tints_[static_cast<int>(Tint::Water)][b] = water;
  }
}

// ------------------------------------------------------------------ JSON loading

namespace {

using simdjson::dom::element;

bool get_floats(simdjson::simdjson_result<element> r, float* out, int n) {
  element e;
  simdjson::dom::array arr;
  if (r.get(e) || e.get(arr)) return false;
  int i = 0;
  for (element v : arr) {
    if (i >= n) break;
    double d;
    if (v.get(d)) return false;
    out[i++] = static_cast<float>(d);
  }
  return i == n;
}

}  // namespace

const BlockModels::Model* BlockModels::load_model(const std::string& raw_name, int depth) {
  std::string name = strip_ns(raw_name);
  if (auto it = models_.find(name); it != models_.end()) return it->second.get();
  if (depth > 16) return nullptr;
  auto data = packs_.read("assets/minecraft/models/" + name + ".json");
  if (!data) {
    models_[name] = nullptr;
    return nullptr;
  }
  auto model = std::make_unique<Model>();
  try {
    simdjson::dom::parser parser;
    simdjson::padded_string ps(reinterpret_cast<const char*>(data->data()), data->size());
    element doc;
    if (parser.parse(ps).get(doc)) {
      log_warn("model {}: invalid JSON", name);
      models_[name] = nullptr;
      return nullptr;
    }
    std::string_view sv;
    if (!doc["parent"].get(sv)) model->parent = strip_ns(std::string(sv));
    bool ao;
    if (!doc["ambientocclusion"].get(ao)) model->ao = ao;
    simdjson::dom::object tex;
    if (!doc["textures"].get(tex))
      for (auto [k, v] : tex)
        if (!v.get(sv)) model->textures[std::string(k)] = std::string(sv);
    simdjson::dom::array elems;
    if (!doc["elements"].get(elems)) {
      model->has_elements = true;
      for (element e : elems) {
        Element el{};
        if (!get_floats(e["from"], el.from, 3) || !get_floats(e["to"], el.to, 3)) continue;
        simdjson::dom::object rot;
        if (!e["rotation"].get(rot)) {
          element r = e["rotation"];
          el.has_rot = true;
          get_floats(r["origin"], el.origin, 3);
          std::string_view ax;
          if (!r["axis"].get(ax)) el.axis = ax == "x" ? 0 : (ax == "y" ? 1 : 2);
          double a;
          if (!r["angle"].get(a)) el.angle = static_cast<float>(a);
          bool rs;
          if (!r["rescale"].get(rs)) el.rescale = rs;
        }
        bool sh;
        if (!e["shade"].get(sh)) el.shade = sh;
        simdjson::dom::object faces;
        if (!e["faces"].get(faces)) {
          for (auto [fname, fv] : faces) {
            int d = dir_from_name(fname);
            if (d < 0) continue;
            Element::Face& f = el.faces[d];
            f.present = true;
            if (!fv["texture"].get(sv)) f.texture = std::string(sv);
            if (get_floats(fv["uv"], f.uv, 4)) f.has_uv = true;
            if (!fv["cullface"].get(sv)) f.cull = dir_from_name(sv);
            int64_t iv;
            if (!fv["rotation"].get(iv)) f.rotation = static_cast<int>(iv);
            if (!fv["tintindex"].get(iv)) f.tint = static_cast<int>(iv);
          }
        }
        model->elements.push_back(std::move(el));
      }
    }
  } catch (const simdjson::simdjson_error& err) {
    log_warn("model {}: {}", name, err.what());
    models_[name] = nullptr;
    return nullptr;
  }
  // Resolve the parent chain (parents are loaded first; recursion is bounded).
  Model* raw = model.get();
  models_[name] = std::move(model);
  const Model* parent = raw->parent.empty() ? nullptr : load_model(raw->parent, depth + 1);
  raw->all_textures = parent ? parent->all_textures : std::map<std::string, std::string>{};
  for (auto& [k, v] : raw->textures) raw->all_textures[k] = v;
  if (raw->has_elements) raw->final_elements = &raw->elements;
  else if (parent) raw->final_elements = parent->final_elements;
  if (!raw->has_elements && parent) raw->ao = parent->ao && raw->ao;
  raw->resolved = true;
  return raw;
}

const BlockModels::BlockState* BlockModels::load_blockstate(const std::string& name) {
  if (auto it = states_.find(name); it != states_.end()) return it->second.get();
  auto data = packs_.read("assets/minecraft/blockstates/" + name + ".json");
  auto bs = std::make_unique<BlockState>();
  if (data) try {
    simdjson::dom::parser parser;
    simdjson::padded_string ps(reinterpret_cast<const char*>(data->data()), data->size());
    element doc;
    if (!parser.parse(ps).get(doc)) {
      auto parse_models = [](element e, std::vector<ModelRef>& out) {
        auto one = [&](element m) {
          ModelRef r;
          std::string_view sv;
          if (m["model"].get(sv)) return;
          r.name = strip_ns(std::string(sv));
          int64_t iv;
          if (!m["x"].get(iv)) r.x = static_cast<int>(iv);
          if (!m["y"].get(iv)) r.y = static_cast<int>(iv);
          bool b;
          if (!m["uvlock"].get(b)) r.uvlock = b;
          out.push_back(std::move(r));
        };
        simdjson::dom::array arr;
        if (!e.get(arr)) { for (element m : arr) one(m); }  // weighted list: we use the first entry
        else one(e);
      };
      simdjson::dom::object variants;
      if (!doc["variants"].get(variants)) {
        for (auto [k, v] : variants) {
          BlockState::Variant var;
          std::string key(k);
          size_t pos = 0;
          while (pos < key.size()) {
            size_t comma = key.find(',', pos);
            std::string kv = key.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
            if (auto eq = kv.find('='); eq != std::string::npos) var.key.emplace_back(kv.substr(0, eq), kv.substr(eq + 1));
            if (comma == std::string::npos) break;
            pos = comma + 1;
          }
          parse_models(v, var.models);
          if (!var.models.empty()) bs->variants.push_back(std::move(var));
        }
      }
      simdjson::dom::array multipart;
      if (!doc["multipart"].get(multipart)) {
        for (element p : multipart) {
          BlockState::Part part;
          parse_models(p["apply"], part.models);
          simdjson::dom::object when;
          if (!p["when"].get(when)) {
            part.has_when = true;
            auto parse_conds = [](simdjson::dom::object o) {
              std::vector<std::pair<std::string, std::vector<std::string>>> conds;
              for (auto [ck, cv] : o) {
                std::string_view sv;
                std::vector<std::string> vals;
                std::string s;
                bool b;
                if (!cv.get(sv)) s = std::string(sv);
                else if (!cv.get(b)) s = b ? "true" : "false";
                size_t pos = 0;
                while (pos <= s.size()) {
                  size_t bar = s.find('|', pos);
                  vals.push_back(s.substr(pos, bar == std::string::npos ? std::string::npos : bar - pos));
                  if (bar == std::string::npos) break;
                  pos = bar + 1;
                }
                conds.emplace_back(std::string(ck), std::move(vals));
              }
              return conds;
            };
            simdjson::dom::array orarr;
            if (!p["when"]["OR"].get(orarr)) {
              for (element c : orarr) {
                simdjson::dom::object co;
                if (!c.get(co)) part.when.push_back(parse_conds(co));
              }
            } else {
              part.when.push_back(parse_conds(when));
            }
          }
          if (!part.models.empty()) bs->parts.push_back(std::move(part));
        }
      }
      bs->valid = !bs->variants.empty() || !bs->parts.empty();
    }
  } catch (const simdjson::simdjson_error& err) {
    log_warn("blockstate {}: {}", name, err.what());
    bs->valid = false;
  }
  auto* raw = bs.get();
  states_[name] = std::move(bs);
  return raw;
}

// ------------------------------------------------------------------ baking

void BlockModels::bake_model(const ModelRef& ref, int /*hint*/, BakedBlock& out) {
  const Model* model = load_model(ref.name);
  if (!model || !model->final_elements) {
    out.missing = true;
    return;
  }
  auto resolve_tex = [&](std::string t) -> u16 {
    for (int i = 0; i < 16 && t.starts_with('#'); i++) {
      auto it = model->all_textures.find(t.substr(1));
      if (it == model->all_textures.end()) return 0;
      t = it->second;
    }
    if (t.starts_with('#') || t.empty()) return 0;
    return add_layer_locked(t);
  };

  for (const Element& el : *model->final_elements) {
    for (int d = 0; d < kDirCount; d++) {
      const Element::Face& f = el.faces[d];
      if (!f.present) continue;
      BakedQuad q{};
      q.layer = resolve_tex(f.texture);
      q.cull = static_cast<i8>(f.cull);
      q.tint = static_cast<i8>(f.tint);
      q.shade = el.shade;
      q.dir = static_cast<i8>(d);

      // Default UVs from the element box (vanilla rules).
      float u[4];
      if (f.has_uv) std::memcpy(u, f.uv, sizeof u);
      else {
        const float *a = el.from, *b = el.to;
        switch (d) {
          case DOWN: u[0] = a[0]; u[1] = 16 - b[2]; u[2] = b[0]; u[3] = 16 - a[2]; break;
          case UP: u[0] = a[0]; u[1] = a[2]; u[2] = b[0]; u[3] = b[2]; break;
          case NORTH: u[0] = 16 - b[0]; u[1] = 16 - b[1]; u[2] = 16 - a[0]; u[3] = 16 - a[1]; break;
          case SOUTH: u[0] = a[0]; u[1] = 16 - b[1]; u[2] = b[0]; u[3] = 16 - a[1]; break;
          case WEST: u[0] = a[2]; u[1] = 16 - b[1]; u[2] = b[2]; u[3] = 16 - a[1]; break;
          default: u[0] = 16 - b[2]; u[1] = 16 - b[1]; u[2] = 16 - a[2]; u[3] = 16 - a[1]; break;
        }
      }
      const float corner[4][2] = {{u[0] / 16, u[1] / 16}, {u[0] / 16, u[3] / 16}, {u[2] / 16, u[3] / 16}, {u[2] / 16, u[1] / 16}};
      const int rot = ((f.rotation % 360) + 360) % 360 / 90;

      for (int v = 0; v < 4; v++) {
        const FaceVert& fv = kFaceVerts[d][v];
        float p[3] = {(fv.sx ? el.to[0] : el.from[0]), (fv.sy ? el.to[1] : el.from[1]), (fv.sz ? el.to[2] : el.from[2])};
        if (el.has_rot && el.angle != 0.0f) {
          float rel[3] = {p[0] - el.origin[0], p[1] - el.origin[1], p[2] - el.origin[2]};
          rotate_axis(rel, el.axis, el.angle);
          if (el.rescale) {
            float k = 1.0f / std::cos(std::abs(el.angle) * std::numbers::pi_v<float> / 180.0f);
            for (int a = 0; a < 3; a++)
              if (a != el.axis) rel[a] *= k;
          }
          for (int a = 0; a < 3; a++) p[a] = rel[a] + el.origin[a];
        }
        for (int a = 0; a < 3; a++) q.pos[v][a] = p[a] / 16.0f;
        const float* c = corner[(fv.uvc + rot) % 4];
        q.uv[v][0] = c[0];
        q.uv[v][1] = c[1];
      }

      // Blockstate rotation about the block centre (x first, then y).
      if (ref.x || ref.y) {
        auto xf = [&](float p[3]) {
          for (int a = 0; a < 3; a++) p[a] -= 0.5f;
          if (ref.x) rotate_axis(p, 0, static_cast<float>(ref.x));
          if (ref.y) rotate_axis(p, 1, static_cast<float>(ref.y), true);
        };
        for (int v = 0; v < 4; v++) {
          xf(q.pos[v]);
          for (int a = 0; a < 3; a++) q.pos[v][a] += 0.5f;
        }
        auto rot_dir = [&](int dir) {
          float vec[3] = {float(kDirVec[dir][0]), float(kDirVec[dir][1]), float(kDirVec[dir][2])};
          if (ref.x) rotate_axis(vec, 0, static_cast<float>(ref.x));
          if (ref.y) rotate_axis(vec, 1, static_cast<float>(ref.y), true);
          return dir_of_vec(vec);
        };
        q.dir = static_cast<i8>(rot_dir(q.dir));
        if (q.cull >= 0) q.cull = static_cast<i8>(rot_dir(q.cull));
      }

      // Boundary check for AO.
      {
        static const int kAxisOfDir[6] = {1, 1, 2, 2, 0, 0};
        const int axis = kAxisOfDir[q.dir];
        const float want = (q.dir % 2) ? 1.0f : 0.0f;
        bool on = true;
        for (int v = 0; v < 4; v++)
          if (std::abs(q.pos[v][axis] - want) > 1e-3f) on = false;
        q.boundary = on;
      }
      out.quads.push_back(q);
    }
  }
}

void BlockModels::bake_locked(BlockId id) {
  const BlockInfo& bi = Blocks::get().info(id);
  auto baked = std::make_unique<BakedBlock>();
  const BlockDef* def = bi.def;
  if (def && (def->kind == Kind::Air || def->kind == Kind::Liquid)) {
    // Air and fluids have no model; the mesher draws fluids itself.
    if (def->kind == Kind::Liquid) {
      water_layer_ = add_layer_locked("block/water_still");
      lava_layer_ = add_layer_locked("block/lava_still");
    }
  } else {
    std::string sname = bi.def && !(bi.flags & BF_Unknown) ? bi.def->java_name() : bi.name.substr(bi.name.find(':') + 1);
    const BlockState* bs = load_blockstate(sname);
    std::vector<ModelRef> refs;
    if (bs && bs->valid) {
      auto prop = [&](const std::string& k) -> const std::string* {
        for (auto& [pk, pv] : bi.java_props)
          if (pk == k) return &pv;
        return nullptr;
      };
      if (!bs->variants.empty()) {
        const BlockState::Variant* best = nullptr;
        int best_score = -1;
        for (auto& v : bs->variants) {
          bool ok = true;
          for (auto& [k, val] : v.key) {
            const std::string* mine = prop(k);
            if (!mine || *mine != val) { ok = false; break; }
          }
          int score = ok ? static_cast<int>(v.key.size()) : -1;
          if (score > best_score) { best_score = score; best = &v; }
        }
        if (!best) best = &bs->variants.front();
        refs.push_back(best->models.front());
      }
      for (auto& part : bs->parts) {
        bool match = !part.has_when;
        for (auto& conj : part.when) {
          bool all = true;
          for (auto& [k, vals] : conj) {
            const std::string* mine = prop(k);
            if (!mine || std::find(vals.begin(), vals.end(), *mine) == vals.end()) { all = false; break; }
          }
          if (all) { match = true; break; }
        }
        if (match) refs.push_back(part.models.front());
      }
    }
    if (refs.empty()) baked->missing = true;
    for (auto& r : refs) bake_model(r, -1, *baked);
    if (baked->quads.empty()) {
      // Model or blockstate not found in any pack layer: draw a missing-texture cube.
      baked->missing = true;
      ModelRef cube{"block/cube_all", 0, 0, false};
      if (const Model* m = load_model("block/cube")) {
        (void)m;
      }
      for (int d = 0; d < 6; d++) {
        BakedQuad q{};
        q.layer = 0;
        q.cull = static_cast<i8>(d);
        q.dir = static_cast<i8>(d);
        q.boundary = true;
        for (int v = 0; v < 4; v++) {
          const FaceVert& fv = kFaceVerts[d][v];
          q.pos[v][0] = static_cast<float>(fv.sx);
          q.pos[v][1] = static_cast<float>(fv.sy);
          q.pos[v][2] = static_cast<float>(fv.sz);
          q.uv[v][0] = (fv.uvc == 2 || fv.uvc == 3) ? 1.0f : 0.0f;
          q.uv[v][1] = (fv.uvc == 1 || fv.uvc == 2) ? 1.0f : 0.0f;
        }
        baked->quads.push_back(q);
      }
    }
  }
  const BakedBlock* raw = baked.get();
  owned_.push_back(std::move(baked));
  table_[id].store(raw, std::memory_order_release);
}

void BlockModels::bake(BlockId id) {
  std::lock_guard lk(m_);
  if (!table_[id].load()) bake_locked(id);
}

void BlockModels::build() {
  std::lock_guard lk(m_);
  BlockId n = Blocks::get().count();
  for (BlockId id = 0; id < n; id++)
    if (!table_[id].load()) bake_locked(id);
  // Fluids need their layers even if no fluid block gets baked first.
  water_layer_ = add_layer_locked("block/water_still");
  lava_layer_ = add_layer_locked("block/lava_still");
  size_t missing = 0;
  for (BlockId id = 0; id < n; id++)
    if (table_[id].load()->missing) {
      missing++;
      if (missing <= 8) log_warn("no model for block state {}", Blocks::get().info(id).name);
    }
  log_info("baked {} block states, {} atlas layers ({}px), {} missing models", n, layers_.load(), tile_, missing);
}

BlockModels::Icon BlockModels::icon(BlockId id) const {
  Icon ic;
  const BakedBlock* b = baked(id);
  if (!b || b->quads.empty()) {
    const BlockInfo& bi = Blocks::get().info(id);
    if (bi.liquid()) { ic.top = ic.left = ic.right = bi.name.ends_with("lava") ? lava_layer_ : water_layer_; }
    return ic;
  }
  bool have_top = false, have_left = false, have_right = false;
  bool cubeish = false;
  int boundary_faces = 0;
  for (auto& q : b->quads)
    if (q.boundary) boundary_faces++;
  cubeish = boundary_faces >= 3;
  for (auto& q : b->quads) {
    if (cubeish && !q.boundary) continue;
    if (q.dir == UP && !have_top) { ic.top = q.layer; have_top = true; }
    else if (q.dir == SOUTH && !have_left) { ic.left = q.layer; have_left = true; }
    else if (q.dir == EAST && !have_right) { ic.right = q.layer; have_right = true; }
  }
  if (!cubeish) {
    ic.flat = true;
    ic.top = ic.left = ic.right = b->quads.front().layer;
  } else {
    if (!have_top) ic.top = ic.left;
    if (!have_left) ic.left = ic.top;
    if (!have_right) ic.right = ic.left;
  }
  return ic;
}

}  // namespace ds
