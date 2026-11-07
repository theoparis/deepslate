module gameplay

import vinecraft.blocks

struct Update {
	x   int
	y   int
	z   int
	due i64
}

pub struct BlockUpdates {
mut:
	queue      []Update
	head       int
	queued     map[u64]bool
	tick_count i64
}

fn update_key(x int, y int, z int) u64 {
	return (u64(u32(x) & 0x3ffffff) << 38) | (u64(u32(z) & 0x3ffffff) << 12) | u64(u32(y + 64) & 0xfff)
}

pub fn (u BlockUpdates) pending() int { return u.queue.len - u.head }

pub fn (u BlockUpdates) now() i64 { return u.tick_count }

pub fn (mut u BlockUpdates) schedule(x int, y int, z int, delay int) {
	if y < min_y || y >= max_y { return }
	key := update_key(x, y, z)
	if key in u.queued { return }
	u.queued[key] = true
	u.queue << Update{ x: x, y: y, z: z, due: u.tick_count + delay }
}

pub fn (mut u BlockUpdates) notify(x int, y int, z int, delay int) {
	u.schedule(x, y, z, delay)
	for d in [[0, -1, 0]!, [0, 1, 0]!, [1, 0, 0]!, [-1, 0, 0]!, [0, 0, 1]!, [0, 0, -1]!]! {
		u.schedule(x + d[0], y + d[1], z + d[2], delay)
	}
}

pub fn (mut u BlockUpdates) tick(mut world World) {
	u.tick_count++
	n := u.pending()
	mut budget := 600
	for _ in 0 .. n {
		if budget <= 0 { break }
		item := u.queue[u.head]
		u.head++
		if item.due > u.tick_count {
			u.queue << item
			continue
		}
		u.queued.delete(update_key(item.x, item.y, item.z))
		u.run(mut world, item.x, item.y, item.z)
		budget--
	}
	if u.head > 4096 && u.head * 2 >= u.queue.len {
		u.queue = u.queue[u.head..].clone()
		u.head = 0
	}
}

fn name_at(world World, x int, y int, z int) string {
	id := world.get_block(x, y, z)
	if id == 0 { return '' }
	return world.block_info(id).def.name
}

fn solid_at(world World, x int, y int, z int) bool {
	id := world.get_block(x, y, z)
	return id != 0 && world.block_info(id).solid()
}

pub fn supported(world World, id blocks.BlockId, x int, y int, z int) bool {
	bi := world.block_info(id)
	if bi.def.name == '' || bi.flags & blocks.bf_unknown != 0 { return true }
	below := name_at(world, x, y - 1, z)
	match bi.def.kind {
		.torch {
			mut dir := 'top'
			for state in bi.states {
				if state.key == 'torch_facing_direction' {
					dir = state.value.s
					break
				}
			}
			return match dir {
				'top' { solid_at(world, x, y - 1, z) }
				'east' { solid_at(world, x - 1, y, z) }
				'west' { solid_at(world, x + 1, y, z) }
				'south' { solid_at(world, x, y, z - 1) }
				else { solid_at(world, x, y, z + 1) }
			}
		}
		.cactus { return below in ['sand', 'red_sand', 'cactus'] }
		.cross {
			n := bi.def.name
			if n == 'reeds' {
				return below in ['sand', 'red_sand', 'dirt', 'coarse_dirt', 'grass_block', 'reeds']
			}
			if n == 'deadbush' { return below in ['sand', 'red_sand', 'dirt', 'coarse_dirt'] }
			if n == 'brown_mushroom' || n == 'red_mushroom' { return solid_at(world, x, y - 1, z) }
			return below in ['grass_block', 'dirt', 'coarse_dirt']
		}
		else { return true }
	}
}

fn (mut u BlockUpdates) run(mut world World, x int, y int, z int) {
	if !world.column_loaded(chunk_coord(x), chunk_coord(z)) { return }
	id := world.get_block(x, y, z)
	if id == 0 { return }
	bi := world.block_info(id)
	if bi.def.kind == .liquid {
		u.fluid(mut world, x, y, z, id)
		return
	}
	if !supported(world, id, x, y, z) {
		world.set_block(x, y, z, 0)
		u.notify(x, y, z, 1)
		return
	}
	u.gravity(mut world, x, y, z, id)
}

