module app

import math
import vinecraft.cli
import vinecraft.gameplay
import vinecraft.storage
import vinecraft.worldgen

// place_player restores a player or chooses the same dry, level spawn as the
// original game. The actual surface is resolved after the spawn chunks load.
pub fn place_player(mut info storage.LevelInfo, gen &worldgen.WorldGen, saved ?storage.PlayerData, opt cli.Options) gameplay.Player {
	mut player := gameplay.Player{}
	if pd := saved {
		player.pos = gameplay.Vec3{ x: pd.pos[0], y: pd.pos[1], z: pd.pos[2] }
		player.yaw = pd.yaw * f32(math.pi / 180.0)
		player.pitch = pd.pitch * f32(math.pi / 180.0)
		player.flying = pd.flying
	} else {
		mut sx := info.spawn_x
		mut sz := info.spawn_z
		if !info.spawn_set {
			mut found := false
			mut fallback := false
			mut fx := 0
			mut fz := 0
			for r := 0; r < 80 && !found; r++ {
				count := if r * 8 > 1 { r * 8 } else { 1 }
				for k := 0; k < count && !found; k++ {
					a := f64(k) * 6.2831853 / f64(count)
					x := int(math.cos(a) * r * 6)
					z := int(math.sin(a) * r * 6)
					h := gen.surface_height(x, z)
					if h <= worldgen.sea_level + 1 || h >= 100 { continue }
					if !fallback {
						fx = x
						fz = z
						fallback = true
					}
					mut lo := h
					mut hi := h
					for d in [[5, 0]!, [-5, 0]!, [0, 5]!, [0, -5]!] {
						hh := gen.surface_height(x + d[0], z + d[1])
						if hh < lo { lo = hh }
						if hh > hi { hi = hh }
					}
					if hi - lo <= 2 && lo > worldgen.sea_level {
						sx = x
						sz = z
						found = true
					}
				}
			}
			if !found && fallback {
				sx = fx
				sz = fz
			}
			info.spawn_x = sx
			info.spawn_z = sz
			info.spawn_y = gen.surface_height(sx, sz) + 1
			info.spawn_set = true
		}
		player.pos = gameplay.Vec3{ x: f64(sx) + 0.5, y: f64(info.spawn_y) + 0.01, z: f64(sz) + 0.5 }
		player.pitch = 0.2
	}
	if pos := opt.start_pos { player.pos = gameplay.Vec3{ x: pos[0], y: pos[1], z: pos[2] } }
	if yaw := opt.yaw { player.yaw = yaw * f32(math.pi / 180.0) }
	if pitch := opt.pitch { player.pitch = pitch * f32(math.pi / 180.0) }
	return player
}
