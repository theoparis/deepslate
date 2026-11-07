module render

import math
import vinecraft.assets

pub enum UiMode {
	solid
	texture
	atlas
}

pub struct UiVertex {
pub:
	x     f32
	y     f32
	u     f32
	v     f32
	layer f32
	r     u8
	g     u8
	b     u8
	a     u8
}

pub struct UiBatch {
pub mut:
	mode     UiMode
	texture  u32
	vertices []UiVertex
}

pub struct UiTexture {
pub:
	id u32
	w  int
	h  int
}

pub struct Ui {
pub mut:
	scale       f32 = 2
	width       f32
	height      f32
	batches     []UiBatch
	font        UiTexture
	glyph_width [256]f32
}

pub fn (mut ui Ui) begin(width int, height int) {
	ui.scale = f32(math.min(4, math.max(1, math.floor(math.min(f32(width) / 320, f32(height) / 240)))))
	ui.width = f32(width) / ui.scale
	ui.height = f32(height) / ui.scale
	ui.batches.clear()
}

pub fn (mut ui Ui) set_font(tex UiTexture, img assets.Image) {
	ui.font = tex
	if img.w < 16 || img.w != img.h { return }
	cell := img.w / 16
	for c in 0 .. 256 {
		cx := c % 16 * cell
		cy := c / 16 * cell
		mut last := -1
		for x in 0 .. cell {
			for y in 0 .. cell {
				if img.rgba[((cy + y) * img.w + cx + x) * 4 + 3] > 0 { last = x }
			}
		}
		ui.glyph_width[c] = if c == 32 {
			f32(4)
		} else if last < 0 {
			f32(0)
		} else {
			f32(last + 1) * 8 / cell
		}
	}
}

pub fn (mut ui Ui) quad(mode UiMode, texture u32, p [4][2]f32, uv [4][2]f32, argb u32, layer f32) {
	if ui.batches.len == 0 || ui.batches.last().mode != mode || ui.batches.last().texture != texture {
		ui.batches << UiBatch{ mode: mode, texture: texture }
	}
	for k in [0, 1, 2, 2, 3, 0] {
		ui.batches[ui.batches.len - 1].vertices << UiVertex{p[k][0], p[k][1], uv[k][0], uv[k][1], layer, u8(argb >> 16), u8(argb >> 8), u8(argb), u8(argb >> 24)}
	}
}

pub fn (mut ui Ui) rect(x f32, y f32, w f32, h f32, argb u32) {
	ui.quad(.solid, 0, [[x, y]!, [x, y + h]!, [x + w, y + h]!, [x + w, y]!]!, [
		[f32(0), f32(0)]!,
		[f32(0), f32(1)]!,
		[f32(1), f32(1)]!,
		[f32(1), f32(0)]!,
	]!, argb, 0)
}

pub fn (mut ui Ui) outline(x f32, y f32, w f32, h f32, argb u32, t f32) {
	ui.rect(x, y, w, t, argb)
	ui.rect(x, y + h - t, w, t, argb)
	ui.rect(x, y + t, t, h - 2 * t, argb)
	ui.rect(x + w - t, y + t, t, h - 2 * t, argb)
}

pub fn (mut ui Ui) sprite(tex UiTexture, x f32, y f32, w f32, h f32, argb u32, u0 f32, v0 f32, u1 f32, v1 f32) {
	if tex.id == 0 { return }
	ui.quad(.texture, tex.id, [[x, y]!, [x, y + h]!, [x + w, y + h]!, [x + w, y]!]!, [
		[u0, v0]!,
		[u0, v1]!,
		[u1, v1]!,
		[u1, v0]!,
	]!, argb, 0)
}

pub fn (ui &Ui) text_width(s string, size f32) f32 {
	mut w := f32(0)
	for c in s.bytes() { w += (ui.glyph_width[c] + 1) * size }
	return if w > 0 { w - size } else { f32(0) }
}

fn (mut ui Ui) text_pass(s string, x f32, y f32, color u32, size f32) {
	mut cx := x
	for c in s.bytes() {
		gw := ui.glyph_width[c]
		if gw > 0 && c != 32 {
			u := f32(c % 16) / 16
			v := f32(c / 16) / 16
			ui.sprite(ui.font, cx, y, gw * size, 8 * size, color, u, v, u + gw / 128, v + f32(1) / 16)
		}
		cx += (gw + 1) * size
	}
}

pub fn (mut ui Ui) text(s string, x f32, y f32, color u32, shadow bool, size f32) {
	if ui.font.id == 0 { return }
	if shadow {
		ui.text_pass(s, x + size, y + size, (color & 0xff000000) | ((color & 0xfcfcfc) >> 2), size)
	}
	ui.text_pass(s, x, y, color, size)
}
