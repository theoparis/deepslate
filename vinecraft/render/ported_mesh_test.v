module render

import math
import vinecraft.assets
import vinecraft.blocks
import vinecraft.models

fn ported_mesh_input(mut chunk blocks.Chunk, reg &blocks.Registry) MeshInput {
	chunk.recompute_heights(reg)
	mut snapshots := [9]blocks.ChunkSnapshot{}
	for i in 0 .. 9 {
		if i == 4 {
			snapshots[i] = chunk.snapshot()
		} else {
			empty := blocks.new_chunk(i % 3 - 1, i / 3 - 1)
			snapshots[i] = empty.snapshot()
		}
	}
	return MeshInput{ chunks: snapshots, section: (64 >> 4) - blocks.min_sub }
}

fn test_ported_mesher_culls_hidden_faces() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut model := models.new_block_models(packs, reg, 256)
	stone := reg.find('stone')
	mut c := blocks.new_chunk(0, 0)
	assert mesh_section(ported_mesh_input(mut c, reg), reg, mut model).quads() == 0
	c.set(4, 64, 4, stone)
	assert mesh_section(ported_mesh_input(mut c, reg), reg, mut model).quads() == 6
	c.set(5, 64, 4, stone)
	assert mesh_section(ported_mesh_input(mut c, reg), reg, mut model).quads() == 10
	mut box := blocks.new_chunk(0, 0)
	for x in 3 .. 6 {
		for y in 64 .. 67 {
			for z in 3 .. 6 { box.set(x, y, z, stone) }
		}
	}
	assert mesh_section(ported_mesh_input(mut box, reg), reg, mut model).quads() == 54
}

fn test_ported_mesher_transparency_and_fluids() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut model := models.new_block_models(packs, reg, 256)
	mut c := blocks.new_chunk(0, 0)
	c.set(4, 64, 4, reg.find('glass'))
	c.set(5, 64, 4, reg.find('glass'))
	assert mesh_section(ported_mesh_input(mut c, reg), reg, mut model).quads() == 10
	mut water := blocks.new_chunk(0, 0)
	water.set(4, 64, 4, reg.find('water'))
	water.set(5, 64, 4, reg.find('water'))
	w := mesh_section(ported_mesh_input(mut water, reg), reg, mut model)
	assert w.opaque.len == 0
	assert w.translucent.len / 4 == 10
	mut top := f32(0)
	for v in w.translucent { if v.y > top { top = v.y } }
	assert top > 0.8 && top < 1.0
	water.set(5, 64, 4, reg.find('stone'))
	ws := mesh_section(ported_mesh_input(mut water, reg), reg, mut model)
	assert ws.translucent.len / 4 == 5
}

fn test_ported_mesher_lighting() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut model := models.new_block_models(packs, reg, 256)
	stone := reg.find('stone')
	mut open := blocks.new_chunk(0, 0)
	open.set(8, 64, 8, stone)
	mesh := mesh_section(ported_mesh_input(mut open, reg), reg, mut model)
	mut lit := 0
	for v in mesh.opaque { if v.sky == 255 { lit++ } }
	assert lit >= 4
	mut room := blocks.new_chunk(0, 0)
	for x in 2 .. 13 {
		for y in 60 .. 71 {
			for z in 2 .. 13 { room.set(x, y, z, stone) }
		}
	}
	for x in 3 .. 12 {
		for y in 61 .. 70 {
			for z in 3 .. 12 { room.set(x, y, z, 0) }
		}
	}
	room.set(4, 66, 4, reg.find('torch'))
	inside := mesh_section(ported_mesh_input(mut room, reg), reg, mut model)
	mut near_blk := u8(0)
	mut far_blk := u8(255)
	mut max_sky := u8(0)
	for v in inside.opaque {
		torch_geometry := math.abs(v.x - 4.5) < 0.2 && math.abs(v.z - 4.5) < 0.2 && v.y < 3.5
		if !torch_geometry && v.x >= 3 && v.x <= 12 && v.z >= 3 && v.z <= 12 && v.y > 0.5 && v.y <= 6 {
			d := math.abs(v.x - 4.5) + math.abs(v.z - 4.5)
			if d < 3 && v.blk > near_blk { near_blk = v.blk }
			if d > 9 && v.blk < far_blk { far_blk = v.blk }
			if v.sky > max_sky { max_sky = v.sky }
		}
	}
	assert near_blk > 150
	assert far_blk < near_blk
	assert max_sky < 30
}

fn ported_same_vertices(a []Vertex, b []Vertex) bool {
	if a.len != b.len { return false }
	for i, v in a {
		w := b[i]
		if v.x != w.x || v.y != w.y || v.z != w.z || v.u != w.u || v.v != w.v || v.layer != w.layer || v.r != w.r || v.g != w.g || v.b != w.b || v.a != w.a || v.sky != w.sky || v.blk != w.blk || v.flags != w.flags || v.pad != w.pad {
			return false
		}
	}
	return true
}

fn ported_mesh_worker(input &MeshInput, reg &blocks.Registry, mut model models.BlockModels, reference []Vertex) bool {
	for _ in 0 .. 10 {
		mesh := mesh_section(input, reg, mut model)
		if !ported_same_vertices(mesh.opaque, reference) { return false }
	}
	return true
}

fn test_ported_mesher_is_thread_safe_and_deterministic() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut model := models.new_block_models(packs, reg, 256)
	mut chunk := blocks.new_chunk(0, 0)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for y in 50 .. 66 { chunk.set(x, y, z, reg.find('stone')) }
			chunk.set(x, 66, z, reg.find('grass_block'))
		}
	}
	chunk.set(8, 67, 8, reg.find('torch'))
	input := ported_mesh_input(mut chunk, reg)
	reference := mesh_section(&input, reg, mut model)
	mut threads := []thread bool{}
	for _ in 0 .. 4 {
		threads << spawn ported_mesh_worker(&input, reg, mut model, reference.opaque)
	}
	for t in threads {
		assert t.wait()
	}
}
