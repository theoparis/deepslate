module models

import vinecraft.assets
import vinecraft.blocks
import json2

pub fn new_block_models(packs &assets.PackStack, registry &blocks.Registry, max_layers int) &BlockModels {
	mut bm := &BlockModels{ packs: packs, registry: registry }
	for probe in ['block/stone', 'block/dirt', 'block/grass_block_top'] {
		data := packs.read('assets/minecraft/textures/${probe}.png') or { continue }
		img := assets.decode_png(data) or { continue }
		bm.tile = clamp_int(img.w, 8, 512)
		break
	}
	bm.cap_layers = clamp_int(max_layers, 0, 2048)
	bm.cap_layers = clamp_int(bm.cap_layers, 0, 96 * 1024 * 1024 / (bm.tile * bm.tile * 4))
	if bm.cap_layers < 64 { bm.cap_layers = 64 }
	for y in 0 .. bm.tile {
		for x in 0 .. bm.tile {
			m := ((x * 2 / bm.tile) + (y * 2 / bm.tile)) % 2 == 0
			bm.pixels << u8(if m { 248 } else { 0 })
			bm.pixels << u8(0)
			bm.pixels << u8(if m { 248 } else { 0 })
			bm.pixels << u8(255)
		}
	}
	bm.anim = [f32(1), f32(1)]
	bm.layer_ids['<missing>'] = 0
	bm.init_tints()
	return bm
}

fn (mut bm BlockModels) add_layer(name string) u16 {
	n := strip_ns(name)
	if n in bm.layer_ids { return bm.layer_ids[n] }
	data := bm.packs.read('assets/minecraft/textures/${n}.png') or {
		bm.layer_ids[n] = 0
		return 0
	}
	img := assets.decode_png(data) or {
		bm.layer_ids[n] = 0
		return 0
	}
	if img.empty() {
		bm.layer_ids[n] = 0
		return 0
	}
	count := if img.h > img.w && img.w > 0 { img.h / img.w } else { 1 }
	mut seq := []int{}
	mut frametime := 1
	if count > 1 {
		if meta := bm.packs.read('assets/minecraft/textures/${n}.png.mcmeta') {
			if doc := json2.decode[json2.Any](meta.bytestr()) {
				anim := object(field(object(doc), 'animation'))
				if 'frametime' in anim {
					frametime = clamp_int(field(anim, 'frametime').int(), 1, 2147483647)
				}
				for frame in json_array(field(anim, 'frames')) {
					if frame is map[string]json2.Any {
						f := frame.as_map()
						if 'index' in f {
							reps := if 'time' in f {
								clamp_int(field(f, 'time').int() / frametime, 1, 16)
							} else {
								1
							}
							for _ in 0 .. reps { seq << field(f, 'index').int() }
						}
					} else {
						seq << frame.int()
					}
				}
			}
		}
		if seq.len == 0 {
			for i in 0 .. count { seq << i }
		}
		if seq.len > 64 { seq = seq[..64].clone() }
	} else {
		seq << 0
	}
	idx := bm.anim.len / 2
	if idx + seq.len > bm.cap_layers {
		bm.layer_ids[n] = 0
		return 0
	}
	for index in seq {
		fi := clamp_int(index, 0, count - 1)
		for y in 0 .. bm.tile {
			for x in 0 .. bm.tile {
				source := ((fi * img.w + y * img.w / bm.tile) * img.w + x * img.w / bm.tile) * 4
				bm.pixels << img.rgba[source..source + 4]
			}
		}
		bm.anim << f32(1)
		bm.anim << f32(1)
	}
	bm.anim[idx * 2] = f32(seq.len)
	bm.anim[idx * 2 + 1] = f32(frametime)
	bm.layer_ids[n] = u16(idx)
	return u16(idx)
}

pub fn (mut bm BlockModels) layer_of(name string) u16 {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	return bm.add_layer(name)
}

pub fn (bm &BlockModels) tile_size() int { return bm.tile }

pub fn (bm &BlockModels) capacity() int { return bm.cap_layers }

pub fn (bm &BlockModels) water_layer() u16 { return bm.water }

pub fn (bm &BlockModels) lava_layer() u16 { return bm.lava }

pub fn (mut bm BlockModels) layer_count() int {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	return bm.anim.len / 2
}

pub fn (mut bm BlockModels) copy_layers(from int) []u8 {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	start := clamp_int(from, 0, bm.anim.len / 2) * bm.tile * bm.tile * 4
	return bm.pixels[start..].clone()
}

pub fn (mut bm BlockModels) copy_anim() []f32 {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	return bm.anim.clone()
}

pub fn (bm &BlockModels) tint_color(kind blocks.Tint, biome u8) u32 {
	return bm.tints[int(kind)][int(biome)]
}

fn sample(img assets.Image, temperature f32, downfall f32, fallback u32) u32 {
	if img.empty() { return fallback }
	t := if temperature < 0 {
		f32(0)
	} else if temperature > 1 {
		f32(1)
	} else {
		temperature
	}
	d := (if downfall < 0 {
		f32(0)
	} else if downfall > 1 {
		f32(1)
	} else {
		downfall
	}) * t
	x := clamp_int(int((1 - t) * f32(img.w - 1)), 0, img.w - 1)
	y := clamp_int(int((1 - d) * f32(img.h - 1)), 0, img.h - 1)
	i := (y * img.w + x) * 4
	return u32(img.rgba[i]) << 16 | u32(img.rgba[i + 1]) << 8 | u32(img.rgba[i + 2])
}

fn (mut bm BlockModels) init_tints() {
	mut grass := assets.Image{}
	mut foliage := assets.Image{}
	if data := bm.packs.read('assets/minecraft/textures/colormap/grass.png') {
		grass = assets.decode_png(data) or { assets.Image{} }
	}
	if data := bm.packs.read('assets/minecraft/textures/colormap/foliage.png') {
		foliage = assets.decode_png(data) or { assets.Image{} }
	}
	for b in 0 .. 256 {
		cl := blocks.biome_climate(u8(b))
		bm.tints[0][b] = 0xffffff
		bm.tints[1][b] = sample(grass, cl.temperature, cl.downfall, 0x91bd59)
		bm.tints[2][b] = sample(foliage, cl.temperature, cl.downfall, 0x77ab2f)
		bm.tints[3][b] = match b {
			10 { u32(0x3938c9) }
			6 { u32(0x617b64) }
			5, 30, 12 { u32(0x3d57d6) }
			else { u32(0x3f76e4) }
		}
		bm.tints[4][b] = 0x80a755
		bm.tints[5][b] = 0x619961
	}
}
