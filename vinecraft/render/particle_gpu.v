module render

import sokol.gfx

const particle_vs = '#version 330 core\nlayout(location=0) in vec3 pos; layout(location=1) in vec3 uvl; layout(location=2) in vec4 col; uniform mat4 vp; out vec3 texcoord; out vec4 color; out float dist; void main(){gl_Position=vp*vec4(pos,1); texcoord=uvl; color=col; dist=length(pos);}'
const particle_fs = '#version 330 core\nin vec3 texcoord; in vec4 color; in float dist; uniform sampler2DArray atlas; uniform vec4 fog; uniform vec4 params; out vec4 frag; void main(){vec4 t=texture(atlas,texcoord); if(t.a<0.3) discard; float f=clamp((dist-params.x)/max(params.y-params.x,0.001),0,1); frag=vec4(mix(t.rgb*color.rgb,fog.rgb,f),1);}'

pub struct ParticleGpu {
mut:
	shader   gfx.Shader
	pipeline gfx.Pipeline
	sampler  gfx.Sampler
}

pub fn new_particle_gpu() ParticleGpu {
	mut sd := gfx.ShaderDesc{}
	sd.vs.source = &char(particle_vs.str)
	sd.fs.source = &char(particle_fs.str)
	sd.vs.uniform_blocks[0].size = 64
	sd.vs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'vp', type: .mat4 }
	sd.fs.uniform_blocks[0].size = 32
	sd.fs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'fog', type: .float4 }
	sd.fs.uniform_blocks[0].uniforms[1] = gfx.ShaderUniformDesc{ name: c'params', type: .float4 }
	sd.fs.images[0].used = true
	sd.fs.images[0].image_type = .array
	sd.fs.samplers[0].used = true
	sd.fs.image_sampler_pairs[0].used = true
	sd.fs.image_sampler_pairs[0].glsl_name = c'atlas'
	shader := gfx.make_shader(&sd)
	mut pd := gfx.PipelineDesc{ shader: shader, depth: gfx.DepthState{ write_enabled: true, compare: .less_equal } }
	pd.layout.buffers[0].stride = int(sizeof(ParticleVertex))
	pd.layout.attrs[0].format = .float3
	pd.layout.attrs[1].format = .float3
	pd.layout.attrs[2].format = .float4
	return ParticleGpu{ shader: shader, pipeline: gfx.make_pipeline(&pd), sampler: gfx.make_sampler(&gfx.SamplerDesc{ min_filter: .nearest, mag_filter: .nearest }) }
}

pub fn (gpu &ParticleGpu) draw(mut particles Particles, cam Camera, sky SkyState, atlas gfx.Image) {
	particles.prepare(cam, sky)
	if particles.vertices.len == 0 { return }
	data := gfx.Range{ ptr: particles.vertices.data, size: u32(particles.vertices.len * int(sizeof(ParticleVertex))) }
	buffer := gfx.make_buffer(&gfx.BufferDesc{ size: data.size, data: data })
	mut binding := gfx.Bindings{}
	binding.vertex_buffers[0] = buffer
	binding.fs.images[0] = atlas
	binding.fs.samplers[0] = gpu.sampler
	gfx.apply_pipeline(gpu.pipeline)
	gfx.apply_bindings(&binding)
	vp := cam.view_proj()
	fs := [sky.fog_color[0], sky.fog_color[1], sky.fog_color[2], f32(0), sky.fog_start, sky.fog_end,
		f32(0), f32(0)]!
	gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: unsafe { &vp[0] }, size: 64 })
	gfx.apply_uniforms(.fs, 0, &gfx.Range{ ptr: unsafe { &fs[0] }, size: 32 })
	gfx.draw(0, particles.vertices.len, 1)
	gfx.destroy_buffer(buffer)
}

pub fn (mut gpu ParticleGpu) free() {
	gfx.destroy_pipeline(gpu.pipeline)
	gfx.destroy_shader(gpu.shader)
	gfx.destroy_sampler(gpu.sampler)
}
