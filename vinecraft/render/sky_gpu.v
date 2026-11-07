module render

import sokol.gfx
import vinecraft.assets
import math

const dome_vs = '#version 330 core\nout vec2 ndc; void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2); ndc=p*2.0-1.0; gl_Position=vec4(ndc,0.999,1);}'
const dome_fs = '#version 330 core\nin vec2 ndc; uniform vec4 forward_tan; uniform vec4 right_aspect; uniform vec4 up_glow; uniform vec4 zenith; uniform vec4 horizon; uniform vec4 sun; out vec4 frag; void main(){vec3 d=normalize(forward_tan.xyz+right_aspect.xyz*(ndc.x*forward_tan.w*right_aspect.w)+up_glow.xyz*(ndc.y*forward_tan.w)); float h=clamp(d.y,-1,1); vec3 c=mix(horizon.xyz,zenith.xyz,pow(clamp(h,0,1),0.55)); if(h<0)c=mix(horizon.xyz,horizon.xyz*0.85,clamp(-h*3,0,1)); float g=pow(max(dot(d,sun.xyz),0),6)*up_glow.w*(1-clamp(abs(h)*1.2,0,1)); frag=vec4(mix(c,vec3(1,0.6,0.3),clamp(g,0,0.85)),1);}'
const sky_quad_vs = '#version 330 core\nlayout(location=0) in vec3 pos; layout(location=1) in vec2 uv; layout(location=2) in vec4 color; uniform mat4 vp; out vec2 vuv; out vec4 vcolor; void main(){gl_Position=vp*vec4(pos,1); vuv=uv; vcolor=color;}'
const sky_quad_fs = '#version 330 core\nin vec2 vuv; in vec4 vcolor; uniform sampler2D tex; out vec4 frag; void main(){frag=texture(tex,vuv)*vcolor;}'

struct SkyVertex {
	x f32
	y f32
	z f32
	u f32
	v f32
	r f32
	g f32
	b f32
	a f32
}

pub struct SkyGpu {
mut:
	dome_shader gfx.Shader
	quad_shader gfx.Shader
	dome        gfx.Pipeline
	quad        gfx.Pipeline
	lines       gfx.Pipeline
	sampler     gfx.Sampler
	white       gfx.Image
	sun         gfx.Image
	moon_sheet  gfx.Image
	moons       [8]gfx.Image
	stars       []Vec3
}

fn sky_image(packs &assets.PackStack, path string) gfx.Image {
	data := packs.read('assets/minecraft/textures/${path}.png') or { return gfx.Image{} }
	img := assets.decode_png(data) or { return gfx.Image{} }
	tex := ui_texture(img)
	return gfx.Image{ id: tex.id }
}

pub fn new_sky_gpu(packs &assets.PackStack) SkyGpu {
	mut ds := gfx.ShaderDesc{}
	ds.vs.source = &char(dome_vs.str)
	ds.fs.source = &char(dome_fs.str)
	ds.fs.uniform_blocks[0].size = 96
	for i, name in [c'forward_tan', c'right_aspect', c'up_glow', c'zenith', c'horizon', c'sun'] {
		ds.fs.uniform_blocks[0].uniforms[i] = gfx.ShaderUniformDesc{ name: name, type: .float4 }
	}
	dome_shader := gfx.make_shader(&ds)
	dome := gfx.make_pipeline(&gfx.PipelineDesc{ shader: dome_shader })
	mut qs := gfx.ShaderDesc{}
	qs.vs.source = &char(sky_quad_vs.str)
	qs.fs.source = &char(sky_quad_fs.str)
	qs.vs.uniform_blocks[0].size = 64
	qs.vs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'vp', type: .mat4 }
	qs.fs.images[0].used = true
	qs.fs.images[0].image_type = ._2d
	qs.fs.samplers[0].used = true
	qs.fs.image_sampler_pairs[0].used = true
	qs.fs.image_sampler_pairs[0].glsl_name = c'tex'
	quad_shader := gfx.make_shader(&qs)
	mut pd := gfx.PipelineDesc{ shader: quad_shader }
	pd.layout.buffers[0].stride = int(sizeof(SkyVertex))
	pd.layout.attrs[0].format = .float3
	pd.layout.attrs[1].format = .float2
	pd.layout.attrs[2].format = .float4
	pd.colors[0].blend = gfx.BlendState{ enabled: true, src_factor_rgb: .src_alpha, dst_factor_rgb: .one, src_factor_alpha: .one, dst_factor_alpha: .one }
	quad := gfx.make_pipeline(&pd)
	pd.primitive_type = .lines
	pd.depth = gfx.DepthState{ compare: .less_equal }
	pd.colors[0].blend = gfx.BlendState{ enabled: true, src_factor_rgb: .src_alpha, dst_factor_rgb: .one_minus_src_alpha, src_factor_alpha: .one, dst_factor_alpha: .one_minus_src_alpha }
	lines := gfx.make_pipeline(&pd)
	white_bytes := [u8(255), 255, 255, 255]!
	mut white_desc := gfx.ImageDesc{ width: 1, height: 1, pixel_format: .rgba8 }
	white_desc.data.subimage[0][0] = gfx.Range{ ptr: unsafe { &white_bytes[0] }, size: 4 }
	mut result := SkyGpu{ dome_shader: dome_shader, quad_shader: quad_shader, dome: dome, quad: quad, lines: lines, sampler: gfx.make_sampler(&gfx.SamplerDesc{ min_filter: .nearest, mag_filter: .nearest }), white: gfx.make_image(&white_desc) }
	result.sun = sky_image(packs, 'environment/sun')
	if result.sun.id == 0 { result.sun = sky_image(packs, 'environment/celestial/sun') }
	for i, phase in ['full_moon', 'waning_gibbous', 'third_quarter', 'waning_crescent', 'new_moon',
		'waxing_crescent', 'first_quarter', 'waxing_gibbous'] {
		result.moons[i] = sky_image(packs, 'environment/celestial/moon/${phase}')
	}
	if result.moons[0].id == 0 { result.moon_sheet = sky_image(packs, 'environment/moon_phases') }
	mut seed := u64(0xc0ffee)
	for _ in 0 .. 400 {
		z := f32(mix64(seed) >> 40) / 16777216 * 2 - 1
		seed += u64(0x9e3779b97f4a7c15)
		a := f32(mix64(seed) >> 40) / 16777216 * 6.2831853
		seed += u64(0x9e3779b97f4a7c15)
		r := f32(math.sqrt(1 - z * z))
		result.stars << Vec3{r * f32(math.cos(a)), z, r * f32(math.sin(a))}
	}
	return result
}

