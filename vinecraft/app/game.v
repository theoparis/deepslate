module app

import math
import vinecraft.blocks
import vinecraft.cli
import vinecraft.gameplay
import vinecraft.render
import vinecraft.storage
import vinecraft.world
import vinecraft.worldgen

pub enum Screen {
	loading
	playing
	inventory
	pause
}

pub struct BrokenBlock {
pub:
	id blocks.BlockId
	x  int
	y  int
	z  int
}

@[heap]
pub struct Game {
pub:
	options cli.Options
pub mut:
	world              &world.World        = unsafe { nil }
	store              &storage.LevelStore = unsafe { nil }
	registry           &blocks.Registry    = unsafe { nil }
	generator          &worldgen.WorldGen  = unsafe { nil }
	player_state       gameplay.Player
	camera             render.Camera
	hit                gameplay.RayHit
	updates            gameplay.BlockUpdates
	script             Script
	screen             Screen = .loading
	hotbar             [9]blocks.BlockId
	selected           int
	radius             int = 10
	ticks              i64 = 1000
	frozen             bool
	show_debug_info    bool
	show_hud           bool = true
	spawn_pending      bool = true
	had_saved_player   bool
	quit_requested     bool
	pending_screenshot string
	renderer_idle      bool
	broken             []BrokenBlock
	name_timer         f64
	toast_timer        f64
	toast              string
	fps                f64
	frame_ms           f64
	threads            int
	autosave_timer     f64
	physics_accum      f64
	update_accum       f64
	tick_accum         f64
	break_cooldown     f64
	place_cooldown     f64
	last_error         string
}

pub fn (g &Game) player() &gameplay.Player { return unsafe { &g.player_state } }

pub fn (g &Game) target() gameplay.RayHit { return g.hit }

pub fn (g &Game) get_block(x int, y int, z int) blocks.BlockId { return g.world.get_block(x, y, z) }

pub fn (g &Game) block_name(id blocks.BlockId) string { return g.registry.info(id).name }

pub fn (g &Game) column_loaded(x int, z int) bool { return g.world.column_loaded(x, z) }

pub fn (g &Game) world_settled() bool {
	cx := int(math.floor(g.player_state.pos.x / 16))
	cz := int(math.floor(g.player_state.pos.z / 16))
	return g.world.all_loaded_around(cx, cz, g.radius + 1) && g.world.inflight_count() == 0 && g.renderer_idle
}

pub fn (mut g Game) set_block(x int, y int, z int, name string, states blocks.StateMap) bool {
	mut id := blocks.BlockId(0)
	if name != 'air' {
		id = if states.len == 0 {
			g.registry.find(name)
		} else {
			g.registry.lookup_or_register(name, states)
		}
	}
	if !g.world.set_block(x, y, z, id) { return false }
	g.updates.notify(x, y, z, 1)
	return true
}

pub fn (mut g Game) break_block() {
	mut w := gameplay.World(g.world)
	id := break_target(mut w, mut g.updates, g.hit, g.player_state.creative)
	if id != 0 { g.broken << BrokenBlock{ id: id, x: g.hit.x, y: g.hit.y, z: g.hit.z } }
}

pub fn (mut g Game) place_block() {
	mut w := gameplay.World(g.world)
	place_target(mut w, mut g.registry, mut g.updates, g.hit, g.hotbar[g.selected], g.player_state)
}

pub fn (mut g Game) pick_block() {
	if !g.hit.hit { return }
	id := g.world.get_block(g.hit.x, g.hit.y, g.hit.z)
	mut base := g.registry.find(g.registry.info(id).name)
	if base == 0 { base = id }
	for i, slot in g.hotbar {
		if slot == base {
			g.select_slot(i)
			return
		}
	}
	g.hotbar[g.selected] = base
	g.name_timer = 2
}

pub fn (mut g Game) select_slot(slot int) {
	g.selected = ((slot % 9) + 9) % 9
	g.name_timer = 2
}

pub fn (mut g Game) set_time(ticks i64) { g.ticks = ticks }

pub fn (mut g Game) freeze_time() { g.frozen = true }

pub fn (mut g Game) toggle_inventory() {
	g.screen = if g.screen == .inventory { .playing } else { .inventory }
}

pub fn (mut g Game) set_radius(radius int) { g.radius = radius }

pub fn (mut g Game) show_debug() { g.show_debug_info = true }

pub fn (mut g Game) request_screenshot(path string) { g.pending_screenshot = path }

pub fn (mut g Game) quit() { g.quit_requested = true }

