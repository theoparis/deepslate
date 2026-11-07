module assets

import vinecraft.blocks

fn model_json(parent string, textures map[string]string) string {
	mut items := []string{}
	for k, v in textures { items << '"${k}":"${v}"' }
	return '{"parent":"${parent}","textures":{${items.join(',')}}}'
}

fn simple_state(model string) string { return '{"variants":{"":{"model":"${model}"}}}' }

pub fn make_builtin_pack() PackSource {
	root := 'assets/minecraft/'
	mp := 'minecraft:block/'
	mut files := map[string][]u8{}
	files['pack.mcmeta'] = '{"pack":{"pack_format":99,"description":"Deepslate Edition built-in pack"}}'.bytes()
	for name, value in {
		'cube':                model_cube
		'cube_all':            model_cube_all
		'cube_column':         model_cube_column
		'cube_bottom_top':     model_cube_bottom_top
		'leaves':              model_leaves
		'cross':               model_cross
		'tinted_cross':        model_tinted_cross
		'slab':                model_slab
		'slab_top':            model_slab_top
		'stairs':              model_stairs
		'template_torch':      model_torch
		'template_torch_wall': model_torch_wall
		'template_cactus':     model_cactus
	} {
		files[root + 'models/block/' + name + '.json'] = value.bytes()
	}
	files[root + 'models/block/wall_torch.json'] = model_json(mp + 'template_torch_wall', {
		'torch': mp + 'torch'
	}).bytes()
	files[root + 'blockstates/wall_torch.json'] = '{"variants":{"facing=east":{"model":"minecraft:block/wall_torch"},"facing=south":{"model":"minecraft:block/wall_torch","y":90},"facing=west":{"model":"minecraft:block/wall_torch","y":180},"facing=north":{"model":"minecraft:block/wall_torch","y":270}}}'.bytes()
	mut recipes := map[string]blocks.TexRecipe{}
	for d in blocks.builtin_defs() {
		if d.kind == .air { continue }
		for recipe in d.recipes { if recipe.name !in recipes { recipes[recipe.name] = recipe } }
		n := d.java_name()
		model_path := root + 'models/block/' + n + '.json'
		state_path := root + 'blockstates/' + n + '.json'
		mut parent := ''
		mut tex := map[string]string{}
		mut state := simple_state(mp + n)
		match d.kind {
			.cube_all {
				parent = if d.flags & blocks.bf_leaves != 0 { 'leaves' } else { 'cube_all' }
				tex['all'] = mp + d.tex[0]
			}
			.column {
				parent = 'cube_column'
				tex['end'] = mp + d.tex[0]
				tex['side'] = mp + d.tex[1]
				state = '{"variants":{"axis=y":{"model":"${mp}${n}"},"axis=z":{"model":"${mp}${n}","x":90},"axis=x":{"model":"${mp}${n}","x":90,"y":90}}}'
			}
			.bottom_top, .slab, .stairs, .cactus {
				parent = match d.kind {
					.bottom_top { 'cube_bottom_top' }
					.slab { 'slab' }
					.stairs { 'stairs' }
					else { 'template_cactus' }
				}
				tex['top'] = mp + d.tex[0]
				tex['side'] = mp + d.tex[1]
				tex['bottom'] = mp + d.tex[2]
				if d.kind == .slab {
					files[root + 'models/block/' + n + '_top.json'] = model_json(mp + 'slab_top', tex).bytes()
					state = '{"variants":{"type=bottom":{"model":"${mp}${n}"},"type=top":{"model":"${mp}${n}_top"},"type=double":{"model":"${mp}${n}"}}}'
				} else if d.kind == .stairs {
					mut variants := []string{}
					for half in ['bottom', 'top'] {
						for i, facing in ['east', 'south', 'west', 'north'] {
							x := if half == 'top' { ',"x":180' } else { '' }
							variants << '"facing=${facing},half=${half},shape=straight":{"model":"${mp}${n}","y":${i * 90}${x}}'
						}
					}
					state = '{"variants":{${variants.join(',')}}}'
				}
			}
			.cross {
				parent = if d.tint != .none { 'tinted_cross' } else { 'cross' }
				tex['cross'] = mp + d.tex[0]
			}
			.torch {
				parent = 'template_torch'
				tex['torch'] = mp + d.tex[0]
			}
			.grass {
				mut base := []string{}
				mut over := []string{}
				for dir in ['down', 'up', 'north', 'south', 'west', 'east'] {
					t := if dir == 'down' {
						'#bottom'
					} else if dir == 'up' {
						'#top'
					} else {
						'#side'
					}
					tint := if dir == 'up' { ',"tintindex":0' } else { '' }
					base << '"${dir}":{"texture":"${t}","cullface":"${dir}"${tint}}'
					if dir != 'down' && dir != 'up' {
						over << '"${dir}":{"texture":"#overlay","cullface":"${dir}","tintindex":0}'
					}
				}
				files[model_path] = '{"textures":{"particle":"#bottom","bottom":"${mp}${d.tex[2]}","top":"${mp}${d.tex[0]}","side":"${mp}${d.tex[1]}","overlay":"${mp}${d.overlay}"},"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{${base.join(',')}}},{"from":[0,0,0],"to":[16,16,16],"faces":{${over.join(',')}}}]}'.bytes()
				state = '{"variants":{"snowy=false":{"model":"${mp}${n}"},"snowy=true":{"model":"${mp}${n}"}}}'
			}
			else { continue }
		}
		if parent != '' { files[model_path] = model_json(mp + parent, tex).bytes() }
		files[state_path] = state.bytes()
	}
	for name, recipe in recipes {
		mut img := new_image(16, if recipe.style == .water || recipe.style == .lava {
			128
		} else {
			16
		})
		frames := img.h / 16
		for f in 0 .. frames {
			frame := paint(recipe, f)
			for i, value in frame.rgba { img.rgba[f * 1024 + i] = value }
		}
		path := root + 'textures/block/' + name + '.png'
		files[path] = encode_png(img) or { panic(err) }
		if frames > 1 { files[path + '.mcmeta'] = '{"animation":{"frametime":3}}'.bytes() }
	}
	files[root + 'textures/colormap/grass.png'] = encode_png(make_colormap(false)) or { panic(err) }
	files[root + 'textures/colormap/foliage.png'] = encode_png(make_colormap(true)) or { panic(err) }
	files[root + 'textures/font/ascii.png'] = fallback_font_png()
	return PackSource{ name: 'builtin', files: files }
}
