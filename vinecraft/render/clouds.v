module render

import vinecraft.assets
import math

const cloud_n = 256
const cloud_cell = 12
const cloud_radius = 22
pub const cloud_height = 192.0

pub struct CloudVertex {
pub:
	x     f32
	y     f32
	z     f32
	shade f32
}

pub struct Clouds {
pub mut:
	mask     []bool
	vertices []CloudVertex
	built_i  int = -2147483648
	built_j  int = -2147483648
}

fn mix64(input u64) u64 {
	mut z := input + u64(0x9e3779b97f4a7c15)
	z = (z ^ (z >> 30)) * u64(0xbf58476d1ce4e5b9)
	z = (z ^ (z >> 27)) * u64(0x94d049bb133111eb)
	return z ^ (z >> 31)
}

fn cloud_noise(x int, y int, period int, salt int) f32 {
	xx := (x % period + period) % period
	yy := (y % period + period) % period
	mut h := mix64(u64(0xc10d) ^ u64(0xa0761d6478bd642f))
	h = mix64(h ^ u64(xx) * u64(0xe7037ed1a0b428db))
	h = mix64(h ^ u64(salt) * u64(0x8ebc6af09c88c6e3))
	h = mix64(h ^ u64(yy) * u64(0x589965cc75374cc3))
	return f32(h >> 40) / 16777216.0
}

fn cloud_smooth(x f32, y f32, period int, salt int) f32 {
	x0 := int(math.floor(x))
	y0 := int(math.floor(y))
	mut tx := x - x0
	mut ty := y - y0
	tx = tx * tx * (3 - 2 * tx)
	ty = ty * ty * (3 - 2 * ty)
	a := cloud_noise(x0, y0, period, salt)
	b := cloud_noise(x0 + 1, y0, period, salt)
	c := cloud_noise(x0, y0 + 1, period, salt)
	d := cloud_noise(x0 + 1, y0 + 1, period, salt)
	return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty
}

pub fn new_clouds(packs &assets.PackStack) Clouds {
	mut result := Clouds{ mask: []bool{len: cloud_n * cloud_n} }
	if data := packs.read('assets/minecraft/textures/environment/clouds.png') {
		if img := assets.decode_png(data) {
			if img.w > 0 && img.h > 0 {
				for y in 0 .. cloud_n {
					for x in 0 .. cloud_n {
						result.mask[y * cloud_n + x] = img.rgba[((y * img.h / cloud_n) * img.w + x * img.w / cloud_n) * 4 + 3] > 127
					}
				}
				return result
			}
		}
	}
	for y in 0 .. cloud_n {
		for x in 0 .. cloud_n {
			v := 0.6 * cloud_smooth(f32(x) / 32, f32(y) / 32, 8, 1) + 0.4 * cloud_smooth(f32(x) / 12, f32(y) / 12, 22, 2)
			result.mask[y * cloud_n + x] = v > 0.6
		}
	}
	return result
}

fn (c &Clouds) cell(i int, j int) bool {
	return c.mask[((j % cloud_n + cloud_n) % cloud_n) * cloud_n + (i % cloud_n + cloud_n) % cloud_n]
}

fn (mut c Clouds) quad(a Vec3, b Vec3, d Vec3, e Vec3, shade f32) {
	for p in [a, b, d, a, d, e] { c.vertices << CloudVertex{p.x, p.y, p.z, shade} }
}

pub fn (mut c Clouds) rebuild(ci int, cj int) {
	c.vertices.clear()
	for j := cj - cloud_radius; j <= cj + cloud_radius; j++ {
		for i := ci - cloud_radius; i <= ci + cloud_radius; i++ {
			if !c.cell(i, j) { continue }
			x := f32(i * cloud_cell)
			z := f32(j * cloud_cell)
			x1 := x + cloud_cell
			z1 := z + cloud_cell
			c.quad(Vec3{x, 4, z}, Vec3{x, 4, z1}, Vec3{x1, 4, z1}, Vec3{x1, 4, z}, 1)
			c.quad(Vec3{x, 0, z}, Vec3{x1, 0, z}, Vec3{x1, 0, z1}, Vec3{x, 0, z1}, 0.62)
			if !c.cell(i - 1, j) {
				c.quad(Vec3{x, 0, z}, Vec3{x, 0, z1}, Vec3{x, 4, z1}, Vec3{x, 4, z}, 0.78)
			}
			if !c.cell(i + 1, j) {
				c.quad(Vec3{x1, 0, z}, Vec3{x1, 4, z}, Vec3{x1, 4, z1}, Vec3{x1, 0, z1}, 0.78)
			}
			if !c.cell(i, j - 1) {
				c.quad(Vec3{x, 0, z}, Vec3{x, 4, z}, Vec3{x1, 4, z}, Vec3{x1, 0, z}, 0.86)
			}
			if !c.cell(i, j + 1) {
				c.quad(Vec3{x, 0, z1}, Vec3{x1, 0, z1}, Vec3{x1, 4, z1}, Vec3{x, 4, z1}, 0.86)
			}
		}
	}
	c.built_i = ci
	c.built_j = cj
}

pub fn (mut c Clouds) prepare(cam Camera, seconds f64) Vec3 {
	scroll := f32(math.fmod(seconds * 1.6, cloud_n * cloud_cell))
	ci := int(math.floor((cam.pos.x - scroll) / cloud_cell))
	cj := int(math.floor(cam.pos.z / cloud_cell))
	if ci != c.built_i || cj != c.built_j { c.rebuild(ci, cj) }
	return Vec3{scroll - f32(cam.pos.x), f32(cloud_height - cam.pos.y), -f32(cam.pos.z)}
}
