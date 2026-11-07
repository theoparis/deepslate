module app

import math
import vinecraft.blocks
import vinecraft.models
import vinecraft.render

pub fn creative_blocks(reg &blocks.Registry) []blocks.BlockId {
	mut out := []blocks.BlockId{}
	for d in blocks.builtin_defs() {
		if d.kind != .air && d.creative {
			id := reg.find(d.name)
			if id != 0 { out << id }
		}
	}
	return out
}

fn centered(mut ui render.Ui, text string, y f32, color u32, shadow bool) {
	ui.text(text, f32(math.floor((ui.width - ui.text_width(text, 1)) / 2)), y, color, shadow, 1)
}

pub fn draw_ui(mut ui render.Ui, mut g Game, mut block_models models.BlockModels, atlas u32, stats render.RenderStats, mut input Input, creative []blocks.BlockId) {
	w := ui.width
	h := ui.height
	if g.screen == .loading {
		centered(mut ui, 'Generating terrain...', f32(math.floor(h / 2 - 4)), 0xffffffff, true)
		centered(mut ui, '${g.world.loaded_count()} chunks loaded', f32(math.floor(h / 2 + 8)), 0xffaaaaaa, true)
		return
	}
	if g.player_state.eyes_in_water { ui.rect(0, 0, w, h, 0x502040c0) }
	if g.show_hud {
		if g.screen == .playing {
			ui.rect(f32(math.floor(w / 2)) - 5, f32(math.floor(h / 2)) - 1, 11, 1, 0xc0ffffff)
			ui.rect(f32(math.floor(w / 2)), f32(math.floor(h / 2)) - 6, 1, 11, 0xc0ffffff)
		}
		hx := f32(math.floor((w - 182) / 2))
		hy := h - 23
		ui.rect(hx, hy, 182, 22, 0xa0000000)
		ui.outline(hx, hy, 182, 22, 0xff555555, 1)
		for n in 1 .. 9 { ui.rect(hx + n * 20, hy + 2, 1, 18, 0x60ffffff) }
		for n, id in g.hotbar {
			if id != 0 {
				ui.block_icon(id, hx + 3 + n * 20, hy + 3, 16, atlas, g.registry, mut block_models)
			}
		}
		ui.outline(hx + g.selected * 20, hy - 1, 24, 24, 0xffffffff, 2)
		if g.name_timer > 0 {
			id := g.hotbar[g.selected]
			label := if id != 0 { g.registry.info(id).display } else { '' }
			a := u32(math.min(1, g.name_timer / 0.5) * 255)
			centered(mut ui, label, hy - 14, (a << 24) | 0xffffff, true)
		}
		if g.toast_timer > 0 { ui.text(g.toast, 4, h - 12, 0xffffff55, true, 1) }
		if g.show_debug_info {
			p := g.player_state.pos
			bx := int(math.floor(p.x))
			by := int(math.floor(p.y))
			bz := int(math.floor(p.z))
			cx := int(math.floor(f64(bx) / 16))
			cz := int(math.floor(f64(bz) / 16))
			lx := bx - cx * 16
			lz := bz - cz * 16
			mut biome := u8(0)
			if chunk := g.world.get_chunk(cx, cz) { biome = chunk.biome[blocks.col_index(lx, lz)] }
			dirs := ['south (+Z)', 'west (-X)', 'north (-Z)', 'east (+X)']!
			direction := int(math.floor(math.fmod(g.player_state.yaw * 180 / math.pi + 3645, 360) / 90)) & 3
			mut lines := [
				'Deepslate Edition 0.1 (${g.fps:.0f} fps, ${g.frame_ms:.1f} ms)',
				'XYZ: ${p.x:.3f} / ${p.y:.3f} / ${p.z:.3f}',
				'Block: ${bx} ${by} ${bz}  Chunk: ${lx} ${lz} in ${cx} ${cz}',
				'Facing: ${dirs[direction]}  Biome id: ${biome}',
				'Chunks: ${g.world.loaded_count()} loaded, ${g.world.inflight_count()} in flight, gen ${g.world.chunks_generated()} / disk ${g.world.chunks_loaded_from_disk()}, write queue ${g.world.writer_queue()}',
				'Sections: ${stats.sections} (${stats.drawn} drawn, ${stats.quads / 1000}k quads), meshing ${stats.in_flight} / pending ${stats.pending}',
				'Render distance: ${g.radius}  Threads: ${g.threads}  Time: ${g.ticks % 24000} (${if g.frozen {
					'frozen'
				} else {
					'running'
				}})',
				'Seed: ${g.store.info.seed}  ${if g.player_state.flying { 'flying ' } else { '' }}${if g.player_state.on_ground {
					'on ground'
				} else {
					'airborne'
				}}',
			]
			if g.hit.hit {
				lines << 'Targeting: ${g.registry.info(g.world.get_block(g.hit.x, g.hit.y, g.hit.z)).name} (${g.hit.x} ${g.hit.y} ${g.hit.z})'
			}
			mut y := f32(3)
			for line in lines {
				ui.rect(2, y - 1, ui.text_width(line, 1) + 3, 10, 0x60000000)
				ui.text(line, 3, y, 0xffe0e0e0, true, 1)
				y += 10
			}
		}
	}
	if g.screen == .inventory {
		ui.rect(0, 0, w, h, 0x90000000)
		px := f32(math.floor((w - 176) / 2))
		py := f32(math.floor((h - 166) / 2))
		ui.rect(px, py, 176, 166, 0xffc6c6c6)
		ui.outline(px, py, 176, 166, 0xff000000, 1)
		ui.text('Creative Inventory', px + 8, py + 6, 0xff404040, false, 1)
		gx := input.mouse_x / ui.scale
		gy := input.mouse_y / ui.scale
		mut hovered := blocks.BlockId(0)
		for r in 0 .. 5 {
			for c in 0 .. 9 {
				idx := (r + input.inventory_scroll) * 9 + c
				x := px + 8 + c * 18
				y := py + 18 + r * 18
				ui.rect(x, y, 18, 18, 0xff8b8b8b)
				ui.rect(x + 1, y + 1, 17, 17, 0xffdbdbdb)
				ui.rect(x + 1, y + 1, 16, 16, 0xff8b8b8b)
				if idx < creative.len {
					ui.block_icon(creative[idx], x + 1, y + 1, 16, atlas, g.registry, mut block_models)
					if gx >= x && gx < x + 18 && gy >= y && gy < y + 18 {
						ui.rect(x + 1, y + 1, 16, 16, 0x80ffffff)
						hovered = creative[idx]
					}
				}
			}
		}
		max_scroll := int(math.max(0, (creative.len + 8) / 9 - 5))
		input.inventory_scroll = int(math.min(input.inventory_scroll, max_scroll))
		if max_scroll > 0 {
			thumb := f32(math.max(8, 90.0 * 5 / (max_scroll + 5)))
			ty := py + 18 + (90 - thumb) * input.inventory_scroll / max_scroll
			ui.rect(px + 173, py + 18, 4, 90, 0xff8b8b8b)
			ui.rect(px + 173, ty, 4, thumb, 0xff404040)
		}
		for n in 0 .. 9 {
			x := px + 8 + n * 18
			y := py + 142
			ui.rect(x, y, 18, 18, if n == g.selected { 0xffffffff } else { 0xff373737 })
			ui.rect(x + 1, y + 1, 16, 16, 0xff8b8b8b)
			if g.hotbar[n] != 0 {
				ui.block_icon(g.hotbar[n], x + 1, y + 1, 16, atlas, g.registry, mut block_models)
			}
		}
		ui.text('Click: set selected slot', px + 8, py + 112, 0xff404040, false, 1)
		ui.text('Right-click a slot: clear it', px + 8, py + 124, 0xff404040, false, 1)
		if hovered != 0 {
			label := g.registry.info(hovered).display
			ui.rect(gx + 6, gy - 14, ui.text_width(label, 1) + 6, 12, 0xf0100010)
			ui.text(label, gx + 9, gy - 12, 0xffffffff, true, 1)
		}
	}
	if g.screen == .pause {
		ui.rect(0, 0, w, h, 0xa0000000)
		bx := f32(math.floor((w - 200) / 2))
		centered(mut ui, 'Game Menu', h / 2 - 50, 0xffffffff, true)
		for idx, label in ['Back to Game', 'Save and Quit'] {
			y := h / 2 - 24 + idx * 28
			ui.rect(bx, y, 200, 20, 0xff000000)
			ui.rect(bx + 1, y + 1, 198, 18, 0xff6f6f6f)
			ui.rect(bx + 1, y + 1, 198, 1, 0xffa0a0a0)
			ui.text(label, f32(math.floor(bx + (200 - ui.text_width(label, 1)) / 2)), y + 6, 0xffffffff, true, 1)
		}
	}
}
