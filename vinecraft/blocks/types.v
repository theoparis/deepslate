module blocks

pub type BlockId = u16

pub enum StateKind {
	byte_value
	int_value
	string_value
}

pub struct StateValue {
pub:
	kind StateKind
	i    int
	s    string
}

pub fn state_byte(v int) StateValue { return StateValue{ kind: .byte_value, i: v } }

pub fn state_int_value(v int) StateValue { return StateValue{ kind: .int_value, i: v } }

pub fn state_string(v string) StateValue { return StateValue{ kind: .string_value, s: v } }

pub struct StateEntry {
pub:
	key   string
	value StateValue
}

pub type StateMap = []StateEntry

pub const bf_solid = u32(1 << 0)
pub const bf_opaque = u32(1 << 1)
pub const bf_liquid = u32(1 << 2)
pub const bf_replaceable = u32(1 << 3)
pub const bf_cutout = u32(1 << 4)
pub const bf_translucent = u32(1 << 5)
pub const bf_emissive = u32(1 << 6)
pub const bf_unbreakable = u32(1 << 7)
pub const bf_plant = u32(1 << 8)
pub const bf_leaves = u32(1 << 9)
pub const bf_no_target = u32(1 << 10)
pub const bf_unknown = u32(1 << 11)
pub const solid = bf_solid | bf_opaque

pub enum Kind {
	air
	cube_all
	column
	bottom_top
	grass
	cross
	slab
	stairs
	cactus
	torch
	liquid
}

pub enum Tint {
	none
	grass
	foliage
	water
	birch
	spruce
}

pub enum TexStyle {
	noise
	stone
	ore
	planks
	log_side
	log_top
	leaves
	bricks
	stone_bricks
	plant
	flower
	glass
	sand
	dirt
	grass_top
	grass_side
	grass_overlay
	cactus
	torch
	sandstone
	bookshelf
	crafting
	tnt
	hay
	pumpkin
	gravel
	snow
	ice
	reeds
	mushroom
	dead_bush
	fern
	water
	lava
	deepslate
	tuff
	glowstone
	obsidian
	bedrock
}

pub struct TexRecipe {
pub mut:
	name  string
	style TexStyle
	c1    u32
	c2    u32
}

pub struct BlockDef {
pub mut:
	name     string
	display  string
	kind     Kind = .cube_all
	tint     Tint
	flags    u32
	emit     u8
	color    u32 = 0xff00ff
	java     string
	tex      [3]string
	overlay  string
	creative bool = true
	recipes  []TexRecipe
}

pub fn (d BlockDef) java_name() string { return if d.java == '' { d.name } else { d.java } }

pub struct Box {
pub:
	min [3]f32
	max [3]f32
}

pub struct JavaProp {
pub:
	key   string
	value string
}

pub struct BlockInfo {
pub mut:
	name          string
	states        StateMap
	def           BlockDef
	flags         u32
	emit          u8
	fluid_depth   u8
	tint          Tint
	nbox          u8
	boxes         [2]Box
	java_props    []JavaProp
	java_override string
	display       string
	color         u32 = 0xff00ff
}

pub fn (b BlockInfo) solid() bool { return b.flags & bf_solid != 0 }

pub fn (b BlockInfo) opaque() bool { return b.flags & bf_opaque != 0 }

pub fn (b BlockInfo) liquid() bool { return b.flags & bf_liquid != 0 }

pub fn (b BlockInfo) replaceable() bool { return b.flags & bf_replaceable != 0 }
