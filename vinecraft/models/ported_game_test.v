module models

import vinecraft.assets
import vinecraft.blocks

fn test_ported_baked_block_geometry_and_missing_fallback() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	mut reg := blocks.new_registry()
	mut models := new_block_models(packs, reg, 256)
	for name in ['stone', 'grass_block', 'short_grass', 'torch', 'water', 'air'] {
		models.bake(reg.find(name))
	}
	stone := models.baked(reg.find('stone')) or { panic('stone not baked') }
	grass := models.baked(reg.find('grass_block')) or { panic('grass not baked') }
	plant := models.baked(reg.find('short_grass')) or { panic('plant not baked') }
	torch := models.baked(reg.find('torch')) or { panic('torch not baked') }
	water := models.baked(reg.find('water')) or { panic('water not baked') }
	air := models.baked(reg.find('air')) or { panic('air not baked') }
	assert stone.quads.len == 6 && !stone.missing
	assert grass.quads.len == 10 && !grass.missing
	mut tinted := 0
	for q in grass.quads { if q.tint >= 0 { tinted++ } }
	assert tinted == 5
	assert plant.quads.len == 4 && !plant.missing
	assert torch.quads.len == 6 && !torch.missing
	assert water.quads.len == 0
	assert air.quads.len == 0
	future := reg.lookup_or_register('minecraft:some_future_block', [])
	models.bake(future)
	missing := models.baked(future) or { panic('missing block not baked') }
	assert missing.missing && missing.quads.len == 6
	assert missing.quads[0].layer == 0
}

fn test_ported_weighted_variant_selection() {
	// Distinct layers identify the selected alternative without relying on array identity.
	b := BakedBlock{
		alts:         [Alt{ quads: [BakedQuad{ layer: 1 }], weight: 1 },
			Alt{ quads: [BakedQuad{ layer: 2 }], weight: 2 },
			Alt{ quads: [BakedQuad{ layer: 3 }], weight: 1 }]
		total_weight: 4
	}
	assert b.pick(0)[0].layer == 1
	assert b.pick(1)[0].layer == 2
	assert b.pick(2)[0].layer == 2
	assert b.pick(3)[0].layer == 3
	assert b.pick(5)[0].layer == 2
}

fn ported_model_state(mut reg blocks.Registry, name string, key string, value string) blocks.BlockId {
	return reg.lookup_or_register('minecraft:${name}', [blocks.StateEntry{ key: key, value: blocks.state_string(value) }])
}

fn ported_layer_for_direction(b BakedBlock, direction int) u16 {
	for q in b.quads { if q.dir == direction { return q.layer } }
	return 65535
}

fn test_ported_rotated_log_and_stairs_models() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	mut reg := blocks.new_registry()
	log_x := ported_model_state(mut reg, 'oak_log', 'pillar_axis', 'x')
	mut models := new_block_models(packs, reg, 256)
	models.bake(log_x)
	models.bake(reg.find('oak_log'))
	x_log := models.baked(log_x) or { panic('x log not baked') }
	y_log := models.baked(reg.find('oak_log')) or { panic('y log not baked') }
	top := models.layer_of('block/oak_log_top')
	side := models.layer_of('block/oak_log')
	assert ported_layer_for_direction(y_log, up) == top
	assert ported_layer_for_direction(x_log, east) == top
	assert ported_layer_for_direction(x_log, up) == side
	stairs_e := reg.lookup_or_register('minecraft:oak_stairs', [
		blocks.StateEntry{ key: 'weirdo_direction', value: blocks.state_int_value(0) },
		blocks.StateEntry{ key: 'upside_down_bit', value: blocks.state_byte(0) },
	])
	stairs_s := reg.lookup_or_register('minecraft:oak_stairs', [
		blocks.StateEntry{ key: 'weirdo_direction', value: blocks.state_int_value(2) },
		blocks.StateEntry{ key: 'upside_down_bit', value: blocks.state_byte(0) },
	])
	models.bake(stairs_e)
	models.bake(stairs_s)
	e := models.baked(stairs_e) or { panic('east stairs not baked') }
	s := models.baked(stairs_s) or { panic('south stairs not baked') }
	mut e_min_x := f32(1)
	mut s_min_x := f32(1)
	mut s_min_z := f32(1)
	for q in e.quads {
		if q.dir == up {
			for v in q.pos { if v[1] > 0.99 && v[0] < e_min_x { e_min_x = v[0] } }
		}
	}
	for q in s.quads {
		if q.dir == up {
			for v in q.pos {
				if v[1] > 0.99 {
					if v[0] < s_min_x { s_min_x = v[0] }
					if v[2] < s_min_z { s_min_z = v[2] }
				}
			}
		}
	}
	assert e_min_x > 0.4999 && e_min_x < 0.5001
	assert s_min_z > 0.4999 && s_min_z < 0.5001
	assert s_min_x > -0.0001 && s_min_x < 0.0001
}

