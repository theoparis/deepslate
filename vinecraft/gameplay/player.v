module gameplay

import math

pub const player_width = 0.6
pub const player_height = 1.8
pub const player_sneak_height = 1.5

pub struct MoveInput {
pub:
	forward f32
	strafe  f32
	jump    bool
	sneak   bool
	sprint  bool
}

pub struct Player {
pub mut:
	pos           Vec3 = Vec3{ y: 100 }
	vel           Vec3
	yaw           f32
	pitch         f32
	on_ground     bool
	flying        bool
	sprinting     bool
	sneaking      bool
	in_water      bool
	eyes_in_water bool
	in_lava       bool
	creative      bool = true
}

pub fn (p Player) eye_height() f64 { return if p.sneaking { 1.27 } else { 1.62 } }

pub fn (p Player) eye() Vec3 { return Vec3{ x: p.pos.x, y: p.pos.y + p.eye_height(), z: p.pos.z } }

pub fn (p Player) box() Aabb {
	h := if p.sneaking { player_sneak_height } else { player_height }
	r := player_width / 2
	return Aabb{ mn: [p.pos.x - r, p.pos.y, p.pos.z - r]!, mx: [p.pos.x + r, p.pos.y + h, p.pos.z + r]! }
}

fn (mut p Player) move_axis(world World, axis int, delta f64) f64 {
	if delta == 0 { return 0 }
	b := p.box()
	mut lo := [3]int{}
	mut hi := [3]int{}
	for i in 0 .. 3 {
		mut a := b.mn[i]
		mut c := b.mx[i]
		if i == axis {
			if delta > 0 { c += delta } else { a += delta }
		}
		lo[i] = floor_int(a)
		hi[i] = floor_int(c)
	}
	mut d := delta
	for x := lo[0]; x <= hi[0]; x++ {
		for y := lo[1]; y <= hi[1]; y++ {
			for z := lo[2]; z <= hi[2]; z++ {
				boxes := block_boxes(world, x, y, z)
				for k in 0 .. boxes.len {
					o := boxes.boxes[k]
					mut overlap := true
					for i in 0 .. 3 {
						if i != axis && (b.mx[i] <= o.mn[i] + 1e-9 || b.mn[i] >= o.mx[i] - 1e-9) {
							overlap = false
						}
					}
					if !overlap { continue }
					if d > 0 && o.mn[axis] >= b.mx[axis] - 1e-9 {
						d = math.min(d, o.mn[axis] - b.mx[axis])
					} else if d < 0 && o.mx[axis] <= b.mn[axis] + 1e-9 {
						d = math.max(d, o.mx[axis] - b.mn[axis])
					}
				}
			}
		}
	}
	match axis {
		0 { p.pos.x += d }
		1 { p.pos.y += d }
		else { p.pos.z += d }
	}
	return d
}

fn approach(v f64, target f64, max_delta f64) f64 {
	return v + math.max(-max_delta, math.min(max_delta, target - v))
}

fn (p Player) fluid_at(world World, y f64) int {
	bi := world.block_info(world.get_block(floor_int(p.pos.x), floor_int(y), floor_int(p.pos.z)))
	if !bi.liquid() { return 0 }
	return if bi.name.ends_with('lava') { 2 } else { 1 }
}

fn (p Player) supported(world World, px f64, pz f64) bool {
	mut b := p.box()
	b.mn[0] += px - p.pos.x
	b.mx[0] += px - p.pos.x
	b.mn[2] += pz - p.pos.z
	b.mx[2] += pz - p.pos.z
	b.mn[1] -= 0.6
	b.mx[1] = p.pos.y - 1e-4
	for x := floor_int(b.mn[0]); x <= floor_int(b.mx[0]); x++ {
		for y := floor_int(b.mn[1]); y <= floor_int(b.mx[1]); y++ {
			for z := floor_int(b.mn[2]); z <= floor_int(b.mx[2]); z++ {
				boxes := block_boxes(world, x, y, z)
				for k in 0 .. boxes.len { if boxes.boxes[k].overlaps(b) { return true } }
			}
		}
	}
	return false
}

