module storage

import vinecraft.blocks
import vinecraft.nbt
import leveldb

pub fn chunk_key(pos blocks.ChunkPos, tag u8, sub ?i8) []u8 {
	mut w := nbt.ByteWriter{}
	w.i32le(pos.x)
	w.i32le(pos.z)
	w.u8_(tag)
	if index := sub { w.u8_(u8(index)) }
	return w.buf
}

pub fn (mut s LevelStore) has_chunk(pos blocks.ChunkPos) !bool {
	s.mutex.@lock()
	defer { s.mutex.unlock() }
	return s.db.has(chunk_key(pos, 0x2c, none), leveldb.ReadOptions{})!
}

pub fn (mut s LevelStore) load_chunk(pos blocks.ChunkPos, mut reg blocks.Registry) !blocks.Chunk {
	s.mutex.@lock()
	defer { s.mutex.unlock() }
	version := s.db.get(chunk_key(pos, 0x2c, none), leveldb.ReadOptions{})!
	if !version.found { return error('chunk not found') }
	mut c := blocks.Chunk{ pos: pos }
	for si in 0 .. blocks.num_subs {
		data := s.db.get(chunk_key(pos, 0x2f, i8(si + blocks.min_sub)), leveldb.ReadOptions{})!
		if !data.found { continue }
		sub, _ := decode_subchunk(data.value, mut reg) or { continue }
		c.subs[si] = sub
	}
	data := s.db.get(chunk_key(pos, 0x2b, none), leveldb.ReadOptions{})!
	if data.found {
		decode_data3d(data.value, mut c)
	} else {
		for i in 0 .. 256 { c.biome[i] = 1 }
	}
	c.recompute_heights(reg)
	return c
}

pub fn (mut s LevelStore) save_chunk(snap blocks.ChunkSnapshot, mut reg blocks.Registry) ! {
	s.mutex.@lock()
	defer { s.mutex.unlock() }
	mut batch := leveldb.new_batch()
	if s.read_only { return error('read-only world') }
	batch.put(chunk_key(snap.pos, 0x2c, none), [u8(40)])
	batch.put(chunk_key(snap.pos, 0x2b, none), encode_data3d(snap))
	mut fin := nbt.ByteWriter{}
	fin.i32le(2)
	batch.put(chunk_key(snap.pos, 0x36, none), fin.buf)
	for si in 0 .. blocks.num_subs {
		key := chunk_key(snap.pos, 0x2f, i8(si + blocks.min_sub))
		mut empty := true
		for id in snap.subs[si] {
			if id != 0 {
				empty = false
				break
			}
		}
		if empty {
			batch.delete(key)
		} else {
			batch.put(key, encode_subchunk(snap.subs[si], si + blocks.min_sub, mut reg)!)
		}
	}
	s.db.write(mut batch, leveldb.WriteOptions{})!
}
