module world

import vinecraft.blocks
import vinecraft.storage
import vinecraft.worldgen
import sync
import math

pub struct DirtyChunk {
pub:
	x            int
	z            int
	section_mask u32
}

struct Job {
	pos      blocks.ChunkPos
	priority int
	seq      u64
}

struct Ready {
mut:
	pos       blocks.ChunkPos
	chunk     &blocks.Chunk = unsafe { nil }
	err       string
	from_disk bool
}

@[heap]
struct WorkerState {
mut:
	mutex       &sync.Mutex         = unsafe { nil }
	wake        &sync.Cond          = unsafe { nil }
	done        &sync.Cond          = unsafe { nil }
	store       &storage.LevelStore = unsafe { nil }
	reg         &blocks.Registry    = unsafe { nil }
	gen         &worldgen.WorldGen  = unsafe { nil }
	jobs        []Job
	ready       []Ready
	outstanding int
	stopping    bool
	generated   u64
	from_disk   u64
}

@[heap]
struct WriterState {
mut:
	mutex    &sync.Mutex         = unsafe { nil }
	wake     &sync.Cond          = unsafe { nil }
	done     &sync.Cond          = unsafe { nil }
	store    &storage.LevelStore = unsafe { nil }
	reg      &blocks.Registry    = unsafe { nil }
	queue    []blocks.ChunkSnapshot
	busy     bool
	stopping bool
	written  u64
	errors   []string
}

fn worker(mut s WorkerState) {
	for {
		s.mutex.lock()
		for s.jobs.len == 0 && !s.stopping { s.wake.wait() }
		if s.stopping {
			s.mutex.unlock()
			return
		}
		mut best := 0
		for i in 1 .. s.jobs.len {
			if s.jobs[i].priority < s.jobs[best].priority || (s.jobs[i].priority == s.jobs[best].priority && s.jobs[i].seq < s.jobs[best].seq) {
				best = i
			}
		}
		job := s.jobs[best]
		s.jobs.delete(best)
		s.mutex.unlock()
		mut result := Ready{ pos: job.pos }
		exists := s.store.has_chunk(job.pos) or {
			result.err = err.msg()
			false
		}
		if result.err == '' {
			if exists {
				chunk := s.store.load_chunk(job.pos, mut s.reg) or {
					result.err = err.msg()
					blocks.Chunk{}
				}
				if result.err == '' {
					result.chunk = &blocks.Chunk{ pos: chunk.pos, subs: chunk.subs, height: chunk.height, light_height: chunk.light_height, biome: chunk.biome, dirty: chunk.dirty }
					result.from_disk = true
				}
			} else {
				result.chunk = s.gen.generate(job.pos.x, job.pos.z, s.reg)
			}
		}
		s.mutex.lock()
		if result.err == '' {
			if result.from_disk { s.from_disk++ } else { s.generated++ }
		}
		s.ready << result
		s.outstanding--
		s.done.broadcast()
		s.mutex.unlock()
	}
}

fn writer(mut s WriterState) {
	for {
		s.mutex.lock()
		for s.queue.len == 0 && !s.stopping { s.wake.wait() }
		if s.queue.len == 0 && s.stopping {
			s.mutex.unlock()
			return
		}
		snap := s.queue[0]
		s.queue.delete(0)
		s.busy = true
		s.mutex.unlock()
		mut failure := ''
		s.store.save_chunk(snap, mut s.reg) or { failure = err.msg() }
		s.mutex.lock()
		if failure != '' {
			s.errors << 'failed to write chunk (${snap.pos.x},${snap.pos.z}): ${failure}'
		}
		s.written++
		s.busy = false
		s.done.broadcast()
		s.mutex.unlock()
	}
}

