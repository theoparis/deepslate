module gameplay

import vinecraft.blocks
import math

// World supplies the loaded terrain and the shared block registry to gameplay.
pub interface World {
	get_block(x int, y int, z int) blocks.BlockId
	column_loaded(cx int, cz int) bool
	block_info(id blocks.BlockId) blocks.BlockInfo
mut:
	set_block(x int, y int, z int, id blocks.BlockId) bool
	fluid_state(id blocks.BlockId, depth int) blocks.BlockId
	block_id(name string) blocks.BlockId
}

pub const min_y = -64
pub const max_y = 320

pub struct Vec3 {
pub mut:
	x f64
	y f64
	z f64
}

fn (v Vec3) component(axis int) f64 {
	return match axis {
		0 { v.x }
		1 { v.y }
		else { v.z }
	}
}

fn floor_int(v f64) int { return int(math.floor(v)) }

fn chunk_coord(v int) int { return floor_int(f64(v) / 16.0) }

pub struct Aabb {
pub mut:
	mn [3]f64
	mx [3]f64
}

pub fn (b Aabb) overlaps(o Aabb) bool {
	for i in 0 .. 3 {
		if b.mx[i] <= o.mn[i] || b.mn[i] >= o.mx[i] { return false }
	}
	return true
}

pub struct CollisionBoxes {
pub mut:
	boxes [2]Aabb
	len   int
}

pub fn block_boxes(world World, x int, y int, z int) CollisionBoxes {
	id := world.get_block(x, y, z)
	if id == 0 { return CollisionBoxes{} }
	bi := world.block_info(id)
	if !bi.solid() { return CollisionBoxes{} }
	mut result := CollisionBoxes{ len: int(bi.nbox) }
	for i in 0 .. result.len {
		b := bi.boxes[i]
		result.boxes[i] = Aabb{
			mn: [f64(x) + f64(b.min[0]), f64(y) + f64(b.min[1]), f64(z) + f64(b.min[2])]!
			mx: [f64(x) + f64(b.max[0]), f64(y) + f64(b.max[1]), f64(z) + f64(b.max[2])]!
		}
	}
	return result
}
