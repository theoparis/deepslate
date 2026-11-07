module render

import vinecraft.blocks
import vinecraft.models
import math

const mesh_radius = 12
const mesh_width = 40
const mesh_volume = 64000
const dirs = [[0, -1, 0]!, [0, 1, 0]!, [0, 0, -1]!, [0, 0, 1]!, [-1, 0, 0]!, [1, 0, 0]!]!
const dir_shade = [f32(0.5), 1, 0.8, 0.8, 0.6, 0.6]!
const ao_values = [f32(0.55), 0.72, 0.87, 1]!

pub struct Vertex {
pub mut:
	x     f32
	y     f32
	z     f32
	u     f32
	v     f32
	layer f32
	r     u8
	g     u8
	b     u8
	a     u8
	sky   u8
	blk   u8
	flags u8
	pad   u8
}

pub struct MeshData {
pub mut:
	opaque      []Vertex
	translucent []Vertex
}

pub fn (m MeshData) quads() int { return (m.opaque.len + m.translucent.len) / 4 }

pub struct MeshInput {
pub:
	chunks  [9]blocks.ChunkSnapshot
	section int
}

struct MeshScratch {
mut:
	ids    []blocks.BlockId = []blocks.BlockId{len: mesh_volume}
	opaque []bool           = []bool{len: mesh_volume}
	sky    []u8             = []u8{len: mesh_volume}
	light  []u8             = []u8{len: mesh_volume}
}

fn mesh_index(x int, y int, z int) int { return (y * mesh_width + z) * mesh_width + x }

fn local_index(x int, y int, z int) int {
	return mesh_index(x + mesh_radius, y + mesh_radius, z + mesh_radius)
}

fn byte_color(v f32) u8 { return u8(math.clamp(v, f32(0), f32(1)) * 255 + 0.5) }

fn flood(mut levels []u8, opaque []bool, mut queue []int) {
	mut head := 0
	for head < queue.len {
		i := queue[head]
		head++
		l := levels[i]
		if l <= 1 { continue }
		x := i % mesh_width
		z := i / mesh_width % mesh_width
		y := i / (mesh_width * mesh_width)
		for d in dirs {
			nx := x + d[0]
			ny := y + d[1]
			nz := z + d[2]
			if nx < 0 || ny < 0 || nz < 0 || nx >= mesh_width || ny >= mesh_width || nz >= mesh_width {
				continue
			}
			j := mesh_index(nx, ny, nz)
			if opaque[j] || levels[j] >= l - 1 { continue }
			levels[j] = l - 1
			queue << j
		}
	}
}

fn coord_hash(seed u64, x int, y int, z int) u64 {
	mut h := mix64(seed ^ u64(0xa0761d6478bd642f))
	h = mix64(h ^ u64(i64(x)) * u64(0xe7037ed1a0b428db))
	h = mix64(h ^ u64(i64(y)) * u64(0x8ebc6af09c88c6e3))
	return mix64(h ^ u64(i64(z)) * u64(0x589965cc75374cc3))
}

// InfoCache memoises Registry.info for one mesh_section call. The registry
// serialises every lookup behind a mutex and returns a large struct by value;
// the mesher looks up every cell of a padded volume, so uncached lookups from
// all mesh workers contend on that one lock.
struct InfoCache {
	reg &blocks.Registry
mut:
	infos []&blocks.BlockInfo
}

fn (mut c InfoCache) get(id blocks.BlockId) &blocks.BlockInfo {
	i := int(id)
	if i >= c.infos.len {
		mut grow := []&blocks.BlockInfo{len: int(math.max(i + 1, c.reg.count())), init: unsafe { nil }}
		for k, p in c.infos { grow[k] = p }
		c.infos = grow
	}
	if c.infos[i] == unsafe { nil } {
		info := c.reg.info(id)
		c.infos[i] = &info
	}
	return c.infos[i]
}

