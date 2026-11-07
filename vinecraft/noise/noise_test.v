module noise

import math

// Values recorded from the FastNoise2 v1.1.1 reference implementation.
const tol = f32(1e-5)

fn test_grid2_matches_reference_values() {
	g := new_fbm(4, 170, 0.5, false)
	mut out := []f32{len: 16 * 16}
	g.grid2(mut out, 0, 0, 16, 16, 0.5, 0.5, 7)
	pins := {
		0:   f32(-8.364865777821251e-08)
		1:   f32(0.04800973832607269)
		17:  f32(0.00010294746607542038)
		255: f32(0.09922872483730316)
	}
	for idx, want in pins {
		assert math.abs(out[idx] - want) < tol
	}
}

fn test_grid3_matches_reference_values() {
	g := new_fbm(2, 48, 0.3, false)
	mut out := []f32{len: 9 * 5 * 7}
	g.grid3(mut out, -500.5, -300, -64.25, 9, 5, 7, 1, 1, 1, 808)
	pins := {
		0:   f32(-0.9058314561843872)
		1:   f32(-0.930600643157959)
		8:   f32(-0.7376459836959839)
		9:   f32(-0.9008548855781555)
		20:  f32(-0.9181239008903503)
		314: f32(-0.6414116621017456)
	}
	for idx, want in pins {
		assert math.abs(out[idx] - want) < tol
	}
}

// A sub-window must sample exactly the same points as the enclosing grid,
// including widths that are not a multiple of the SIMD lane count.
fn test_grid2_subwindow_matches_enclosing_grid() {
	g := new_fbm(5, 1100, 0.5, false)
	mut big := []f32{len: 33 * 17}
	g.grid2(mut big, -1234.5, 777.25, 33, 17, 1, 1, 1234567)
	mut small := []f32{len: 5 * 7}
	g.grid2(mut small, -1234.5 + 10, 777.25 + 3, 5, 7, 1, 1, 1234567)
	for y in 0 .. 7 {
		for x in 0 .. 5 {
			assert small[y * 5 + x] == big[(y + 3) * 33 + x + 10]
		}
	}
}

fn test_grid3_subwindow_matches_enclosing_grid() {
	g := new_fbm(2, 90, 0.5, false)
	mut big := []f32{len: 12 * 4 * 3}
	g.grid3(mut big, 12.5, 40.0, -3.5, 12, 4, 3, 0.25, 1, 2, -123456)
	mut small := []f32{len: 6 * 2 * 2}
	g.grid3(mut small, 12.5 + 0.25 * 3, 40.0 + 1, -3.5 + 2, 6, 2, 2, 0.25, 1, 2, -123456)
	for z in 0 .. 2 {
		for y in 0 .. 2 {
			for x in 0 .. 6 {
				assert small[(z * 2 + y) * 6 + x] == big[((z + 1) * 4 + (y + 1)) * 12 + x + 3]
			}
		}
	}
}

fn test_fbm_is_deterministic_and_seeded() {
	g := new_fbm(4, 170, 0.5, false)
	mut a := []f32{len: 16}
	mut b := []f32{len: 16}
	g.grid2(mut a, 12, -34, 4, 4, 1, 1, 42)
	g.grid2(mut b, 12, -34, 4, 4, 1, 1, 42)
	assert a == b
	g.grid2(mut b, 12, -34, 4, 4, 1, 1, 43)
	assert a != b
}
