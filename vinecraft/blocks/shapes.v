module blocks

fn box(x0 f32, y0 f32, z0 f32, x1 f32, y1 f32, z1 f32) Box {
	return Box{ min: [x0, y0, z0]!, max: [x1, y1, z1]! }
}

fn prop(key string, value string) JavaProp { return JavaProp{ key: key, value: value } }

fn derive_shape(mut b BlockInfo) {
	match b.def.kind {
		.air, .liquid, .cross {}
		.torch {
			f := state_str(b.states, 'torch_facing_direction', 'top')
			b.nbox = 1
			b.boxes[0] = match f {
				'east' { box(0, 0.219, 0.344, 0.344, 0.8125, 0.656) }
				'west' { box(0.656, 0.219, 0.344, 1, 0.8125, 0.656) }
				'south' { box(0.344, 0.219, 0, 0.656, 0.8125, 0.344) }
				'north' { box(0.344, 0.219, 0.656, 0.656, 0.8125, 1) }
				else { box(0.4375, 0, 0.4375, 0.5625, 0.625, 0.5625) }
			}
			if f != 'top' {
				b.java_override = 'wall_torch'
				b.java_props = [prop('facing', f)]
			}
		}
		.cactus {
			b.nbox = 1
			b.boxes[0] = box(0.0625, 0, 0.0625, 0.9375, 0.9375, 0.9375)
		}
		.slab {
			top := state_str(b.states, 'minecraft:vertical_half', 'bottom') == 'top'
			b.nbox = 1
			b.boxes[0] = if top { box(0, 0.5, 0, 1, 1, 1) } else { box(0, 0, 0, 1, 0.5, 1) }
			b.java_props = [prop('type', if top { 'top' } else { 'bottom' }),
				prop('waterlogged', 'false')]
		}
		.stairs {
			dir := state_int(b.states, 'weirdo_direction', 0) & 3
			up := state_int(b.states, 'upside_down_bit', 0) != 0
			b.java_props = [prop('facing', ['east', 'west', 'south', 'north'][dir]),
				prop('half', if up { 'top' } else { 'bottom' }), prop('shape', 'straight'),
				prop('waterlogged', 'false')]
			b.nbox = 2
			b.boxes[0] = if up { box(0, 0.5, 0, 1, 1, 1) } else { box(0, 0, 0, 1, 0.5, 1) }
			y0 := if up { f32(0) } else { f32(0.5) }
			y1 := if up { f32(0.5) } else { f32(1) }
			b.boxes[1] = match dir {
				0 { box(0.5, y0, 0, 1, y1, 1) }
				1 { box(0, y0, 0, 0.5, y1, 1) }
				2 { box(0, y0, 0.5, 1, y1, 1) }
				else { box(0, y0, 0, 1, y1, 0.5) }
			}
		}
		else {
			b.nbox = 1
			b.boxes[0] = box(0, 0, 0, 1, 1, 1)
		}
	}
	if b.def.kind == .column {
		b.java_props = [prop('axis', state_str(b.states, 'pillar_axis', 'y'))]
	}
	if b.def.kind == .grass { b.java_props = [prop('snowy', 'false')] }
	if b.def.kind == .liquid {
		depth := state_int(b.states, 'liquid_depth', 0)
		b.fluid_depth = u8(if depth < 0 {
			0
		} else if depth > 15 {
			15
		} else {
			depth
		})
	}
}
