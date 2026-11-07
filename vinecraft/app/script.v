module app

import math
import vinecraft.blocks
import vinecraft.gameplay

// ScriptHost is implemented by the running game; the driver keeps waits and
// frame-based movement independent of the event loop's frame rate.
pub interface ScriptHost {
	world_settled() bool
	get_block(x int, y int, z int) blocks.BlockId
	block_name(id blocks.BlockId) string
	column_loaded(cx int, cz int) bool
	player() &gameplay.Player
	target() gameplay.RayHit
mut:
	set_block(x int, y int, z int, name string, states blocks.StateMap) bool
	break_block()
	place_block()
	select_slot(slot int)
	set_time(ticks i64)
	freeze_time()
	toggle_inventory()
	set_radius(radius int)
	save()
	show_debug()
	request_screenshot(path string)
	quit()
}

pub struct Script {
mut:
	actions         []string
	next            int
	wait_frames     int
	waiting_idle    bool
	waiting_ground  bool
	deadline        f64
	movement        gameplay.MoveInput
	movement_frames int
	mark            [3]int
pub mut:
	failures int
}

pub fn new_script(text string) Script {
	mut actions := []string{}
	for action in text.split(';') {
		t := action.trim_space()
		if t != '' { actions << t }
	}
	return Script{ actions: actions }
}

fn arg(args []string, i int, fallback f64) f64 {
	if i >= args.len { return fallback }
	return args[i].f64()
}

fn name(host ScriptHost, id blocks.BlockId) string {
	n := host.block_name(id)
	return if n.starts_with('minecraft:') { n[10..] } else { n }
}

fn (mut s Script) check(label string, ok bool, got string) {
	if ok {
		println('script: ${label} : PASS')
	} else {
		println('script: ${label} : FAIL (got ${got})')
		s.failures++
	}
}