@[heap]
pub struct World {
mut:
	reg            &blocks.Registry = unsafe { nil }
	workers        &WorkerState     = unsafe { nil }
	writer         &WriterState     = unsafe { nil }
	threads        []thread
	writer_thread  thread
	worker_count   int
	no_save        bool
	stopped        bool
	sequence       u64
	chunks         map[string]&blocks.Chunk
	inflight       map[string]bool
	dirty          map[string]u32
	offsets        []blocks.ChunkPos
	offsets_radius int = -1
	frame          int
	errors         []string
}

pub fn new_world(mut store storage.LevelStore, reg &blocks.Registry, gen &worldgen.WorldGen, workers int, no_save bool) &World {
	wm := sync.new_mutex()
	writer_mutex := sync.new_mutex()
	mut state := &WorkerState{ mutex: wm, wake: sync.new_cond(wm), done: sync.new_cond(wm), store: store, reg: reg, gen: gen }
	mut ws := &WriterState{ mutex: writer_mutex, wake: sync.new_cond(writer_mutex), done: sync.new_cond(writer_mutex), store: store, reg: reg }
	mut w := &World{
		reg:          reg
		workers:      state
		writer:       ws
		worker_count: if workers > 0 {
			workers
		} else {
			1
		}
		no_save:      no_save
	}
	for _ in 0 .. w.worker_count { w.threads << spawn worker(mut state) }
	w.writer_thread = spawn writer(mut ws)
	return w
}

fn key(x int, z int) string { return '${x},${z}' }

fn floor_div16(x int) int { return if x >= 0 { x / 16 } else { (x - 15) / 16 } }

fn local16(x int) int { return x - floor_div16(x) * 16 }

pub fn (w &World) column_loaded(cx int, cz int) bool { return key(cx, cz) in w.chunks }

pub fn (w &World) get_chunk(cx int, cz int) ?&blocks.Chunk {
	return w.chunks[key(cx, cz)] or { return none }
}

pub fn (w &World) get_block(x int, y int, z int) blocks.BlockId {
	if y < blocks.min_y || y >= blocks.max_y { return 0 }
	c := w.get_chunk(floor_div16(x), floor_div16(z)) or { return 0 }
	return c.get(local16(x), y, local16(z))
}

pub fn (w &World) column_height(x int, z int) int {
	c := w.get_chunk(floor_div16(x), floor_div16(z)) or { return blocks.min_y }
	return int(c.height[blocks.col_index(local16(x), local16(z))])
}

pub fn (w &World) block_info(id blocks.BlockId) blocks.BlockInfo { return w.reg.info(id) }

pub fn (mut w World) block_id(name string) blocks.BlockId { return w.reg.find(name) }

pub fn (mut w World) fluid_state(id blocks.BlockId, depth int) blocks.BlockId {
	info := w.reg.info(id)
	mut states := info.states.clone()
	mut found := false
	for i in 0 .. states.len {
		if states[i].key == 'liquid_depth' {
			states[i] = blocks.StateEntry{ key: 'liquid_depth', value: blocks.state_int_value(depth) }
			found = true
			break
		}
	}
	if !found {
		states << blocks.StateEntry{ key: 'liquid_depth', value: blocks.state_int_value(depth) }
	}
	return w.reg.lookup_or_register(info.name, states)
}

fn (mut w World) mark_dirty(x int, z int, mask u32) {
	k := key(x, z)
	if k in w.chunks { w.dirty[k] = w.dirty[k] | mask }
}

