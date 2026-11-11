module assets

import compress.szip
import crypto.sha256
import net.http
import os

pub struct PackSource {
pub:
	name  string
	root  string
	files map[string][]u8
}

pub fn (p PackSource) read(path string) ![]u8 {
	if p.root != '' { return os.read_bytes(os.join_path(p.root, path)) }
	if path !in p.files { return error('resource not found: ${path}') }
	return p.files[path].clone()
}

pub fn (p PackSource) has(path string) bool {
	if p.root != '' { return os.is_file(os.join_path(p.root, path)) }
	return path in p.files
}

pub fn (p PackSource) list(prefix string) []string {
	mut result := []string{}
	if p.root != '' {
		for path in os.walk_ext(p.root, '') {
			rel := path[p.root.trim_right('/').len..].trim_left('/')
			if rel.starts_with(prefix) { result << rel }
		}
	} else {
		for path, _ in p.files { if path.starts_with(prefix) { result << path } }
	}
	return result
}

fn wanted(path string) bool {
	for prefix in ['assets/minecraft/blockstates/', 'assets/minecraft/models/block/',
		'assets/minecraft/textures/block/', 'assets/minecraft/textures/colormap/',
		'assets/minecraft/textures/font/', 'assets/minecraft/textures/gui/',
		'assets/minecraft/textures/environment/', 'assets/minecraft/textures/item/', 'pack.mcmeta',
		'pack.png'] {
		if path.starts_with(prefix) { return true }
	}
	return false
}

pub fn open_zip_pack(path string) !PackSource {
	mut zip := szip.open_lazy(path)!
	defer { zip.close() }
	mut files := map[string][]u8{}
	for i in 0 .. zip.total()! {
		zip.open_entry_by_index(i)!
		name := zip.name()
		if !name.ends_with('/') && wanted(name) {
			data := zip.read_entry_bytes() or { continue }
			if name !in files { files[name] = data }
		}
	}
	if files.len == 0 { return error('archive contains no resource pack assets') }
	return PackSource{ name: path, files: files }
}

pub fn open_dir_pack(path string) !PackSource {
	if !os.is_file(os.join_path(path, 'pack.mcmeta')) && !os.is_dir(os.join_path(path, 'assets')) {
		return error('directory does not look like a resource pack (no pack.mcmeta or assets/)')
	}
	return PackSource{ name: path, root: path }
}

pub fn download_pack(url string) !string {
	if !url.starts_with('https://') {
		return error('only HTTPS resource pack URLs are allowed')
	}
	mut cache := os.getenv('XDG_CACHE_HOME')
	if cache == '' {
		home := os.getenv('HOME')
		cache = if home != '' { os.join_path(home, '.cache') } else { os.temp_dir() }
	}
	cache = os.join_path(cache, 'deepslate-edition', 'packs')
	os.mkdir_all(cache)!
	target := os.join_path(cache, sha256.hexhash(url) + '.zip')
	if os.exists(target) { return target }
	response := http.fetch(
		method: .get
		url: url
		validate: true
	)!
	if response.status_code < 200 || response.status_code >= 400 {
		return error('download failed: HTTP ${response.status_code}')
	}
	tmp := target + '.part'
	os.write_file_array(tmp, response.body.bytes())!
	os.mv(tmp, target)!
	return target
}

@[heap]
pub struct PackStack {
pub mut:
	layers []PackSource
}

pub fn (mut s PackStack) add_spec(spec string) ! {
	path := if spec.starts_with('http://') || spec.starts_with('https://') {
		download_pack(spec)!
	} else {
		spec
	}
	pack := if os.is_dir(path) {
		open_dir_pack(path)!
	} else if os.is_file(path) {
		open_zip_pack(path)!
	} else {
		return error('no such file or directory: ${path}')
	}
	s.layers << pack
}

pub fn (mut s PackStack) add(pack PackSource) { s.layers << pack }

pub fn (mut s PackStack) add_builtin_fallback() { s.layers << make_builtin_pack() }

pub fn (s PackStack) read(path string) ![]u8 {
	for layer in s.layers { if data := layer.read(path) { return data } }
	return error('resource not found: ${path}')
}

pub fn (s PackStack) has(path string) bool {
	for layer in s.layers { if layer.has(path) { return true } }
	return false
}

pub fn (s PackStack) list(prefix string) []string {
	mut all := map[string]bool{}
	for layer in s.layers {
		for path in layer.list(prefix) { all[path] = true }
	}
	mut paths := all.keys()
	paths.sort()
	return paths
}

pub fn (s PackStack) describe() string {
	mut names := []string{}
	for layer in s.layers { names << layer.name }
	return names.join(' > ')
}

pub fn (s PackStack) layer_count() int { return s.layers.len }

pub fn builtin_pack_files() []string {
	mut paths := make_builtin_pack().list('')
	paths.sort()
	return paths
}

pub fn export_builtin_pack(dir string) ! {
	pack := make_builtin_pack()
	for path in pack.list('') {
		out := os.join_path(dir, path)
		os.mkdir_all(os.dir(out))!
		os.write_file_array(out, pack.read(path)!)!
	}
}

pub fn export_builtin_pack_zip(path string) ! {
	mut zip := szip.open(path, .no_compression, .write)!
	defer { zip.close() }
	pack := make_builtin_pack()
	for name in pack.list('') {
		data := pack.read(name)!
		zip.open_entry(name)!
		zip.write_entry(data)!
	}
}