// advance executes instantaneous actions until it reaches a wait. A returned
// movement input overrides physical input for exactly one frame.
pub fn (mut s Script) advance(mut host ScriptHost, now f64, screenshot_pending bool) ?gameplay.MoveInput {
	if screenshot_pending { return none }
	if s.wait_frames > 0 {
		s.wait_frames--
		return none
	}
	if s.waiting_idle {
		if host.world_settled() || now > s.deadline {
			if now > s.deadline { eprintln('script: idle timeout') }
			s.waiting_idle = false
			s.wait_frames = 2
		}
		return none
	}
	if s.movement_frames > 0 {
		s.movement_frames--
		return s.movement
	}
	if s.waiting_ground {
		if host.player().on_ground || now > s.deadline {
			s.waiting_ground = false
			s.wait_frames = 2
		}
		return none
	}
	for s.next < s.actions.len {
		line := s.actions[s.next]
		s.next++
		a := line.fields()
		if a.len == 0 { continue }
		match a[0] {
			'wait' {
				s.wait_frames = int(arg(a, 1, 1))
				return none
			}
			'ground' {
				s.waiting_ground = true
				s.deadline = now + 30
				return none
			}
			'idle' {
				s.waiting_idle = true
				s.deadline = now + 180
				return none
			}
			'shot' {
				if a.len > 1 {
					host.request_screenshot(a[1])
					return none
				}
			}
			'tp', 'nudge' {
				mut p := host.player()
				v := gameplay.Vec3{ x: arg(a, 1, 0), y: arg(a, 2, 0), z: arg(a, 3, 0) }
				if a[0] == 'tp' {
					p.pos = v
				} else {
					p.pos.x += v.x
					p.pos.y += v.y
					p.pos.z += v.z
				}
				p.vel = gameplay.Vec3{}
			}
			'setblock' {
				x := int(arg(a, 1, 0))
				y := int(arg(a, 2, 0))
				z := int(arg(a, 3, 0))
				mut states := blocks.StateMap{}
				if a.len > 5 {
					for kv in a[5..] {
						parts := kv.split_nth('=', 2)
						if parts.len != 2 { continue }
						v := parts[1]
						mut numeric := v.len > 0
						for c in v.bytes() { if c < `0` || c > `9` { numeric = false } }
						value := if numeric {
							if parts[0].ends_with('_bit') {
								blocks.state_byte(v.int())
							} else {
								blocks.state_int_value(v.int())
							}
						} else {
							blocks.state_string(v)
						}
						states << blocks.StateEntry{ key: parts[0], value: value }
					}
				}
				block := if a.len > 4 { a[4] } else { '' }
				if !host.set_block(x, y, z, block, states) && !host.column_loaded(int(math.floor(f64(x) / 16)), int(math.floor(f64(z) / 16))) {
					eprintln('script: setblock outside loaded area')
				}
			}
			'mark' {
				h := host.target()
				if !h.hit {
					println('script: mark FAIL (no target)')
					s.failures++
				} else {
					s.mark = [h.x, h.y, h.z]!
					println('script: MARK ${h.x} ${h.y} ${h.z}')
				}
			}
			'assert_marked' {
				want := if a.len > 1 { a[1] } else { '' }
				got := name(host, host.get_block(s.mark[0], s.mark[1], s.mark[2]))
				s.check('assert_marked ${want}', got == want, got)
			}
			'look' {
				mut p := host.player()
				p.yaw = f32(arg(a, 1, 0) * math.pi / 180)
				p.pitch = f32(arg(a, 2, 0) * math.pi / 180)
			}
			'break' { host.break_block() }
			'place' { host.place_block() }
			'select' { host.select_slot(int(arg(a, 1, 0))) }
			'time' { host.set_time(i64(arg(a, 1, 0))) }
			'freeze' { host.freeze_time() }
			'fly' {
				mut p := host.player()
				p.flying = a.len > 1 && a[1] == 'on'
			}
			'walk', 'jump' {
				if a[0] == 'walk' {
					s.movement = gameplay.MoveInput{ forward: f32(arg(a, 1, 0)), strafe: f32(arg(a, 2, 0)) }
					s.movement_frames = int(arg(a, 3, 1))
				} else {
					s.movement = gameplay.MoveInput{ jump: true }
					s.movement_frames = int(arg(a, 1, 1))
				}
				if s.movement_frames > 0 { return none }
			}
			'inv' { host.toggle_inventory() }
			'radius' { host.set_radius(int(math.max(2, math.min(32, arg(a, 1, 0))))) }
			'save' { host.save() }
			'debug' { host.show_debug() }
			'where' {
				p := host.player()
				h := host.target()
				println('script: pos ${p.pos.x:.3f} ${p.pos.y:.3f} ${p.pos.z:.3f} yaw ${p.yaw * 57.29578:.1f} pitch ${p.pitch * 57.29578:.1f} ground ${p.on_ground}')
				if h.hit {
					println('script: target ${h.x} ${h.y} ${h.z} face ${h.face} = ${host.block_name(host.get_block(h.x, h.y, h.z))}')
				} else {
					println('script: no target')
				}
			}
			'assert_hit' { s.check('assert_hit', host.target().hit, 'no target') }
			'quit' { host.quit() }
			'log' { println('script: ${line[3..].trim_space()}') }
			'assert_block' {
				x := int(arg(a, 1, 0))
				y := int(arg(a, 2, 0))
				z := int(arg(a, 3, 0))
				want := if a.len > 4 { a[4] } else { '' }
				got := name(host, host.get_block(x, y, z))
				s.check('assert_block ${x} ${y} ${z} == ${want}', got == want, got)
			}
			'assert_target' {
				want := if a.len > 1 { a[1] } else { '' }
				h := host.target()
				got := if h.hit { name(host, host.get_block(h.x, h.y, h.z)) } else { 'none' }
				s.check('assert_target ${want}', got == want, got)
			}
			'assert_ground' { s.check('assert_ground', host.player().on_ground, 'airborne') }
			else { eprintln('script: unknown action ${line}') }
		}
	}
	return none
}
