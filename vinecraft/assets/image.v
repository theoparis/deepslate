module assets

import stbi
import os

#include "@VMODROOT/vinecraft/assets/png_memory.h"

fn C.stbi_write_png_to_mem(pixels &u8, stride_bytes int, x int, y int, n int, out_len &int) &u8
fn C.stbi__callback_free(ptr voidptr)

pub struct Image {
pub mut:
	w    int
	h    int
	rgba []u8
}

pub fn new_image(w int, h int) Image {
	return Image{ w: w, h: h, rgba: []u8{len: w * h * 4} }
}

pub fn (img Image) empty() bool { return img.w == 0 || img.h == 0 }

pub fn decode_png(bytes []u8) !Image {
	if bytes.len == 0 { return error('empty image') }
	decoded := stbi.load_from_memory(bytes.data, bytes.len, desired_channels: 4)!
	defer { decoded.free() }
	return Image{ w: decoded.width, h: decoded.height, rgba: unsafe { decoded.data.vbytes(decoded.width * decoded.height * 4).clone() } }
}

pub fn encode_png(img Image) ![]u8 {
	if img.w <= 0 || img.h <= 0 || img.rgba.len != img.w * img.h * 4 {
		return error('invalid image')
	}
	mut length := 0
	p := C.stbi_write_png_to_mem(img.rgba.data, img.w * 4, img.w, img.h, 4, &length)
	if isnil(p) { return error('PNG encoding failed') }
	defer { C.stbi__callback_free(p) }
	return unsafe { p.vbytes(length).clone() }
}

pub fn write_png_file(path string, img Image) ! {
	data := encode_png(img)!
	os.write_file_array(path, data)!
}
