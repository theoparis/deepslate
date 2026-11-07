module nbt

import math

pub struct ByteWriter {
pub mut:
	buf []u8
}

pub fn (mut w ByteWriter) u8_(v u8) { w.buf << v }

pub fn (mut w ByteWriter) u16le(v u16) {
	w.u8_(u8(v))
	w.u8_(u8(v >> 8))
}

pub fn (mut w ByteWriter) u32le(v u32) {
	for i in 0 .. 4 { w.u8_(u8(v >> (8 * i))) }
}

pub fn (mut w ByteWriter) u64le(v u64) {
	for i in 0 .. 8 { w.u8_(u8(v >> (8 * i))) }
}

pub fn (mut w ByteWriter) i16le(v i16) { w.u16le(u16(v)) }

pub fn (mut w ByteWriter) i32le(v int) { w.u32le(u32(v)) }

pub fn (mut w ByteWriter) i64le(v i64) { w.u64le(u64(v)) }

pub fn (mut w ByteWriter) f32le(v f32) { w.u32le(math.f32_bits(v)) }

pub fn (mut w ByteWriter) f64le(v f64) { w.u64le(math.f64_bits(v)) }

pub fn (mut w ByteWriter) bytes(v []u8) { w.buf << v }

pub fn (mut w ByteWriter) write_string(v string) { w.buf << v.bytes() }

// A failed read is sticky and leaves the cursor at its previous position.
pub struct ByteReader {
pub:
	data []u8
pub mut:
	pos    int
	failed bool
}

pub fn new_reader(data []u8) ByteReader { return ByteReader{ data: data } }

pub fn (r &ByteReader) ok() bool { return !r.failed }

pub fn (r &ByteReader) remaining() int { return r.data.len - r.pos }

pub fn (r &ByteReader) eof() bool { return r.pos >= r.data.len }

fn (mut r ByteReader) take(n int) bool {
	if r.failed || n < 0 || n > r.remaining() {
		r.failed = true
		return false
	}
	r.pos += n
	return true
}

pub fn (mut r ByteReader) u8_() u8 {
	if !r.take(1) { return 0 }
	return r.data[r.pos - 1]
}

pub fn (mut r ByteReader) u16le() u16 {
	if !r.take(2) { return 0 }
	return u16(r.data[r.pos - 2]) | (u16(r.data[r.pos - 1]) << 8)
}

pub fn (mut r ByteReader) u32le() u32 {
	if !r.take(4) { return 0 }
	mut v := u32(0)
	for i in 0 .. 4 { v |= u32(r.data[r.pos - 4 + i]) << (8 * i) }
	return v
}

pub fn (mut r ByteReader) u64le() u64 {
	if !r.take(8) { return 0 }
	mut v := u64(0)
	for i in 0 .. 8 { v |= u64(r.data[r.pos - 8 + i]) << (8 * i) }
	return v
}

pub fn (mut r ByteReader) i16le() i16 { return i16(r.u16le()) }

pub fn (mut r ByteReader) i32le() int { return int(i32(r.u32le())) }

pub fn (mut r ByteReader) i64le() i64 { return i64(r.u64le()) }

pub fn (mut r ByteReader) f32le() f32 { return math.f32_from_bits(r.u32le()) }

pub fn (mut r ByteReader) f64le() f64 { return math.f64_from_bits(r.u64le()) }

pub fn (mut r ByteReader) bytes(n int) []u8 {
	if !r.take(n) { return []u8{} }
	return r.data[r.pos - n..r.pos]
}

pub fn (mut r ByteReader) read_string(n int) string { return r.bytes(n).bytestr() }
