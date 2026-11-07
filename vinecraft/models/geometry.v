module models

import math

const dir_vec = [[f32(0), -1, 0]!, [f32(0), 1, 0]!, [f32(0), 0, -1]!, [f32(0), 0, 1]!,
	[f32(-1), 0, 0]!, [f32(1), 0, 0]!]!
const face_verts = [
	[[0, 0, 1, 0]!, [0, 0, 0, 1]!, [1, 0, 0, 2]!, [1, 0, 1, 3]!]!,
	[[0, 1, 0, 0]!, [0, 1, 1, 1]!, [1, 1, 1, 2]!, [1, 1, 0, 3]!]!,
	[[1, 1, 0, 0]!, [1, 0, 0, 1]!, [0, 0, 0, 2]!, [0, 1, 0, 3]!]!,
	[[0, 1, 1, 0]!, [0, 0, 1, 1]!, [1, 0, 1, 2]!, [1, 1, 1, 3]!]!,
	[[0, 1, 0, 0]!, [0, 0, 0, 1]!, [0, 0, 1, 2]!, [0, 1, 1, 3]!]!,
	[[1, 1, 1, 0]!, [1, 0, 1, 1]!, [1, 0, 0, 2]!, [1, 1, 0, 3]!]!,
]!

fn rotate(p [3]f32, axis int, degrees f32, clockwise bool) [3]f32 {
	r := degrees * f32(math.pi / 180.0)
	c := f32(math.cos(r))
	s := f32(math.sin(r))
	mut v := [p[0], p[1], p[2]]!
	match axis {
		0 {
			v[1] = p[1] * c - p[2] * s
			v[2] = p[1] * s + p[2] * c
		}
		1 {
			if clockwise {
				v[0] = p[0] * c - p[2] * s
				v[2] = p[0] * s + p[2] * c
			} else {
				v[0] = p[0] * c + p[2] * s
				v[2] = -p[0] * s + p[2] * c
			}
		}
		else {
			v[0] = p[0] * c - p[1] * s
			v[1] = p[0] * s + p[1] * c
		}
	}
	return v
}

fn rotate_dir(d int, x int, y int) int {
	mut v := dir_vec[d]
	if x != 0 { v = rotate(v, 0, f32(x), false) }
	if y != 0 { v = rotate(v, 1, f32(y), true) }
	mut best := 1
	mut bd := f32(-2)
	for i in 0 .. 6 {
		dot := v[0] * dir_vec[i][0] + v[1] * dir_vec[i][1] + v[2] * dir_vec[i][2]
		if dot > bd {
			bd = dot
			best = i
		}
	}
	return best
}

fn (mut bm BlockModels) bake_model(ref ModelRef, mut out BakedBlock) {
	model := bm.load_model(ref.name, 0) or {
		out.missing = true
		return
	}
	if !model.has_final {
		out.missing = true
		return
	}
	for el in model.final_elements {
		for d in 0 .. 6 {
			f := el.faces[d]
			if !f.present { continue }
			mut tex := f.texture
			for _ in 0 .. 16 {
				if !tex.starts_with('#') { break }
				key := tex[1..]
				if key !in model.all_textures {
					tex = ''
					break
				}
				tex = model.all_textures[key]
			}
			layer := if tex == '' || tex.starts_with('#') { u16(0) } else { bm.add_layer(tex) }
			mut q := BakedQuad{ layer: layer, cull: i8(f.cull), tint: i8(f.tint), shade: el.shade, dir: i8(d) }
			a := el.from
			b := el.to
			u := if f.has_uv {
				f.uv
			} else {
				match d {
					0 { [a[0], 16 - b[2], b[0], 16 - a[2]]! }
					1 { [a[0], a[2], b[0], b[2]]! }
					2 { [16 - b[0], 16 - b[1], 16 - a[0], 16 - a[1]]! }
					3 { [a[0], 16 - b[1], b[0], 16 - a[1]]! }
					4 { [a[2], 16 - b[1], b[2], 16 - a[1]]! }
					else { [16 - b[2], 16 - b[1], 16 - a[2], 16 - a[1]]! }
				}
			}
			corners := [[u[0] / 16, u[1] / 16]!, [u[0] / 16, u[3] / 16]!, [u[2] / 16, u[3] / 16]!,
				[u[2] / 16, u[1] / 16]!]!
			rot := ((f.rotation % 360) + 360) % 360 / 90
			for v in 0 .. 4 {
				fv := face_verts[d][v]
				mut p := [if fv[0] != 0 { b[0] } else { a[0] }, if fv[1] != 0 { b[1] } else { a[1] },
					if fv[2] != 0 { b[2] } else { a[2] }]!
				if el.has_rot && el.angle != 0 {
					mut rel := [p[0] - el.origin[0], p[1] - el.origin[1], p[2] - el.origin[2]]!
					rel = rotate(rel, el.axis, el.angle, false)
					if el.rescale {
						k := f32(1.0 / math.cos(math.abs(el.angle) * math.pi / 180))
						for axis in 0 .. 3 { if axis != el.axis { rel[axis] *= k } }
					}
					for axis in 0 .. 3 { p[axis] = rel[axis] + el.origin[axis] }
				}
				for axis in 0 .. 3 { p[axis] /= 16 }
				if ref.x != 0 || ref.y != 0 {
					for axis in 0 .. 3 { p[axis] -= 0.5 }
					if ref.x != 0 { p = rotate(p, 0, f32(ref.x), false) }
					if ref.y != 0 { p = rotate(p, 1, f32(ref.y), true) }
					for axis in 0 .. 3 { p[axis] += 0.5 }
				}
				q.pos[v] = p
				q.uv[v] = corners[(fv[3] + rot) % 4]
			}
			if ref.x != 0 || ref.y != 0 {
				q.dir = i8(rotate_dir(d, ref.x, ref.y))
				if q.cull >= 0 { q.cull = i8(rotate_dir(int(q.cull), ref.x, ref.y)) }
			}
			axes := [1, 1, 2, 2, 0, 0]!
			axis := axes[int(q.dir)]
			want := if int(q.dir) % 2 != 0 { f32(1) } else { f32(0) }
			q.boundary = true
			for v in 0 .. 4 { if math.abs(q.pos[v][axis] - want) > 0.001 { q.boundary = false } }
			out.quads << q
		}
	}
}
