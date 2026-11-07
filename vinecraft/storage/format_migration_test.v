module storage

import vinecraft.blocks
import vinecraft.nbt

fn test_format_chunk_key_negative_coordinates() {
	key := chunk_key(blocks.ChunkPos{ x: -2, z: 3 }, 0x2f, i8(-4))
	assert key == [u8(0xfe), 0xff, 0xff, 0xff, 3, 0, 0, 0, 0x2f, 0xfc]
	assert chunk_key(blocks.ChunkPos{ x: 1, z: 1 }, 0x2c, none) == [u8(1), 0, 0, 0, 1, 0, 0, 0,
		0x2c]
}

fn test_format_palette_entries_and_legacy_alias() {
	mut reg := blocks.new_registry()
	for name in ['stone', 'oak_log', 'grass_block', 'water', 'oak_leaves'] {
		id := reg.find(name)
		assert id != 0
		tag := palette_entry(mut reg, id)
		assert tag.get_string('name', '') == reg.info(id).name
		assert (tag.find('states') or { panic('missing states') }).typ == .compound
		assert (tag.find('version') or { panic('missing version') }).typ == .int_tag
		assert palette_id(mut reg, tag) == id
	}
	mut legacy := nbt.make_compound()
	legacy.set('name', nbt.make_string('minecraft:grass'))
	legacy.set('states', nbt.make_compound())
	assert palette_id(mut reg, legacy) == reg.find('grass_block')
}

fn test_format_subchunk_palette_widths_and_versions() ! {
	mut reg := blocks.new_registry()
	mut ids := []blocks.BlockId{}
	for i in 0 .. 257 {
		ids << reg.lookup_or_register('test:palette_${i}', [])
	}
	sizes := [1, 2, 3, 4, 7, 8, 9, 16, 17, 32, 33, 64, 65, 200, 257]
	widths := [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 16]
	for n, size in sizes {
		mut sub := []blocks.BlockId{len: 4096}
		for i in 0 .. sub.len { sub[i] = ids[i % size] }
		encoded := encode_subchunk(sub, -3, mut reg)!
		assert encoded[..3] == [u8(9), 1, 0xfd]
		assert int(encoded[3] >> 1) == widths[n]
		decoded, index := decode_subchunk(encoded, mut reg)!
		assert index == -3
		assert decoded == sub
		mut v8 := [u8(8), 1]
		v8 << encoded[3..]
		decoded8, index8 := decode_subchunk(v8, mut reg)!
		assert index8 == 0
		assert decoded8 == sub
		mut v1 := [u8(1)]
		v1 << encoded[3..]
		decoded1, index1 := decode_subchunk(v1, mut reg)!
		assert index1 == 0
		assert decoded1 == sub
	}
}

fn test_format_subchunk_bedrock_word_layout() ! {
	mut reg := blocks.new_registry()
	mut sub := []blocks.BlockId{len: 4096}
	sub[blocks.sub_index(0, 0, 0)] = reg.find('stone')
	sub[blocks.sub_index(0, 1, 0)] = reg.find('dirt')
	encoded := encode_subchunk(sub, 0, mut reg)!
	assert encoded[3] == 4
	// First-use palette: stone=0, dirt=1, air=2; y varies fastest.
	assert encoded[4..8] == [u8(0xa4), 0xaa, 0xaa, 0xaa]
}

fn format_subchunk_is_invalid(data []u8, mut reg blocks.Registry) bool {
	_, _ := decode_subchunk(data, mut reg) or { return true }
	return false
}

fn test_format_subchunk_rejects_invalid_data() ! {
	mut reg := blocks.new_registry()
	sub := []blocks.BlockId{len: 4096}
	encoded := encode_subchunk(sub, -3, mut reg)!
	assert format_subchunk_is_invalid(encoded[..40], mut reg)
	mut runtime := encoded.clone()
	runtime[3] |= 1
	assert format_subchunk_is_invalid(runtime, mut reg)
	assert format_subchunk_is_invalid([u8(7)], mut reg)
	assert format_subchunk_is_invalid([u8(9), 1, 0, 0], mut reg)
	if _ := encode_subchunk([]blocks.BlockId{}, 0, mut reg) {
		assert false
	}
}

fn test_format_uniform_biome_compact_encoding() {
	mut chunk := blocks.new_chunk(0, 0)
	for i in 0 .. 256 { chunk.biome[i] = blocks.biome_taiga }
	data := encode_data3d(chunk.snapshot())
	assert data.len == 512 + 24 * 5
	mut restored := blocks.new_chunk(0, 0)
	decode_data3d(data, mut restored)
	assert restored.biome[37] == blocks.biome_taiga
	assert restored.height == chunk.height
}
