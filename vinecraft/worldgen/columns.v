module worldgen

import math
import vinecraft.noise

pub const sea_level = 62
const pad = 4
const ext = 24

struct Column {
mut:
	height int
	biome  u8
	temp   f32
	hum    f32
}

fn clampf(v f32, lo f32, hi f32) f32 {
	return if v < lo {
		lo
	} else if v > hi {
		hi
	} else {
		v
	}
}

fn smoothstep(a f32, b f32, x f32) f32 {
	t := clampf((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
}

pub struct WorldGen {
pub:
	seed i64
mut:
	s32         int
	continental noise.Generator
	hills       noise.Generator
	ridged      noise.Generator
	temperature noise.Generator
	humidity    noise.Generator
	cave_a      noise.Generator
	cave_b      noise.Generator
	cheese      noise.Generator
	detail      noise.Generator
}

pub fn new_worldgen(seed i64) WorldGen {
	return WorldGen{ seed: seed, s32: int(mix64(u64(seed)) & 0x7fffffff), continental: noise.new_fbm(5, 1100, 0.5, false), hills: noise.new_fbm(4, 170, 0.5, false), ridged: noise.new_fbm(4, 420, 0.5, true), temperature: noise.new_fbm(2, 1500, 0.5, false), humidity: noise.new_fbm(2, 1200, 0.5, false), cave_a: noise.new_fbm(2, 48, 0.3, false), cave_b: noise.new_fbm(2, 48, 0.3, false), cheese: noise.new_fbm(2, 90, 0.5, false), detail: noise.new_fbm(2, 22, 0.5, false) }
}

fn (g &WorldGen) columns(px int, pz int) []Column {
	x0 := px * 16 - pad
	z0 := pz * 16 - pad
	mut cont := []f32{len: ext * ext}
	mut hill := []f32{len: ext * ext}
	mut ridge := []f32{len: ext * ext}
	mut temp := []f32{len: ext * ext}
	mut hum := []f32{len: ext * ext}
	mut detail := []f32{len: ext * ext}
	g.continental.grid2(mut cont, f32(x0), f32(z0), ext, ext, 1, 1, g.s32)
	g.hills.grid2(mut hill, f32(x0), f32(z0), ext, ext, 1, 1, g.s32 + 101)
	g.ridged.grid2(mut ridge, f32(x0), f32(z0), ext, ext, 1, 1, g.s32 + 202)
	g.temperature.grid2(mut temp, f32(x0), f32(z0), ext, ext, 1, 1, g.s32 + 303)
	g.humidity.grid2(mut hum, f32(x0), f32(z0), ext, ext, 1, 1, g.s32 + 404)
	g.detail.grid2(mut detail, f32(x0), f32(z0), ext, ext, 1, 1, g.s32 + 505)
	mut out := []Column{len: ext * ext}
	for i in 0 .. out.len {
		c := clampf(cont[i] * f32(0.85) + f32(0.12), -1, 1)
		land := smoothstep(-0.30, 0.02, c)
		seafloor := clampf(50 + (c + f32(0.55)) * 55, 14, 58)
		base := seafloor + (65 + c * 14 - seafloor) * land
		hv := clampf(hill[i] * f32(0.6), -1.2, 1.2)
		rough := 3 + 11 * land * (f32(0.4) + f32(0.6) * clampf(hv * f32(0.5) + f32(0.5), 0, 1))
		mut h := base + hv * rough + detail[i] * f32(1.2)
		h += math.max(f32(0), ridge[i] - f32(0.85)) * 110 * smoothstep(0, 0.5, c)
		h = clampf(h, 8, 300)
		height := int(h)
		temperature := temp[i] * f32(0.72) + f32(0.1)
		humidity := hum[i] * f32(0.85)
		t := temperature - math.max(f32(0), h - 100) * f32(0.012)
		biome := if height < sea_level - 1 {
			if t < -0.4 {
				u8(10)
			} else if height < 38 {
				u8(24)
			} else {
				u8(0)
			}
		} else if height <= sea_level + 1 && c < 0.1 {
			u8(16)
		} else if h > 120 {
			u8(3)
		} else if t < -0.4 {
			if humidity > 0 { u8(30) } else { u8(12) }
		} else if t < -0.12 {
			u8(5)
		} else if t > 0.38 {
			if humidity < -0.1 {
				u8(2)
			} else if humidity < 0.2 {
				u8(35)
			} else if humidity > 0.4 {
				u8(21)
			} else {
				u8(1)
			}
		} else if humidity > 0.45 && t > 0.05 {
			u8(29)
		} else if humidity > 0.25 {
			if t < 0.2 { u8(27) } else { u8(4) }
		} else if humidity > -0.08 {
			u8(4)
		} else {
			u8(1)
		}
		out[i] = Column{ height: height, biome: biome, temp: temperature, hum: humidity }
	}
	return out
}

pub fn (g &WorldGen) surface_height(wx int, wz int) int {
	px := if wx < 0 { (wx - 15) / 16 } else { wx / 16 }
	pz := if wz < 0 { (wz - 15) / 16 } else { wz / 16 }
	cols := g.columns(px, pz)
	return cols[(wz - pz * 16 + pad) * ext + wx - px * 16 + pad].height
}
