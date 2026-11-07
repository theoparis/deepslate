module assets

import math
import vinecraft.blocks

struct Rgb {
	r f64
	g f64
	b f64
}

fn rgb(c u32) Rgb {
	return Rgb{f64((c >> 16) & 255) / 255, f64((c >> 8) & 255) / 255, f64(c & 255) / 255}
}

fn mul(c Rgb, f f64) Rgb { return Rgb{c.r * f, c.g * f, c.b * f} }

fn mix(a Rgb, b Rgb, t f64) Rgb {
	return Rgb{a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t}
}

// libstdc++'s std::hash<string> uses the 64-bit MurmurHash2 variant.
fn name_seed(name string) u64 {
	bytes := name.bytes()
	m := u64(0xc6a4a7935bd1e995)
	mut h := u64(0xc70f6907) ^ (u64(bytes.len) * m)
	mut pos := 0
	for pos + 8 <= bytes.len {
		mut k := u64(0)
		for i in 0 .. 8 { k |= u64(bytes[pos + i]) << (8 * i) }
		k *= m
		k ^= k >> 47
		k *= m
		h = (h ^ k) * m
		pos += 8
	}
	mut rem := u64(0)
	for i in 0 .. bytes.len - pos { rem |= u64(bytes[pos + i]) << (8 * i) }
	if pos < bytes.len { h = (h ^ rem) * m }
	h ^= h >> 47
	h *= m
	h ^= h >> 47
	return h
}

fn mix64(z0 u64) u64 {
	mut z := z0 + u64(0x9e3779b97f4a7c15)
	z = (z ^ (z >> 30)) * u64(0xbf58476d1ce4e5b9)
	z = (z ^ (z >> 27)) * u64(0x94d049bb133111eb)
	return z ^ (z >> 31)
}

fn rand_pixel(seed u64, x int, y int, salt int) f64 {
	mut h := mix64(seed ^ u64(0xa0761d6478bd642f))
	h = mix64(h ^ u64(i64(x)) * u64(0xe7037ed1a0b428db))
	h = mix64(h ^ u64(i64(y)) * u64(0x8ebc6af09c88c6e3))
	h = mix64(h ^ u64(i64(salt)) * u64(0x589965cc75374cc3))
	return f64(h >> 40) / 16777216
}

fn (mut img Image) set_pixel(x int, y int, c Rgb, alpha f64) {
	if x < 0 || y < 0 || x >= img.w || y >= img.h { return }
	i := (y * img.w + x) * 4
	img.rgba[i] = u8(math.clamp(c.r, 0, 1) * 255 + 0.5)
	img.rgba[i + 1] = u8(math.clamp(c.g, 0, 1) * 255 + 0.5)
	img.rgba[i + 2] = u8(math.clamp(c.b, 0, 1) * 255 + 0.5)
	img.rgba[i + 3] = u8(math.clamp(alpha, 0, 1) * 255 + 0.5)
}

