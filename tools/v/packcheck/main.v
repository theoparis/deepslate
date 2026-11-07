module main

import os
import vinecraft.assets
import vinecraft.blocks
import vinecraft.models

struct CheckedBlock {
	name string
	id   blocks.BlockId
}

fn main() {
	if os.args.len < 2 {
		eprintln('usage: packcheck <pack> [--verbose]')
		exit(2)
	}
	verbose := os.args.len > 2 && os.args[2] == '--verbose'
	mut packs := &assets.PackStack{}
	packs.add_spec(os.args[1]) or {
		eprintln('error: ${err.msg()}')
		exit(1)
	}
	packs.add_builtin_fallback()
	mut registry := blocks.new_registry()
	mut baker := models.new_block_models(packs, registry, 2048)
	mut ids := []CheckedBlock{}
	prefix := 'assets/minecraft/blockstates/'
	for path in packs.list(prefix) {
		if !path.ends_with('.json') { continue }
		name := path[prefix.len..path.len - 5]
		if name.contains('/') { continue }
		id := registry.lookup_or_register('minecraft:${name}', [blocks.StateEntry{
			key:   '__packcheck'
			value: blocks.state_byte(1)
		}])
		ids << CheckedBlock{ name: name, id: id }
	}
	baker.build()
	mut no_model := 0
	mut bad_tex := 0
	mut quads := 0
	for checked in ids {
		baked := baker.baked(checked.id) or { continue }
		quads += baked.quads.len
		mut missing_layers := 0
		for quad in baked.quads {
			if quad.layer == 0 { missing_layers++ }
		}
		if baked.missing || baked.quads.len == 0 {
			no_model++
			if verbose { println('no model:       ${checked.name}') }
		} else if missing_layers > 0 {
			bad_tex++
			if verbose {
				println('missing texture: ${checked.name} (${missing_layers}/${baked.quads.len} quads)')
			}
		}
	}
	println('blockstates: ${ids.len}, baked quads: ${quads}, atlas layers: ${baker.layer_count()} (${baker.tile_size()}px)')
	println('  without a usable model: ${no_model}')
	println('  with unresolved textures: ${bad_tex}')
}
