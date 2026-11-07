module gameplay

import math
import vinecraft.blocks

@[heap]
struct PortedWorld {
mut:
	reg   &blocks.Registry = unsafe { nil }
	cells map[string]blocks.BlockId
}

fn ported_key(x int, y int, z int) string { return '${x},${y},${z}' }

fn (w PortedWorld) get_block(x int, y int, z int) blocks.BlockId {
	return w.cells[ported_key(x, y, z)] or { 0 }
}

fn (w PortedWorld) column_loaded(cx int, cz int) bool { return true }

fn (w PortedWorld) block_info(id blocks.BlockId) blocks.BlockInfo { return w.reg.info(id) }

fn (mut w PortedWorld) set_block(x int, y int, z int, id blocks.BlockId) bool {
	w.cells[ported_key(x, y, z)] = id
	return true
}

fn (mut w PortedWorld) fluid_state(id blocks.BlockId, depth int) blocks.BlockId {
	return w.reg.lookup_or_register(w.reg.info(id).name, [blocks.StateEntry{ key: 'liquid_depth', value: blocks.state_int_value(depth) }])
}

fn (mut w PortedWorld) block_id(name string) blocks.BlockId { return w.reg.find(name) }

fn ported_floor(mut w PortedWorld, radius int, y int) {
	stone := w.reg.find('stone')
	for x := -radius; x <= radius; x++ {
		for z := -radius; z <= radius; z++ { w.set_block(x, y, z, stone) }
	}
}

fn ported_depth(w PortedWorld, x int, y int, z int, name string) int {
	id := w.get_block(x, y, z)
	if id == 0 { return -1 }
	bi := w.block_info(id)
	return if bi.def.name == name { int(bi.fluid_depth) } else { -1 }
}

fn test_ported_player_fall_walk_jump_and_wall() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 12, 100)
	mut p := Player{ pos: Vec3{ x: 0.5, y: 105, z: 0.5 } }
	for _ in 0 .. 240 { p.update(1.0 / 60, MoveInput{}, w) }
	assert p.on_ground
	assert math.abs(p.pos.y - 101) < 1e-6
	start := p.pos.z
	for _ in 0 .. 60 { p.update(1.0 / 60, MoveInput{ forward: 1 }, w) }
	assert p.pos.z - start > 3.8 && p.pos.z - start < 4.6
	p.vel = Vec3{}
	mut peak := p.pos.y
	for i in 0 .. 40 {
		p.update(1.0 / 60, MoveInput{ jump: i < 2 }, w)
		peak = math.max(peak, p.pos.y)
	}
	assert peak - 101 > 1.1 && peak - 101 < 1.4
	for _ in 0 .. 60 { p.update(1.0 / 60, MoveInput{}, w) }
	assert p.on_ground
	stone := w.reg.find('stone')
	w.set_block(3, 101, 0, stone)
	w.set_block(3, 102, 0, stone)
	p.pos = Vec3{ x: 0.5, y: 101, z: 0.5 }
	p.vel = Vec3{}
	p.yaw = f32(3 * math.pi / 2)
	for _ in 0 .. 120 { p.update(1.0 / 60, MoveInput{ forward: 1 }, w) }
	assert p.pos.x < 2.700001
}

fn test_ported_player_steps_onto_slab() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 8, 100)
	w.set_block(3, 101, 0, w.reg.find('oak_slab'))
	mut p := Player{ pos: Vec3{ x: 0.5, y: 101, z: 0.5 }, yaw: f32(3 * math.pi / 2) }
	for _ in 0 .. 90 { p.update(1.0 / 60, MoveInput{ forward: 1 }, w) }
	assert p.pos.x > 3.5
}

fn test_ported_lava_flow_limit() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 8, 200)
	mut u := BlockUpdates{}
	w.set_block(0, 201, 0, w.reg.find('lava'))
	u.notify(0, 201, 0, 1)
	for _ in 0 .. 20 { u.tick(mut w) }
	assert ported_depth(w, 3, 201, 0, 'lava') == -1
	for _ in 0 .. 400 { u.tick(mut w) }
	assert ported_depth(w, 3, 201, 0, 'lava') == 3
	assert ported_depth(w, 4, 201, 0, 'lava') == -1
}

