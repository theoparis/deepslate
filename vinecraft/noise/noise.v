// Scalar port of the FastNoise2 (v1.1.1) Simplex generator wrapped in
// FractalFBm or FractalRidged, as used by worldgen. Operation order follows
// FastNoise2's portable code path, so each sample is a pure f32 function.
module noise

const prime_x = i32(-0x08683A39)
const prime_y = i32(0x6C060C89)
const prime_z = i32(0x465FD04F)
const hash_mul = i32(-0x481F5A0B)

const root3 = 1.7320508075688772935274463415059
const root2_f = f32(1.4142135623730951)
const skew2 = f32(1.0 / (root3 + 1.0))
const unskew2 = f32(-1.0 / (root3 + 3.0))
const unskew2_p1 = f32(-1.0 / (root3 + 3.0) + 1.0)
const unskew2_x2_p1 = f32(-1.0 / (root3 + 3.0) * 2.0 + 1.0)
const falloff2_c = f32(-4.0 * (root3 + 2.0) / (root3 + 3.0))
const two_thirds_neg = f32(-2.0 / 3.0)
const grad2_c = f32(1.0 + f64(root2_f))
const bounding2 = f32(0.0261208079755306243896484375)
const skew3 = f32(1.0 / 3.0)
const reflect3 = f32(-1.0 / 2.0)
const reflect3_3p1 = f32(-1.0 / 2.0 * 3.0 + 1.0)
const falloff3_r2 = f32(0.6)
const three_quarters = f32(3.0 / 4.0)
const bounding3 = f32(0.030586399137973785400390625)

pub struct Generator {
pub:
	octaves int
	gain    f32
	ridged  bool
	freq    f32
}

pub fn new_fbm(octaves int, scale f32, gain f32, ridged bool) Generator {
	assert octaves >= 1
	return Generator{
		octaves: octaves
		gain:    gain
		ridged:  ridged
		freq:    f32(1.0) / scale
	}
}

@[inline]
fn floor_f32(v f32) f32 {
	t := f32(int(v))
	return if v < t { t - 1 } else { t }
}

@[inline]
fn mul_i32(a i32, b i32) i32 {
	return i32(u32(a) * u32(b))
}

@[inline]
fn hash_mix(h i32) i32 {
	return (h >> 15) ^ h
}

@[inline]
fn bit_set(h i32, bit u32) bool {
	return (u32(h) >> bit) & 1 != 0
}

@[inline]
fn max0(v f32) f32 {
	return if v > 0 { v } else { 0 }
}

@[inline]
fn scale_output(value f32, bound f32) f32 {
	scale := f32(1.0) / (bound + bound) * f32(2.0)
	return (value + bound) * scale + f32(-1.0)
}

@[inline]
fn grad2(hash i32, fx f32, fy f32) f32 {
	x := if bit_set(hash, 0) { -fx } else { fx }
	y := if bit_set(hash, 1) { -fy } else { fy }
	high := bit_set(hash, 2)
	u := if high { y } else { x }
	v := if high { x } else { y }
	return u * grad2_c + v
}

@[inline]
fn grad3(hash i32, fx f32, fy f32, fz f32) f32 {
	h13 := hash & 13
	mut u := if h13 > 7 { fy } else { fx }
	mut v := if h13 == 12 { fx } else { fz }
	v = if h13 < 2 { fy } else { v }
	u = if bit_set(hash, 0) { -u } else { u }
	v = if bit_set(hash, 1) { -v } else { v }
	return u + v
}

