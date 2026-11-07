module gameplay

import vinecraft.blocks

struct RayWorld {
	reg &blocks.Registry
}

fn (w RayWorld) get_block(x int, y int, z int) blocks.BlockId {
	return if x == 0 && y == 0 && z == 3 { w.reg.find('stone') } else { blocks.BlockId(0) }
}

fn (w RayWorld) column_loaded(x int, z int) bool { return true }

fn (w RayWorld) block_info(id blocks.BlockId) blocks.BlockInfo { return w.reg.info(id) }

fn (mut w RayWorld) set_block(x int, y int, z int, id blocks.BlockId) bool { return false }

fn (mut w RayWorld) fluid_state(id blocks.BlockId, depth int) blocks.BlockId { return id }

fn (mut w RayWorld) block_id(name string) blocks.BlockId { return w.reg.find(name) }

fn test_raycast_stops_at_reach_and_hits_cube_face() {
	w := RayWorld{ reg: blocks.new_registry() }
	origin := Vec3{ x: 0.5, y: 0.5, z: 0.5 }
	dir := Vec3{ z: 1 }
	assert !raycast(w, origin, dir, 2).hit
	hit := raycast(w, origin, dir, 5)
	assert hit.hit && hit.x == 0 && hit.y == 0 && hit.z == 3
	assert hit.face == 2 && hit.dist == 2.5
}
