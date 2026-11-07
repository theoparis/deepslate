module worldgen

import vinecraft.blocks
import math

pub fn (g &WorldGen) generate(px int, pz int, reg &blocks.Registry) &blocks.Chunk {
	mut c := blocks.new_chunk(px, pz)
	cols := g.columns(px, pz)
	for x in 0 .. 16 {
		for z in 0 .. 16 { c.biome[x * 16 + z] = cols[(z + pad) * ext + x + pad].biome }
	}
	g.carve(mut c, cols, reg, px, pz)
	g.ores(mut c, reg, px, pz)
	g.features(mut c, cols, reg, px, pz)
	c.recompute_heights(reg)
	c.dirty = true
	return c
}

fn (g &WorldGen) carve(mut c blocks.Chunk, cols []Column, reg &blocks.Registry, px int, pz int) {
	mut max_h := 0
	for x in 0 .. 16 {
		for z in 0 .. 16 { max_h = int(math.max(max_h, cols[(z + pad) * ext + x + pad].height)) }
	}
	ny := int(math.max(1, math.min(max_h, 200) + 61))
	mut ca := []f32{len: 256 * ny}
	mut cb := []f32{len: 256 * ny}
	mut ch := []f32{len: 256 * ny}
	wx := px * 16
	wz := pz * 16
	g.cave_a.grid3(mut ca, f32(wx), f32(wz), -60 * f32(1.4), 16, 16, ny, 1, 1, 1.4, g.s32 + 11)
	g.cave_b.grid3(mut cb, f32(wx), f32(wz), -60 * f32(1.4), 16, 16, ny, 1, 1, 1.4, g.s32 + 12)
	g.cheese.grid3(mut ch, f32(wx), f32(wz), -60 * f32(1.7), 16, 16, ny, 1, 1, 1.7, g.s32 + 13)
	stone := reg.find('stone')
	deep := reg.find('deepslate')
	bedrock := reg.find('bedrock')
	sand := reg.find('sand')
	snow := reg.find('snow')
	dirt := reg.find('dirt')
	water := reg.find('water')
	lava := reg.find('lava')
	for lx in 0 .. 16 {
		for lz in 0 .. 16 {
			col := cols[(lz + pad) * ext + lx + pad]
			h := col.height
			rnd := hash_unit(hash_coords(u64(g.seed), wx + lx, 7, wz + lz))
			mut top_block := reg.find('grass_block')
			mut filler := dirt
			mut depth := 3 + int(rnd * 2)
			match col.biome {
				2 {
					top_block = sand
					filler = sand
					depth = 4
				}
				16 {
					top_block = sand
					filler = sand
					depth = 3
				}
				0, 24, 10 {
					k := hash_unit(hash_coords(u64(g.seed), (wx + lx) >> 3, 3, (wz + lz) >> 3))
					top_block = if k < 0.15 {
						reg.find('gravel')
					} else if k < 0.25 {
						reg.find('clay')
					} else {
						sand
					}
					if h > 56 { top_block = sand }
					filler = top_block
				}
				12, 30 { top_block = snow }
				3 {
					if h > 150 {
						top_block = snow
						filler = snow
						depth = 1
					} else if h > 118 {
						top_block = stone
						filler = stone
						depth = 1
					}
				}
				else {}
			}
			if col.biome == 35 && rnd < 0.05 { top_block = reg.find('coarse_dirt') }
			top := int(math.max(h, sea_level))
			for y := -64; y <= top; y++ {
				mut id := blocks.BlockId(0)
				if y <= h {
					if y < -63 || (y < -59 && rnd * 5 > f32(y + 64)) {
						id = bedrock
					} else if y == h {
						id = top_block
					} else if y > h - depth {
						id = filler
					} else if y < 0 {
						id = deep
					} else if y < 8 && hash_unit(hash_coords(u64(g.seed), wx + lx, y, wz + lz)) < f32(8 - y) / 8 {
						id = deep
					} else {
						id = stone
					}
					if id == sand && y <= h - 4 && col.biome == 2 { id = reg.find('sandstone') }
					if y > -60 && y <= h - 1 && id != bedrock {
						yi := y + 60
						if yi >= 0 && yi < ny {
							gi := yi * 256 + lz * 16 + lx
							tunnel := math.abs(ca[gi]) < 0.07 && math.abs(cb[gi]) < 0.07
							cavern := ch[gi] > 1.1 && y < 48
							roof := h - y
							if (tunnel || cavern) && (roof > 4 || (tunnel && roof > 1 && h > sea_level + 2)) {
								id = if y < -54 { lava } else { blocks.BlockId(0) }
							}
						}
					}
				} else if y <= sea_level {
					id = if col.biome == 10 && y == sea_level { reg.find('ice') } else { water }
				}
				if id != 0 { c.set(lx, y, lz, id) }
			}
		}
	}
}