@[inline]
fn simplex2(seed i32, x f32, y f32) f32 {
	skew_delta := skew2 * (x + y)
	x_skewed := x + skew_delta
	y_skewed := y + skew_delta
	x_base := floor_f32(x_skewed)
	y_base := floor_f32(y_skewed)
	dx_skewed := x_skewed - x_base
	dy_skewed := y_skewed - y_base
	x_primed := mul_i32(i32(x_base), prime_x)
	y_primed := mul_i32(i32(y_base), prime_y)
	ge := dx_skewed >= dy_skewed
	unskew_delta := unskew2 * (dx_skewed + dy_skewed)
	dx0 := dx_skewed + unskew_delta
	dy0 := dy_skewed + unskew_delta
	dx1 := (if !ge { dx0 + 1 } else { dx0 }) - unskew2_p1
	dy1 := (if ge { dy0 + 1 } else { dy0 }) - unskew2_p1
	dx2 := dx0 - unskew2_x2_p1
	dy2 := dy0 - unskew2_x2_p1

	mut f0 := (0.5 - dy0 * dy0) - dx0 * dx0
	mut f1 := (0.5 - dy1 * dy1) - dx1 * dx1
	mut f2 := f0 + (unskew_delta * falloff2_c + two_thirds_neg)
	f0 = max0(f0)
	f1 = max0(f1)
	f2 = max0(f2)
	f0 = f0 * f0
	f0 = f0 * f0
	f1 = f1 * f1
	f1 = f1 * f1
	f2 = f2 * f2
	f2 = f2 * f2

	g0 := grad2(hash_mix(mul_i32(seed ^ x_primed ^ y_primed, hash_mul)), dx0, dy0)
	x1 := x_primed + if ge { prime_x } else { 0 }
	y1 := y_primed + if !ge { prime_y } else { 0 }
	g1 := grad2(hash_mix(mul_i32(seed ^ x1 ^ y1, hash_mul)), dx1, dy1)
	xp2 := x_primed + prime_x
	yp2 := y_primed + prime_y
	g2 := grad2(hash_mix(mul_i32(seed ^ xp2 ^ yp2, hash_mul)), dx2, dy2)

	value := g0 * f0 + (g1 * f1 + g2 * f2)
	return scale_output(value, bounding2)
}

@[inline]
fn simplex3(seed i32, x f32, y f32, z f32) f32 {
	skew_delta := skew3 * ((x + y) + z)
	x_skewed := x + skew_delta
	y_skewed := y + skew_delta
	z_skewed := z + skew_delta
	x_base := floor_f32(x_skewed)
	y_base := floor_f32(y_skewed)
	z_base := floor_f32(z_skewed)
	dx_skewed := x_skewed - x_base
	dy_skewed := y_skewed - y_base
	dz_skewed := z_skewed - z_base
	x_primed := mul_i32(i32(x_base), prime_x)
	y_primed := mul_i32(i32(y_base), prime_y)
	z_primed := mul_i32(i32(z_base), prime_z)
	x_ge_y := dx_skewed >= dy_skewed
	y_ge_z := dy_skewed >= dz_skewed
	x_ge_z := dx_skewed >= dz_skewed
	unskew_delta := reflect3 * ((dx_skewed + dy_skewed) + dz_skewed)
	dx0 := dx_skewed + unskew_delta
	dy0 := dy_skewed + unskew_delta
	dz0 := dz_skewed + unskew_delta
	mask_x1 := x_ge_y && x_ge_z
	mask_y1 := y_ge_z && !x_ge_y
	mask_z1 := x_ge_z || y_ge_z
	n_mask_x2 := x_ge_y || x_ge_z
	n_mask_y2 := x_ge_y && !y_ge_z
	n_mask_z2 := x_ge_z && y_ge_z
	dx3 := dx0 - reflect3_3p1
	dy3 := dy0 - reflect3_3p1
	dz3 := dz0 - reflect3_3p1
	dx1 := if mask_x1 { dx3 - 1 } else { dx3 }
	dy1 := if mask_y1 { dy3 - 1 } else { dy3 }
	dz1 := if mask_z1 { dz3 } else { dz3 - 1 }
	dx2 := if !n_mask_x2 { dx0 + 1 } else { dx0 }
	dy2 := if n_mask_y2 { dy0 + 1 } else { dy0 }
	dz2 := if n_mask_z2 { dz0 + 1 } else { dz0 }

	mut f0 := falloff3_r2 - dx0 * dx0
	f0 = f0 - dy0 * dy0
	f0 = f0 - dz0 * dz0
	mut f1 := falloff3_r2 - dx1 * dx1
	f1 = f1 - dy1 * dy1
	f1 = f1 - dz1 * dz1
	mut f2 := falloff3_r2 - dx2 * dx2
	f2 = f2 - dy2 * dy2
	f2 = f2 - dz2 * dz2
	mut f3 := f0 - (unskew_delta + three_quarters)
	f0 = max0(f0)
	f1 = max0(f1)
	f2 = max0(f2)
	f3 = max0(f3)
	f0 = f0 * f0
	f0 = f0 * f0
	f1 = f1 * f1
	f1 = f1 * f1
	f2 = f2 * f2
	f2 = f2 * f2
	f3 = f3 * f3
	f3 = f3 * f3

	g0 := grad3(hash_mix(mul_i32(seed ^ x_primed ^ y_primed ^ z_primed, hash_mul)), dx0, dy0, dz0)
	x1 := x_primed + if mask_x1 { prime_x } else { 0 }
	y1 := y_primed + if mask_y1 { prime_y } else { 0 }
	z1 := z_primed + if !mask_z1 { prime_z } else { 0 }
	g1 := grad3(hash_mix(mul_i32(seed ^ x1 ^ y1 ^ z1, hash_mul)), dx1, dy1, dz1)
	x2 := x_primed + if n_mask_x2 { prime_x } else { 0 }
	y2 := y_primed + if !n_mask_y2 { prime_y } else { 0 }
	z2 := z_primed + if !n_mask_z2 { prime_z } else { 0 }
	g2 := grad3(hash_mix(mul_i32(seed ^ x2 ^ y2 ^ z2, hash_mul)), dx2, dy2, dz2)
	x3 := x_primed + prime_x
	y3 := y_primed + prime_y
	z3 := z_primed + prime_z
	g3 := grad3(hash_mix(mul_i32(seed ^ x3 ^ y3 ^ z3, hash_mul)), dx3, dy3, dz3)

	value := g3 * f3 + (g2 * f2 + (g1 * f1 + g0 * f0))
	return scale_output(value, bounding3)
}