pub fn (mut w World) set_block(x int, y int, z int, id blocks.BlockId) bool {
	if y < blocks.min_y || y >= blocks.max_y { return false }
	cx := floor_div16(x)
	cz := floor_div16(z)
	mut c := w.chunks[key(cx, cz)] or { return false }
	lx := local16(x)
	lz := local16(z)
	old := c.get(lx, y, lz)
	if !c.set(lx, y, lz, id) { return false }
	c.dirty = true
	index := blocks.col_index(lx, lz)
	old_h := c.height[index]
	old_lh := c.light_height[index]
	oi := w.reg.info(old)
	ni := w.reg.info(id)
	sky := blocks.bf_opaque | blocks.bf_liquid | blocks.bf_leaves
	if (oi.flags & sky != 0) != (ni.flags & sky != 0) || oi.opaque() != ni.opaque() {
		c.recompute_column_height(lx, lz, w.reg)
	}
	changed := c.height[index] != old_h || c.light_height[index] != old_lh
	wide := changed || oi.emit != ni.emit || oi.opaque() != ni.opaque()
	sec := (y >> 4) - blocks.min_sub
	ly := y & 15
	for dz := if lz == 0 || wide { -1 } else { 0 }; dz <= if lz == 15 || wide { 1 } else { 0 }; dz++ {
		for dx := if lx == 0 || wide { -1 } else { 0 }; dx <= if lx == 15 || wide { 1 } else { 0 }; dx++ {
			mut mask := u32(0)
			for ds := if ly == 0 || wide { -1 } else { 0 }; ds <= if ly == 15 || wide {
				1
			} else {
				0
			}; ds++ {
				s := sec + ds
				if s >= 0 && s < blocks.num_subs { mask |= u32(1) << u32(s) }
			}
			w.mark_dirty(cx + dx, cz + dz, if changed { u32(0xffffff) } else { mask })
		}
	}
	return true
}

pub fn (w &World) neighbourhood_loaded(cx int, cz int) bool {
	for dz in -1 .. 2 {
		for dx in -1 .. 2 { if !w.column_loaded(cx + dx, cz + dz) { return false } }
	}
	return true
}

pub fn (w &World) all_loaded_around(cx int, cz int, radius int) bool {
	for dz in -radius .. radius + 1 {
		for dx in -radius .. radius + 1 {
			if dx * dx + dz * dz <= radius * radius && !w.column_loaded(cx + dx, cz + dz) {
				return false
			}
		}
	}
	return true
}

pub fn (w &World) snapshot3x3(cx int, cz int) ?[9]blocks.ChunkSnapshot {
	mut out := [9]blocks.ChunkSnapshot{}
	for dz in -1 .. 2 {
		for dx in -1 .. 2 {
			c := w.get_chunk(cx + dx, cz + dz) or { return none }
			out[(dz + 1) * 3 + dx + 1] = c.snapshot()
		}
	}
	return out
}

pub fn (mut w World) take_dirty() []DirtyChunk {
	mut out := []DirtyChunk{cap: w.dirty.len}
	for k, mask in w.dirty {
		if c := w.chunks[k] { out << DirtyChunk{ x: c.pos.x, z: c.pos.z, section_mask: mask } }
	}
	w.dirty.clear()
	return out
}

fn (mut w World) enqueue(s blocks.ChunkSnapshot) {
	if w.no_save { return }
	w.writer.mutex.lock()
	w.writer.queue << s
	w.writer.wake.signal()
	w.writer.mutex.unlock()
}

pub fn (mut w World) save_dirty(wait bool) ! {
	if !w.no_save {
		for _, mut c in w.chunks {
			if c.dirty {
				w.enqueue(c.snapshot())
				c.dirty = false
			}
		}
	}
	if wait {
		w.writer.mutex.lock()
		for w.writer.queue.len > 0 || w.writer.busy { w.writer.done.wait() }
		errors := w.writer.errors.clone()
		w.writer.errors.clear()
		w.writer.mutex.unlock()
		if errors.len > 0 { return error(errors.join('\n')) }
	}
}

fn (mut w World) unload_far(cx int, cz int, radius int) {
	keep := radius + 2
	mut remove := []string{}
	for k, c in w.chunks {
		dx := c.pos.x - cx
		dz := c.pos.z - cz
		if dx * dx + dz * dz > keep * keep {
			if c.dirty && !w.no_save { w.enqueue(c.snapshot()) }
			remove << k
		}
	}
	for k in remove {
		w.chunks.delete(k)
		w.dirty.delete(k)
	}
}

