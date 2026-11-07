module app

import runtime
import time
import vinecraft.blocks
import vinecraft.cli
import vinecraft.storage
import vinecraft.world
import vinecraft.worldgen

fn mixed_seed(value u64) i64 {
	mut x := value + u64(0x9e3779b97f4a7c15)
	x = (x ^ (x >> 30)) * u64(0xbf58476d1ce4e5b9)
	x = (x ^ (x >> 27)) * u64(0x94d049bb133111eb)
	return i64(x ^ (x >> 31))
}

// new_game opens the level and initializes all non-graphics gameplay state.
pub fn new_game(opt cli.Options) !&Game {
	seed := if s := opt.seed { s } else { mixed_seed(u64(time.now().unix()) ^ u64(0xdee951a7e)) }
	mut store := if opt.no_save {
		storage.open_read_only(opt.world_dir, seed)!
	} else {
		storage.open(opt.world_dir, seed)!
	}
	mut gen_value := worldgen.new_worldgen(store.info.seed)
	mut gen := &gen_value
	reg := blocks.new_registry()
	mut workers := opt.threads
	if workers <= 0 {
		workers = runtime.nr_cpus() - 1
		if workers < 2 { workers = 2 }
	}
	mut w := world.new_world(mut store, reg, gen, workers, opt.no_save)
	mut saved := ?storage.PlayerData(none)
	if data := store.load_player() { saved = data }
	player := place_player(mut store.info, gen, saved, opt)
	hotbar, selected := initial_hotbar(reg, saved)
	ticks := if t := opt.time { t } else { store.info.time }
	return &Game{
		options:          opt
		store:            store
		registry:         reg
		generator:        gen
		world:            w
		player_state:     player
		hotbar:           hotbar
		selected:         selected
		had_saved_player: saved != none
		radius:           if opt.render_distance < 2 {
			2
		} else if opt.render_distance > 32 {
			32
		} else {
			opt.render_distance
		}
		ticks:            ticks
		script:           new_script(opt.script)
	}
}

pub fn (mut g Game) shutdown() ! {
	mut failure := ''
	g.save_all(true) or { failure = err.msg() }
	g.world.shutdown() or { if failure == '' { failure = err.msg() } }
	g.store.close() or { if failure == '' { failure = err.msg() } }
	if failure != '' { return error(failure) }
}
