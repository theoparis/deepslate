module worldgen

import vinecraft.blocks

fn same_generated_blocks(a &blocks.Chunk, b &blocks.Chunk) bool {
	for s in 0 .. blocks.num_subs {
		if a.subs[s] != b.subs[s] { return false }
	}
	return true
}

fn generation_worker(g &WorldGen, reg &blocks.Registry, reference &blocks.Chunk, worker int) bool {
	for i in 0 .. 6 {
		chunk := g.generate(3, 3, reg)
		if !same_generated_blocks(chunk, reference) || chunk.biome != reference.biome {
			return false
		}
		g.generate(3 + worker, 4 + i, reg)
	}
	return true
}

fn test_ported_worldgen_seed_determinism() {
	mut a := new_worldgen(1234)
	mut b := new_worldgen(1234)
	mut c := new_worldgen(4321)
	reg := blocks.new_registry()
	ca := a.generate(5, -9, reg)
	cb := b.generate(5, -9, reg)
	cc := c.generate(5, -9, reg)
	assert same_generated_blocks(ca, cb)
	assert ca.biome == cb.biome
	assert !same_generated_blocks(ca, cc)
}

fn test_ported_worldgen_structure() {
	mut gen := new_worldgen(77)
	reg := blocks.new_registry()
	bedrock := reg.find('bedrock')
	grass := reg.find('grass_block')
	water := reg.find('water')
	ice := reg.find('ice')
	mut water_cols := 0
	mut land_cols := 0
	for cz in -6 .. 6 {
		for cx in -6 .. 6 {
			chunk := gen.generate(cx * 7, cz * 7, reg)
			for x := 0; x < 16; x += 5 {
				for z := 0; z < 16; z += 5 {
					assert chunk.get(x, -64, z) == bedrock
					assert chunk.get(x, -20, z) != grass
					h := chunk.height[blocks.col_index(x, z)]
					assert h > blocks.min_y && h < blocks.max_y
					id := chunk.get(x, sea_level, z)
					if id == water || id == ice { water_cols++ } else { land_cols++ }
				}
			}
		}
	}
	assert water_cols > 20
	assert land_cols > 20
}

fn test_ported_worldgen_concurrent_determinism() {
	mut gen := new_worldgen(99)
	reg := blocks.new_registry()
	reference := gen.generate(3, 3, reg)
	mut threads := []thread bool{}
	for t in 0 .. 4 { threads << spawn generation_worker(&gen, reg, reference, t) }
	for worker in threads {
		assert worker.wait()
	}
}

fn test_ported_surface_height_matches_chunk() {
	mut gen := new_worldgen(5)
	reg := blocks.new_registry()
	chunk := gen.generate(2, 2, reg)
	for x := 0; x < 16; x += 3 {
		for z := 0; z < 16; z += 3 {
			h := gen.surface_height(32 + x, 32 + z)
			assert chunk.get(x, h, z) != 0
		}
	}
}
