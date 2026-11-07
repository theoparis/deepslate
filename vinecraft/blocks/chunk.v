module blocks

pub const chunk_w = 16
pub const min_y = -64
pub const max_y = 320
pub const num_subs = 24
pub const min_sub = -4
pub const biome_ocean = u8(0)
pub const biome_plains = u8(1)
pub const biome_desert = u8(2)
pub const biome_hills = u8(3)
pub const biome_forest = u8(4)
pub const biome_taiga = u8(5)
pub const biome_swamp = u8(6)
pub const biome_frozen_ocean = u8(10)
pub const biome_snowy_plains = u8(12)
pub const biome_beach = u8(16)
pub const biome_jungle = u8(21)
pub const biome_deep_ocean = u8(24)
pub const biome_birch_forest = u8(27)
pub const biome_dark_forest = u8(29)
pub const biome_cold_taiga = u8(30)
pub const biome_savanna = u8(35)

pub struct Climate {
pub:
	temperature f32
	downfall    f32
}

pub fn biome_climate(b u8) Climate {
	return match b {
		biome_ocean, biome_deep_ocean { Climate{0.5, 0.5} }
		biome_desert { Climate{2, 0} }
		biome_hills { Climate{0.2, 0.3} }
		biome_forest, biome_dark_forest { Climate{0.7, 0.8} }
		biome_taiga { Climate{0.25, 0.8} }
		biome_swamp { Climate{0.8, 0.9} }
		biome_frozen_ocean, biome_snowy_plains { Climate{0, 0.5} }
		biome_birch_forest { Climate{0.6, 0.6} }
		biome_cold_taiga { Climate{-0.5, 0.4} }
		biome_savanna { Climate{1.2, 0} }
		biome_jungle { Climate{0.95, 0.9} }
		else { Climate{0.8, 0.4} }
	}
}

pub fn sub_index(x int, y int, z int) int { return (x << 8) | (z << 4) | y }

pub fn col_index(x int, z int) int { return x * 16 + z }

pub struct ChunkPos {
pub mut:
	x int
	z int
}

pub struct Chunk {
pub mut:
	pos          ChunkPos
	subs         [24][]BlockId
	height       [256]i16
	light_height [256]i16
	biome        [256]u8
	dirty        bool
}

pub struct ChunkSnapshot {
pub:
	pos          ChunkPos
	subs         [24][]BlockId
	height       [256]i16
	light_height [256]i16
	biome        [256]u8
}

pub fn new_chunk(x int, z int) &Chunk {
	mut c := &Chunk{ pos: ChunkPos{ x: x, z: z } }
	for i in 0 .. 256 {
		c.height[i] = min_y
		c.light_height[i] = min_y
	}
	return c
}

pub fn (c &Chunk) get(x int, y int, z int) BlockId {
	if y < min_y || y >= max_y { return 0 }
	s := c.subs[(y >> 4) - min_sub]
	return if s.len == 0 { BlockId(0) } else { s[sub_index(x, y & 15, z)] }
}

pub fn (c ChunkSnapshot) get(x int, y int, z int) BlockId {
	if y < min_y || y >= max_y { return 0 }
	s := c.subs[(y >> 4) - min_sub]
	return if s.len == 0 { BlockId(0) } else { s[sub_index(x, y & 15, z)] }
}

pub fn (mut c Chunk) set(x int, y int, z int, id BlockId) bool {
	if y < min_y || y >= max_y { return false }
	si := (y >> 4) - min_sub
	if c.subs[si].len == 0 {
		if id == 0 { return false }
		c.subs[si] = []BlockId{len: 4096}
	}
	i := sub_index(x, y & 15, z)
	if c.subs[si][i] == id { return false }
	c.subs[si][i] = id
	return true
}

pub fn (mut c Chunk) recompute_column_height(x int, z int, r &Registry) {
	mut h := min_y
	mut lh := min_y
	for si := num_subs - 1; si >= 0 && lh == min_y; si-- {
		s := c.subs[si]
		if s.len == 0 { continue }
		for y := 15; y >= 0; y-- {
			id := s[sub_index(x, y, z)]
			if id == 0 { continue }
			wy := (si + min_sub) * 16 + y + 1
			flags := r.info(id).flags
			if h == min_y && flags & (bf_opaque | bf_liquid | bf_leaves) != 0 { h = wy }
			if flags & bf_opaque != 0 {
				lh = wy
				break
			}
		}
	}
	if h == min_y { h = lh }
	c.height[col_index(x, z)] = i16(h)
	c.light_height[col_index(x, z)] = i16(lh)
}

pub fn (mut c Chunk) recompute_heights(r &Registry) {
	for x in 0 .. 16 {
		for z in 0 .. 16 { c.recompute_column_height(x, z, r) }
	}
}

pub fn (c &Chunk) snapshot() ChunkSnapshot {
	mut subs := [24][]BlockId{}
	for i in 0 .. num_subs { subs[i] = c.subs[i].clone() }
	return ChunkSnapshot{ pos: c.pos, subs: subs, height: c.height, light_height: c.light_height, biome: c.biome }
}

pub fn (c &Chunk) empty() bool {
	for s in c.subs { if s.len != 0 { return false } }
	return true
}
