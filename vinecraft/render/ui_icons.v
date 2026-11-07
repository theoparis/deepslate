module render

import vinecraft.blocks
import vinecraft.models

fn icon_color(rgb u32, shade f32) u32 {
	r := u32(f32((rgb >> 16) & 255) * shade)
	g := u32(f32((rgb >> 8) & 255) * shade)
	b := u32(f32(rgb & 255) * shade)
	return u32(0xff000000) | (r << 16) | (g << 8) | b
}

pub fn (mut ui Ui) block_icon(id blocks.BlockId, x f32, y f32, size f32, atlas u32, reg &blocks.Registry, mut model models.BlockModels) {
	icon := model.icon(id)
	info := reg.info(id)
	top_tint := if info.tint == .none {
		u32(0xffffff)
	} else {
		model.tint_color(info.tint, blocks.biome_plains)
	}
	side_tint := if info.def.kind == .grass { u32(0xffffff) } else { top_tint }
	uv := [[f32(0), f32(0)]!, [f32(0), f32(1)]!, [f32(1), f32(1)]!, [f32(1), f32(0)]!]!
	if icon.flat {
		ui.quad(.atlas, atlas, [[x, y]!, [x, y + size]!, [x + size, y + size]!, [x + size, y]!]!, uv, icon_color(top_tint, 1), f32(icon.top))
		return
	}
	top := [x + size / 2, y]!
	tl := [x, y + size * 0.25]!
	tr := [x + size, y + size * 0.25]!
	center := [x + size / 2, y + size * 0.5]!
	bl := [x, y + size * 0.75]!
	br := [x + size, y + size * 0.75]!
	bottom := [x + size / 2, y + size]!
	top_uv := [[f32(1), f32(0)]!, [f32(0), f32(0)]!, [f32(0), f32(1)]!, [f32(1), f32(1)]!]!
	ui.quad(.atlas, atlas, [top, tl, center, tr]!, top_uv, icon_color(top_tint, 1), f32(icon.top))
	ui.quad(.atlas, atlas, [tl, bl, bottom, center]!, uv, icon_color(side_tint, 0.82), f32(icon.left))
	ui.quad(.atlas, atlas, [center, bottom, br, tr]!, uv, icon_color(side_tint, 0.62), f32(icon.right))
}
