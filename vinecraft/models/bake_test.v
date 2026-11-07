module models

import vinecraft.assets
import vinecraft.blocks

fn test_stone_model_resolves_builtin_texture() {
	mut packs := &assets.PackStack{}
	packs.add_builtin_fallback()
	reg := blocks.new_registry()
	mut models := new_block_models(packs, reg, 256)
	id := reg.find('stone')
	models.bake(id)
	stone := models.baked(id) or { panic('stone model not baked') }
	assert !stone.missing
	assert stone.quads.len == 6
	for quad in stone.quads {
		assert quad.layer != 0
	}
}
