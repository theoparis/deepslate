module storage

import vinecraft.nbt
import leveldb

pub fn (mut s LevelStore) save_player(p PlayerData) ! {
	s.mutex.@lock()
	defer { s.mutex.unlock() }
	if s.read_only { return error('read-only world') }
	mut t := nbt.make_compound()
	mut pos := nbt.make_list(.float_tag)
	for d in p.pos { pos.list << nbt.make_float(d) }
	t.set('Pos', pos)
	mut rot := nbt.make_list(.float_tag)
	rot.list << nbt.make_float(p.yaw)
	rot.list << nbt.make_float(p.pitch)
	t.set('Rotation', rot)
	mut mot := nbt.make_list(.float_tag)
	for _ in 0 .. 3 { mot.list << nbt.make_float(0) }
	t.set('Motion', mot)
	t.set('OnGround', nbt.make_byte(0))
	t.set('Health', nbt.make_short(20))
	t.set('DimensionId', nbt.make_int(0))
	t.set('UniqueID', nbt.make_long(1))
	mut ab := nbt.make_compound()
	ab.set('flying', nbt.make_byte(if p.flying { 1 } else { 0 }))
	ab.set('mayfly', nbt.make_byte(1))
	t.set('abilities', ab)
	t.set('SelectedInventorySlot', nbt.make_int(p.selected))
	mut inv := nbt.make_list(.compound)
	for i, slot in p.hotbar {
		mut e := nbt.make_compound()
		e.set('Slot', nbt.make_byte(i))
		e.set('Count', nbt.make_byte(if slot.block == '' { 0 } else { slot.count }))
		e.set('Damage', nbt.make_short(0))
		e.set('Name', nbt.make_string(slot.block))
		inv.list << e
	}
	t.set('Inventory', inv)
	mut w := nbt.ByteWriter{}
	nbt.write_root(mut w, '', t)!
	s.db.put('~local_player'.bytes(), w.buf, leveldb.WriteOptions{})!
}

pub fn (mut s LevelStore) load_player() !PlayerData {
	s.mutex.@lock()
	defer { s.mutex.unlock() }
	value := s.db.get('~local_player'.bytes(), leveldb.ReadOptions{})!
	if !value.found { return error('player not found') }
	mut r := nbt.new_reader(value.value)
	t := nbt.read_root(mut r)!.tag
	pos := t.find('Pos') or { return error('player position missing') }
	if pos.list.len < 3 { return error('player position truncated') }
	mut p := PlayerData{ hotbar: []InventorySlot{len: 9} }
	for i in 0 .. 3 { p.pos[i] = pos.list_num(i, 0) }
	if rot := t.find('Rotation') {
		p.yaw = f32(rot.list_num(0, 0))
		p.pitch = f32(rot.list_num(1, 0))
	}
	if ab := t.find('abilities') { p.flying = ab.get_int('flying', 0) != 0 }
	p.selected = int(t.get_int('SelectedInventorySlot', 0))
	if inv := t.find('Inventory') {
		for e in inv.list {
			slot := int(e.get_int('Slot', -1))
			if slot >= 0 && slot < 9 {
				p.hotbar[slot] = InventorySlot{ block: e.get_string('Name', ''), count: int(e.get_int('Count', 0)) }
			}
		}
	}
	return p
}
