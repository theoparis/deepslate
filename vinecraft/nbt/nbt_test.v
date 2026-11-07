module nbt

import math

fn test_byte_reader_writer() {
	mut w := ByteWriter{}
	w.u8_(0xab)
	w.u16le(0x1234)
	w.u32le(0x12345678)
	w.u64le(0x0123456789abcdef)
	w.i16le(-2)
	w.i32le(-3)
	w.i64le(-4)
	w.f32le(1.5)
	w.f64le(-2.25)
	w.write_string('hi')
	assert w.buf[..7] == [u8(0xab), 0x34, 0x12, 0x78, 0x56, 0x34, 0x12]
	mut r := new_reader(w.buf)
	assert r.u8_() == 0xab
	assert r.u16le() == 0x1234
	assert r.u32le() == 0x12345678
	assert r.u64le() == u64(0x0123456789abcdef)
	assert r.i16le() == -2
	assert r.i32le() == -3
	assert r.i64le() == -4
	assert r.f32le() == f32(1.5)
	assert r.f64le() == -2.25
	assert r.read_string(2) == 'hi'
	assert r.eof() && r.ok()
	assert r.u16le() == 0
	assert !r.ok()
	assert r.u8_() == 0
	assert r.remaining() == 0
}

fn test_all_tags_and_sequential_roots() ! {
	mut root := make_compound()
	root.set('byte', make_byte(-1))
	root.set('short', make_short(-1234))
	root.set('int', make_int(-123456))
	root.set('long', make_long(-1234567890123))
	root.set('float', make_float(1.5))
	root.set('double', make_double(-2.25))
	root.set('string', make_string('hello'))
	root.set('bytes', make_byte_array([u8(0), 128, 255]))
	root.set('ints', make_int_array([-1, 0, 12345]))
	root.set('longs', make_long_array([i64(-1), 9876543210]))
	mut list := make_list(.int_tag)
	list.list << make_int(7)
	list.list << make_int(-8)
	root.set('list', list)
	root.set('nested', make_compound())
	root.set('byte', make_byte(-2))
	mut w := ByteWriter{}
	write_root(mut w, 'root', root)!
	write_root(mut w, '', make_string('next'))!
	assert w.buf[..7] == [u8(10), 4, 0, `r`, `o`, `o`, `t`]
	mut r := new_reader(w.buf)
	decoded := read_root(mut r)!
	assert decoded.name == 'root'
	assert decoded.tag.get_int('byte', 0) == -2
	assert decoded.tag.get_int('short', 0) == -1234
	assert decoded.tag.get_int('int', 0) == -123456
	assert decoded.tag.get_int('long', 0) == -1234567890123
	assert decoded.tag.get_num('float', 0) == 1.5
	assert decoded.tag.get_num('double', 0) == -2.25
	assert decoded.tag.get_string('string', '') == 'hello'
	assert (decoded.tag.find('bytes') or { panic('missing') }).bytes == [u8(0), 128, 255]
	assert (decoded.tag.find('ints') or { panic('missing') }).ints == [-1, 0, 12345]
	assert (decoded.tag.find('longs') or { panic('missing') }).longs == [i64(-1), 9876543210]
	items := decoded.tag.find('list') or { panic('missing') }
	assert items.list_type == .int_tag
	assert items.list_num(1, 0) == -8
	assert items.list_num(2, 42) == 42
	assert (decoded.tag.find('nested') or { panic('missing') }).typ == .compound
	assert read_root(mut r)!.tag.s == 'next'
	assert r.eof()
}

fn test_little_endian_known_vector() ! {
	data := [u8(10), 0, 0, 3, 1, 0, `x`, 0x78, 0x56, 0x34, 0x12, 0]
	mut r := new_reader(data)
	root := read_root(mut r)!
	assert root.tag.get_int('x', 0) == 0x12345678
	mut w := ByteWriter{}
	write_root(mut w, '', root.tag)!
	assert w.buf == data
}

fn test_rejects_malformed_input() {
	vectors := [
		[]u8{},
		[u8(0)],
		[u8(13), 0, 0],
		[u8(8), 0, 0, 5, 0, `x`],
		[u8(10), 0, 0],
		[u8(10), 0, 0, 13],
		[u8(7), 0, 0, 0xff, 0xff, 0xff, 0xff],
		[u8(11), 0, 0, 2, 0, 0, 0, 1, 2, 3, 4],
		[u8(9), 0, 0, 0, 1, 0, 0, 0],
		[u8(9), 0, 0, 13, 0, 0, 0, 0],
	]
	for data in vectors {
		mut r := new_reader(data)
		if _ := read_root(mut r) {
			assert false
		}
	}
}

fn test_float_bit_patterns() {
	mut w := ByteWriter{}
	w.f32le(math.f32_from_bits(0x7fc01234))
	w.f64le(math.f64_from_bits(u64(0x8000000000000000)))
	mut r := new_reader(w.buf)
	assert math.f32_bits(r.f32le()) == u32(0x7fc01234)
	assert math.f64_bits(r.f64le()) == u64(0x8000000000000000)
}

fn test_invalid_writes() {
	mut w := ByteWriter{}
	mut list := make_list(.int_tag)
	list.list << make_string('wrong')
	if _ := write_root(mut w, '', list) {
		assert false
	}
	mut w2 := ByteWriter{}
	if _ := write_root(mut w2, '', Tag{}) {
		assert false
	}
}

fn test_truncated_compound_at_every_offset() ! {
	mut root := make_compound()
	root.set('data', make_long_array([i64(-1), 2, 3]))
	root.set('text', make_string('abc'))
	mut w := ByteWriter{}
	write_root(mut w, 'root', root)!
	for n in 0 .. w.buf.len {
		mut r := new_reader(w.buf[..n])
		if _ := read_root(mut r) {
			assert false
		}
	}
}

fn test_rejects_excessive_nesting() {
	mut data := [u8(10), 0, 0]
	for _ in 0 .. 66 { data << [u8(10), 0, 0] }
	for _ in 0 .. 67 { data << u8(0) }
	mut r := new_reader(data)
	if _ := read_root(mut r) {
		assert false
	}
}
