module worldgen

import vinecraft.blocks
import math

fn put(mut c blocks.Chunk, reg &blocks.Registry, x int, y int, z int, id blocks.BlockId, only_air bool) {
	if x < 0 || x > 15 || z < 0 || z > 15 { return }
	cur := c.get(x, y, z)
	if only_air && cur != 0 && reg.info(cur).flags & blocks.bf_plant == 0 { return }
	c.set(x, y, z, id)
}

fn layer(mut c blocks.Chunk, reg &blocks.Registry, mut rng Rng, cx int, cy int, cz int, r int, keep f32, leaves blocks.BlockId) {
	for dx := -r; dx <= r; dx++ {
		for dz := -r; dz <= r; dz++ {
			if math.abs(dx) == r && math.abs(dz) == r && !rng.chance(keep) { continue }
			put(mut c, reg, cx + dx, cy, cz + dz, leaves, true)
		}
	}
}

fn (g &WorldGen) features(mut c blocks.Chunk, cols []Column, reg &blocks.Registry, px int, pz int) {
	wx0 := px * 16
	wz0 := pz * 16
	for lz := -pad; lz < 16 + pad; lz++ {
		for lx := -pad; lx < 16 + pad; lx++ {
			col := cols[(lz + pad) * ext + lx + pad]
			density := match col.biome {
				4, 27 { f32(0.030) }
				5, 30 { f32(0.028) }
				21 { f32(0.055) }
				29 { f32(0.05) }
				1 { f32(0.0015) }
				35 { f32(0.006) }
				12 { f32(0.002) }
				3 {
					if col.height < 110 { f32(0.006) } else { f32(0) }
				}
				else { f32(0) }
			}
			if density <= 0 || col.height < sea_level + 1 { continue }
			wx := wx0 + lx
			wz := wz0 + lz
			hv := hash_coords(u64(g.seed), wx, 55, wz)
			v := hash_unit(hv)
			if v >= density { continue }
			mut best := true
			for dz := -2; dz <= 2 && best; dz++ {
				for dx := -2; dx <= 2; dx++ {
					if dx == 0 && dz == 0 { continue }
					if hash_unit(hash_coords(u64(g.seed), wx + dx, 55, wz + dz)) < v {
						best = false
						break
					}
				}
			}
			if !best { continue }
			mut rng := Rng{ s: hv ^ 0x1234 }
			mut shape := 0
			mut log := reg.find('oak_log')
			mut leaves := reg.find('oak_leaves')
			mut trunk := rng.range(4, 6)
			match col.biome {
				27 {
					log = reg.find('birch_log')
					leaves = reg.find('birch_leaves')
					trunk = rng.range(5, 7)
				}
				4 {
					if rng.chance(0.2) {
						log = reg.find('birch_log')
						leaves = reg.find('birch_leaves')
						trunk = rng.range(5, 7)
					}
				}
				5, 30, 12, 3 {
					log = reg.find('spruce_log')
					leaves = reg.find('spruce_leaves')
					trunk = rng.range(6, 9)
					shape = 1
				}
				35 {
					log = reg.find('acacia_log')
					leaves = reg.find('acacia_leaves')
					trunk = rng.range(4, 5)
					shape = 2
				}
				21 {
					log = reg.find('jungle_log')
					leaves = reg.find('jungle_leaves')
					if rng.chance(0.55) {
						trunk = rng.range(9, 15)
						shape = 3
					} else {
						trunk = rng.range(4, 6)
					}
				}
				29 {
					log = reg.find('dark_oak_log')
					leaves = reg.find('dark_oak_leaves')
					trunk = rng.range(5, 7)
					shape = 4
				}
				else {}
			}
			base := col.height + 1
			if shape == 0 {
				for y in 0 .. trunk { put(mut c, reg, lx, base + y, lz, log, false) }
				top := base + trunk
				for dy := -2; dy <= 1; dy++ {
					r := if dy >= 0 { 1 } else { 2 }
					for dx := -r; dx <= r; dx++ {
						for dz := -r; dz <= r; dz++ {
							if math.abs(dx) == r && math.abs(dz) == r && (dy >= 0 || rng.chance(0.4)) {
								continue
							}
							if dx == 0 && dz == 0 && dy < 0 { continue }
							put(mut c, reg, lx + dx, top + dy, lz + dz, leaves, true)
						}
					}
				}
				put(mut c, reg, lx, top + 1, lz, leaves, true)
			} else if shape == 1 {
				for y in 0 .. trunk { put(mut c, reg, lx, base + y, lz, log, false) }
				top := base + trunk
				mut r := 0
				for y := top + 1; y >= base + 2; y-- {
					for dx := -r; dx <= r; dx++ {
						for dz := -r; dz <= r; dz++ {
							if math.abs(dx) + math.abs(dz) > r + if r > 1 { 1 } else { 0 } {
								continue
							}
							if dx == 0 && dz == 0 && y <= top { continue }
							put(mut c, reg, lx + dx, y, lz + dz, leaves, true)
						}
					}
					r = (r + 1) % 3 + if top + 1 - y > 4 { 1 } else { 0 }
					if r > 3 { r = 1 }
				}
			} else if shape == 2 {
				dirs := [[1, 0], [-1, 0], [0, 1], [0, -1]]
				dir := dirs[rng.range(0, 3)]
				mut y := 0
				for y < trunk - 1 {
					put(mut c, reg, lx, base + y, lz, log, false)
					y++
				}
				mut cx := lx
				mut cz := lz
				for _ in 0 .. 2 {
					cx += dir[0]
					cz += dir[1]
					put(mut c, reg, cx, base + y, cz, log, false)
					y++
				}
				top := base + y
				layer(mut c, reg, mut rng, cx, top, cz, 2, 0.5, leaves)
				layer(mut c, reg, mut rng, cx, top + 1, cz, 1, 0, leaves)
				layer(mut c, reg, mut rng, cx, top - 1, cz, 1, 0, leaves)
			} else if shape == 3 {
				for y in 0 .. trunk { put(mut c, reg, lx, base + y, lz, log, false) }
				top := base + trunk
				layer(mut c, reg, mut rng, lx, top - 2, lz, 3, 0.4, leaves)
				layer(mut c, reg, mut rng, lx, top - 1, lz, 3, 0.7, leaves)
				layer(mut c, reg, mut rng, lx, top, lz, 2, 0.8, leaves)
				layer(mut c, reg, mut rng, lx, top + 1, lz, 1, 0, leaves)
			} else {
				for y in 0 .. trunk {
					for dx in 0 .. 2 {
						for dz in 0 .. 2 { put(mut c, reg, lx + dx, base + y, lz + dz, log, false) }
					}
				}
				top := base + trunk
				layer(mut c, reg, mut rng, lx, top - 2, lz, 2, 0.4, leaves)
				layer(mut c, reg, mut rng, lx, top - 1, lz, 3, 0.5, leaves)
				layer(mut c, reg, mut rng, lx, top, lz, 3, 0.7, leaves)
				layer(mut c, reg, mut rng, lx, top + 1, lz, 2, 0.5, leaves)
			}
		}
	}
	g.ground_cover(mut c, cols, reg, px, pz)
}

