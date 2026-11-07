module blocks

fn test_chunk_bounds_heights_and_snapshot_isolation() {
	reg := new_registry()
	stone := reg.find('stone')
	water := reg.find('water')
	assert stone != 0 && water != 0
	mut c := new_chunk(-1, 2)
	assert !c.set(1, min_y - 1, 2, stone)
	assert !c.set(1, max_y, 2, stone)
	assert c.set(1, min_y, 2, stone)
	assert c.set(1, 10, 2, water)
	c.recompute_column_height(1, 2, reg)
	assert c.height[col_index(1, 2)] == 11
	assert c.light_height[col_index(1, 2)] == min_y + 1
	snapshot := c.snapshot()
	assert c.set(1, min_y, 2, 0)
	assert snapshot.get(1, min_y, 2) == stone
	assert c.get(1, min_y, 2) == 0
}
