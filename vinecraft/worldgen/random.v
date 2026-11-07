module worldgen

fn mix64(value u64) u64 {
	mut z := value + u64(0x9e3779b97f4a7c15)
	z = (z ^ (z >> 30)) * u64(0xbf58476d1ce4e5b9)
	z = (z ^ (z >> 27)) * u64(0x94d049bb133111eb)
	return z ^ (z >> 31)
}

fn hash_coords(seed u64, x int, y int, z int) u64 {
	mut h := mix64(seed ^ u64(0xa0761d6478bd642f))
	h = mix64(h ^ u64(i64(x)) * u64(0xe7037ed1a0b428db))
	h = mix64(h ^ u64(i64(y)) * u64(0x8ebc6af09c88c6e3))
	return mix64(h ^ u64(i64(z)) * u64(0x589965cc75374cc3))
}

fn hash_unit(h u64) f32 { return f32(h >> 40) * (f32(1.0) / f32(16777216.0)) }

struct Rng {
mut:
	s u64
}

fn (mut r Rng) next() u64 {
	r.s += u64(0x9e3779b97f4a7c15)
	return mix64(r.s)
}

fn (mut r Rng) unit() f32 { return hash_unit(r.next()) }

fn (mut r Rng) range(lo int, hi int) int { return lo + int(r.next() % u64(hi - lo + 1)) }

fn (mut r Rng) chance(p f32) bool { return r.unit() < p }