pub fn (mut p Player) update(dt f64, input MoveInput, world World) {
	if !world.column_loaded(chunk_coord(floor_int(p.pos.x)), chunk_coord(floor_int(p.pos.z))) {
		return
	}
	p.sneaking = input.sneak && !p.flying
	feet := p.fluid_at(world, p.pos.y + 0.1)
	body := p.fluid_at(world, p.pos.y + 0.9)
	p.in_water = feet == 1 || body == 1
	p.in_lava = feet == 2 || body == 2
	p.eyes_in_water = p.fluid_at(world, p.eye().y) == 1
	in_fluid := p.in_water || p.in_lava
	sy := math.sin(f64(p.yaw))
	cy := math.cos(f64(p.yaw))
	mut wx := -sy * f64(input.forward) - cy * f64(input.strafe)
	mut wz := cy * f64(input.forward) - sy * f64(input.strafe)
	wl := math.sqrt(wx * wx + wz * wz)
	if wl > 1 {
		wx /= wl
		wz /= wl
	}
	p.sprinting = input.sprint && input.forward > 0 && !p.sneaking
	mut speed := 4.317
	if p.sneaking {
		speed = 1.295
	} else if p.sprinting {
		speed = 5.612
	}
	if p.flying { speed = if p.sprinting { 21.8 } else { 10.9 } }
	if in_fluid && !p.flying { speed *= if p.in_lava { 0.3 } else { 0.6 } }
	if p.flying {
		p.vel.x = approach(p.vel.x, wx * speed, 80 * dt)
		p.vel.z = approach(p.vel.z, wz * speed, 80 * dt)
		vy := (if input.jump { 1.0 } else { 0.0 }) - (if input.sneak { 1.0 } else { 0.0 })
		p.vel.y = approach(p.vel.y, vy * (if p.sprinting { 11.0 } else { 7.5 }), 60 * dt)
	} else {
		accel := if p.on_ground {
			55.0
		} else if in_fluid {
			20.0
		} else {
			14.0
		}
		p.vel.x = approach(p.vel.x, wx * speed, accel * dt)
		p.vel.z = approach(p.vel.z, wz * speed, accel * dt)
		if in_fluid {
			p.vel.y -= (if p.in_lava { 4.0 } else { 8.0 }) * dt
			p.vel.y *= math.pow(if p.in_lava { 0.5 } else { 0.8 }, dt * 20)
			if input.jump {
				p.vel.y = approach(p.vel.y, if p.in_lava { 2.5 } else { 4.0 }, 30 * dt)
			}
		} else {
			p.vel.y -= 32 * dt
			p.vel.y *= math.pow(0.98, dt * 20)
			if p.vel.y < -78 { p.vel.y = -78 }
			if input.jump && p.on_ground {
				p.vel.y = 8.4
				if p.sprinting {
					p.vel.x += -sy * 2
					p.vel.z += cy * 2
				}
			}
		}
	}
	start := p.pos
	mut dx := p.vel.x * dt
	dy := p.vel.y * dt
	mut dz := p.vel.z * dt
	if p.sneaking && p.on_ground {
		for dx != 0 && !p.supported(world, p.pos.x + dx, p.pos.z) {
			dx = if math.abs(dx) < 0.05 { 0.0 } else { dx - math.copysign(0.05, dx) }
		}
		for dz != 0 && !p.supported(world, p.pos.x, p.pos.z + dz) {
			dz = if math.abs(dz) < 0.05 { 0.0 } else { dz - math.copysign(0.05, dz) }
		}
	}
	was_on_ground := p.on_ground
	mut my := p.move_axis(world, 1, dy)
	mut mx := p.move_axis(world, 0, dx)
	mut mz := p.move_axis(world, 2, dz)
	hit_h := math.abs(mx - dx) > 1e-9 || math.abs(mz - dz) > 1e-9
	if hit_h && (was_on_ground || my != dy) && !p.flying && !in_fluid && p.vel.y <= 0.01 {
		after := p.pos
		p.pos = start
		up := p.move_axis(world, 1, 0.6)
		sx := p.move_axis(world, 0, dx)
		sz := p.move_axis(world, 2, dz)
		p.move_axis(world, 1, -up - 0.001)
		if math.abs(sx) + math.abs(sz) <= math.abs(mx) + math.abs(mz) + 1e-6 {
			p.pos = after
		} else {
			mx = sx
			mz = sz
			my = dy
		}
	}
	p.on_ground = dy < 0 && math.abs(my - dy) > 1e-9
	if math.abs(my - dy) > 1e-9 { p.vel.y = 0 }
	if math.abs(mx - dx) > 1e-9 { p.vel.x = 0 }
	if math.abs(mz - dz) > 1e-9 { p.vel.z = 0 }
	if p.flying && p.on_ground { p.flying = false }
	if !p.on_ground && dy >= -1e-9 && dy <= 1e-9 {
		old := p.pos
		t := p.move_axis(world, 1, -0.01)
		p.pos = old
		p.on_ground = t > -0.0099
	}
}
