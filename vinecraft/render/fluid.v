module render

import vinecraft.blocks
import vinecraft.models

fn fluid_height(b blocks.BlockInfo) f32 {
	return if b.fluid_depth >= 8 { f32(1) } else { f32(0.889) - 0.111 * b.fluid_depth }
}

fn fluid_same(reg &blocks.Registry, id blocks.BlockId, name string) bool {
	return id != 0 && reg.info(id).name == name
}

fn fluid_mesh(mut out MeshData, s MeshScratch, reg &blocks.Registry, model &models.BlockModels, id blocks.BlockId, x int, y int, z int, biome u8) {
	info := reg.info(id)
	lava := info.name.ends_with('lava')
	layer := if lava { model.lava_layer() } else { model.water_layer() }
	tint := if lava { u32(0xffffff) } else { model.tint_color(.water, biome) }
	top := if fluid_same(reg, s.ids[local_index(x, y + 1, z)], info.name) {
		f32(1)
	} else {
		fluid_height(info)
	}
	x0 := f32(x)
	x1 := x0 + 1
	z0 := f32(z)
	z1 := z0 + 1
	for d in 0 .. 6 {
		dir := dirs[d]
		nx := x + dir[0]
		ny := y + dir[1]
		nz := z + dir[2]
		i := local_index(nx, ny, nz)
		if s.opaque[i] { continue }
		nid := s.ids[i]
		mut bottom := f32(0)
		if fluid_same(reg, nid, info.name) {
			if d < 2 { continue }
			nh := if fluid_same(reg, s.ids[local_index(nx, ny + 1, nz)], info.name) {
				f32(1)
			} else {
				fluid_height(reg.info(nid))
			}
			if nh >= top { continue }
			bottom = nh
		}
		yb := f32(y) + bottom
		yt := f32(y) + top
		y0 := f32(y)
		points := match d {
			0 { [[x0, y0, z1]!, [x0, y0, z0]!, [x1, y0, z0]!, [x1, y0, z1]!]! }
			1 { [[x0, yt, z0]!, [x0, yt, z1]!, [x1, yt, z1]!, [x1, yt, z0]!]! }
			2 { [[x1, yt, z0]!, [x1, yb, z0]!, [x0, yb, z0]!, [x0, yt, z0]!]! }
			3 { [[x0, yt, z1]!, [x0, yb, z1]!, [x1, yb, z1]!, [x1, yt, z1]!]! }
			4 { [[x0, yt, z0]!, [x0, yb, z0]!, [x0, yb, z1]!, [x0, yt, z1]!]! }
			else { [[x1, yt, z1]!, [x1, yb, z1]!, [x1, yb, z0]!, [x1, yt, z0]!]! }
		}
		vt := if d >= 2 { 1 - top } else { f32(0) }
		vb := if d >= 2 { 1 - bottom } else { f32(1) }
		uvs := [[f32(0), vt]!, [f32(0), vb]!, [f32(1), vb]!, [f32(1), vt]!]!
		shade := if lava { f32(1) } else { dir_shade[d] }
		for k in 0 .. 4 {
			v := Vertex{
				x:     points[k][0]
				y:     points[k][1]
				z:     points[k][2]
				u:     uvs[k][0]
				v:     uvs[k][1]
				layer: layer
				r:     byte_color(f32((tint >> 16) & 255) / 255 * shade)
				g:     byte_color(f32((tint >> 8) & 255) / 255 * shade)
				b:     byte_color(f32(tint & 255) / 255 * shade)
				a:     if lava {
					u8(255)
				} else {
					u8(200)
				}
				sky:   if lava { u8(255) } else { byte_color(f32(s.sky[i]) / 15) }
				blk:   if lava {
					u8(255)
				} else {
					byte_color(f32(s.light[i]) / 15)
				}
			}
			if lava { out.opaque << v } else { out.translucent << v }
		}
	}
}
