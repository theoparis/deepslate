module render

import vinecraft.world
import vinecraft.models
import vinecraft.blocks
import sokol.gfx
import sync
import math
import time

struct MeshJob {
	key      string
	input    MeshInput
	priority int
}

struct MeshResult {
	key  string
	data MeshData
}

@[heap]
struct MeshWorkers {
mut:
	mutex    &sync.Mutex         = unsafe { nil }
	wake     &sync.Cond          = unsafe { nil }
	registry &blocks.Registry    = unsafe { nil }
	model    &models.BlockModels = unsafe { nil }
	jobs     []MeshJob
	results  []MeshResult
	active   int
	stopping bool
}

fn meshing_worker(mut state MeshWorkers) {
	for {
		state.mutex.lock()
		for state.jobs.len == 0 && !state.stopping { state.wake.wait() }
		if state.stopping {
			state.mutex.unlock()
			return
		}
		mut best := 0
		for i in 1 .. state.jobs.len {
			if state.jobs[i].priority < state.jobs[best].priority { best = i }
		}
		job := state.jobs[best]
		state.jobs.delete(best)
		state.mutex.unlock()
		data := mesh_section(&job.input, state.registry, mut state.model)
		state.mutex.lock()
		state.results << MeshResult{ key: job.key, data: data }
		state.active--
		state.mutex.unlock()
	}
}

struct RenderSection {
mut:
	x           int
	y           int
	z           int
	opaque      GpuMesh
	translucent GpuMesh
	in_flight   bool
}

struct RenderColumn {
	x        int
	z        int
	distance int
	key      string
}

pub struct RenderStats {
pub mut:
	sections  int
	drawn     int
	quads     int
	pending   int
	in_flight int
	meshed    u64
}

@[heap]
pub struct WorldRenderer {
pub mut:
	stats RenderStats
mut:
	gpu          WorldGpu
	model        &models.BlockModels = unsafe { nil }
	workers      &MeshWorkers        = unsafe { nil }
	threads      []thread
	worker_count int
	sections     map[string]RenderSection
	pending      map[string]u32
	positions    map[string]blocks.ChunkPos
	frame        int
	layers       int
	backlog      bool
}

fn column_key(x int, z int) string { return '${x},${z}' }

fn section_key(x int, y int, z int) string { return '${x},${y},${z}' }

pub fn new_world_renderer(mut model models.BlockModels, registry &blocks.Registry, workers int) &WorldRenderer {
	count := if workers > 0 { workers } else { 1 }
	mutex := sync.new_mutex()
	mut state := &MeshWorkers{ mutex: mutex, wake: sync.new_cond(mutex), registry: registry, model: &model }
	anim := model.copy_anim()
	pixels := model.copy_layers(0)
	layers := anim.len / 2
	mut r := &WorldRenderer{ gpu: new_world_gpu(model.tile_size(), layers, pixels, anim), model: &model, workers: state, worker_count: count, layers: layers }
	for _ in 0 .. count { r.threads << spawn meshing_worker(mut state) }
	return r
}

