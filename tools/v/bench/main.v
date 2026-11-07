module main

import os
import time
import vinecraft.assets
import vinecraft.blocks
import vinecraft.models
import vinecraft.render
import vinecraft.worldgen

fn main() {
	seed := if os.args.len > 1 { os.args[1].i64() } else { i64(42) }
	n := if os.args.len > 2 { os.args[2].int() } else { 8 }
	reg := blocks.new_registry()
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	mut model := models.new_block_models(packs, reg, 1024)
	model.build()
	gen := worldgen.new_worldgen(seed)
	mut chunks := []&blocks.Chunk{cap: n * n}
	mut started := time.sys_mono_now()
	for z in 0 .. n {
		for x in 0 .. n { chunks << gen.generate(x - n / 2, z - n / 2, reg) }
	}
	gen_ms := f64(time.sys_mono_now() - started) / 1e6
	println('generate: ${n * n} chunks in ${gen_ms} ms  (${gen_ms / f64(n * n)} ms/chunk)')
	started = time.sys_mono_now()
	mut sections := 0
	mut quads := 0
	for z := 1; z < n - 1; z++ {
		for x := 1; x < n - 1; x++ {
			mut snapshots := [9]blocks.ChunkSnapshot{}
			for dz := -1; dz <= 1; dz++ {
				for dx := -1; dx <= 1; dx++ {
					snapshots[(dz + 1) * 3 + dx + 1] = chunks[(z + dz) * n + x + dx].snapshot()
				}
			}
			c := chunks[z * n + x]
			for s in 0 .. blocks.num_subs {
				if c.subs[s].len == 0 { continue }
				input := render.MeshInput{ chunks: snapshots, section: s }
				mesh := render.mesh_section(&input, reg, mut model)
				sections++
				quads += mesh.quads()
			}
		}
	}
	mesh_ms := f64(time.sys_mono_now() - started) / 1e6
	println('mesh: ${sections} sections in ${mesh_ms} ms  (${mesh_ms / f64(sections)} ms/section, ${quads / sections} quads/section)')
}
