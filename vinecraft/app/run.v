module app

import math
import runtime
import time
import sokol.sapp
import sokol.gfx
import vinecraft.assets
import vinecraft.blocks
import vinecraft.cli
import vinecraft.models
import vinecraft.render
import vinecraft.world

@[heap]
struct Runtime {
mut:
	game         &Game                 = unsafe { nil }
	packs        &assets.PackStack     = unsafe { nil }
	models       &models.BlockModels   = unsafe { nil }
	renderer     &render.WorldRenderer = unsafe { nil }
	ui           render.Ui
	ui_gpu       render.UiGpu
	sky_gpu      render.SkyGpu
	cloud_gpu    render.CloudGpu
	particle_gpu render.ParticleGpu
	clouds       render.Clouds
	particles    render.Particles
	input        Input
	creative     []blocks.BlockId
	last_time    f64
	fps_elapsed  f64
	fps_frames   int
	frame        int
	exit_code    int
	initialized  bool
}

struct ParticleWorld {
	world &world.World
}

fn (p ParticleWorld) is_solid(x int, y int, z int) bool {
	return p.world.block_info(p.world.get_block(x, y, z)).solid()
}

fn seconds() f64 { return f64(time.sys_mono_now()) / 1e9 }

fn init(data voidptr) {
	mut rt := unsafe { &Runtime(data) }
	mut desc := sapp.create_desc()
	// Each visible section can own opaque and translucent vertex buffers.
	// Sokol's default pool of 128 is too small for normal render distances.
	desc.buffer_pool_size = 65535
	gfx.setup(desc)
	rt.ui_gpu = render.new_ui_gpu()
	font_data := rt.packs.read('assets/minecraft/textures/font/ascii.png') or {
		eprintln('font: ${err}')
		rt.exit_code = 1
		sapp.quit()
		return
	}
	font := assets.decode_png(font_data) or {
		eprintln('font: ${err}')
		rt.exit_code = 1
		sapp.quit()
		return
	}
	rt.ui.set_font(render.ui_texture(font), font)
	mut workers := rt.game.options.threads
	if workers <= 0 {
		workers = runtime.nr_cpus() - 1
		if workers < 2 { workers = 2 }
	}
	rt.game.threads = workers
	rt.renderer = render.new_world_renderer(mut rt.models, rt.game.registry, workers)
	rt.sky_gpu = render.new_sky_gpu(rt.packs)
	rt.cloud_gpu = render.new_cloud_gpu()
	rt.particle_gpu = render.new_particle_gpu()
	rt.clouds = render.new_clouds(rt.packs)
	rt.creative = creative_blocks(rt.game.registry)
	rt.last_time = seconds()
	rt.initialized = true
}

