module render

import sokol.gfx
import vinecraft.assets

const ui_vs = '#version 330 core\nlayout(location=0) in vec2 a_pos; layout(location=1) in vec2 a_uv; layout(location=2) in float a_layer; layout(location=3) in vec4 a_color; uniform vec2 u_size; out vec2 uv; flat out float layer; out vec4 color; void main(){ gl_Position=vec4(a_pos.x/u_size.x*2.0-1.0,1.0-a_pos.y/u_size.y*2.0,0.0,1.0); uv=a_uv; layer=a_layer; color=a_color; }'
const ui_fs = '#version 330 core\nin vec2 uv; flat in float layer; in vec4 color; uniform sampler2D tex; out vec4 frag; void main(){ frag=texture(tex,uv)*color; }'
const ui_array_fs = '#version 330 core\nin vec2 uv; flat in float layer; in vec4 color; uniform sampler2DArray tex; out vec4 frag; void main(){ frag=texture(tex,vec3(uv,layer))*color; }'

pub struct UiGpu {
mut:
	shader_2d      gfx.Shader
	shader_array   gfx.Shader
	pipeline_2d    gfx.Pipeline
	pipeline_array gfx.Pipeline
	sampler        gfx.Sampler
	white          gfx.Image
}

fn ui_pipeline(array bool) (gfx.Shader, gfx.Pipeline) {
	mut desc := gfx.ShaderDesc{}
	desc.vs.source = &char(ui_vs.str)
	desc.fs.source = if array { &char(ui_array_fs.str) } else { &char(ui_fs.str) }
	desc.vs.uniform_blocks[0].size = 8
	desc.vs.uniform_blocks[0].uniforms[0].name = c'u_size'
	desc.vs.uniform_blocks[0].uniforms[0].type = .float2
	desc.fs.images[0].used = true
	desc.fs.images[0].image_type = if array { .array } else { ._2d }
	desc.fs.samplers[0].used = true
	desc.fs.image_sampler_pairs[0].used = true
	desc.fs.image_sampler_pairs[0].glsl_name = c'tex'
	shader := gfx.make_shader(&desc)
	mut pip := gfx.PipelineDesc{}
	pip.shader = shader
	pip.layout.buffers[0].stride = int(sizeof(UiVertex))
	pip.layout.attrs[0].format = .float2
	pip.layout.attrs[1].format = .float2
	pip.layout.attrs[2].format = .float
	pip.layout.attrs[3].format = .ubyte4n
	pip.colors[0].blend = gfx.BlendState{ enabled: true, src_factor_rgb: .src_alpha, dst_factor_rgb: .one_minus_src_alpha, src_factor_alpha: .one, dst_factor_alpha: .one_minus_src_alpha }
	pipeline := gfx.make_pipeline(&pip)
	return shader, pipeline
}

pub fn new_ui_gpu() UiGpu {
	sh2, p2 := ui_pipeline(false)
	sha, pa := ui_pipeline(true)
	sampler := gfx.make_sampler(&gfx.SamplerDesc{ min_filter: .nearest, mag_filter: .nearest })
	pixels := [u8(255), 255, 255, 255]!
	mut desc := gfx.ImageDesc{ width: 1, height: 1, pixel_format: .rgba8 }
	desc.data.subimage[0][0] = gfx.Range{ ptr: unsafe { &pixels[0] }, size: 4 }
	return UiGpu{ shader_2d: sh2, shader_array: sha, pipeline_2d: p2, pipeline_array: pa, sampler: sampler, white: gfx.make_image(&desc) }
}

pub fn ui_texture(img assets.Image) UiTexture {
	mut desc := gfx.ImageDesc{ width: img.w, height: img.h, pixel_format: .rgba8 }
	desc.data.subimage[0][0] = gfx.Range{ ptr: img.rgba.data, size: u32(img.rgba.len) }
	image := gfx.make_image(&desc)
	return UiTexture{ id: image.id, w: img.w, h: img.h }
}

// Called inside an active Sokol pass after Ui.begin and drawing commands.
pub fn (gpu &UiGpu) draw(ui &Ui) {
	for batch in ui.batches {
		if batch.vertices.len == 0 { continue }
		data := gfx.Range{ ptr: batch.vertices.data, size: u32(batch.vertices.len * int(sizeof(UiVertex))) }
		buf := gfx.make_buffer(&gfx.BufferDesc{ size: data.size, data: data })
		mut bind := gfx.Bindings{}
		bind.vertex_buffers[0] = buf
		bind.fs.samplers[0] = gpu.sampler
		bind.fs.images[0] = if batch.mode == .solid {
			gpu.white
		} else {
			gfx.Image{ id: batch.texture }
		}
		gfx.apply_pipeline(if batch.mode == .atlas { gpu.pipeline_array } else { gpu.pipeline_2d })
		gfx.apply_bindings(&bind)
		size := [ui.width, ui.height]!
		gfx.apply_uniforms(.vs, 0, &gfx.Range{ ptr: unsafe { &size[0] }, size: 8 })
		gfx.draw(0, batch.vertices.len, 1)
		gfx.destroy_buffer(buf)
	}
}

pub fn (mut gpu UiGpu) free() {
	gfx.destroy_pipeline(gpu.pipeline_2d)
	gfx.destroy_pipeline(gpu.pipeline_array)
	gfx.destroy_shader(gpu.shader_2d)
	gfx.destroy_shader(gpu.shader_array)
	gfx.destroy_sampler(gpu.sampler)
	gfx.destroy_image(gpu.white)
}
