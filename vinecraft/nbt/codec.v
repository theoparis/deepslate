module nbt

pub struct NamedTag {
pub:
	name string
	tag  Tag
}

fn checked_type(id u8) !Type {
	if id > 12 { return error('invalid NBT tag type') }
	return unsafe { Type(id) }
}

fn read_string(mut r ByteReader) !string {
	n := int(r.u16le())
	if !r.ok() || n > r.remaining() { return error('truncated NBT string') }
	return r.read_string(n)
}

fn write_string(mut w ByteWriter, s string) ! {
	if s.len > 65535 { return error('NBT string is too long') }
	w.u16le(u16(s.len))
	w.write_string(s)
}

// Reads one named tag, leaving subsequent bytes available in the reader.
pub fn read_root(mut r ByteReader) !NamedTag {
	id := r.u8_()
	if !r.ok() { return error('truncated NBT root') }
	typ := checked_type(id)!
	if typ == .end { return error('NBT root cannot be an end tag') }
	name := read_string(mut r)!
	tag := read_payload(mut r, typ)!
	return NamedTag{ name: name, tag: tag }
}

pub fn read_payload(mut r ByteReader, typ Type) !Tag {
	return read_nested(mut r, typ, 0)
}

fn min_size(typ Type) int {
	return match typ {
		.end { 0 }
		.byte_tag { 1 }
		.short_tag, .string_tag { 2 }
		.int_tag, .float_tag, .byte_array, .int_array, .long_array { 4 }
		.long_tag, .double_tag { 8 }
		.list { 5 }
		.compound { 1 }
	}
}

fn read_count(mut r ByteReader, element_size int) !int {
	n := r.i32le()
	if !r.ok() || n < 0 || (element_size > 0 && n > r.remaining() / element_size) {
		return error('invalid or truncated NBT collection')
	}
	return n
}

fn read_nested(mut r ByteReader, typ Type, depth int) !Tag {
	if depth > 64 { return error('NBT nesting too deep') }
	mut t := Tag{ typ: typ }
	match typ {
		.end {}
		.byte_tag { t.i = i64(i8(r.u8_())) }
		.short_tag { t.i = i64(r.i16le()) }
		.int_tag { t.i = i64(r.i32le()) }
		.long_tag { t.i = r.i64le() }
		.float_tag { t.d = f64(r.f32le()) }
		.double_tag { t.d = r.f64le() }
		.byte_array {
			n := read_count(mut r, 1)!
			t.bytes = r.bytes(n).clone()
		}
		.string_tag { t.s = read_string(mut r)! }
		.list {
			id := r.u8_()
			if !r.ok() { return error('truncated NBT list') }
			t.list_type = checked_type(id)!
			n := read_count(mut r, min_size(t.list_type))!
			if t.list_type == .end && n != 0 { return error('nonempty NBT end list') }
			for _ in 0 .. n { t.list << read_nested(mut r, t.list_type, depth + 1)! }
		}
		.compound {
			for {
				id := r.u8_()
				if !r.ok() { return error('unterminated NBT compound') }
				child_type := checked_type(id)!
				if child_type == .end { break }
				name := read_string(mut r)!
				value := read_nested(mut r, child_type, depth + 1)!
				t.compound << Entry{ name: name, value: value }
			}
		}
		.int_array {
			n := read_count(mut r, 4)!
			for _ in 0 .. n { t.ints << r.i32le() }
		}
		.long_array {
			n := read_count(mut r, 8)!
			for _ in 0 .. n { t.longs << r.i64le() }
		}
	}
	if !r.ok() { return error('truncated NBT payload') }
	return t
}

pub fn write_root(mut w ByteWriter, name string, t Tag) ! {
	if t.typ == .end { return error('NBT root cannot be an end tag') }
	w.u8_(u8(t.typ))
	write_string(mut w, name)!
	write_payload(mut w, t)!
}

pub fn write_payload(mut w ByteWriter, t Tag) ! {
	write_nested(mut w, t, 0)!
}

fn write_nested(mut w ByteWriter, t Tag, depth int) ! {
	if depth > 64 { return error('NBT nesting too deep') }
	match t.typ {
		.end {}
		.byte_tag { w.u8_(u8(t.i)) }
		.short_tag { w.i16le(i16(t.i)) }
		.int_tag { w.i32le(int(t.i)) }
		.long_tag { w.i64le(t.i) }
		.float_tag { w.f32le(f32(t.d)) }
		.double_tag { w.f64le(t.d) }
		.byte_array {
			w.i32le(t.bytes.len)
			w.bytes(t.bytes)
		}
		.string_tag { write_string(mut w, t.s)! }
		.list {
			if t.list.len > 0 && t.list_type == .end { return error('nonempty NBT end list') }
			w.u8_(if t.list.len == 0 { u8(0) } else { u8(t.list_type) })
			w.i32le(t.list.len)
			for item in t.list {
				if item.typ != t.list_type { return error('mixed NBT list types') }
				write_nested(mut w, item, depth + 1)!
			}
		}
		.compound {
			for entry in t.compound {
				if entry.value.typ == .end { return error('named NBT end tag') }
				w.u8_(u8(entry.value.typ))
				write_string(mut w, entry.name)!
				write_nested(mut w, entry.value, depth + 1)!
			}
			w.u8_(0)
		}
		.int_array {
			w.i32le(t.ints.len)
			for value in t.ints { w.i32le(value) }
		}
		.long_array {
			w.i32le(t.longs.len)
			for value in t.longs { w.i64le(value) }
		}
	}
}