fn frame(data voidptr) {
	mut rt := unsafe { &Runtime(data) }
	if !rt.initialized { return }
	now := seconds()
	dt := math.min(0.1, now - rt.last_time)
	rt.last_time = now
	old_screen := rt.game.screen
	move := rt.input.movement(mut rt.game)
	rt.game.renderer_idle = rt.renderer.idle()
	rt.game.update(dt, now, move, rt.input.left, rt.input.right, sapp.width(), sapp.height())
	if old_screen != rt.game.screen { sapp.lock_mouse(rt.game.screen == .playing) }
	if rt.game.last_error != '' {
		eprintln(rt.game.last_error)
		rt.game.last_error = ''
		rt.exit_code = 1
	}
	for broken in rt.game.broken {
		icon := rt.models.icon(broken.id)
		bi := rt.game.registry.info(broken.id)
		rt.particles.emit_break(broken.x, broken.y, broken.z, icon.top, rt.models.tint_color(bi.tint, 1), bi.liquid())
	}
	rt.game.broken.clear()
	rt.particles.update(dt, ParticleWorld{ world: rt.game.world })
	rt.renderer.update(mut rt.game.world, rt.game.camera, rt.game.radius) or {
		eprintln('world renderer: ${err}')
		rt.exit_code = 1
		sapp.quit()
		return
	}
	tod := render.TimeOfDay{ ticks: rt.game.ticks }
	mut sky := render.sky_state(tod, f32(rt.game.radius * 16))
	sky.anim_tick = f32(now * 20)
	if rt.game.player_state.eyes_in_water {
		light := 0.25 + 0.75 * sky.sky_light
		sky.fog_color = [f32(0.05 * light), f32(0.18 * light), f32(0.45 * light)]!
		sky.fog_start = 0
		sky.fog_end = 28
		sky.underwater = true
	}
	action := gfx.create_clear_pass_action(sky.fog_color[0], sky.fog_color[1], sky.fog_color[2], 1)
	gfx.begin_pass(sapp.create_default_pass(action))
	if rt.game.screen != .loading {
		if !rt.game.player_state.eyes_in_water { rt.sky_gpu.draw(rt.game.camera, tod, sky) }
		rt.renderer.draw(rt.game.camera, sky, false)
		if rt.game.hit.hit && rt.game.screen == .playing {
			h := rt.game.hit
			rt.sky_gpu.draw_box_outline(rt.game.camera, render.Vec3d{h.box_min[0], h.box_min[1], h.box_min[2]}, render.Vec3d{h.box_max[0], h.box_max[1], h.box_max[2]}, 1)
		}
		rt.renderer.draw(rt.game.camera, sky, true)
		rt.particle_gpu.draw(mut rt.particles, rt.game.camera, sky, rt.renderer.atlas_image())
		if !rt.game.player_state.eyes_in_water {
			rt.cloud_gpu.draw(mut rt.clouds, rt.game.camera, sky, now)
		}
	}
	rt.ui.begin(sapp.width(), sapp.height())
	draw_ui(mut rt.ui, mut rt.game, mut rt.models, rt.renderer.atlas_image().id, rt.renderer.stats, mut rt.input, rt.creative)
	rt.ui_gpu.draw(&rt.ui)
	gfx.end_pass()
	if rt.game.pending_screenshot != '' {
		take_screenshot(rt.game.pending_screenshot) or {
			eprintln('screenshot: ${err}')
			rt.exit_code = 1
		}
		rt.game.pending_screenshot = ''
	}
	gfx.commit()
	rt.frame++
	rt.game.frame_ms = (seconds() - now) * 1000
	rt.fps_frames++
	rt.fps_elapsed += dt
	if rt.fps_elapsed >= 0.5 {
		rt.game.fps = rt.fps_frames / rt.fps_elapsed
		rt.fps_frames = 0
		rt.fps_elapsed = 0
	}
	if rt.game.script.failures > 0 { rt.exit_code = 1 }
	if rt.game.quit_requested || (rt.game.options.max_frames >= 0 && rt.frame >= rt.game.options.max_frames) {
		sapp.quit()
	}
}

fn event(e &sapp.Event, data voidptr) {
	mut rt := unsafe { &Runtime(data) }
	if !rt.initialized { return }
	rt.input.event(mut rt.game, e, seconds(), rt.ui.width, rt.ui.height, rt.ui.scale, rt.creative)
}

fn cleanup(data voidptr) {
	mut rt := unsafe { &Runtime(data) }
	if rt.initialized {
		rt.renderer.free()
		rt.sky_gpu.free()
		rt.cloud_gpu.free()
		rt.particle_gpu.free()
		gfx.destroy_image(gfx.Image{ id: rt.ui.font.id })
		rt.ui_gpu.free()
	}
	rt.game.shutdown() or {
		eprintln('shutdown: ${err}')
		rt.exit_code = 1
	}
	gfx.shutdown()
}

pub fn run(opt cli.Options) int {
	mut packs := &assets.PackStack{}
	for spec in opt.packs {
		packs.add_spec(spec) or {
			eprintln('resource pack ${spec}: ${err}')
			return 1
		}
	}
	packs.add_builtin_fallback()
	println('resource packs: ${packs.describe()}')
	mut game := new_game(opt) or {
		eprintln(err)
		return 1
	}
	mut block_models := models.new_block_models(packs, game.registry, 2048)
	block_models.build()
	mut rt := &Runtime{ game: game, packs: packs, models: block_models }
	sapp.run(
		window_title:        c'Deepslate Edition'
		width:               opt.width
		height:              opt.height
		fullscreen:          opt.fullscreen
		high_dpi:            true
		swap_interval:       if opt.vsync { 1 } else { 0 }
		init_userdata_cb:    init
		frame_userdata_cb:   frame
		event_userdata_cb:   event
		cleanup_userdata_cb: cleanup
		user_data:           rt
	)
	return rt.exit_code
}
