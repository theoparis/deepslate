module nbt

// Values are the on-disk NBT type IDs.
pub enum Type {
	end        = 0
	byte_tag   = 1
	short_tag  = 2
	int_tag    = 3
	long_tag   = 4
	float_tag  = 5
	double_tag = 6
	byte_array = 7
	string_tag = 8
	list       = 9
	compound   = 10
	int_array  = 11
	long_array = 12
}

pub struct Tag {
pub mut:
	typ       Type
	i         i64
	d         f64
	s         string
	bytes     []u8
	ints      []int
	longs     []i64
	list_type Type
	list      []Tag
	compound  []Entry
}

pub struct Entry {
pub mut:
	name  string
	value Tag
}

pub fn make_byte(v i64) Tag { return Tag{ typ: .byte_tag, i: v } }

pub fn make_short(v i64) Tag { return Tag{ typ: .short_tag, i: v } }

pub fn make_int(v i64) Tag { return Tag{ typ: .int_tag, i: v } }

pub fn make_long(v i64) Tag { return Tag{ typ: .long_tag, i: v } }

pub fn make_float(v f64) Tag { return Tag{ typ: .float_tag, d: v } }

pub fn make_double(v f64) Tag { return Tag{ typ: .double_tag, d: v } }

pub fn make_string(v string) Tag { return Tag{ typ: .string_tag, s: v } }

pub fn make_compound() Tag { return Tag{ typ: .compound } }

pub fn make_list(elem Type) Tag { return Tag{ typ: .list, list_type: elem } }

pub fn make_byte_array(v []u8) Tag { return Tag{ typ: .byte_array, bytes: v } }

pub fn make_int_array(v []int) Tag { return Tag{ typ: .int_array, ints: v } }

pub fn make_long_array(v []i64) Tag { return Tag{ typ: .long_array, longs: v } }

pub fn (mut t Tag) set(name string, value Tag) {
	for mut entry in t.compound {
		if entry.name == name {
			entry.value = value
			return
		}
	}
	t.compound << Entry{ name: name, value: value }
}

pub fn (t &Tag) find(name string) ?Tag {
	for entry in t.compound {
		if entry.name == name { return entry.value }
	}
	return none
}

pub fn (t &Tag) get_int(name string, default_value i64) i64 {
	v := t.find(name) or { return default_value }
	return if v.typ in [.byte_tag, .short_tag, .int_tag, .long_tag] { v.i } else { default_value }
}

pub fn (t &Tag) get_num(name string, default_value f64) f64 {
	v := t.find(name) or { return default_value }
	if v.typ in [.float_tag, .double_tag] { return v.d }
	if v.typ in [.byte_tag, .short_tag, .int_tag, .long_tag] { return f64(v.i) }
	return default_value
}

pub fn (t &Tag) get_string(name string, default_value string) string {
	v := t.find(name) or { return default_value }
	return if v.typ == .string_tag { v.s } else { default_value }
}

pub fn (t &Tag) list_num(idx int, default_value f64) f64 {
	if t.typ != .list || idx < 0 || idx >= t.list.len { return default_value }
	v := t.list[idx]
	return if v.typ in [.float_tag, .double_tag] { v.d } else { f64(v.i) }
}
