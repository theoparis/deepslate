module storage

import vinecraft.nbt

fn pick_bits(size int) int {
	for b in [1, 2, 3, 4, 5, 6, 8, 16] {
		if size <= (1 << b) { return b }
	}
	return 16
}

fn pack_words(mut w nbt.ByteWriter, idx []u16, bits int) {
	per_word := 32 / bits
	for wi in 0 .. (4096 + per_word - 1) / per_word {
		mut word := u32(0)
		for k in 0 .. per_word {
			i := wi * per_word + k
			if i >= 4096 { break }
			word |= u32(idx[i]) << (k * bits)
		}
		w.u32le(word)
	}
}

fn unpack_words(mut r nbt.ByteReader, bits int) ![]u16 {
	if bits < 1 || bits > 16 { return error('invalid palette bit width') }
	mut idx := []u16{len: 4096}
	per_word := 32 / bits
	mask := (u32(1) << bits) - 1
	for wi in 0 .. (4096 + per_word - 1) / per_word {
		word := r.u32le()
		if !r.ok() { return error('truncated palette') }
		for k in 0 .. per_word {
			i := wi * per_word + k
			if i >= 4096 { break }
			idx[i] = u16((word >> (k * bits)) & mask)
		}
	}
	return idx
}