pub fn (mut w World) update(px f64, pz f64, radius int) {
	if w.stopped { return }
	w.frame++
	cx := floor_div16(int(math.floor(px)))
	cz := floor_div16(int(math.floor(pz)))
	load_r := radius + 1
	w.workers.mutex.lock()
	done := w.workers.ready.clone()
	w.workers.ready.clear()
	w.workers.mutex.unlock()
	for r in done {
		k := key(r.pos.x, r.pos.z)
		w.inflight.delete(k)
		if r.err != '' {
			w.errors << 'failed to load chunk (${r.pos.x},${r.pos.z}): ${r.err}'
			continue
		}
		dx := r.pos.x - cx
		dz := r.pos.z - cz
		if dx * dx + dz * dz > (load_r + 1) * (load_r + 1) { continue }
		w.chunks[k] = r.chunk
		w.dirty[k] = w.dirty[k] | u32(0xffffff)
	}
	if w.frame % 20 == 0 { w.unload_far(cx, cz, load_r) }
	if w.offsets_radius != load_r {
		w.offsets.clear()
		for dz in -load_r .. load_r + 1 {
			for dx in -load_r .. load_r + 1 {
				if dx * dx + dz * dz <= load_r * load_r {
					w.offsets << blocks.ChunkPos{ x: dx, z: dz }
				}
			}
		}
		w.offsets.sort_with_compare(fn (a &blocks.ChunkPos, b &blocks.ChunkPos) int {
			return (a.x * a.x + a.z * a.z) - (b.x * b.x + b.z * b.z)
		})
		w.offsets_radius = load_r
	}
	for p in w.offsets {
		if w.inflight.len >= w.worker_count * 2 + 2 { break }
		x := cx + p.x
		z := cz + p.z
		k := key(x, z)
		if k in w.chunks || k in w.inflight { continue }
		w.inflight[k] = true
		w.workers.mutex.lock()
		w.workers.outstanding++
		w.workers.jobs << Job{ pos: blocks.ChunkPos{ x: x, z: z }, priority: p.x * p.x + p.z * p.z, seq: w.sequence }
		w.sequence++
		w.workers.wake.signal()
		w.workers.mutex.unlock()
	}
}

pub fn (mut w World) take_errors() []string {
	out := w.errors.clone()
	w.errors.clear()
	return out
}

pub fn (w &World) loaded_count() int { return w.chunks.len }

pub fn (w &World) inflight_count() int { return w.inflight.len }

pub fn (w &World) writer_queue() int {
	mut s := w.writer
	s.mutex.lock()
	n := s.queue.len + if s.busy { 1 } else { 0 }
	s.mutex.unlock()
	return n
}

pub fn (w &World) writer_written() u64 {
	mut s := w.writer
	s.mutex.lock()
	n := s.written
	s.mutex.unlock()
	return n
}

pub fn (w &World) chunks_generated() u64 {
	mut s := w.workers
	s.mutex.lock()
	n := s.generated
	s.mutex.unlock()
	return n
}

pub fn (w &World) chunks_loaded_from_disk() u64 {
	mut s := w.workers
	s.mutex.lock()
	n := s.from_disk
	s.mutex.unlock()
	return n
}

pub fn (mut w World) shutdown() ! {
	if w.stopped { return }
	w.stopped = true
	w.workers.mutex.lock()
	for w.workers.outstanding > 0 { w.workers.done.wait() }
	w.workers.stopping = true
	w.workers.wake.broadcast()
	w.workers.mutex.unlock()
	for t in w.threads { t.wait() }
	mut failure := ''
	w.save_dirty(true) or { failure = err.msg() }
	w.writer.mutex.lock()
	w.writer.stopping = true
	w.writer.wake.signal()
	w.writer.mutex.unlock()
	w.writer_thread.wait()
	if failure != '' { return error(failure) }
}
