module main

import os
import math
import vinecraft.assets
import vinecraft.blocks
import vinecraft.worldgen

fn floor_div16(x int) int {
	return if x < 0 { (x - 15) / 16 } else { x / 16 }
}

fn biome_color(b u8) u32 {
	return match b {
		blocks.biome_ocean { 0x2050b0 }
		blocks.biome_deep_ocean { 0x102060 }
		blocks.biome_frozen_ocean { 0x7080c0 }
		blocks.biome_plains { 0x8db360 }
		blocks.biome_forest { 0x056621 }
		blocks.biome_birch_forest { 0x307444 }
		blocks.biome_dark_forest { 0x40511a }
		blocks.biome_taiga { 0x0b6659 }
		blocks.biome_cold_taiga { 0x31554a }
		blocks.biome_snowy_plains { 0xffffff }
		blocks.biome_desert { 0xfa9418 }
		blocks.biome_savanna { 0xbdb25f }
		blocks.biome_jungle { 0x537b09 }
		blocks.biome_hills { 0x606060 }
		blocks.biome_beach { 0xfade55 }
		blocks.biome_swamp { 0x07f9b2 }
		else { 0xff00ff }
	}
}

fn main() {
	if os.args.len < 6 {
		eprintln('usage: worldmap seed cx cz size out.png [step]')
		exit(2)
	}
	seed := os.args[1].i64()
	cx := os.args[2].int()
	cz := os.args[3].int()
	size := os.args[4].int()
	step := if os.args.len > 6 { os.args[6].int() } else { 4 }
	biome_mode := os.args.len > 7 && os.args[7] == 'biomes'
	reg := blocks.new_registry()
	gen := worldgen.new_worldgen(seed)
	n := size / step
	mut img := assets.new_image(n, n)
	x0 := cx - size / 2
	z0 := cz - size / 2
	mut cache := map[string]&blocks.Chunk{}
	grass := reg.find('grass_block')
	for j in 0 .. n {
		for i in 0 .. n {
			wx := x0 + i * step
			wz := z0 + j * step
			px := floor_div16(wx)
			pz := floor_div16(wz)
			key := '${px},${pz}'
			if key !in cache { cache[key] = gen.generate(px, pz, reg) }
			c := cache[key] or { nil }
			lx := wx - px * 16
			lz := wz - pz * 16
			index := blocks.col_index(lx, lz)
			h := int(c.height[index]) - 1
			mut top := blocks.BlockId(0)
			for y := h; y >= blocks.min_y; y-- {
				top = c.get(lx, y, lz)
				if top != 0 && reg.info(top).flags & blocks.bf_plant == 0 { break }
			}
			info := reg.info(top)
			mut shade := f32(0.7) + f32(0.3) * math.clamp(f32(h - 40) / 120, f32(0), f32(1))
			if info.flags & blocks.bf_liquid != 0 {
				shade = f32(0.55) + f32(0.45) * math.clamp(f32(h + 20) / 80, f32(0), f32(1))
			}
			mut color := info.color
			if biome_mode {
				color = biome_color(c.biome[index])
				shade = 1
			} else if top == grass {
				tint := [u32(0), 0x7cbd6b, 0, 0, 0x4f9a3e, 0x4b7f50]!
				b := int(c.biome[index])
				if b < 6 && tint[b] != 0 { color = tint[b] }
			}
			p := (j * n + i) * 4
			img.rgba[p] = u8(f32((color >> 16) & 255) * shade)
			img.rgba[p + 1] = u8(f32((color >> 8) & 255) * shade)
			img.rgba[p + 2] = u8(f32(color & 255) * shade)
			img.rgba[p + 3] = 255
		}
	}
	assets.write_png_file(os.args[5], img) or {
		eprintln(err)
		exit(1)
	}
	println('wrote ${os.args[5]} (${n}x${n})')
}
