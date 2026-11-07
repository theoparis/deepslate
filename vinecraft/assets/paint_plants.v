module assets

import math
import vinecraft.blocks

fn paint_plants(mut img Image, r blocks.TexRecipe, seed u64) {
	c1 := rgb(r.c1)
	c2 := rgb(r.c2)
	match r.style {
		.plant, .fern {
			fern := r.style == .fern
			for x in 1 .. 15 {
				if fern && x % 2 == 0 { continue }
				h := if fern {
					6.0 + rand_pixel(seed, x, 0, 1) * 8
				} else {
					3.0 + rand_pixel(seed, x, 0, 1) * 10
				}
				if !fern && rand_pixel(seed, x, 1, 2) < 0.35 { continue }
				for j in 0 .. 16 {
					y := 15 - j
					if f64(y) <= 15 - h { break }
					shade := 0.55 + 0.45 * f64(15 - y) / 15 + rand_pixel(seed, x, y, 0) * 0.1
					xx := x + if fern { int(math.sin(f64(y) * 0.8 + f64(x)) * 1.5) } else { 0 }
					img.set_pixel(xx, y, mul(Rgb{0.9, 0.9, 0.9}, shade), 1)
				}
			}
		}
		.dead_bush {
			for i in 0 .. 4 {
				x := 3 + i * 3
				for j in 0 .. 16 {
					y := 15 - j
					if y <= 5 + i { break }
					img.set_pixel(x + (15 - y) / 4 * if i % 2 != 0 { 1 } else { -1 }, y, mul(c1, 0.8 + rand_pixel(seed, x, y, 0) * 0.3), 1)
				}
			}
		}
		.flower {
			for y in 6 .. 16 { img.set_pixel(7, y, Rgb{0.2, 0.55, 0.15}, 1) }
			img.set_pixel(8, 12, Rgb{0.2, 0.55, 0.15}, 1)
			img.set_pixel(6, 10, Rgb{0.2, 0.55, 0.15}, 1)
			for dx in -2 .. 3 {
				for dy in -2 .. 3 {
					if math.abs(dx) + math.abs(dy) <= 3 {
						img.set_pixel(7 + dx, 4 + dy, if dx == 0 && dy == 0 {
							Rgb{1, 0.85, 0.2}
						} else {
							mul(c2, 0.85 + rand_pixel(seed, dx + 9, dy + 9, 0) * 0.3)
						}, 1)
					}
				}
			}
		}
		.mushroom {
			for y in 9 .. 16 {
				for x in 7 .. 9 { img.set_pixel(x, y, Rgb{0.85, 0.8, 0.7}, 1) }
			}
			for y in 5 .. 9 {
				for x in 4 .. 12 {
					if y > 5 || (x > 5 && x < 10) {
						img.set_pixel(x, y, mul(c1, 0.85 + rand_pixel(seed, x, y, 0) * 0.3), 1)
					}
				}
			}
		}
		.reeds {
			for x in [3, 8, 12] {
				for y in 0 .. 16 {
					img.set_pixel(x, y, mul(Rgb{0.55, 0.75, 0.35}, if y % 5 == 0 {
						0.7
					} else {
						1 - rand_pixel(seed, x, y, 0) * 0.15
					}), 1)
				}
			}
			for y in 0 .. 16 { img.set_pixel(4, y, Rgb{0.4, 0.6, 0.25}, 1) }
		}
		.torch {
			for y in 6 .. 16 {
				for x in 7 .. 9 {
					img.set_pixel(x, y, mul(Rgb{0.55, 0.4, 0.2}, 0.8 + rand_pixel(seed, x, y, 0) * 0.3), 1)
				}
			}
			for y in 3 .. 7 {
				for x in 7 .. 9 {
					img.set_pixel(x, y, if y < 5 { Rgb{1, 0.9, 0.4} } else { Rgb{1, 0.6, 0.15} }, 1)
				}
			}
		}
		else {}
	}
}

fn make_colormap(foliage bool) Image {
	mut img := new_image(256, 256)
	cold := if foliage { Rgb{0.38, 0.60, 0.35} } else { Rgb{0.55, 0.72, 0.55} }
	warm := if foliage { Rgb{0.55, 0.65, 0.17} } else { Rgb{0.75, 0.72, 0.33} }
	lush := if foliage { Rgb{0.19, 0.73, 0.09} } else { Rgb{0.35, 0.79, 0.24} }
	for y in 0 .. 256 {
		for x in 0 .. 256 {
			t := 1 - f64(x) / 255
			w := 1 - f64(y) / 255
			c := mix(mix(mix(cold, warm, t), lush, w * (0.4 + 0.6 * t)), cold, (1 - t) * 0.5)
			i := (y * 256 + x) * 4
			img.rgba[i] = u8(math.clamp(c.r, 0, 1) * 255)
			img.rgba[i + 1] = u8(math.clamp(c.g, 0, 1) * 255)
			img.rgba[i + 2] = u8(math.clamp(c.b, 0, 1) * 255)
			img.rgba[i + 3] = 255
		}
	}
	return img
}