fn test_ported_gravity_stops_at_world_bottom() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	sand := w.reg.find('sand')
	w.set_block(0, min_y, 0, sand)
	mut u := BlockUpdates{}
	u.notify(0, min_y, 0, 1)
	for _ in 0 .. 20 { u.tick(mut w) }
	assert w.get_block(0, min_y, 0) == sand
	assert w.get_block(0, min_y - 1, 0) == 0
}

fn test_ported_player_flight_and_sneak_ledge() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 8, 100)
	mut p := Player{ pos: Vec3{ x: 0.5, y: 110, z: 0.5 }, flying: true }
	for _ in 0 .. 120 { p.update(1.0 / 60, MoveInput{}, w) }
	assert math.abs(p.pos.y - 110) < 0.01
	for x in 5 .. 9 {
		for z := -8; z <= 8; z++ { w.set_block(x, 100, z, 0) }
	}
	p.flying = false
	p.pos = Vec3{ x: 3.5, y: 101, z: 0.5 }
	p.vel = Vec3{}
	p.yaw = f32(3 * math.pi / 2)
	for _ in 0 .. 20 { p.update(1.0 / 60, MoveInput{}, w) }
	for _ in 0 .. 240 { p.update(1.0 / 60, MoveInput{ forward: 1, sneak: true }, w) }
	assert p.on_ground && p.pos.x < 5.3
}

fn test_ported_raycast_faces_water_and_slab() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	w.set_block(5, 250, 5, w.reg.find('stone'))
	hit := raycast(w, Vec3{ x: 0.5, y: 250.5, z: 5.5 }, Vec3{ x: 1 }, 10)
	assert hit.hit && hit.x == 5 && hit.face == 4 && math.abs(hit.dist - 4.5) < 1e-9
	assert raycast(w, Vec3{ x: 5.5, y: 260, z: 5.5 }, Vec3{ y: -1 }, 20).face == 1
	assert !raycast(w, Vec3{ x: 5.5, y: 260, z: 5.5 }, Vec3{ y: -1 }, 5).hit
	assert raycast(w, Vec3{ x: 5.5, y: 240, z: 5.5 }, Vec3{ y: 1 }, 20).face == 0
	w.set_block(5, 251, 5, w.reg.find('water'))
	h := raycast(w, Vec3{ x: 5.5, y: 255, z: 5.5 }, Vec3{ x: -0.0, y: -1 }, 20)
	assert h.hit && h.y == 250
	w.set_block(8, 250, 5, w.reg.find('oak_slab'))
	assert !raycast(w, Vec3{ x: 6.5, y: 250.75, z: 5.5 }, Vec3{ x: 1 }, 5).hit
	low := raycast(w, Vec3{ x: 6.5, y: 250.25, z: 5.5 }, Vec3{ x: 1 }, 5)
	assert low.hit && low.x == 8
}

fn test_ported_water_spreads_and_drains() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 9, 200)
	mut u := BlockUpdates{}
	w.set_block(0, 201, 0, w.reg.find('water'))
	u.notify(0, 201, 0, 1)
	for _ in 0 .. 300 { u.tick(mut w) }
	assert ported_depth(w, 1, 201, 0, 'water') == 1
	assert ported_depth(w, 3, 201, 0, 'water') == 3
	assert ported_depth(w, 0, 201, -7, 'water') == 7
	assert ported_depth(w, 8, 201, 0, 'water') == -1
	assert ported_depth(w, 3, 201, 3, 'water') == 6
	assert u.pending() == 0
	w.set_block(0, 201, 0, 0)
	u.notify(0, 201, 0, 1)
	for _ in 0 .. 300 { u.tick(mut w) }
	for id in w.cells.values() {
		assert id == 0 || w.block_info(id).def.name != 'water'
	}
}

fn test_ported_falling_water_and_gravity_blocks() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 9, 200)
	ported_floor(mut w, 9, 196)
	w.set_block(0, 200, 0, 0)
	w.set_block(0, 201, 0, w.reg.find('water'))
	mut u := BlockUpdates{}
	u.notify(0, 201, 0, 1)
	for _ in 0 .. 400 { u.tick(mut w) }
	assert ported_depth(w, 0, 200, 0, 'water') == 8
	assert ported_depth(w, 0, 197, 0, 'water') == 8
	assert ported_depth(w, 1, 197, 0, 'water') == 1
	w.set_block(5, 206, 5, w.reg.find('sand'))
	w.set_block(6, 204, 5, w.reg.find('gravel'))
	u.notify(5, 206, 5, 1)
	u.notify(6, 204, 5, 1)
	for _ in 0 .. 100 { u.tick(mut w) }
	assert w.get_block(5, 201, 5) == w.reg.find('sand')
	assert w.get_block(5, 206, 5) == 0
	assert w.get_block(6, 201, 5) == w.reg.find('gravel')
}

