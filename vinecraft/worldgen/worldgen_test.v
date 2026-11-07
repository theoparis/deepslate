module worldgen

import vinecraft.blocks

fn test_generation_is_deterministic() {
	mut gen := new_worldgen(7)
	reg := blocks.new_registry()
	a := gen.generate(-1, 2, reg)
	b := gen.generate(-1, 2, reg)
	assert a.height == b.height
	assert a.biome == b.biome
	for y in blocks.min_y .. blocks.max_y {
		assert a.get(3, y, 12) == b.get(3, y, 12)
	}
}
