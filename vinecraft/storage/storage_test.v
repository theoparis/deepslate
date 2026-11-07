module storage

import vinecraft.blocks
import vinecraft.nbt
import io.util
import os

fn test_chunk_keys_and_subchunk_roundtrip() {
	pos := blocks.ChunkPos{ x: -7, z: 12 }
	mut r := nbt.new_reader(chunk_key(pos, 0x2f, i8(-4)))
	assert r.i32le() == -7
	assert r.i32le() == 12
	assert r.u8_() == 0x2f
	assert i8(r.u8_()) == -4
	mut reg := blocks.new_registry()
	stone := reg.find('minecraft:stone')
	mut sub := []blocks.BlockId{len: 4096}
	sub[0] = stone
	sub[4095] = stone
	encoded := encode_subchunk(sub, -4, mut reg) or { panic(err) }
	decoded, index := decode_subchunk(encoded, mut reg) or { panic(err) }
	assert index == -4
	assert decoded == sub
	// Versions 8 and 1 omit the section index.
	mut v8 := [u8(8), u8(1)]
	v8 << encoded[3..]
	decoded8, _ := decode_subchunk(v8, mut reg) or { panic(err) }
	assert decoded8 == sub
	mut v1 := [u8(1)]
	v1 << encoded[3..]
	decoded1, _ := decode_subchunk(v1, mut reg) or { panic(err) }
	assert decoded1 == sub
}

fn test_biome_storage_roundtrip() {
	mut c := blocks.new_chunk(0, 0)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			i := blocks.col_index(x, z)
			c.height[i] = i16(60 + x)
			c.biome[i] = if (x + z) % 2 == 0 { blocks.biome_forest } else { blocks.biome_desert }
		}
	}
	data := encode_data3d(c.snapshot())
	mut restored := blocks.new_chunk(0, 0)
	decode_data3d(data, mut restored)
	assert restored.height == c.height
	assert restored.biome == c.biome
}

fn test_saved_chunk_survives_reopen() {
	dir := util.temp_dir(pattern: 'deepslate-storage-*') or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	mut reg := blocks.new_registry()
	stone := reg.find('stone')
	mut store := open(dir, 42) or { panic(err) }
	mut chunk := blocks.new_chunk(-3, 8)
	assert chunk.set(4, -30, 5, stone)
	store.save_chunk(chunk.snapshot(), mut reg) or { panic(err) }
	store.write_level_dat() or { panic(err) }
	store.close() or { panic(err) }
	mut reopened := open(dir, 0) or { panic(err) }
	assert reopened.info.seed == 42
	restored := reopened.load_chunk(blocks.ChunkPos{ x: -3, z: 8 }, mut reg) or { panic(err) }
	assert restored.get(4, -30, 5) == stone
	reopened.close() or { panic(err) }
}
