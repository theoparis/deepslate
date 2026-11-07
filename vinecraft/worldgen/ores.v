module worldgen

import vinecraft.blocks
import math

struct Ore {
	name  string
	deep  string
	tries int
	min_y int
	max_y int
	size  int
}

fn (g &WorldGen) ores(mut c blocks.Chunk, reg &blocks.Registry, px int, pz int) {
	ores := [Ore{'coal_ore', 'deepslate_coal_ore', 18, 0, 128, 8},
		Ore{'iron_ore', 'deepslate_iron_ore', 16, -60, 72, 6},
		Ore{'copper_ore', 'deepslate_copper_ore', 12, -16, 112, 8},
		Ore{'gold_ore', 'deepslate_gold_ore', 4, -60, 32, 6},
		Ore{'redstone_ore', 'deepslate_redstone_ore', 6, -60, 16, 6},
		Ore{'lapis_ore', 'deepslate_lapis_ore', 2, -60, 32, 5},
		Ore{'diamond_ore', 'deepslate_diamond_ore', 4, -60, 14, 4},
		Ore{'emerald_ore', 'emerald_ore', 2, 4, 100, 1}, Ore{'granite', 'granite', 3, 0, 80, 24},
		Ore{'diorite', 'diorite', 3, 0, 80, 24}, Ore{'andesite', 'andesite', 3, 0, 80, 24},
		Ore{'tuff', 'tuff', 4, -60, 0, 24}, Ore{'gravel', 'gravel', 3, -60, 80, 20},
		Ore{'dirt', 'dirt', 3, 0, 120, 20}]
	stone := reg.find('stone')
	deepslate := reg.find('deepslate')
	dirt := reg.find('dirt')
	tuff := reg.find('tuff')
	gravel := reg.find('gravel')
	for idx, o in ores {
		normal := reg.find(o.name)
		deep := reg.find(o.deep)
		is_ore := o.name.ends_with('_ore')
		for t in 0 .. o.tries {
			mut rng := Rng{ s: hash_coords(u64(g.seed), px, 1000 + idx * 31 + t, pz) }
			cx := rng.range(0, 15)
			cz := rng.range(0, 15)
			cy := rng.range(o.min_y, o.max_y)
			if is_ore && rng.chance(0.35) && math.abs(cy - (o.min_y + o.max_y) / 2) > (o.max_y - o.min_y) / 3 {
				continue
			}
			n := if is_ore { int(math.max(1, o.size - rng.range(0, o.size / 2))) } else { o.size }
			radius := f32(math.cbrt(n)) * if is_ore { f32(0.75) } else { f32(1.1) }
			rx := radius * (f32(0.7) + rng.unit() * f32(0.6))
			ry := radius * (f32(0.6) + rng.unit() * f32(0.5))
			rz := radius * (f32(0.7) + rng.unit() * f32(0.6))
			ir := int(math.ceil(math.max(rx, math.max(ry, rz))))
			for dx := -ir; dx <= ir; dx++ {
				for dy := -ir; dy <= ir; dy++ {
					for dz := -ir; dz <= ir; dz++ {
						x := cx + dx
						y := cy + dy
						z := cz + dz
						if x < 0 || x > 15 || z < 0 || z > 15 { continue }
						d := f32(dx * dx) / (rx * rx) + f32(dy * dy) / (ry * ry) + f32(dz * dz) / (rz * rz)
						if d > 1 || rng.unit() < 0.25 { continue }
						cur := c.get(x, y, z)
						if cur != stone && cur != deepslate && !(!is_ore && (cur == dirt || cur == tuff)) {
							continue
						}
						if !is_ore && cur == dirt && normal != gravel && normal != dirt { continue }
						c.set(x, y, z, if cur == deepslate { deep } else { normal })
					}
				}
			}
		}
	}
}