fn ported_torch(mut w PortedWorld, direction string) blocks.BlockId {
	return w.reg.lookup_or_register('minecraft:torch', [blocks.StateEntry{ key: 'torch_facing_direction', value: blocks.state_string(direction) }])
}

fn test_ported_support_rules_and_cascading_drops() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	grass := w.reg.find('grass_block')
	sand := w.reg.find('sand')
	stone := w.reg.find('stone')
	plant := w.reg.find('short_grass')
	poppy := w.reg.find('poppy')
	cactus := w.reg.find('cactus')
	cane := w.reg.find('reeds')
	w.set_block(0, 200, 0, grass)
	w.set_block(4, 200, 4, stone)
	w.set_block(5, 200, 5, sand)
	assert supported(w, plant, 0, 201, 0)
	assert !supported(w, poppy, 4, 201, 4)
	assert !supported(w, poppy, 5, 201, 5)
	assert supported(w, cactus, 5, 201, 5)
	assert !supported(w, cactus, 0, 201, 0)
	assert supported(w, w.reg.find('deadbush'), 5, 201, 5)
	assert supported(w, cane, 5, 201, 5)
	for y in 201 .. 204 { w.set_block(5, y, 5, cane) }
	w.set_block(0, 201, 0, plant)
	mut updates := BlockUpdates{}
	for _ in 0 .. 10 { updates.tick(mut w) }
	assert w.get_block(5, 203, 5) == cane
	w.set_block(5, 200, 5, 0)
	w.set_block(0, 200, 0, 0)
	updates.notify(5, 200, 5, 1)
	updates.notify(0, 200, 0, 1)
	for _ in 0 .. 30 { updates.tick(mut w) }
	for y in 201 .. 204 {
		assert w.get_block(5, y, 5) == 0
	}
	assert w.get_block(0, 201, 0) == 0
}

fn test_ported_torch_support_and_removal() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	stone := w.reg.find('stone')
	standing := w.reg.find('torch')
	east := ported_torch(mut w, 'east')
	west := ported_torch(mut w, 'west')
	north := ported_torch(mut w, 'north')
	south := ported_torch(mut w, 'south')
	w.set_block(8, 200, 8, stone)
	w.set_block(12, 201, 12, stone)
	assert supported(w, standing, 8, 201, 8)
	assert !supported(w, standing, 9, 202, 8)
	assert supported(w, east, 13, 201, 12)
	assert supported(w, west, 11, 201, 12)
	assert supported(w, north, 12, 201, 11)
	assert supported(w, south, 12, 201, 13)
	assert !supported(w, east, 11, 201, 12)
	w.set_block(13, 201, 12, east)
	w.set_block(8, 201, 8, standing)
	w.set_block(12, 201, 12, 0)
	w.set_block(8, 200, 8, 0)
	mut updates := BlockUpdates{}
	updates.notify(12, 201, 12, 1)
	updates.notify(8, 200, 8, 1)
	for _ in 0 .. 20 { updates.tick(mut w) }
	assert w.get_block(13, 201, 12) == 0
	assert w.get_block(8, 201, 8) == 0
}

fn test_ported_water_lava_reaction() {
	mut w := PortedWorld{ reg: blocks.new_registry() }
	ported_floor(mut w, 9, 200)
	lava := w.reg.find('lava')
	w.set_block(0, 201, 0, lava)
	w.set_block(4, 201, 0, w.reg.find('water'))
	mut updates := BlockUpdates{}
	updates.notify(0, 201, 0, 1)
	updates.notify(4, 201, 0, 1)
	for _ in 0 .. 400 { updates.tick(mut w) }
	obsidian := w.reg.find('obsidian')
	cobble := w.reg.find('cobblestone')
	mut found_obsidian := false
	mut found_cobble := false
	for x := -6; x <= 6; x++ {
		for z := -6; z <= 6; z++ {
			id := w.get_block(x, 201, z)
			if id == obsidian { found_obsidian = true }
			if id == cobble { found_cobble = true }
		}
	}
	assert found_obsidian || found_cobble
	assert w.get_block(0, 201, 0) != lava || found_cobble
}