fn paint(r blocks.TexRecipe, frame int) Image {
	seed := name_seed(r.name)
	c1 := rgb(r.c1)
	c2 := rgb(r.c2)
	phase := f64(frame) * 0.7854
	mut img := new_image(16, 16)
	for y in 0 .. 16 {
		for x in 0 .. 16 {
			rnd := rand_pixel(seed, x, y, 0)
			mut color := c1
			mut alpha := 1.0
			match r.style {
				.noise { color = mul(c1, 1 + (rnd - 0.5) * if r.c2 == 1 { 0.2 } else { 0.1 }) }
				.stone, .tuff, .deepslate, .bedrock {
					amp := if r.style == .bedrock { 0.35 } else { 0.12 }
					color = mul(c1, 1 + (rnd - 0.5) * 2 * amp)
					if rand_pixel(seed, x / 3, y / 3, 9) > 0.7 {
						color = mix(mul(c1, 0.8 + rnd * 0.2), if r.c2 != 0 {
							c2
						} else {
							mul(c1, 1.15)
						}, 0.6)
					}
					if r.style == .deepslate && (x + y / 4) % 5 == 0 { color = mul(c1, 0.8) }
				}
				.ore {
					color = mul(c1, 1 + (rnd - 0.5) * 0.2)
					for pt in [[3, 3], [10, 2], [6, 8], [12, 10], [3, 12], [9, 13]] {
						if x >= pt[0] && x < pt[0] + 2 + (pt[0] + pt[1]) % 2 && y >= pt[1] && y < pt[1] + 2 {
							color = mul(c2, 0.85 + rnd * 0.3)
						}
					}
				}
				.planks {
					color = mul(c1, 1 + (rnd - 0.5) * 0.1)
					if y % 4 == 3 {
						color = mul(c1, 0.72)
					} else if x == if (y / 4) % 2 != 0 { 4 } else { 11 } {
						color = mul(c1, 0.8)
					}
				}
				.log_side {
					color = mul(c1, 0.75 + 0.35 * rand_pixel(seed, x, 0, 3) + (rand_pixel(seed, x, y, 4) - 0.5) * 0.1)
				}
				.log_top {
					dx := f64(x) - 7.5
					dy := f64(y) - 7.5
					wood := if r.c2 != 0 { c2 } else { mul(c1, 1.6) }
					color = if math.max(math.abs(dx), math.abs(dy)) > 6.5 {
						mul(c1, 0.9 + rnd * 0.2)
					} else {
						mul(wood, 0.85 + 0.15 * math.sin(math.sqrt(dx * dx + dy * dy) * 1.9) + rnd * 0.05)
					}
				}
				.leaves {
					v := rand_pixel(seed, x, y, 5)
					if v < 0.18 {
						alpha = 0
					} else {
						color = mul(Rgb{0.85, 0.85, 0.85}, 0.55 + 0.5 * rand_pixel(seed, x / 2, y / 2, 6) + (v - 0.5) * 0.2)
					}
				}
				.bricks, .stone_bricks {
					size := if r.style == .bricks { 4 } else { 8 }
					color = mul(c1, 1 + (rnd - 0.5) * if size == 4 { 0.14 } else { 0.16 })
					if y % size == size - 1 || (x + if (y / size) % 2 != 0 { size } else { 0 }) % (size * 2) == size * 2 - 1 {
						color = mul(c2, if size == 4 { 0.9 + rnd * 0.1 } else { 0.9 })
					}
				}
				.plant, .fern, .dead_bush, .flower, .mushroom, .reeds, .torch { alpha = 0 }
				.glass {
					if x == 0 || y == 0 || x == 15 || y == 15 {
						color = mul(c1, 0.9)
						alpha = 0.9
					} else if (x + y) % 9 == 0 && x < 8 {
						alpha = 0.5
					} else {
						alpha = 0
					}
				}
				.sand, .sandstone, .dirt {
					amp := if r.style == .dirt {
						0.1
					} else if r.style == .sandstone {
						0.04
					} else {
						0.05
					}
					color = mul(c1, 1 + (rnd - 0.5) * 2 * amp)
					if (r.style == .sand && rand_pixel(seed, x, y, 8) > 0.9) || (r.style == .dirt && rand_pixel(seed, x, y, 8) > 0.85) || (r.style == .sandstone && y in [
						3,
						4,
						11,
					]) {
						color = mul(c1, if r.style == .dirt { 0.75 } else { 0.88 })
					}
				}
				.gravel {
					b := rand_pixel(seed, x / 3, y / 2, 12)
					color = mul(if b > 0.5 {
						c1
					} else if r.c2 != 0 {
						c2
					} else {
						mul(c1, 1.2)
					}, 0.85 + rnd * 0.3)
				}
				.grass_top { color = mul(Rgb{0.78, 0.78, 0.78}, 1 + (rnd - 0.5) * 0.2) }
				.grass_side { color = mul(c1, 1 + (rnd - 0.5) * 0.2) }
				.grass_overlay {
					if y < 2 + int(rand_pixel(seed, x, 0, 21) * 3) {
						color = mul(Rgb{0.78, 0.78, 0.78}, 0.9 + rnd * 0.2)
					} else {
						alpha = 0
					}
				}
				.cactus {
					color = mul(c1, if x == 0 || x == 15 { 0.7 } else { 0.9 + rnd * 0.2 })
					if r.c2 == 1 && math.max(math.abs(f64(x) - 7.5), math.abs(f64(y) - 7.5)) > 6.5 {
						color = mul(c1, 0.75)
					} else if r.c2 != 1 && x % 4 == 2 && y % 4 == 1 {
						color = Rgb{0.85, 0.9, 0.7}
					}
				}
				.bookshelf {
					cols := [Rgb{0.6, 0.15, 0.1}, Rgb{0.2, 0.3, 0.6}, Rgb{0.2, 0.5, 0.2},
						Rgb{0.6, 0.5, 0.15}]
					color = if y < 2 || y > 13 || (y > 5 && y < 8) {
						Rgb{0.62, 0.48, 0.26}
					} else {
						mul(cols[(x / 2 + if y > 7 { 2 } else { 0 }) % 4], 0.7 + rnd * 0.3)
					}
				}
				.crafting {
					color = mul(Rgb{0.62, 0.47, 0.26}, 1 + (rnd - 0.5) * 0.1)
					if (x % 5 == 2 && y > 2 && y < 13) || (y % 5 == 2 && x > 2 && x < 13) {
						color = Rgb{0.35, 0.24, 0.12}
					}
				}
				.tnt {
					color = if y >= 6 && y <= 9 {
						Rgb{0.9, 0.9, 0.88}
					} else {
						mul(c1, 1 + (rnd - 0.5) * 0.1)
					}
				}
				.hay {
					color = if y in [5, 6, 10, 11] {
						Rgb{0.5, 0.35, 0.15}
					} else {
						mul(c1, 0.75 + 0.35 * rand_pixel(seed, x, 0, 30) + (rnd - 0.5) * 0.1)
					}
				}
				.pumpkin {
					color = mul(c1, (if x % 4 == 0 { 0.8 } else { 1.0 }) + (rnd - 0.5) * 0.1)
				}
				.snow { color = mul(Rgb{0.98, 0.99, 1}, 1 + (rnd - 0.5) * 0.04) }
				.ice {
					color = mul(c1, 0.95 + rnd * 0.1)
					alpha = if r.c1 == 0x9fbfff { 0.75 } else { 1 }
				}
				.water {
					color = mul(Rgb{0.75, 0.85, 1}, 0.85 + 0.15 * math.sin((f64(x) + f64(y) * 0.5) * 0.9 - phase) + rnd * 0.03)
				}
				.lava {
					v := 0.5 + 0.5 * math.sin(f64(x) * 0.7 + math.sin(f64(y) * 0.5 + phase) * 2) * math.cos(f64(y) * 0.6 + f64(x) * 0.2 - phase * 0.5)
					color = Rgb{1, 0.35 + 0.5 * v, 0.05 + 0.15 * rnd}
				}
				.glowstone {
					color = mul(c1, 0.75 + 0.35 * rand_pixel(seed, x / 3, y / 3, 40) + rnd * 0.1)
				}
				.obsidian { color = mul(c1, 1 + (rnd - 0.5) * 0.5) }
			}
			img.set_pixel(x, y, color, alpha)
		}
	}
	paint_plants(mut img, r, seed)
	return img
}