fn add_sky_quad(mut verts []SkyVertex, direction Vec3, size f32, color [4]f32, uv [4]f32) {
	nlen := f32(math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z))
	n := Vec3{direction.x / nlen, direction.y / nlen, direction.z / nlen}
	len := f32(math.sqrt(n.x * n.x + n.y * n.y))
	right := if len < 0.001 { Vec3{1, 0, 0} } else { Vec3{n.y / len, -n.x / len, 0} }
	up := Vec3{right.y * n.z, -right.x * n.z, right.x * n.y - right.y * n.x}
	for k in [0, 1, 2, 2, 3, 0] {
		sx := if k == 0 || k == 3 { f32(-1) } else { f32(1) }
		sy := if k < 2 { f32(-1) } else { f32(1) }
		u := if sx < 0 { uv[0] } else { uv[2] }
		v := if sy < 0 { uv[3] } else { uv[1] }
		verts << SkyVertex{n.x * 100 + (right.x * sx + up.x * sy) * size, n.y * 100 + (right.y * sx + up.y * sy) * size, n.z * 100 + (right.z * sx + up.z * sy) * size, u, v, color[0], color[1], color[2], color[3]}
	}
}

fn (gpu &SkyGpu) draw_vertices(vertices []SkyVertex, texture gfx.Image, cam Camera, lines bool) {
	if vertices.len == 0 { return }
	data := gfx.Range{ ptr: vertices.data, size: u32(vertices.len * int(sizeof(SkyVertex))) }
	buffer := gfx.make_buffer(&gfx.BufferDesc{ size: data.size, data: data })
	mut binding := gfx.Bindings{}
	binding.vertex_buffers[0] = buffer
	binding.fs.images[0] = if texture.id == 0 { gpu.white } else { texture }
	binding.fs.samplers[0] = gpu.sampler
	gfx.apply_pipeline(if lines { gpu.lines } else { gpu.quad })
	gfx.apply_bindings(&binding)
	vp := cam.view_proj()
	gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: unsafe { &vp[0] }, size: 64 })
	gfx.draw(0, vertices.len, 1)
	gfx.destroy_buffer(buffer)
}

