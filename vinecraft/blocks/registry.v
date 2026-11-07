module blocks

import sync

@[heap]
pub struct Registry {
mut:
	mutex    sync.Mutex
	infos    []BlockInfo
	by_key   map[string]BlockId
	defaults map[string]BlockId
	defs     map[string]BlockDef
	listener ?fn (BlockId)
}

pub fn sort_states(mut states StateMap) { states.sort(a.key < b.key) }

pub fn state_key(name string, states StateMap) string {
	mut key := name
	for e in states {
		value := match e.value.kind {
			.byte_value { 'b${e.value.i}' }
			.int_value { 'i${e.value.i}' }
			.string_value { 's${e.value.s}' }
		}
		key += '|${e.key}=${value}'
	}
	return key
}

pub fn find_state(states StateMap, key string) ?StateValue {
	for e in states { if e.key == key { return e.value } }
	return none
}

fn state_int(states StateMap, key string, fallback int) int {
	v := find_state(states, key) or { return fallback }
	return v.i
}

fn state_str(states StateMap, key string, fallback string) string {
	v := find_state(states, key) or { return fallback }
	return if v.kind == .string_value { v.s } else { fallback }
}

fn full_name(n string) string { return if n.contains(':') { n } else { 'minecraft:${n}' } }

fn short_name(n string) string { return if n.starts_with('minecraft:') { n[10..] } else { n } }

fn entry(key string, value StateValue) StateEntry { return StateEntry{ key: key, value: value } }

pub fn new_registry() &Registry {
	mut r := &Registry{}
	defs := builtin_defs()
	for d in defs { r.defs[d.name] = d }
	r.add('minecraft:air', [])
	for d in defs {
		if d.name == 'air' { continue }
		n := full_name(d.name)
		match d.kind {
			.column {
				for a in ['y', 'x', 'z'] { r.add(n, [entry('pillar_axis', state_string(a))]) }
			}
			.slab {
				for a in ['bottom', 'top'] {
					r.add(n, [entry('minecraft:vertical_half', state_string(a))])
				}
			}
			.stairs {
				for up in 0 .. 2 {
					for dir in 0 .. 4 {
						r.add(n, [entry('upside_down_bit', state_byte(up)),
							entry('weirdo_direction', state_int_value(dir))])
					}
				}
			}
			.liquid {
				for depth in 0 .. 9 { r.add(n, [entry('liquid_depth', state_int_value(depth))]) }
			}
			.torch {
				for a in ['top', 'west', 'east', 'north', 'south'] {
					r.add(n, [entry('torch_facing_direction', state_string(a))])
				}
			}
			else {
				if d.flags & bf_leaves != 0 {
					r.add(n, [entry('persistent_bit', state_byte(0)),
						entry('update_bit', state_byte(0))])
				} else {
					r.add(n, [])
				}
			}
		}
	}
	return r
}

fn guess_flags(n string) u32 {
	if n.contains('leaves') { return bf_solid | bf_cutout | bf_leaves | bf_unknown }
	if n.contains('glass') || (n.contains('ice') && !n.contains('packed') && !n.contains('blue')) {
		return bf_solid | bf_cutout | bf_unknown
	}
	for word in ['torch', 'flower', 'sapling', 'grass', 'fern', 'vine', 'tulip', 'mushroom', 'bush',
		'orchid', 'allium', 'bluet', 'daisy', 'cornflower', 'lily', 'coral', 'kelp', 'seagrass',
		'rail', 'redstone_wire', 'lever', 'button', 'sign', 'banner', 'carpet', 'pressure_plate',
		'web', 'fire', 'crop', 'wheat', 'carrots', 'potatoes'] {
		if n.contains(word) {
			mut f := bf_plant | bf_cutout | bf_unknown
			if n.contains('grass') || n.contains('fern') || n.contains('vine') || n.contains('bush') {
				f |= bf_replaceable
			}
			return f
		}
	}
	for word in ['slab', 'stairs', 'fence', 'wall', 'door', 'trapdoor', 'bed', 'chest', 'lantern',
		'candle', 'pane', 'bars', 'anvil'] {
		if n.contains(word) { return bf_solid | bf_cutout | bf_unknown }
	}
	if n.contains('water') || n.contains('lava') { return bf_liquid | bf_unknown }
	return bf_solid | bf_opaque | bf_unknown
}

fn (mut r Registry) add(name string, input StateMap) BlockId {
	mut states := input.clone()
	sort_states(mut states)
	key := state_key(name, states)
	if key in r.by_key { return r.by_key[key] }
	if r.infos.len >= 65535 { return 0 }
	short := short_name(name)
	unknown := short !in r.defs
	def := if unknown {
		BlockDef{ name: 'unknown', display: 'Unknown Block', flags: bf_solid | bf_opaque | bf_unknown, color: 0xc030c0, creative: false }
	} else {
		r.defs[short]
	}
	mut bi := BlockInfo{
		name:    name
		states:  states
		def:     def
		flags:   if unknown {
			guess_flags(short)
		} else {
			def.flags
		}
		emit:    def.emit
		tint:    def.tint
		display: if unknown { name } else { def.display }
		color:   def.color
	}
	derive_shape(mut bi)
	id := BlockId(r.infos.len)
	r.infos << bi
	r.by_key[key] = id
	if name !in r.defaults { r.defaults[name] = id }
	return id
}

pub fn (mut r Registry) lookup_or_register(name string, states StateMap) BlockId {
	r.mutex.@lock()
	before := r.infos.len
	id := r.add(name, states)
	listener := r.listener
	changed := r.infos.len != before
	r.mutex.unlock()
	if changed {
		if callback := listener { callback(id) }
	}
	return id
}

pub fn (mut r Registry) set_listener(callback ?fn (BlockId)) {
	r.mutex.@lock()
	r.listener = callback
	r.mutex.unlock()
}

pub fn (r &Registry) find(name string) BlockId {
	mut rr := unsafe { &Registry(r) }
	rr.mutex.@lock()
	defer { rr.mutex.unlock() }
	return rr.defaults[full_name(name)] or { 0 }
}

pub fn (r &Registry) info(id BlockId) BlockInfo {
	mut rr := unsafe { &Registry(r) }
	rr.mutex.@lock()
	defer { rr.mutex.unlock() }
	return rr.infos[int(id)]
}

pub fn (r &Registry) count() int {
	mut rr := unsafe { &Registry(r) }
	rr.mutex.@lock()
	defer { rr.mutex.unlock() }
	return rr.infos.len
}