pub fn (mut r WorldRenderer) update(mut w world.World, cam Camera, radius int) ! {
	r.frame++
	count := r.model.layer_count()
	if count != r.layers {
		anim := r.model.copy_anim()
		pixels := r.model.copy_layers(0)
		r.gpu.free()
		r.gpu = new_world_gpu(r.model.tile_size(), count, pixels, anim)
		r.layers = count
	}
	for d in w.take_dirty() {
		key := column_key(d.x, d.z)
		r.pending[key] = (r.pending[key] or { u32(0) }) | d.section_mask
		r.positions[key] = blocks.ChunkPos{ x: d.x, z: d.z }
	}
	pcx := int(math.floor(cam.pos.x / 16))
	pcz := int(math.floor(cam.pos.z / 16))
	r.workers.mutex.lock()
	mut finished := r.workers.results.clone()
	r.workers.results.clear()
	r.workers.mutex.unlock()
	start := time.now().unix_nano()
	mut n := 0
	for result in finished {
		if mut sec := r.sections[result.key] {
			sec.in_flight = false
			opaque := upload_mesh(result.data.opaque)!
			translucent := upload_mesh(result.data.translucent) or {
				opaque.free()
				return err
			}
			sec.opaque.free()
			sec.translucent.free()
			sec.opaque = opaque
			sec.translucent = translucent
			r.sections[result.key] = sec
			r.stats.meshed++
		}
		n++
		if time.now().unix_nano() - start > 4000000 { break }
	}
	if n < finished.len {
		r.workers.mutex.lock()
		r.workers.results.prepend(finished[n..])
		r.workers.mutex.unlock()
	}
	mut cols := []RenderColumn{}
	for key, _ in r.pending {
		pos := r.positions[key]
		dx := pos.x - pcx
		dz := pos.z - pcz
		cols << RenderColumn{ x: pos.x, z: pos.z, distance: dx * dx + dz * dz, key: key }
	}
	cols.sort(a.distance < b.distance)
	r.backlog = false
	mut submitted := 0
	for col in cols {
		if col.distance > radius * radius + 2 { continue }
		chunk := w.get_chunk(col.x, col.z) or { continue }
		if !w.neighbourhood_loaded(col.x, col.z) { continue }
		mut mask := r.pending[col.key]
		for si in 0 .. blocks.num_subs {
			bit := u32(1) << si
			if mask & bit == 0 { continue }
			skey := section_key(col.x, si, col.z)
			mut sec := r.sections[skey] or { RenderSection{ x: col.x, y: si, z: col.z } }
			if sec.in_flight { continue }
			if chunk.subs[si].len == 0 {
				sec.opaque.free()
				sec.translucent.free()
				sec.opaque = GpuMesh{}
				sec.translucent = GpuMesh{}
				r.sections[skey] = sec
				mask &= ~bit
				continue
			}
			r.workers.mutex.lock()
			active := r.workers.active
			r.workers.mutex.unlock()
			if active >= r.worker_count * 2 + 2 || submitted >= 64 {
				r.backlog = true
				break
			}
			snapshots := w.snapshot3x3(col.x, col.z) or { break }
			sec.in_flight = true
			r.sections[skey] = sec
			mask &= ~bit
			r.workers.mutex.lock()
			r.workers.jobs << MeshJob{ key: skey, input: MeshInput{ chunks: snapshots, section: si }, priority: col.distance }
			r.workers.active++
			r.workers.wake.signal()
			r.workers.mutex.unlock()
			submitted++
		}
		if mask == 0 {
			r.pending.delete(col.key)
			r.positions.delete(col.key)
		} else {
			r.pending[col.key] = mask
		}
	}
	if r.frame % 30 == 0 {
		keep := radius + 3
		for key, sec in r.sections {
			dx := sec.x - pcx
			dz := sec.z - pcz
			if !sec.in_flight && (dx * dx + dz * dz > keep * keep || !w.column_loaded(sec.x, sec.z)) {
				sec.opaque.free()
				sec.translucent.free()
				r.sections.delete(key)
			}
		}
		for key, pos in r.positions {
			if !w.column_loaded(pos.x, pos.z) {
				r.positions.delete(key)
				r.pending.delete(key)
			}
		}
	}
	r.workers.mutex.lock()
	active := r.workers.active
	r.workers.mutex.unlock()
	r.stats.sections = r.sections.len
	r.stats.pending = r.pending.len
	r.stats.in_flight = active
}

struct DrawItem {
	mesh     GpuMesh
	offset   Vec3
	distance f32
}

pub fn (mut r WorldRenderer) draw(cam Camera, sky SkyState, translucent bool) {
	fr := cam.frustum()
	mut items := []DrawItem{}
	for _, sec in r.sections {
		mesh := if translucent { sec.translucent } else { sec.opaque }
		if mesh.count == 0 { continue }
		off := Vec3{f32(sec.x * 16 - cam.pos.x), f32((sec.y + blocks.min_sub) * 16 - cam.pos.y), f32(sec.z * 16 - cam.pos.z)}
		if !fr.intersects(off, Vec3{off.x + 16, off.y + 16, off.z + 16}) { continue }
		d := (off.x + 8) * (off.x + 8) + (off.y + 8) * (off.y + 8) + (off.z + 8) * (off.z + 8)
		items << DrawItem{ mesh: mesh, offset: off, distance: d }
	}
	if translucent { items.sort(a.distance > b.distance) }
	mut quads := 0
	for item in items {
		r.gpu.draw(item.mesh, cam, sky, item.offset, translucent)
		quads += item.mesh.count / 6
	}
	if !translucent {
		r.stats.drawn = items.len
		r.stats.quads = quads
	}
}

pub fn (r &WorldRenderer) atlas_image() gfx.Image { return r.gpu.atlas_image() }

pub fn (mut r WorldRenderer) idle() bool {
	r.workers.mutex.lock()
	busy := r.workers.active > 0 || r.workers.results.len > 0
	r.workers.mutex.unlock()
	return !busy && !r.backlog
}

pub fn (mut r WorldRenderer) free() {
	r.workers.mutex.lock()
	r.workers.stopping = true
	r.workers.wake.broadcast()
	r.workers.mutex.unlock()
	for t in r.threads { t.wait() }
	for _, sec in r.sections {
		sec.opaque.free()
		sec.translucent.free()
	}
	r.gpu.free()
}