fn test_ported_wall_torch_models_and_selection_shape() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	mut reg := blocks.new_registry()
	east_id := ported_model_state(mut reg, 'torch', 'torch_facing_direction', 'east')
	west_id := ported_model_state(mut reg, 'torch', 'torch_facing_direction', 'west')
	south_id := ported_model_state(mut reg, 'torch', 'torch_facing_direction', 'south')
	mut models := new_block_models(packs, reg, 256)
	models.bake(east_id)
	models.bake(south_id)
	models.bake(reg.find('torch'))
	east_torch := models.baked(east_id) or { panic('east torch not baked') }
	south_torch := models.baked(south_id) or { panic('south torch not baked') }
	standing := models.baked(reg.find('torch')) or { panic('standing torch not baked') }
	assert !east_torch.missing && east_torch.quads.len == 6
	mut top_x := f32(0)
	mut bottom_x := f32(1)
	for q in east_torch.quads {
		for v in q.pos {
			if v[1] > 0.7 && v[0] > top_x { top_x = v[0] }
			if v[1] < 0.3 && v[0] < bottom_x { bottom_x = v[0] }
		}
	}
	assert top_x > bottom_x + 0.1
	assert east_torch.quads[0].pos[0][0] < standing.quads[0].pos[0][0] - 0.05
	mut top_z := f32(0)
	mut bottom_z := f32(1)
	for q in south_torch.quads {
		for v in q.pos {
			if v[1] > 0.7 && v[2] > top_z { top_z = v[2] }
			if v[1] < 0.3 && v[2] < bottom_z { bottom_z = v[2] }
		}
	}
	assert top_z > bottom_z + 0.1
	east_info := reg.info(east_id)
	assert east_info.boxes[0].min[0] == 0
	assert east_info.boxes[0].max[0] < 0.4
	assert reg.info(west_id).boxes[0].max[0] == 1
	assert east_info.emit == 14 && !east_info.solid()
}

fn test_ported_weighted_variants_from_pack() {
	mut packs := &assets.PackStack{}
	state := r'{"variants":{"":[{"model":"minecraft:block/stone"},{"model":"minecraft:block/stone","y":90,"weight":2},{"model":"minecraft:block/stone","y":180},{"model":"minecraft:block/stone","y":270}]}}'
	packs.add(assets.PackSource{
		name:  'weighted'
		files: {
			'assets/minecraft/blockstates/stone.json': state.bytes()
		}
	})
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut models := new_block_models(packs, reg, 256)
	models.bake(reg.find('stone'))
	models.bake(reg.find('dirt'))
	stone := models.baked(reg.find('stone')) or { panic('stone not baked') }
	dirt := models.baked(reg.find('dirt')) or { panic('dirt not baked') }
	assert stone.alts.len == 4 && stone.total_weight == 5
	assert stone.alts[1].weight == 2
	assert stone.quads.len == 6 && !stone.missing
	assert dirt.alts.len == 0
	assert stone.alts[0].quads[0].pos[0][0] != stone.alts[1].quads[0].pos[0][0] || stone.alts[0].quads[0].pos[0][2] != stone.alts[1].quads[0].pos[0][2]
	assert stone.pick(0)[0].pos[0][0] == stone.alts[0].quads[0].pos[0][0]
	assert stone.pick(1)[0].pos[0][0] == stone.alts[1].quads[0].pos[0][0]
	assert stone.pick(2)[0].pos[0][0] == stone.alts[1].quads[0].pos[0][0]
	assert stone.pick(3)[0].pos[0][0] == stone.alts[2].quads[0].pos[0][0]
	assert stone.pick(4)[0].pos[0][0] == stone.alts[3].quads[0].pos[0][0]
}