fn (mut u BlockUpdates) gravity(mut world World, x int, y int, z int, id blocks.BlockId) bool {
	n := world.block_info(id).def.name
	if n != 'sand' && n != 'red_sand' && n != 'gravel' { return false }
	below := world.get_block(x, y - 1, z)
	if y <= min_y || !world.block_info(below).replaceable() { return false }
	world.set_block(x, y, z, 0)
	world.set_block(x, y - 1, z, id)
	u.notify(x, y, z, 1)
	u.schedule(x, y - 1, z, 2)
	return true
}

fn same_fluid(world World, id blocks.BlockId, name string) bool {
	return id != 0 && world.block_info(id).def.name == name
}

fn rests(world World, x int, y int, z int, name string) bool {
	id := world.get_block(x, y, z)
	if id == 0 { return false }
	bi := world.block_info(id)
	return !bi.replaceable() || (bi.def.name == name && bi.fluid_depth < 8)
}

fn (mut u BlockUpdates) react(mut world World, x int, y int, z int, name string, lava bool) bool {
	id := world.get_block(x, y, z)
	if id == 0 { return false }
	bi := world.block_info(id)
	if bi.def.kind != .liquid || bi.def.name == name { return false }
	result := if lava {
		'stone'
	} else if bi.fluid_depth == 0 {
		'obsidian'
	} else {
		'cobblestone'
	}
	replacement := world.block_id(result)
	world.set_block(x, y, z, replacement)
	u.notify(x, y, z, 1)
	return true
}

fn (mut u BlockUpdates) fluid(mut world World, x int, y int, z int, block_id blocks.BlockId) {
	mut id := block_id
	me := world.block_info(id)
	name := me.def.name
	lava := me.name.ends_with('lava')
	delay := if lava { 30 } else { 5 }
	max_flow := if lava { 3 } else { 7 }
	mut depth := int(me.fluid_depth)
	sides := [[1, 0]!, [-1, 0]!, [0, 1]!, [0, -1]!]!
	if depth > 0 {
		mut best := 99
		fed := same_fluid(world, world.get_block(x, y + 1, z), name)
		if fed { best = 8 }
		for s in sides {
			if fed { break }
			nb := world.get_block(x + s[0], y, z + s[1])
			if !same_fluid(world, nb, name) { continue }
			nd := int(world.block_info(nb).fluid_depth)
			if nd >= 8 {
				if rests(world, x + s[0], y - 1, z + s[1], name) && best > 1 { best = 1 }
			} else if nd < max_flow && nd + 1 < best {
				best = nd + 1
			}
		}
		if best == 99 {
			world.set_block(x, y, z, 0)
			u.notify(x, y, z, delay)
			return
		}
		if best != depth {
			depth = best
			id = world.fluid_state(id, depth)
			world.set_block(x, y, z, id)
			u.notify(x, y, z, delay)
		}
	}
	if y > min_y && u.react(mut world, x, y - 1, z, name, lava) { return }
	if y > min_y && !rests(world, x, y - 1, z, name) {
		below := world.get_block(x, y - 1, z)
		bel := world.block_info(below)
		if below == 0 || (bel.replaceable() && (bel.def.kind != .liquid || same_fluid(world, below, name))) {
			if !(same_fluid(world, below, name) && bel.fluid_depth >= 8) {
				falling := world.fluid_state(id, 8)
				world.set_block(x, y - 1, z, falling)
				u.notify(x, y - 1, z, delay)
			}
		}
		return
	}
	nd := if depth >= 8 { 1 } else { depth + 1 }
	if nd > max_flow { return }
	for s in sides {
		nx := x + s[0]
		nz := z + s[1]
		if u.react(mut world, nx, y, nz, name, lava) { continue }
		nb := world.get_block(nx, y, nz)
		ni := world.block_info(nb)
		place := nb == 0 || (ni.replaceable() && ni.def.kind != .liquid) || (same_fluid(world, nb, name) && ni.fluid_depth > nd && ni.fluid_depth < 8)
		if !place { continue }
		flowing := world.fluid_state(id, nd)
		world.set_block(nx, y, nz, flowing)
		u.notify(nx, y, nz, delay)
	}
}
