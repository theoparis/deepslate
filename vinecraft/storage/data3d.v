module storage

import vinecraft.blocks
import vinecraft.nbt

struct BiomeStore {
mut:
	idx   []u16
	pal   []int
	valid bool
}

pub fn encode_data3d(snap blocks.ChunkSnapshot) []u8 {
	mut w := nbt.ByteWriter{}
	for z in 0 .. 16 {
		for x in 0 .. 16 { w.i16le(i16(int(snap.height[blocks.col_index(x, z)]) - blocks.min_y)) }
	}
	for _ in 0 .. blocks.num_subs {
		mut pal := []u8{}
		mut idx := []u16{len: 4096}
		for x in 0 .. 16 {
			for z in 0 .. 16 {
				b := snap.biome[blocks.col_index(x, z)]
				mut pi := pal.index(b)
				if pi < 0 {
					pi = pal.len
					pal << b
				}
				for y in 0 .. 16 { idx[(x << 8) | (z << 4) | y] = u16(pi) }
			}
		}
		if pal.len == 1 {
			w.u8_(1)
			w.i32le(int(pal[0]))
		} else {
			bits := pick_bits(pal.len)
			w.u8_(u8((bits << 1) | 1))
			pack_words(mut w, idx, bits)
			w.i32le(pal.len)
			for b in pal { w.i32le(int(b)) }
		}
	}
	return w.buf
}

pub fn decode_data3d(data []u8, mut c blocks.Chunk) {
	mut r := nbt.new_reader(data)
	for z in 0 .. 16 {
		for x in 0 .. 16 { c.height[blocks.col_index(x, z)] = i16(int(r.i16le()) + blocks.min_y) }
	}
	mut stores := []BiomeStore{cap: 32}
	for !r.eof() && r.ok() && stores.len < 32 {
		flag := r.u8_()
		mut st := BiomeStore{ idx: []u16{len: 4096} }
		if flag == 0xff {
			if stores.len > 0 { st = stores[stores.len - 1] }
		} else {
			bits := int(flag >> 1)
			if bits == 0 {
				st.pal << r.i32le()
			} else {
				st.idx = unpack_words(mut r, bits) or { break }
				count := r.i32le()
				if count < 0 || count > 4096 { break }
				for _ in 0 .. count { st.pal << r.i32le() }
			}
			st.valid = r.ok()
		}
		stores << st
	}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			ci := blocks.col_index(x, z)
			y := if int(c.height[ci]) - 1 > blocks.min_y {
				int(c.height[ci]) - 1
			} else {
				blocks.min_y
			}
			mut b := u8(1)
			if stores.len > 0 {
				mut si := (y >> 4) - blocks.min_sub
				if si < 0 { si = 0 }
				if si >= stores.len { si = stores.len - 1 }
				st := stores[si]
				if st.valid {
					pi := st.idx[(x << 8) | (z << 4) | (y & 15)]
					if int(pi) < st.pal.len { b = u8(st.pal[pi]) }
				}
			}
			c.biome[ci] = b
		}
	}
}
