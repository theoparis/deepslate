module models

import vinecraft.assets
import vinecraft.blocks

fn test_ported_atlas_layers_animation_and_tints() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut model := new_block_models(packs, reg, 256)
	assert model.layer_of('block/does_not_exist') == 0
	stone := model.layer_of('block/stone')
	assert stone != 0
	assert model.layer_of('minecraft:block/stone') == stone
	water := model.layer_of('block/water_still')
	assert water != 0
	anim := model.copy_anim()
	assert anim[int(water) * 2] == 8
	assert anim[int(water) * 2 + 1] == 3
	pixels := model.copy_layers(0)
	tile_bytes := model.tile_size() * model.tile_size() * 4
	assert pixels.len == model.layer_count() * tile_bytes
	assert pixels[0] == 248 && pixels[1] == 0 && pixels[2] == 248 && pixels[3] == 255
	assert model.copy_layers(int(water)).len == pixels.len - int(water) * tile_bytes
	assert model.tint_color(.grass, blocks.biome_plains) != model.tint_color(.grass, blocks.biome_desert)
	assert model.tint_color(.water, blocks.biome_swamp) != model.tint_color(.water, blocks.biome_plains)
}
