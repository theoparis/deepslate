module models

import json2

fn object(v json2.Any) map[string]json2.Any {
	if v is map[string]json2.Any { return v }
	return map[string]json2.Any{}
}

fn json_array(v json2.Any) []json2.Any {
	if v is []json2.Any { return v }
	return []json2.Any{}
}

fn field(o map[string]json2.Any, key string) json2.Any {
	return o[key] or { json2.Any(json2.Null{}) }
}

fn vec3(a json2.Any, fallback [3]f32) [3]f32 {
	v := json_array(a)
	if v.len < 3 { return fallback }
	return [v[0].f32(), v[1].f32(), v[2].f32()]!
}

fn vec4(a json2.Any) [4]f32 {
	v := json_array(a)
	if v.len < 4 { return [f32(0), 0, 16, 16]! }
	return [v[0].f32(), v[1].f32(), v[2].f32(), v[3].f32()]!
}

fn (mut bm BlockModels) load_model(raw string, depth int) ?Model {
	name := strip_ns(raw)
	if name in bm.models {
		m := bm.models[name]
		if !m.has_final && m.parent == '<missing>' { return none }
		return m
	}
	if depth > 16 { return none }
	data := bm.packs.read('assets/minecraft/models/${name}.json') or {
		bm.models[name] = Model{ parent: '<missing>' }
		return none
	}
	doc := json2.decode[json2.Any](data.bytestr()) or {
		bm.models[name] = Model{ parent: '<missing>' }
		return none
	}
	obj := object(doc)
	mut model := Model{}
	if 'parent' in obj { model.parent = strip_ns(field(obj, 'parent').str()) }
	if 'ambientocclusion' in obj { model.ao = field(obj, 'ambientocclusion').bool() }
	for k, v in object(field(obj, 'textures')) {
		if v is string {
			model.textures[k] = v
		} else {
			model.textures[k] = field(object(v), 'sprite').str()
		}
	}
	elements := field(obj, 'elements')
	if elements is []json2.Any {
		model.has_elements = true
		for e in elements {
			o := object(e)
			from := field(o, 'from')
			to := field(o, 'to')
			if json_array(from).len < 3 || json_array(to).len < 3 { continue }
			mut el := Element{ from: vec3(from, [3]f32{}), to: vec3(to, [3]f32{}) }
			rotation := field(o, 'rotation')
			if rotation is map[string]json2.Any {
				r := rotation.clone()
				el.has_rot = true
				el.origin = vec3(field(r, 'origin'), el.origin)
				if 'axis' in r {
					el.axis = match field(r, 'axis').str() {
						'x' { 0 }
						'y' { 1 }
						else { 2 }
					}
				}
				el.angle = field(r, 'angle').f32()
				el.rescale = field(r, 'rescale').bool()
			}
			if 'shade' in o { el.shade = field(o, 'shade').bool() }
			for k, v in object(field(o, 'faces')) {
				d := dir_name(k)
				if d < 0 { continue }
				f := object(v)
				mut face := Face{ present: true, texture: field(f, 'texture').str() }
				uv := field(f, 'uv')
				if json_array(uv).len >= 4 {
					face.has_uv = true
					face.uv = vec4(uv)
				}
				if 'cullface' in f { face.cull = dir_name(field(f, 'cullface').str()) }
				if 'rotation' in f { face.rotation = field(f, 'rotation').int() }
				if 'tintindex' in f { face.tint = field(f, 'tintindex').int() }
				el.faces[d] = face
			}
			model.elements << el
		}
	}
	// Insert before recursion to break parent cycles, just as the native implementation does.
	bm.models[name] = model
	if model.parent != '' {
		if parent := bm.load_model(model.parent, depth + 1) {
			model.all_textures = parent.all_textures.clone()
			if !model.has_elements {
				model.final_elements = parent.final_elements
				model.has_final = parent.has_final
				model.ao = parent.ao && model.ao
			}
		}
	}
	for k, v in model.textures { model.all_textures[k] = v }
	if model.has_elements {
		model.final_elements = model.elements
		model.has_final = true
	}
	bm.models[name] = model
	return model
}

fn parse_one(v json2.Any) ?ModelRef {
	o := object(v)
	if 'model' !in o { return none }
	mut r := ModelRef{ name: strip_ns(field(o, 'model').str()) }
	if 'x' in o { r.x = field(o, 'x').int() }
	if 'y' in o { r.y = field(o, 'y').int() }
	if 'uvlock' in o { r.uvlock = field(o, 'uvlock').bool() }
	if 'weight' in o { r.weight = clamp_int(field(o, 'weight').int(), 1, 1000) }
	return r
}

fn parse_refs(v json2.Any) []ModelRef {
	mut refs := []ModelRef{}
	if v is []json2.Any {
		for e in v { if r := parse_one(e) { refs << r } }
	} else {
		if r := parse_one(v) { refs << r }
	}
	return refs
}

fn conditions(v json2.Any) map[string][]string {
	mut c := map[string][]string{}
	for k, val in object(v) {
		s := if val is string {
			val
		} else if val is bool {
			if val { 'true' } else { 'false' }
		} else {
			''
		}
		c[k] = s.split('|')
	}
	return c
}

fn (mut bm BlockModels) load_state(name string) BlockState {
	if name in bm.states { return bm.states[name] }
	mut bs := BlockState{}
	data := bm.packs.read('assets/minecraft/blockstates/${name}.json') or {
		bm.states[name] = bs
		return bs
	}
	doc := json2.decode[json2.Any](data.bytestr()) or {
		bm.states[name] = bs
		return bs
	}
	o := object(doc)
	for key, val in object(field(o, 'variants')) {
		mut variant := Variant{ models: parse_refs(val) }
		for kv in key.split(',') {
			idx := kv.index('=') or { continue }
			variant.key[kv[..idx]] = kv[idx + 1..]
		}
		if variant.models.len > 0 { bs.variants << variant }
	}
	for v in json_array(field(o, 'multipart')) {
		p := object(v)
		mut part := Part{ models: parse_refs(field(p, 'apply')) }
		when := field(p, 'when')
		if when is map[string]json2.Any {
			part.has_when = true
			w := when.clone()
			disjunction := field(w, 'OR')
			if disjunction is []json2.Any {
				for c in disjunction { if c is map[string]json2.Any { part.when << conditions(c) } }
			} else {
				part.when << conditions(when)
			}
		}
		if part.models.len > 0 { bs.parts << part }
	}
	bs.valid = bs.variants.len > 0 || bs.parts.len > 0
	bm.states[name] = bs
	return bs
}

fn clamp_int(v int, low int, high int) int {
	return if v < low {
		low
	} else if v > high {
		high
	} else {
		v
	}
}