@[inline]
fn octave_term(g Generator, n f32) f32 {
	if g.ridged {
		return n * -2.0 + 1.0
	}
	return n
}

// sample2 evaluates the fractal at one point.
fn (g Generator) sample2(seed i32, x f32, y f32) f32 {
	mut s := seed
	mut px := x * g.freq
	mut py := y * g.freq
	mut amp := f32(1.0)
	mut n := simplex2(s, px, py)
	if g.ridged { n = if n < 0 { -n } else { n } }
	mut sum := octave_term(g, n)
	for _ in 1 .. g.octaves {
		s = i32(u32(s) + 1)
		amp = amp * g.gain
		px = px * 2.0
		py = py * 2.0
		n = simplex2(s, px, py)
		if g.ridged { n = if n < 0 { -n } else { n } }
		sum = octave_term(g, n) * amp + sum
	}
	return sum
}

fn (g Generator) sample3(seed i32, x f32, y f32, z f32) f32 {
	mut s := seed
	mut px := x * g.freq
	mut py := y * g.freq
	mut pz := z * g.freq
	mut amp := f32(1.0)
	mut n := simplex3(s, px, py, pz)
	if g.ridged { n = if n < 0 { -n } else { n } }
	mut sum := octave_term(g, n)
	for _ in 1 .. g.octaves {
		s = i32(u32(s) + 1)
		amp = amp * g.gain
		px = px * 2.0
		py = py * 2.0
		pz = pz * 2.0
		n = simplex3(s, px, py, pz)
		if g.ridged { n = if n < 0 { -n } else { n } }
		sum = octave_term(g, n) * amp + sum
	}
	return sum
}

// grid2 fills out[y * nx + x] for x in 0..nx, y in 0..ny.
pub fn (g Generator) grid2(mut out []f32, x f32, y f32, nx int, ny int, dx f32, dy f32, seed int) {
	assert nx > 0 && ny > 0 && i64(nx) * i64(ny) <= out.len
	seed_v := i32(seed)
	for iy in 0 .. ny {
		ys := f32(iy) * dy + y
		for ix in 0 .. nx {
			xs := f32(ix) * dx + x
			out[iy * nx + ix] = g.sample2(seed_v, xs, ys)
		}
	}
}

// grid3 fills out[(z * ny + y) * nx + x].
pub fn (g Generator) grid3(mut out []f32, x f32, y f32, z f32, nx int, ny int, nz int, dx f32, dy f32, dz f32, seed int) {
	assert nx > 0 && ny > 0 && nz > 0 && i64(nx) * i64(ny) * i64(nz) <= out.len
	seed_v := i32(seed)
	for iz in 0 .. nz {
		zs := f32(iz) * dz + z
		for iy in 0 .. ny {
			ys := f32(iy) * dy + y
			row := (iz * ny + iy) * nx
			for ix in 0 .. nx {
				xs := f32(ix) * dx + x
				out[row + ix] = g.sample3(seed_v, xs, ys, zs)
			}
		}
	}
}
