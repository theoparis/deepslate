module render

import sokol.gfx
import math

const cloud_vs = '#version 330 core\nlayout(location=0) in vec3 pos; layout(location=1) in float shade; uniform mat4 vp; uniform vec4 offset; out float vshade; out float dist; void main(){ vec3 p=pos+offset.xyz; gl_Position=vp*vec4(p,1); vshade=shade; dist=length(p); }'
const cloud_fs = '#version 330 core\nin float vshade; in float dist; uniform vec4 cloud_color; uniform vec4 fog; uniform vec4 params; out vec4 frag; void main(){float f=clamp((dist-params.x)/max(params.y-params.x,0.001),0,1); frag=vec4(mix(cloud_color.rgb*vshade,fog.rgb,f),0.82*(1-f*0.9));}'

pub struct CloudGpu {
mut:
	shader gfx.Shader
	depth  gfx.Pipeline
	color  gfx.Pipeline
}

pub fn new_cloud_gpu() CloudGpu {
	mut sd := gfx.ShaderDesc{}
	sd.vs.source = &char(cloud_vs.str)
	sd.fs.source = &char(cloud_fs.str)
	sd.vs.uniform_blocks[0].size = 80
	sd.vs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'vp', type: .mat4 }
	sd.vs.uniform_blocks[0].uniforms[1] = gfx.ShaderUniformDesc{ name: c'offset', type: .float4 }
	sd.fs.uniform_blocks[0].size = 48
	sd.fs.uniform_blocks[0].uniforms[0] = gfx.ShaderUniformDesc{ name: c'cloud_color', type: .float4 }
	sd.fs.uniform_blocks[0].uniforms[1] = gfx.ShaderUniformDesc{ name: c'fog', type: .float4 }
	sd.fs.uniform_blocks[0].uniforms[2] = gfx.ShaderUniformDesc{ name: c'params', type: .float4 }
	shader := gfx.make_shader(&sd)
	mut pd := gfx.PipelineDesc{ shader: shader, depth: gfx.DepthState{ write_enabled: true, compare: .less_equal } }
	pd.layout.buffers[0].stride = int(sizeof(CloudVertex))
	pd.layout.attrs[0].format = .float3
	pd.layout.attrs[1].format = .float
	pd.colors[0].write_mask = .none
	depth := gfx.make_pipeline(&pd)
	pd.colors[0].write_mask = .rgba
	pd.depth.write_enabled = false
	pd.depth.compare = .equal
	pd.colors[0].blend = gfx.BlendState{ enabled: true, src_factor_rgb: .src_alpha, dst_factor_rgb: .one_minus_src_alpha, src_factor_alpha: .one, dst_factor_alpha: .one_minus_src_alpha }
	color := gfx.make_pipeline(&pd)
	return CloudGpu{ shader: shader, depth: depth, color: color }
}

pub fn (gpu &CloudGpu) draw(mut clouds Clouds, cam Camera, sky SkyState, seconds f64) {
	offset := clouds.prepare(cam, seconds)
	if clouds.vertices.len == 0 { return }
	data := gfx.Range{ ptr: clouds.vertices.data, size: u32(clouds.vertices.len * int(sizeof(CloudVertex))) }
	buffer := gfx.make_buffer(&gfx.BufferDesc{ size: data.size, data: data })
	mut binding := gfx.Bindings{}
	binding.vertex_buffers[0] = buffer
	mat := cam.view_proj()
	mut vs := [20]f32{}
	for i in 0 .. 16 { vs[i] = mat[i] }
	vs[16] = offset.x
	vs[17] = offset.y
	vs[18] = offset.z
	l := 0.12 + 0.88 * sky.sky_light
	fs := [(1 + (sky.fog_color[0] - 1) * 0.35) * l, (1 + (sky.fog_color[1] - 1) * 0.35) * l,
		(1 + (sky.fog_color[2] - 1) * 0.35) * l, f32(0), sky.fog_color[0], sky.fog_color[1],
		sky.fog_color[2], f32(0), f32(math.max(sky.fog_start, 60)),
		f32(math.max(sky.fog_end * 1.9, 200)), f32(0), f32(0)]!
	for pip in [gpu.depth, gpu.color] {
		gfx.apply_pipeline(pip)
		gfx.apply_bindings(&binding)
		gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: unsafe { &vs[0] }, size: 80 })
		gfx.apply_uniforms(.fs, 0, &gfx.Range{ ptr: unsafe { &fs[0] }, size: 48 })
		gfx.draw(0, clouds.vertices.len, 1)
	}
	gfx.destroy_buffer(buffer)
}

pub fn (mut gpu CloudGpu) free() {
	gfx.destroy_pipeline(gpu.depth)
	gfx.destroy_pipeline(gpu.color)
	gfx.destroy_shader(gpu.shader)
}
