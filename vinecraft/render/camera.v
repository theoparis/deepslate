module render

import math

pub struct Vec3 {
pub mut:
	x f32
	y f32
	z f32
}

pub struct Vec3d {
pub mut:
	x f64
	y f64
	z f64
}

// Matrices use column-major layout, as expected by the graphics shaders.
pub type Mat4 = [16]f32

pub struct Camera {
pub mut:
	pos    Vec3d = Vec3d{0, 80, 0}
	yaw    f32
	pitch  f32
	fovy   f32 = 1.2217
	aspect f32 = 16.0 / 9.0
	znear  f32 = 0.05
	zfar   f32 = 600
}

pub fn (c Camera) forward() Vec3 {
	return Vec3{f32(-math.sin(c.yaw) * math.cos(c.pitch)), f32(-math.sin(c.pitch)), f32(math.cos(c.yaw) * math.cos(c.pitch))}
}

pub fn (c Camera) view_rot() Mat4 {
	f := c.forward()
	len := f32(math.sqrt(f.x * f.x + f.z * f.z))
	r := Vec3{-f.z / len, 0, f.x / len}
	u := Vec3{-r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y}
	return Mat4([r.x, u.x, -f.x, f32(0), r.y, u.y, -f.y, 0, r.z, u.z, -f.z, 0, 0, 0, 0, 1]!)
}

pub fn (c Camera) proj() Mat4 {
	t := f32(1.0 / math.tan(c.fovy * 0.5))
	mut p := Mat4{}
	p[0] = t / c.aspect
	p[5] = t
	p[10] = (c.zfar + c.znear) / (c.znear - c.zfar)
	p[14] = 2 * c.zfar * c.znear / (c.znear - c.zfar)
	p[11] = -1
	return p
}

pub fn (c Camera) view_proj() Mat4 {
	a := c.proj()
	b := c.view_rot()
	mut m := Mat4{}
	for col in 0 .. 4 {
		for row in 0 .. 4 {
			for k in 0 .. 4 { m[col * 4 + row] += a[k * 4 + row] * b[col * 4 + k] }
		}
	}
	return m
}

pub struct Frustum {
pub:
	planes [6][4]f32
}

pub fn (c Camera) frustum() Frustum {
	m := c.view_proj()
	mut planes := [6][4]f32{}
	for i in 0 .. 6 {
		row := i / 2
		sign := if i % 2 == 0 { f32(1) } else { f32(-1) }
		for col in 0 .. 4 { planes[i][col] = m[col * 4 + 3] + sign * m[col * 4 + row] }
		n := f32(math.sqrt(planes[i][0] * planes[i][0] + planes[i][1] * planes[i][1] + planes[i][2] * planes[i][2]))
		for col in 0 .. 4 { planes[i][col] /= n }
	}
	return Frustum{ planes: planes }
}

pub fn (f Frustum) intersects(mn Vec3, mx Vec3) bool {
	for p in f.planes {
		x := if p[0] > 0 { mx.x } else { mn.x }
		y := if p[1] > 0 { mx.y } else { mn.y }
		z := if p[2] > 0 { mx.z } else { mn.z }
		if p[0] * x + p[1] * y + p[2] * z + p[3] < 0 { return false }
	}
	return true
}
