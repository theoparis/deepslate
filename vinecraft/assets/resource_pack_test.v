module assets

fn test_builtin_stone_assets_decode() {
	pack := make_builtin_pack()
	assert pack.has('assets/minecraft/blockstates/stone.json')
	png := pack.read('assets/minecraft/textures/block/stone.png') or { panic(err) }
	image := decode_png(png) or { panic(err) }
	assert image.w == 16 && image.h == 16
}
