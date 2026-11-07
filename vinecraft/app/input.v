module app

import math
import os
import time
import sokol.sapp
import vinecraft.blocks
import vinecraft.gameplay

pub struct Input {
pub mut:
	keys             [512]bool
	left             bool
	right            bool
	mouse_x          f32
	mouse_y          f32
	dx               f32
	dy               f32
	last_w           f64 = -10
	last_space       f64 = -10
	sprint_latch     bool
	inventory_scroll int
}

fn (i Input) key(k sapp.KeyCode) bool { return i.keys[int(k)] }

pub fn (mut i Input) event(mut g Game, e &sapp.Event, now f64, ui_width f32, ui_height f32, ui_scale f32, creative []blocks.BlockId) {
	match e.@type {
		.unfocused {
			if g.screen == .playing {
				g.screen = .pause
				sapp.lock_mouse(false)
			}
			i.keys = [512]bool{}
			i.left = false
			i.right = false
		}
		.quit_requested { g.quit_requested = true }
		.mouse_move {
			i.mouse_x = e.mouse_x
			i.mouse_y = e.mouse_y
			if g.screen == .playing {
				i.dx += e.mouse_dx
				i.dy += e.mouse_dy
			}
		}
		.mouse_scroll {
			if g.screen == .playing {
				if e.scroll_y > 0 {
					g.select_slot(g.selected - 1)
				} else if e.scroll_y < 0 {
					g.select_slot(g.selected + 1)
				}
			} else if g.screen == .inventory {
				i.inventory_scroll = int(math.max(0, i.inventory_scroll - int(e.scroll_y)))
			}
		}
		.mouse_down {
			if g.screen == .playing {
				match e.mouse_button {
					.left {
						i.left = true
						g.break_cooldown = 0
					}
					.right {
						i.right = true
						g.place_cooldown = 0
					}
					.middle { g.pick_block() }
					else {}
				}
			} else if g.screen == .inventory || g.screen == .pause {
				x := e.mouse_x / ui_scale
				y := e.mouse_y / ui_scale
				if g.screen == .inventory {
					px := math.floor((ui_width - 176) / 2)
					py := math.floor((ui_height - 166) / 2)
					for r in 0 .. 5 {
						for c in 0 .. 9 {
							idx := (r + i.inventory_scroll) * 9 + c
							sx := px + 8 + c * 18
							sy := py + 18 + r * 18
							if idx < creative.len && x >= sx && x < sx + 18 && y >= sy && y < sy + 18 {
								g.hotbar[g.selected] = creative[idx]
								g.name_timer = 2
							}
						}
					}
					for n in 0 .. 9 {
						sx := px + 8 + n * 18
						sy := py + 142
						if x >= sx && x < sx + 18 && y >= sy && y < sy + 18 {
							if e.mouse_button == .right {
								g.hotbar[n] = 0
							} else {
								g.select_slot(n)
							}
						}
					}
				} else {
					bx := math.floor((ui_width - 200) / 2)
					if x >= bx && x < bx + 200 {
						if y >= ui_height / 2 - 24 && y < ui_height / 2 - 4 {
							g.screen = .playing
							sapp.lock_mouse(true)
						} else if y >= ui_height / 2 + 4 && y < ui_height / 2 + 24 {
							g.quit_requested = true
						}
					}
				}
			}
		}
		.mouse_up {
			if e.mouse_button == .left { i.left = false }
			if e.mouse_button == .right { i.right = false }
		}
		.key_up {
			if int(e.key_code) < i.keys.len { i.keys[int(e.key_code)] = false }
			if e.key_code == .w { i.sprint_latch = false }
		}
		.key_down {
			if int(e.key_code) < i.keys.len { i.keys[int(e.key_code)] = true }
			if e.key_repeat { return }
			if g.screen == .playing && e.key_code == .w {
				if now - i.last_w < 0.3 { i.sprint_latch = true }
				i.last_w = now
			}
			if g.screen == .playing && e.key_code == .space && g.player_state.creative {
				if now - i.last_space < 0.3 {
					g.player_state.flying = !g.player_state.flying
					g.player_state.vel.y = 0
				}
				i.last_space = now
			}
			match e.key_code {
				.escape {
					if g.screen == .playing {
						g.screen = .pause
						sapp.lock_mouse(false)
					} else if g.screen == .pause || g.screen == .inventory {
						g.screen = .playing
						sapp.lock_mouse(true)
					}
				}
				.e {
					if g.screen == .playing || g.screen == .inventory {
						g.toggle_inventory()
						sapp.lock_mouse(g.screen == .playing)
					}
				}
				.f1 { g.show_hud = !g.show_hud }
				.f3 { g.show_debug_info = !g.show_debug_info }
				.f2 {
					os.mkdir_all('screenshots') or { eprintln(err) }
					g.pending_screenshot = 'screenshots/${time.now().format_ss().replace(':', '.').replace(' ', '_')}.png'
					g.toast = 'Saved ${g.pending_screenshot}'
					g.toast_timer = 3
				}
				.f11 { sapp.toggle_fullscreen() }
				else {
					if g.screen == .playing {
						k := int(e.key_code)
						if k >= int(sapp.KeyCode._1) && k <= int(sapp.KeyCode._9) {
							g.select_slot(k - int(sapp.KeyCode._1))
						} else {
							match e.key_code {
								.minus {
									g.radius = int(math.max(2, g.radius - 1))
									g.toast = 'Render distance: ${g.radius}'
									g.toast_timer = 2
								}
								.equal {
									g.radius = int(math.min(32, g.radius + 1))
									g.toast = 'Render distance: ${g.radius}'
									g.toast_timer = 2
								}
								.page_up { g.ticks += 1000 }
								.page_down { g.ticks -= 1000 }
								.t {
									g.frozen = !g.frozen
									g.toast = if g.frozen { 'Time frozen' } else { 'Time running' }
									g.toast_timer = 2
								}
								else {}
							}
						}
					}
				}
			}
		}
		else {}
	}
}

pub fn (mut i Input) movement(mut g Game) gameplay.MoveInput {
	if g.screen != .playing {
		i.dx = 0
		i.dy = 0
		return gameplay.MoveInput{}
	}
	g.player_state.yaw += i.dx * 0.0022
	g.player_state.pitch = f32(math.max(-1.553, math.min(1.553, g.player_state.pitch + i.dy * 0.0022)))
	i.dx = 0
	i.dy = 0
	return gameplay.MoveInput{
		forward: f32((if i.key(.w) { 1 } else { 0 }) - (if i.key(.s) { 1 } else { 0 }))
		strafe:  f32((if i.key(.d) { 1 } else { 0 }) - (if i.key(.a) { 1 } else { 0 }))
		jump:    i.key(.space)
		sneak:   i.key(.left_shift) || i.key(.right_shift)
		sprint:  i.key(.left_control) || i.sprint_latch
	}
}