fn (g &WorldGen) ground_cover(mut c blocks.Chunk, cols []Column, reg &blocks.Registry, px int, pz int) {
	grass := reg.find('grass_block')
	sand := reg.find('sand')
	dirt := reg.find('dirt')
	water := reg.find('water')
	flowers := ['dandelion', 'poppy', 'azure_bluet', 'oxeye_daisy', 'cornflower', 'allium', 'red_tulip',
		'pink_tulip', 'lily_of_the_valley']
	for lx in 0 .. 16 {
		for lz in 0 .. 16 {
			col := cols[(lz + pad) * ext + lx + pad]
			h := col.height
			if h < sea_level - 1 || h >= 312 { continue }
			hv := hash_coords(u64(g.seed), px * 16 + lx, 77, pz * 16 + lz)
			v := hash_unit(hv)
			ground := c.get(lx, h, lz)
			if c.get(lx, h + 1, lz) != 0 { continue }
			if ground == grass {
				match col.biome {
					1, 4, 27, 35 {
						if v < 0.16 {
							c.set(lx, h + 1, lz, reg.find('short_grass'))
						} else if v < 0.175 {
							c.set(lx, h + 1, lz, reg.find(flowers[int((hv >> 20) % 9)]))
						} else if v > 0.9995 {
							c.set(lx, h + 1, lz, reg.find('pumpkin'))
						}
					}
					5, 30 {
						if v < 0.08 {
							c.set(lx, h + 1, lz, reg.find('fern'))
						} else if v < 0.12 {
							c.set(lx, h + 1, lz, reg.find('short_grass'))
						}
					}
					21 {
						if v < 0.22 {
							c.set(lx, h + 1, lz, reg.find('short_grass'))
						} else if v < 0.34 {
							c.set(lx, h + 1, lz, reg.find('fern'))
						}
					}
					29 {
						if v < 0.06 {
							c.set(lx, h + 1, lz, reg.find('short_grass'))
						} else if v < 0.075 {
							c.set(lx, h + 1, lz, reg.find(if (hv >> 20) % 2 != 0 {
								'brown_mushroom'
							} else {
								'red_mushroom'
							}))
						}
					}
					else {}
				}
			} else if ground == sand && col.biome == 2 {
				if v < 0.004 {
					for i in 0 .. (1 + int((hv >> 24) % 3)) {
						c.set(lx, h + 1 + i, lz, reg.find('cactus'))
					}
				} else if v < 0.02 {
					c.set(lx, h + 1, lz, reg.find('dead_bush'))
				}
			} else if (ground == sand || ground == dirt || ground == grass) && h == sea_level && v < 0.05 {
				mut near_water := false
				for dir in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
					nx := lx + dir[0]
					nz := lz + dir[1]
					if nx >= 0 && nx <= 15 && nz >= 0 && nz <= 15 && c.get(nx, h, nz) == water {
						near_water = true
					}
				}
				if near_water {
					for i in 0 .. (1 + int((hv >> 24) % 3)) {
						c.set(lx, h + 1 + i, lz, reg.find('sugar_cane'))
					}
				}
			}
		}
	}
}
