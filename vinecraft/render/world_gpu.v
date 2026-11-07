module render

import sokol.gfx

const world_vs = '#version 330 core\nlayout(location=0) in vec3 a_pos; layout(location=1) in vec2 a_uv; layout(location=2) in float a_layer; layout(location=3) in vec4 a_color; layout(location=4) in vec4 a_light; uniform mat4 u_vp; uniform vec4 u_offset; out vec2 uv; flat out float layer; out vec4 color; out vec2 light; out float dist; void main(){vec3 p=a_pos+u_offset.xyz; gl_Position=u_vp*vec4(p,1); uv=a_uv; layer=a_layer; color=a_color; light=a_light.xy; dist=length(p);}'
const world_fs = '#version 330 core\nin vec2 uv; flat in float layer; in vec4 color; in vec2 light; in float dist; uniform sampler2DArray atlas; uniform sampler2D anim; uniform vec4 u_fog; uniform vec4 u_params; out vec4 frag; void main(){vec2 an=texelFetch(anim,ivec2(int(layer+0.5),0),0).rg; float frame=floor(mod(u_params.z/max(an.y,1.0),max(an.x,1.0))); vec4 texel=texture(atlas,vec3(uv,layer+frame)); if(texel.a<u_params.w) discard; vec3 l=max(vec3(light.x*u_fog.w),vec3(1,0.87,0.70)*light.y); vec3 b=mix(vec3(0.035),vec3(1),l*l*(0.35+0.65*l)); float f=clamp((dist-u_params.x)/max(u_params.y-u_params.x,0.001),0,1); frag=vec4(mix(texel.rgb*color.rgb*b,u_fog.rgb,f),texel.a*color.a);}'

pub struct GpuMesh {
	buffer gfx.Buffer
	count  int
}

pub struct WorldGpu {
mut:
	shader      gfx.Shader
	opaque      gfx.Pipeline
	translucent gfx.Pipeline
	atlas       gfx.Image
	animation   gfx.Image
	sampler     gfx.Sampler
}

pub fn new_world_gpu(tile int, layers int, pixels []u8, animation []f32) WorldGpu {
	mut desc := gfx.ShaderDesc{}
	desc.vs.source = &char(world_vs.str)
	desc.fs.source = &char(world_fs.str)
	desc.vs.uniform_blocks[0].size = 80
	desc.vs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'u_vp', type: .mat4 }
	desc.vs.uniform_blocks[0].uniforms[1] = gfx.ShaderUniformDesc{ name: c'u_offset', type: .float4 }
	desc.fs.uniform_blocks[0].size = 32
	desc.fs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'u_fog', type: .float4 }
	desc.fs.uniform_blocks[0].uniforms[1] = gfx.ShaderUniformDesc{ name: c'u_params', type: .float4 }
	for i in 0 .. 2 {
		desc.fs.images[i].used = true
		desc.fs.images[i].image_type = if i == 0 { .array } else { ._2d }
		desc.fs.samplers[i].used = true
		desc.fs.image_sampler_pairs[i].used = true
		desc.fs.image_sampler_pairs[i].image_slot = i
		desc.fs.image_sampler_pairs[i].sampler_slot = i
	}
	desc.fs.image_sampler_pairs[0].glsl_name = c'atlas'
	desc.fs.image_sampler_pairs[1].glsl_name = c'anim'
	shader := gfx.make_shader(&desc)
	mut pd := gfx.PipelineDesc{ shader: shader, cull_mode: .back, face_winding: .ccw, depth: gfx.DepthState{ write_enabled: true, compare: .less_equal } }
	pd.layout.buffers[0].stride = int(sizeof(Vertex))
	pd.layout.attrs[0].format = .float3
	pd.layout.attrs[1].format = .float2
	pd.layout.attrs[2].format = .float
	pd.layout.attrs[3].format = .ubyte4n
	pd.layout.attrs[4].format = .ubyte4n
	opaque := gfx.make_pipeline(&pd)
	pd.depth.write_enabled = false
	pd.cull_mode = .none
	pd.colors[0].blend = gfx.BlendState{ enabled: true, src_factor_rgb: .src_alpha, dst_factor_rgb: .one_minus_src_alpha, src_factor_alpha: .one, dst_factor_alpha: .one_minus_src_alpha }
	translucent := gfx.make_pipeline(&pd)
	mut atlas_desc := gfx.ImageDesc{ type: .array, width: tile, height: tile, num_slices: layers, pixel_format: .rgba8 }
	atlas_desc.data.subimage[0][0] = gfx.Range{ ptr: pixels.data, size: u32(pixels.len) }
	mut anim_desc := gfx.ImageDesc{ width: layers, height: 1, pixel_format: .rg32f }
	anim_desc.data.subimage[0][0] = gfx.Range{ ptr: animation.data, size: u32(animation.len * int(sizeof(f32))) }
	return WorldGpu{ shader: shader, opaque: opaque, translucent: translucent, atlas: gfx.make_image(&atlas_desc), animation: gfx.make_image(&anim_desc), sampler: gfx.make_sampler(&gfx.SamplerDesc{ min_filter: .nearest, mag_filter: .nearest }) }
}

