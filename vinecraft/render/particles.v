module render

import math

pub struct Particle {
pub mut:
	pos   Vec3d
	vel   Vec3d
	life  f32
	size  f32
	u0    f32
	v0    f32
	du    f32
	layer u16
	r     f32
	g     f32
	b     f32
}

pub struct ParticleVertex {
pub:
	x     f32
	y     f32
	z     f32
	u     f32
	v     f32
	layer f32
	r     f32
	g     f32
	b     f32
	a     f32
}

pub interface ParticleWorld {
	is_solid(x int, y int, z int) bool
}

pub struct Particles {
pub mut:
	list         []Particle
	vertices     []ParticleVertex
	random_state u64
}

fn (mut p Particles) random() f32 {
	p.random_state += u64(0x9e3779b97f4a7c15)
	// mix64 includes the splitmix increment, so compensate for it here.
	h := mix64(p.random_state - u64(0x9e3779b97f4a7c15))
	return f32(h >> 40) / 16777216.0
}

fn (mut p Particles) random_range4() f32 {
	p.random_state += u64(0x9e3779b97f4a7c15)
	h := mix64(p.random_state - u64(0x9e3779b97f4a7c15))
	return f32(h % 4)
}

// tint and layer are selected from the block definition and icon by the caller;
// liquid blocks do not emit debris.
pub fn (mut p Particles) emit_break(x int, y int, z int, layer u16, tint u32, liquid bool) {
	if liquid { return }
	for _ in 0 .. 24 {
		if p.list.len >= 4000 { break }
		pos := Vec3d{x + 0.1 + p.random() * 0.8, y + 0.1 + p.random() * 0.8, z + 0.1 + p.random() * 0.8}
		vel := Vec3d{(p.random() - 0.5) * 3.2, p.random() * 2.6 + 0.4, (p.random() - 0.5) * 3.2}
		life := 0.5 + p.random() * 0.7
		size := 0.07 + p.random() * 0.06
		u := p.random_range4() * 0.25
		v := p.random_range4() * 0.25
		sh := 0.75 + p.random() * 0.25
		p.list << Particle{pos, vel, life, size, u, v, 0.25, layer, f32((tint >> 16) & 255) / 255 * sh, f32((tint >> 8) & 255) / 255 * sh, f32(tint & 255) / 255 * sh}
	}
}

fn floor_int(x f64) int { return int(math.floor(x)) }

pub fn (mut p Particles) update(dt f64, world ParticleWorld) {
	mut i := 0
	for i < p.list.len {
		mut q := p.list[i]
		q.life -= f32(dt)
		if q.life <= 0 {
			p.list[i] = p.list[p.list.len - 1]
			p.list.delete_last()
			continue
		}
		q.vel.y -= 22 * dt
		mut np := Vec3d{q.pos.x + q.vel.x * dt, q.pos.y + q.vel.y * dt, q.pos.z + q.vel.z * dt}
		if world.is_solid(floor_int(np.x), floor_int(np.y), floor_int(np.z)) {
			if world.is_solid(floor_int(np.x), floor_int(q.pos.y), floor_int(q.pos.z)) {
				q.vel.x = 0
			} else if world.is_solid(floor_int(q.pos.x), floor_int(q.pos.y), floor_int(np.z)) {
				q.vel.z = 0
			} else {
				q.vel.y = 0
				q.vel.x *= 0.6
				q.vel.z *= 0.6
			}
			np = Vec3d{q.pos.x + q.vel.x * dt, q.pos.y + q.vel.y * dt, q.pos.z + q.vel.z * dt}
		}
		q.pos = np
		p.list[i] = q
		i++
	}
}

pub fn (mut p Particles) prepare(cam Camera, sky SkyState) {
	p.vertices.clear()
	f := cam.forward()
	len := f32(math.sqrt(f.x * f.x + f.z * f.z))
	right := Vec3{-f.z / len, 0, f.x / len}
	up := Vec3{-right.z * f.y, right.z * f.x - right.x * f.z, right.x * f.y}
	br := 0.25 + 0.75 * sky.sky_light
	for q in p.list {
		center := Vec3{f32(q.pos.x - cam.pos.x), f32(q.pos.y - cam.pos.y), f32(q.pos.z - cam.pos.z)}
		for k in [0, 1, 2, 0, 2, 3] {
			sx := if k == 0 || k == 3 { f32(-1) } else { f32(1) }
			sy := if k < 2 { f32(-1) } else { f32(1) }
			u := if sx < 0 { q.u0 } else { q.u0 + q.du }
			v := if sy < 0 { q.v0 + q.du } else { q.v0 }
			p.vertices << ParticleVertex{center.x + (right.x * sx + up.x * sy) * q.size, center.y + (right.y * sx + up.y * sy) * q.size, center.z + (right.z * sx + up.z * sy) * q.size, u, v, f32(q.layer), q.r * br, q.g * br, q.b * br, 1}
		}
	}
}