pub fn (gpu &SkyGpu) draw(cam Camera, t TimeOfDay, sky SkyState) {
	sun := t.sun_dir()
	f := cam.forward()
	len := f32(math.sqrt(f.x * f.x + f.z * f.z))
	r := Vec3{-f.z / len, 0, f.x / len}
	u := Vec3{-r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y}
	d := f32(math.clamp((sun.y + 0.18) / 0.4, 0, 1))
	day := d * d * (3 - 2 * d)
	twilight := f32(math.max(0, 1 - math.abs(sun.y) * 4.5))
	values := [f.x, f.y, f.z, f32(math.tan(cam.fovy * 0.5)), r.x, r.y, r.z, cam.aspect, u.x, u.y,
		u.z, twilight * 1.2, 0.01 + 0.38 * day, 0.015 + 0.585 * day, 0.05 + 0.93 * day, f32(0),
		sky.fog_color[0], sky.fog_color[1], sky.fog_color[2], f32(0), sun.x, sun.y, sun.z, f32(0)]!
	gfx.apply_pipeline(gpu.dome)
	gfx.apply_bindings(&gfx.Bindings{})
	gfx.apply_uniforms(.fs, 0, &gfx.Range{ ptr: unsafe { &values[0] }, size: 96 })
	gfx.draw(0, 3, 1)
	mut vertices := []SkyVertex{}
	uv := [f32(0), 0, 1, 1]!
	if day < 0.95 {
		a := t.sun_angle()
		ca := f32(math.cos(a))
		sa := f32(math.sin(a))
		for star in gpu.stars {
			p := Vec3{star.x * ca - star.y * sa, star.x * sa + star.y * ca, star.z}
			if p.y >= -0.05 {
				add_sky_quad(mut vertices, p, 0.35, [f32(1), 1, 1, (1 - day) * 0.9]!, uv)
			}
		}
		gpu.draw_vertices(vertices, gfx.Image{}, cam, false)
		vertices.clear()
	}
	sun_size := if gpu.sun.id != 0 { f32(30) } else { f32(8) }
	sun_color := if gpu.sun.id != 0 { [f32(1), 1, 1, 1]! } else { [f32(1), 0.95, 0.7, 1]! }
	add_sky_quad(mut vertices, sun, sun_size, sun_color, uv)
	gpu.draw_vertices(vertices, gpu.sun, cam, false)
	vertices.clear()
	phase := int(((t.ticks / 24000) % 8 + 8) % 8)
	moon := if gpu.moons[phase].id != 0 { gpu.moons[phase] } else { gpu.moon_sheet }
	moon_uv := if moon.id != 0 && moon.id == gpu.moon_sheet.id {
		[f32(phase % 4) / 4, f32(phase / 4) / 2, f32(phase % 4 + 1) / 4, f32(phase / 4 + 1) / 2]!
	} else {
		uv
	}
	moon_color := if moon.id != 0 { [f32(1), 1, 1, 1]! } else { [f32(0.85), 0.87, 0.95, 1]! }
	add_sky_quad(mut vertices, Vec3{-sun.x, -sun.y, -sun.z}, if moon.id != 0 { 20 } else { 6 }, moon_color, moon_uv)
	gpu.draw_vertices(vertices, moon, cam, false)
}

pub fn (gpu &SkyGpu) draw_box_outline(cam Camera, mn Vec3d, mx Vec3d, alpha f32) {
	a := Vec3{f32(mn.x - cam.pos.x) - 0.003, f32(mn.y - cam.pos.y) - 0.003, f32(mn.z - cam.pos.z) - 0.003}
	b := Vec3{f32(mx.x - cam.pos.x) + 0.003, f32(mx.y - cam.pos.y) + 0.003, f32(mx.z - cam.pos.z) + 0.003}
	c := [Vec3{a.x, a.y, a.z}, Vec3{b.x, a.y, a.z}, Vec3{b.x, a.y, b.z}, Vec3{a.x, a.y, b.z},
		Vec3{a.x, b.y, a.z}, Vec3{b.x, b.y, a.z}, Vec3{b.x, b.y, b.z}, Vec3{a.x, b.y, b.z}]!
	edges := [[0, 1]!, [1, 2]!, [2, 3]!, [3, 0]!, [4, 5]!, [5, 6]!, [6, 7]!, [7, 4]!, [0, 4]!,
		[1, 5]!, [2, 6]!, [3, 7]!]!
	mut vertices := []SkyVertex{}
	for edge in edges {
		for k in edge {
			p := c[k]
			vertices << SkyVertex{p.x, p.y, p.z, 0, 0, 0, 0, 0, alpha}
		}
	}
	gpu.draw_vertices(vertices, gfx.Image{}, cam, true)
}

pub fn (mut gpu SkyGpu) free() {
	gfx.destroy_pipeline(gpu.dome)
	gfx.destroy_pipeline(gpu.quad)
	gfx.destroy_pipeline(gpu.lines)
	gfx.destroy_shader(gpu.dome_shader)
	gfx.destroy_shader(gpu.quad_shader)
	gfx.destroy_sampler(gpu.sampler)
	gfx.destroy_image(gpu.white)
	if gpu.sun.id != 0 { gfx.destroy_image(gpu.sun) }
	if gpu.moon_sheet.id != 0 { gfx.destroy_image(gpu.moon_sheet) }
	for moon in gpu.moons { if moon.id != 0 { gfx.destroy_image(moon) } }
}
