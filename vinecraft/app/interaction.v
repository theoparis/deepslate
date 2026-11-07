module app

import math
import vinecraft.blocks
import vinecraft.gameplay

fn set_state(mut states blocks.StateMap, key string, value blocks.StateValue) {
	for i, entry in states {
		if entry.key == key {
			states[i] = blocks.StateEntry{ key: key, value: value }
			return
		}
	}
	states << blocks.StateEntry{ key: key, value: value }
}

// placement_state chooses the Bedrock block state from the clicked face and view.
pub fn placement_state(mut reg blocks.Registry, base blocks.BlockId, hit gameplay.RayHit, yaw f32) blocks.BlockId {
	bi := reg.info(base)
	mut states := bi.states.clone()
	upper := hit.face == 0 || (hit.face >= 2 && hit.point.y - math.floor(hit.point.y) > 0.5)
	match bi.def.kind {
		.column {
			set_state(mut states, 'pillar_axis', blocks.state_string(if hit.face <= 1 {
				'y'
			} else if hit.face <= 3 {
				'z'
			} else {
				'x'
			}))
		}
		.slab {
			set_state(mut states, 'minecraft:vertical_half', blocks.state_string(if upper {
				'top'
			} else {
				'bottom'
			}))
		}
		.stairs {
			fx := -math.sin(yaw)
			fz := math.cos(yaw)
			dir := if math.abs(fx) > math.abs(fz) {
				if fx > 0 { 0 } else { 1 }
			} else {
				if fz > 0 { 2 } else { 3 }
			}
			set_state(mut states, 'upside_down_bit', blocks.state_byte(if upper { 1 } else { 0 }))
			set_state(mut states, 'weirdo_direction', blocks.state_int_value(dir))
		}
		.torch {
			set_state(mut states, 'torch_facing_direction', blocks.state_string(['top', 'top',
				'north', 'south', 'west', 'east'][hit.face]))
		}
		else { return base }
	}
	return reg.lookup_or_register(bi.name, states)
}

// break_target returns the removed block so the caller can emit break particles.
pub fn break_target(mut world gameplay.World, mut updates gameplay.BlockUpdates, hit gameplay.RayHit, creative bool) blocks.BlockId {
	if !hit.hit { return 0 }
	id := world.get_block(hit.x, hit.y, hit.z)
	if world.block_info(id).flags & blocks.bf_unbreakable != 0 && !creative { return 0 }
	if world.set_block(hit.x, hit.y, hit.z, 0) {
		updates.notify(hit.x, hit.y, hit.z, 1)
		return id
	}
	return 0
}

pub fn place_target(mut world gameplay.World, mut reg blocks.Registry, mut updates gameplay.BlockUpdates, hit gameplay.RayHit, held blocks.BlockId, player gameplay.Player) bool {
	if !hit.hit || held == 0 { return false }
	directions := [[0, -1, 0]!, [0, 1, 0]!, [0, 0, -1]!, [0, 0, 1]!, [-1, 0, 0]!, [1, 0, 0]!]!
	mut x := hit.x
	mut y := hit.y
	mut z := hit.z
	if !world.block_info(world.get_block(x, y, z)).replaceable() {
		x += directions[hit.face][0]
		y += directions[hit.face][1]
		z += directions[hit.face][2]
	}
	if y < gameplay.min_y || y >= gameplay.max_y || !world.block_info(world.get_block(x, y, z)).replaceable() {
		return false
	}
	if reg.info(held).def.kind == .torch && hit.face == 0 { return false }
	id := placement_state(mut reg, held, hit, player.yaw)
	if !gameplay.supported(world, id, x, y, z) { return false }
	bi := reg.info(id)
	if bi.solid() {
		for i in 0 .. int(bi.nbox) {
			b := bi.boxes[i]
			box := gameplay.Aabb{
				mn: [f64(x) + b.min[0], f64(y) + b.min[1], f64(z) + b.min[2]]!
				mx: [
					f64(x) + b.max[0],
					f64(y) + b.max[1],
					f64(z) + b.max[2],
				]!
			}
			if box.overlaps(player.box()) { return false }
		}
	}
	if !world.set_block(x, y, z, id) { return false }
	updates.notify(x, y, z, 1)
	return true
}
