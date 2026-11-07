module gameplay

import vinecraft.blocks
import math

pub struct RayHit {
pub mut:
	hit     bool
	x       int
	y       int
	z       int
	face    int
	dist    f64
	point   Vec3
	box_min [3]f64
	box_max [3]f64
}

pub struct SelectionBoxes {
pub mut:
	boxes [2]blocks.Box
	len   int
}

pub fn selection_boxes(bi blocks.BlockInfo) SelectionBoxes {
	mut result := SelectionBoxes{}
	if bi.flags & blocks.bf_no_target != 0 { return result }
	if bi.nbox > 0 {
		result.boxes = bi.boxes
		result.len = int(bi.nbox)
		return result
	}
	result.len = 1
	if bi.flags & blocks.bf_plant != 0 {
		result.boxes[0] = blocks.Box{ min: [f32(0.15), 0, 0.15]!, max: [f32(0.85), 0.8, 0.85]! }
	} else {
		result.boxes[0] = blocks.Box{ min: [f32(0), 0, 0]!, max: [f32(1), 1, 1]! }
	}
	return result
}

pub fn raycast(world World, o Vec3, d Vec3, reach f64) RayHit {
	mut best := RayHit{ dist: reach + 1 }
	mut x := floor_int(o.x)
	mut y := floor_int(o.y)
	mut z := floor_int(o.z)
	sx := if d.x > 0 { 1 } else { -1 }
	sy := if d.y > 0 { 1 } else { -1 }
	sz := if d.z > 0 { 1 } else { -1 }
	inv := [if d.x != 0 { 1 / d.x } else { 1e30 }, if d.y != 0 { 1 / d.y } else { 1e30 },
		if d.z != 0 { 1 / d.z } else { 1e30 }]!
	mut tmax := [(f64(if sx > 0 { x + 1 } else { x }) - o.x) * inv[0],
		(f64(if sy > 0 { y + 1 } else { y }) - o.y) * inv[1],
		(f64(if sz > 0 { z + 1 } else { z }) - o.z) * inv[2]]!
	mut tdelta := [math.abs(inv[0]), math.abs(inv[1]), math.abs(inv[2])]!
	for a in 0 .. 3 {
		if d.component(a) == 0 {
			tmax[a] = 1e30
			tdelta[a] = 1e30
		}
	}
	for _ in 0 .. 64 {
		id := world.get_block(x, y, z)
		if id != 0 {
			boxes := selection_boxes(world.block_info(id))
			for k in 0 .. boxes.len {
				box := boxes.boxes[k]
				bmin := [f64(x) + f64(box.min[0]), f64(y) + f64(box.min[1]), f64(z) + f64(box.min[2])]!
				bmax := [f64(x) + f64(box.max[0]), f64(y) + f64(box.max[1]), f64(z) + f64(box.max[2])]!
				mut t0 := 0.0
				mut t1 := reach
				mut face := -1
				mut ok := true
				for a in 0 .. 3 {
					oa := o.component(a)
					da := d.component(a)
					if math.abs(da) < 1e-12 {
						if oa < bmin[a] || oa > bmax[a] {
							ok = false
							break
						}
						continue
					}
					mut ta := (bmin[a] - oa) / da
					mut tb := (bmax[a] - oa) / da
					faces := [[4, 5]!, [0, 1]!, [2, 3]!]!
					fa := faces[a][if da > 0 { 0 } else { 1 }]
					if ta > tb {
						tmp := ta
						ta = tb
						tb = tmp
					}
					if ta > t0 {
						t0 = ta
						face = fa
					}
					if tb < t1 { t1 = tb }
					if t0 > t1 {
						ok = false
						break
					}
				}
				if !ok || t0 >= best.dist { continue }
				best = RayHit{
					hit:     true
					x:       x
					y:       y
					z:       z
					dist:    t0
					face:    if face < 0 {
						1
					} else {
						face
					}
					point:   Vec3{ x: o.x + d.x * t0, y: o.y + d.y * t0, z: o.z + d.z * t0 }
					box_min: bmin
					box_max: bmax
				}
			}
			if best.hit { return best }
		}
		a := if tmax[0] < tmax[1] {
			if tmax[0] < tmax[2] { 0 } else { 2 }
		} else {
			if tmax[1] < tmax[2] { 1 } else { 2 }
		}
		if tmax[a] > reach { break }
		if a == 0 {
			x += sx
		} else if a == 1 {
			y += sy
		} else {
			z += sz
		}
		tmax[a] += tdelta[a]
	}
	return best
}
