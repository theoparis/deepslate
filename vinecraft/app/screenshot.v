module app

import sokol.sapp
import vinecraft.assets

// Capture after drawing the frame and before committing the swapchain.
pub fn take_screenshot(path string) ! {
	mut shot := sapp.screenshot_window()
	defer { unsafe { shot.destroy() } }
	mut image := assets.new_image(shot.width, shot.height)
	pixels := unsafe { shot.pixels().vbytes(shot.size) }
	stride := shot.width * 4
	for y in 0 .. shot.height {
		for x in 0 .. shot.width {
			src := (shot.height - 1 - y) * stride + x * 4
			dst := y * stride + x * 4
			image.rgba[dst] = pixels[src]
			image.rgba[dst + 1] = pixels[src + 1]
			image.rgba[dst + 2] = pixels[src + 2]
			image.rgba[dst + 3] = 255
		}
	}
	assets.write_png_file(path, image)!
}
