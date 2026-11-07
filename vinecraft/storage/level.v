module storage

import os
import time
import vinecraft.nbt
import leveldb
import sync
import io.util

pub struct LevelInfo {
pub mut:
	name        string = 'Deepslate World'
	seed        i64
	game_type   int = 1
	spawn_x     int
	spawn_y     int = 100
	spawn_z     int
	time        i64 = 1000
	last_played i64
	spawn_set   bool
}

pub struct InventorySlot {
pub mut:
	block string
	count int
}

pub struct PlayerData {
pub mut:
	pos      [3]f64
	yaw      f32
	pitch    f32
	flying   bool
	selected int
	hotbar   []InventorySlot
}

pub struct LevelStore {
pub:
	dir string
pub mut:
	is_new bool
	info   LevelInfo
mut:
	mutex     sync.Mutex
	temp_dir  string
	read_only bool
	db        &leveldb.DB = unsafe { nil }
}

pub fn open(dir string, seed i64) !&LevelStore {
	os.mkdir_all(os.join_path(dir, 'db'))!
	mut s := &LevelStore{ dir: dir }
	s.read_level_dat() or {
		s.is_new = true
		s.info.seed = seed
		s.info.name = os.file_name(dir)
		if s.info.name == '' { s.info.name = 'Deepslate World' }
	}
	s.db = leveldb.open(os.join_path(dir, 'db'), leveldb.Options{ compression: .raw_deflate })!
	return s
}

pub fn (mut s LevelStore) close() ! {
	s.mutex.@lock()
	defer { s.mutex.unlock() }
	s.db.close()!
	if s.temp_dir != '' {
		os.rmdir_all(s.temp_dir)!
		s.temp_dir = ''
	}
}

// Opening LevelDB performs recovery, so no-save mode uses an isolated copy.
pub fn open_read_only(dir string, seed i64) !&LevelStore {
	temp := util.temp_dir(util.TempDirOptions{ pattern: 'deepslate-world-*' })!
	copy := os.join_path(temp, 'world')
	if os.exists(dir) {
		os.cp_all(dir, copy, true) or {
			os.rmdir_all(temp) or {}
			return err
		}
	}
	mut s := open(copy, seed) or {
		os.rmdir_all(temp) or {}
		return err
	}
	if s.is_new {
		s.info.name = os.file_name(dir)
		if s.info.name == '' { s.info.name = 'Deepslate World' }
	}
	s.temp_dir = temp
	s.read_only = true
	return s
}

pub fn (mut s LevelStore) write_level_dat() ! {
	if s.read_only { return error('read-only world') }
	mut t := nbt.make_compound()
	t.set('StorageVersion', nbt.make_int(10))
	t.set('NetworkVersion', nbt.make_int(898))
	mut v := nbt.make_list(.int_tag)
	for x in [1, 21, 50, 0, 0] { v.list << nbt.make_int(x) }
	t.set('lastOpenedWithVersion', v)
	mut m := nbt.make_list(.int_tag)
	for x in [1, 21, 0, 0, 0] { m.list << nbt.make_int(x) }
	t.set('MinimumCompatibleClientVersion', m)
	t.set('LevelName', nbt.make_string(s.info.name))
	t.set('RandomSeed', nbt.make_long(s.info.seed))
	t.set('GameType', nbt.make_int(s.info.game_type))
	t.set('Generator', nbt.make_int(1))
	t.set('Difficulty', nbt.make_int(2))
	t.set('SpawnX', nbt.make_int(s.info.spawn_x))
	t.set('SpawnY', nbt.make_int(s.info.spawn_y))
	t.set('SpawnZ', nbt.make_int(s.info.spawn_z))
	t.set('Time', nbt.make_long(s.info.time))
	t.set('currentTick', nbt.make_long(s.info.time))
	s.info.last_played = time.now().unix()
	t.set('LastPlayed', nbt.make_long(s.info.last_played))
	t.set('baseGameVersion', nbt.make_string('*'))
	t.set('commandsEnabled', nbt.make_byte(1))
	t.set('dodaylightcycle', nbt.make_byte(1))
	t.set('immutableWorld', nbt.make_byte(0))
	t.set('spawnMobs', nbt.make_byte(0))
	t.set('hasBeenLoadedInCreative', nbt.make_byte(if s.info.game_type == 1 { 1 } else { 0 }))
	t.set('eduLevel', nbt.make_byte(0))
	t.set('rainLevel', nbt.make_float(0))
	t.set('rainTime', nbt.make_int(100000))
	t.set('lightningLevel', nbt.make_float(0))
	t.set('lightningTime', nbt.make_int(100000))
	t.set('FlatWorldLayers', nbt.make_string(''))
	mut body := nbt.ByteWriter{}
	nbt.write_root(mut body, '', t)!
	mut file := nbt.ByteWriter{}
	file.i32le(10)
	file.i32le(body.buf.len)
	file.bytes(body.buf)
	tmp := os.join_path(s.dir, 'level.dat.tmp')
	os.write_file_array(tmp, file.buf)!
	os.mv(tmp, os.join_path(s.dir, 'level.dat'))!
	os.write_file(os.join_path(s.dir, 'levelname.txt'), s.info.name) or {}
}

fn (mut s LevelStore) read_level_dat() ! {
	data := os.read_bytes(os.join_path(s.dir, 'level.dat'))!
	mut r := nbt.new_reader(data)
	r.i32le()
	len := r.i32le()
	if !r.ok() || len < 0 || len > r.remaining() { return error('invalid level.dat header') }
	root := nbt.read_root(mut r)!
	t := root.tag
	if t.typ != .compound { return error('invalid level.dat root') }
	s.info.name = t.get_string('LevelName', s.info.name)
	s.info.seed = t.get_int('RandomSeed', 0)
	s.info.game_type = int(t.get_int('GameType', 1))
	s.info.spawn_x = int(t.get_int('SpawnX', 0))
	s.info.spawn_y = int(t.get_int('SpawnY', 100))
	s.info.spawn_z = int(t.get_int('SpawnZ', 0))
	s.info.time = t.get_int('Time', 1000)
	s.info.last_played = t.get_int('LastPlayed', 0)
	s.info.spawn_set = true
}
