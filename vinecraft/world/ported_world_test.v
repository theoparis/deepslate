module world

import io.util
import os
import time
import vinecraft.blocks
import vinecraft.storage
import vinecraft.worldgen

fn ported_load_around(mut w World, x f64, z f64, cx int, cz int, radius int) bool {
	for _ in 0 .. 4000 {
		w.update(x, z, radius)
		if w.all_loaded_around(cx, cz, radius) && w.inflight_count() == 0 { return true }
		time.sleep(2 * time.millisecond)
	}
	return false
}

fn test_ported_world_streams_and_unloads() {
	dir := util.temp_dir(pattern: 'deepslate-stream-*') or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	mut store := storage.open(dir, 3) or { panic(err) }
	mut gen := worldgen.new_worldgen(3)
	reg := blocks.new_registry()
	mut w := new_world(mut store, reg, &gen, 3, false)
	defer {
		w.shutdown() or { panic(err) }
		store.close() or { panic(err) }
	}
	assert ported_load_around(mut w, 8, 8, 0, 0, 3)
	assert w.loaded_count() >= 29
	assert w.chunks_generated() >= 29
	assert ported_load_around(mut w, 648, 8, 40, 0, 3)
	for _ in 0 .. 100 { w.update(648, 8, 3) }
	assert !w.column_loaded(0, 0)
	assert w.column_loaded(40, 0)
	assert w.take_errors().len == 0
}

fn test_ported_world_dirty_edits_persist() {
	dir := util.temp_dir(pattern: 'deepslate-edits-*') or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	mut store := storage.open(dir, 3) or { panic(err) }
	mut gen := worldgen.new_worldgen(3)
	mut reg := blocks.new_registry()
	mut w := new_world(mut store, reg, &gen, 3, false)
	defer {
		w.shutdown() or { panic(err) }
		store.close() or { panic(err) }
	}
	assert ported_load_around(mut w, 8, 8, 0, 0, 2)
	assert w.take_dirty().len > 0
	glowstone := reg.find('glowstone')
	stone := reg.find('stone')
	assert w.set_block(3, 100, 3, glowstone)
	assert w.get_block(3, 100, 3) == glowstone
	assert !w.set_block(3, 100, 3, glowstone)
	mut found_center := false
	for d in w.take_dirty() {
		if d.x == 0 && d.z == 0 && d.section_mask & (u32(1) << u32((100 >> 4) - blocks.min_sub)) != 0 {
			found_center = true
		}
	}
	assert found_center
	assert w.set_block(15, 100, 5, stone)
	mut neighbour := false
	for d in w.take_dirty() { if d.x == 1 && d.z == 0 { neighbour = true } }
	assert neighbour
	assert !w.set_block(1000000, 10, 0, stone)
	w.save_dirty(true) or { panic(err) }
	reloaded := store.load_chunk(blocks.ChunkPos{ x: 0, z: 0 }, mut reg) or { panic(err) }
	assert reloaded.get(3, 100, 3) == glowstone
	assert reloaded.get(15, 100, 5) == stone
	assert w.take_errors().len == 0
}
