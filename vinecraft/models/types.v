module models

import vinecraft.blocks
import vinecraft.assets
import sync

pub const down = 0
pub const up = 1
pub const north = 2
pub const south = 3
pub const west = 4
pub const east = 5

pub struct BakedQuad {
pub mut:
	pos      [4][3]f32
	uv       [4][2]f32
	layer    u16
	cull     i8   = -1
	dir      i8   = 1
	tint     i8   = -1
	shade    bool = true
	boundary bool
}

pub struct Alt {
pub mut:
	quads  []BakedQuad
	weight int = 1
}

pub struct BakedBlock {
pub mut:
	quads        []BakedQuad
	alts         []Alt
	total_weight int
	missing      bool
}

pub fn (b BakedBlock) pick(hash u64) []BakedQuad {
	if b.alts.len == 0 || b.total_weight <= 0 { return b.quads }
	mut r := int(hash % u64(b.total_weight))
	for a in b.alts {
		if r < a.weight { return a.quads }
		r -= a.weight
	}
	return b.alts.last().quads
}

pub struct Icon {
pub mut:
	top   u16
	left  u16
	right u16
	flat  bool
}

struct Face {
mut:
	present  bool
	has_uv   bool
	uv       [4]f32
	texture  string
	cull     int = -1
	rotation int
	tint     int = -1
}

struct Element {
mut:
	from    [3]f32
	to      [3]f32
	has_rot bool
	origin  [3]f32 = [f32(8), 8, 8]!
	axis    int    = 1
	angle   f32
	rescale bool
	shade   bool = true
	faces   [6]Face
}

struct Model {
mut:
	parent         string
	textures       map[string]string
	elements       []Element
	has_elements   bool
	ao             bool = true
	all_textures   map[string]string
	final_elements []Element
	has_final      bool
}

struct ModelRef {
mut:
	name   string
	x      int
	y      int
	uvlock bool
	weight int = 1
}

struct Variant {
mut:
	key    map[string]string
	models []ModelRef
}

struct Part {
mut:
	has_when bool
	when     []map[string][]string
	models   []ModelRef
}

struct BlockState {
mut:
	variants []Variant
	parts    []Part
	valid    bool
}

pub struct BlockModels {
mut:
	packs      &assets.PackStack = unsafe { nil }
	registry   &blocks.Registry  = unsafe { nil }
	tile       int               = 16
	cap_layers int               = 1024
	pixels     []u8
	anim       []f32
	layer_ids  map[string]u16
	water      u16
	lava       u16
	tints      [6][256]u32
	models     map[string]Model
	states     map[string]BlockState
	table      map[u16]BakedBlock
	mutex      sync.Mutex
}

fn strip_ns(s string) string { return if s.starts_with('minecraft:') { s[10..] } else { s } }

fn dir_name(s string) int {
	return match s {
		'down' { 0 }
		'up' { 1 }
		'north' { 2 }
		'south' { 3 }
		'west' { 4 }
		'east' { 5 }
		else { -1 }
	}
}
