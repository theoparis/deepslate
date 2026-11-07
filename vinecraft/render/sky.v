module render

import math

pub struct SkyState {
pub mut:
	sky_light  f32    = 1
	fog_color  [3]f32 = [f32(0.7), 0.8, 1.0]!
	fog_start  f32    = 100
	fog_end    f32    = 160
	anim_tick  f32
	underwater bool
}

pub struct TimeOfDay {
pub:
	ticks i64
}

pub fn (t TimeOfDay) sun_angle() f32 {
	return f32(2.0 * math.pi * (f64(t.ticks % 24000) - 6000.0) / 24000.0)
}

pub fn (t TimeOfDay) sun_dir() Vec3 {
	a := t.sun_angle()
	return Vec3{f32(-math.sin(a)), f32(math.cos(a)), 0}
}

pub fn sky_state(t TimeOfDay, distance f32) SkyState {
	sun := t.sun_dir()
	v := math.clamp((sun.y + 0.18) / 0.4, f32(0), f32(1))
	day := v * v * (3 - 2 * v)
	twilight := math.max(f32(0), 1 - f32(math.abs(sun.y)) * 4.5) * 0.55
	mut fog := [3]f32{}
	night := [f32(0.03), 0.04, 0.09]!
	daylight := [f32(0.72), 0.83, 1.0]!
	warm := [f32(0.95), 0.55, 0.35]!
	for i in 0 .. 3 {
		h := night[i] + (daylight[i] - night[i]) * day
		fog[i] = h + (warm[i] - h) * twilight
	}
	return SkyState{ sky_light: 0.13 + 0.87 * day, fog_color: fog, fog_start: distance * 0.55, fog_end: distance * 0.98 }
}