pub fn mesh_section(input &MeshInput, registry &blocks.Registry, mut model models.BlockModels) MeshData {
	mut s := MeshScratch{}
	mut queue := []int{}
	mut seeds := []int{}
	center := input.chunks[4]
	mut cache := InfoCache{ reg: registry }
	oy := (input.section + blocks.min_sub) * 16
	for zi in 0 .. mesh_width {
		lzw := zi - mesh_radius
		cdz := if lzw < 0 {
			-1
		} else if lzw > 15 {
			1
		} else {
			0
		}
		lz := lzw - cdz * 16
		for xi in 0 .. mesh_width {
			lxw := xi - mesh_radius
			cdx := if lxw < 0 {
				-1
			} else if lxw > 15 {
				1
			} else {
				0
			}
			lx := lxw - cdx * 16
			ci := (cdz + 1) * 3 + cdx + 1
			col := blocks.col_index(lx, lz)
			h := int(input.chunks[ci].height[col])
			lh := int(input.chunks[ci].light_height[col])
			for yi in 0 .. mesh_width {
				wy := oy - mesh_radius + yi
				id := input.chunks[ci].get(lx, wy, lz)
				index := mesh_index(xi, yi, zi)
				info := cache.get(id)
				s.ids[index] = id
				s.opaque[index] = info.opaque()
				if info.opaque() { continue }
				sk := if wy >= blocks.max_y || wy >= h {
					15
				} else if wy >= lh {
					int(math.max(15 - (h - wy), 6))
				} else {
					0
				}
				if sk != 0 {
					s.sky[index] = u8(sk)
					queue << index
				}
				if info.emit != 0 {
					s.light[index] = info.emit
					seeds << index
				}
			}
		}
	}
	flood(mut s.sky, s.opaque, mut queue)
	if seeds.len > 0 { flood(mut s.light, s.opaque, mut seeds) }
	mut result := MeshData{}
	for y in 0 .. 16 {
		for z in 0 .. 16 {
			for x in 0 .. 16 {
				id := s.ids[local_index(x, y, z)]
				if id == 0 { continue }
				info := cache.get(id)
				mut surrounded := info.opaque()
				for d in dirs {
					if !s.opaque[local_index(x + d[0], y + d[1], z + d[2])] {
						surrounded = false
						break
					}
				}
				if surrounded { continue }
				biome := center.biome[blocks.col_index(x, z)]
				if info.liquid() {
					fluid_mesh(mut result, s, registry, model, id, x, y, z, biome)
					continue
				}
				model.bake(id)
				baked := model.baked(id) or { continue }
				translucent := info.flags & blocks.bf_translucent != 0
				emissive := info.flags & blocks.bf_emissive != 0
				tint := if info.tint != .none {
					model.tint_color(info.tint, biome)
				} else {
					u32(0xffffff)
				}
				quads := baked.pick(coord_hash(0xa17, center.pos.x * 16 + x, oy + y, center.pos.z * 16 + z))
				for q in quads {
					if q.cull >= 0 {
						d := dirs[int(q.cull)]
						i := local_index(x + d[0], y + d[1], z + d[2])
						if s.opaque[i] || (translucent && s.ids[i] == id) || (info.flags & blocks.bf_cutout != 0 && info.flags & (blocks.bf_leaves | blocks.bf_plant) == 0 && s.ids[i] == id) {
							continue
						}
					}
					color := if q.tint >= 0 && info.tint != .none { tint } else { u32(0xffffff) }
					shade := if q.shade { dir_shade[int(q.dir)] } else { f32(1) }
					for v in 0 .. 4 {
						mut ao := f32(1)
						mut sk := f32(0)
						mut bk := f32(0)
						if q.boundary {
							axis := [1, 1, 2, 2, 0, 0]![int(q.dir)]
							sign := if q.dir % 2 != 0 { 1 } else { -1 }
							t1 := (axis + 1) % 3
							t2 := (axis + 2) % 3
							s1 := if q.pos[v][t1] > 0.5 { 1 } else { -1 }
							s2 := if q.pos[v][t2] > 0.5 { 1 } else { -1 }
							mut base := [x, y, z]!
							base[axis] += sign
							mut cells := [4][3]int{}
							for k in 0 .. 4 { cells[k] = base }
							cells[1][t1] += s1
							cells[2][t2] += s2
							cells[3][t1] += s1
							cells[3][t2] += s2
							o1 := s.opaque[local_index(cells[1][0], cells[1][1], cells[1][2])]
							o2 := s.opaque[local_index(cells[2][0], cells[2][1], cells[2][2])]
							o3 := s.opaque[local_index(cells[3][0], cells[3][1], cells[3][2])]
							count := (if o1 { 1 } else { 0 }) + (if o2 { 1 } else { 0 }) + (if o3 {
								1
							} else {
								0
							})
							ao = ao_values[if o1 && o2 { 0 } else { 3 - count }]
							mut n := 0
							for c in cells {
								i := local_index(c[0], c[1], c[2])
								if s.opaque[i] { continue }
								sk += f32(s.sky[i])
								bk += f32(s.light[i])
								n++
							}
							if n > 0 {
								sk /= f32(n)
								bk /= f32(n)
							}
						} else {
							i := local_index(x, y, z)
							sk = f32(s.sky[i])
							bk = f32(s.light[i])
						}
						f := shade * ao
						vert := Vertex{
							x:     f32(x) + q.pos[v][0]
							y:     f32(y) + q.pos[v][1]
							z:     f32(z) + q.pos[v][2]
							u:     q.uv[v][0]
							v:     q.uv[v][1]
							layer: f32(q.layer)
							r:     byte_color(f32((color >> 16) & 255) / 255 * f)
							g:     byte_color(f32((color >> 8) & 255) / 255 * f)
							b:     byte_color(f32(color & 255) / 255 * f)
							a:     255
							sky:   if emissive {
								u8(255)
							} else {
								byte_color(sk / 15)
							}
							blk:   if emissive { u8(255) } else { byte_color(bk / 15) }
						}
						if translucent { result.translucent << vert } else { result.opaque << vert }
					}
				}
			}
		}
	}
	return result
}