pub fn upload_mesh(vertices []Vertex) !GpuMesh {
	if vertices.len == 0 { return GpuMesh{} }
	mut triangles := []Vertex{cap: vertices.len / 4 * 6}
	for i := 0; i + 3 < vertices.len; i += 4 {
		for k in [0, 1, 2, 0, 2, 3] { triangles << vertices[i + k] }
	}
	data := gfx.Range{ ptr: triangles.data, size: u32(triangles.len * int(sizeof(Vertex))) }
	buffer := gfx.make_buffer(&gfx.BufferDesc{ size: data.size, data: data })
	state := gfx.query_buffer_state(buffer)
	if state != .valid {
		if state != .invalid { gfx.destroy_buffer(buffer) }
		return error('could not allocate chunk vertex buffer (${state})')
	}
	return GpuMesh{ buffer: buffer, count: triangles.len }
}

pub fn (m &GpuMesh) free() { if m.count > 0 { gfx.destroy_buffer(m.buffer) } }

pub fn (gpu &WorldGpu) draw(mesh GpuMesh, cam Camera, sky SkyState, offset Vec3, translucent bool) {
	if mesh.count == 0 { return }
	mut binding := gfx.Bindings{}
	binding.vertex_buffers[0] = mesh.buffer
	binding.fs.images[0] = gpu.atlas
	binding.fs.images[1] = gpu.animation
	binding.fs.samplers[0] = gpu.sampler
	binding.fs.samplers[1] = gpu.sampler
	gfx.apply_pipeline(if translucent { gpu.translucent } else { gpu.opaque })
	gfx.apply_bindings(&binding)
	mat := cam.view_proj()
	mut vs := [20]f32{}
	for i in 0 .. 16 { vs[i] = mat[i] }
	vs[16] = offset.x
	vs[17] = offset.y
	vs[18] = offset.z
	fs := [sky.fog_color[0], sky.fog_color[1], sky.fog_color[2], sky.sky_light, sky.fog_start,
		sky.fog_end, sky.anim_tick, if translucent { f32(0.02) } else { f32(0.12) }]!
	gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: unsafe { &vs[0] }, size: 80 })
	gfx.apply_uniforms(.fs, 0, &gfx.Range{ ptr: unsafe { &fs[0] }, size: 32 })
	gfx.draw(0, mesh.count, 1)
}

pub fn (mut gpu WorldGpu) free() {
	gfx.destroy_pipeline(gpu.opaque)
	gfx.destroy_pipeline(gpu.translucent)
	gfx.destroy_shader(gpu.shader)
	gfx.destroy_image(gpu.atlas)
	gfx.destroy_image(gpu.animation)
	gfx.destroy_sampler(gpu.sampler)
}

pub fn (gpu &WorldGpu) atlas_image() gfx.Image { return gpu.atlas }