pub fn (mut g Game) save() { g.save_all(true) or { g.last_error = err.msg() } }

pub fn (mut g Game) save_all(wait bool) ! {
	if g.options.no_save { return }
	g.world.save_dirty(wait)!
	if !g.spawn_pending {
		g.store.save_player(saved_player(g.player_state, g.hotbar, g.selected, g.registry))!
	}
	g.store.info.time = g.ticks
	g.store.write_level_dat()!
}

// update advances streaming, script, fixed-step physics, ticks and targeting.
pub fn (mut g Game) update(dt f64, now f64, input gameplay.MoveInput, left bool, right bool, width int, height int) {
	g.world.update(g.player_state.pos.x, g.player_state.pos.z, g.radius)
	for e in g.world.take_errors() { eprintln('world: ${e}') }
	if g.screen == .loading {
		eye := g.player_state.eye()
		g.camera.pos = render.Vec3d{ x: eye.x, y: eye.y, z: eye.z }
		g.camera.yaw = g.player_state.yaw
		g.camera.pitch = g.player_state.pitch
		cx := int(math.floor(g.player_state.pos.x / 16))
		cz := int(math.floor(g.player_state.pos.z / 16))
		mut ready := true
		for x := cx - 1; x <= cx + 1; x++ {
			for z := cz - 1; z <= cz + 1; z++ { if !g.world.column_loaded(x, z) { ready = false } }
		}
		if ready && g.spawn_pending {
			if !g.had_saved_player && g.options.start_pos == none {
				x := int(math.floor(g.player_state.pos.x))
				z := int(math.floor(g.player_state.pos.z))
				for y := gameplay.max_y - 1; y > gameplay.min_y; y-- {
					bi := g.registry.info(g.world.get_block(x, y, z))
					if bi.solid() && bi.flags & blocks.bf_leaves == 0 {
						g.player_state.pos.y = y + 1.001
						break
					}
				}
			}
			g.spawn_pending = false
			g.screen = .playing
		}
		return
	}
	mut host := ScriptHost(g)
	scripted := g.script.advance(mut host, now, g.pending_screenshot != '')
	movement := if forced := scripted { forced } else { input }
	g.physics_accum += dt
	mut steps := 0
	for g.physics_accum >= 1.0 / 60.0 && steps < 6 {
		g.player_state.update(1.0 / 60.0, movement, gameplay.World(g.world))
		g.physics_accum -= 1.0 / 60.0
		steps++
	}
	if steps == 6 { g.physics_accum = 0 }
	if g.player_state.pos.y < gameplay.min_y - 64 {
		g.player_state.pos.y = 200
		g.player_state.vel = gameplay.Vec3{}
	}
	g.update_accum += dt
	mut w := gameplay.World(g.world)
	for _ in 0 .. 4 {
		if g.update_accum < 0.05 { break }
		g.updates.tick(mut w)
		g.update_accum -= 0.05
	}
	if g.update_accum > 0.2 { g.update_accum = 0 }
	if !g.frozen {
		g.tick_accum += dt * 20
		whole := i64(g.tick_accum)
		g.ticks += whole
		g.tick_accum -= whole
	}
	eye := g.player_state.eye()
	g.camera.pos = render.Vec3d{ x: eye.x, y: eye.y, z: eye.z }
	g.camera.yaw = g.player_state.yaw
	g.camera.pitch = g.player_state.pitch
	g.camera.aspect = f32(width) / f32(if height > 0 { height } else { 1 })
	g.camera.fovy = f32((70 + if g.player_state.sprinting { 6 } else { 0 }) * math.pi / 180)
	g.camera.zfar = f32(math.max(160, g.radius * 32))
	f := g.camera.forward()
	g.hit = gameplay.raycast(gameplay.World(g.world), eye, gameplay.Vec3{ x: f.x, y: f.y, z: f.z }, if g.player_state.creative {
		8
	} else {
		5
	})
	g.break_cooldown = math.max(0, g.break_cooldown - dt)
	g.place_cooldown = math.max(0, g.place_cooldown - dt)
	if g.screen == .playing {
		if left && g.break_cooldown <= 0 {
			g.break_block()
			g.break_cooldown = 0.2
		}
		if right && g.place_cooldown <= 0 {
			g.place_block()
			g.place_cooldown = 0.2
		}
	}
	g.name_timer = math.max(0, g.name_timer - dt)
	g.toast_timer = math.max(0, g.toast_timer - dt)
	g.autosave_timer += dt
	if g.autosave_timer > 30 {
		g.autosave_timer = 0
		g.save_all(false) or { g.last_error = err.msg() }
	}
}
