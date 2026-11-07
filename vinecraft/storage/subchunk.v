module storage

import vinecraft.blocks
import vinecraft.nbt

fn palette_entry(mut reg blocks.Registry, id blocks.BlockId) nbt.Tag {
	info := reg.info(id)
	mut tag := nbt.make_compound()
	tag.set('name', nbt.make_string(info.name))
	mut states := nbt.make_compound()
	for e in info.states {
		value := match e.value.kind {
			.byte_value { nbt.make_byte(e.value.i) }
			.int_value { nbt.make_int(e.value.i) }
			.string_value { nbt.make_string(e.value.s) }
		}
		states.set(e.key, value)
	}
	tag.set('states', states)
	tag.set('version', nbt.make_int(18153475))
	return tag
}

fn palette_id(mut reg blocks.Registry, tag nbt.Tag) blocks.BlockId {
	mut name := tag.get_string('name', 'minecraft:air')
	mut states := blocks.StateMap{}
	if st := tag.find('states') {
		if st.typ == .compound {
			for e in st.compound {
				match e.value.typ {
					.byte_tag {
						states << blocks.StateEntry{ key: e.name, value: blocks.state_byte(int(e.value.i)) }
					}
					.int_tag, .short_tag {
						states << blocks.StateEntry{ key: e.name, value: blocks.state_int_value(int(e.value.i)) }
					}
					.string_tag {
						states << blocks.StateEntry{ key: e.name, value: blocks.state_string(e.value.s) }
					}
					else {}
				}
			}
		}
	}
	if name == 'minecraft:grass' { name = 'minecraft:grass_block' }
	if name == 'minecraft:flowing_water' { name = 'minecraft:water' }
	if name == 'minecraft:flowing_lava' { name = 'minecraft:lava' }
	return reg.lookup_or_register(name, states)
}

pub fn encode_subchunk(sub []blocks.BlockId, index int, mut reg blocks.Registry) ![]u8 {
	if sub.len != 4096 { return error('invalid subchunk length') }
	mut lookup := map[blocks.BlockId]u16{}
	mut palette := []blocks.BlockId{}
	mut idx := []u16{len: 4096}
	for i, id in sub {
		if id !in lookup {
			lookup[id] = u16(palette.len)
			palette << id
		}
		idx[i] = lookup[id]
	}
	mut w := nbt.ByteWriter{}
	w.u8_(9)
	w.u8_(1)
	w.u8_(u8(index))
	bits := pick_bits(palette.len)
	w.u8_(u8(bits << 1))
	pack_words(mut w, idx, bits)
	w.i32le(palette.len)
	for id in palette { nbt.write_root(mut w, '', palette_entry(mut reg, id))! }
	return w.buf
}

pub fn decode_subchunk(data []u8, mut reg blocks.Registry) !([]blocks.BlockId, int) {
	mut r := nbt.new_reader(data)
	version := r.u8_()
	mut layers := 1
	mut index := 0
	if version == 8 || version == 9 {
		layers = int(r.u8_())
		if version == 9 { index = int(i8(r.u8_())) }
	} else if version != 1 {
		return error('unsupported subchunk version')
	}
	mut sub := []blocks.BlockId{len: 4096}
	for layer in 0 .. layers {
		flag := r.u8_()
		if !r.ok() || flag & 1 != 0 { return error('invalid persistent palette') }
		idx := unpack_words(mut r, int(flag >> 1))!
		count := r.i32le()
		if !r.ok() || count < 0 || count > 65536 { return error('invalid palette size') }
		mut palette := []blocks.BlockId{cap: count}
		for _ in 0 .. count {
			root := nbt.read_root(mut r)!
			palette << palette_id(mut reg, root.tag)
		}
		if layer == 0 {
			for i, pi in idx { if int(pi) < palette.len { sub[i] = palette[pi] } }
		}
	}
	return sub, index
}
