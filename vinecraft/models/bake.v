module models

import vinecraft.blocks

fn matches(props []blocks.JavaProp, key string, values []string) bool {
	for p in props { if p.key == key { return p.value in values } }
	return false
}

fn (mut bm BlockModels) bake_locked(id blocks.BlockId) {
	bi := bm.registry.info(id)
	mut baked := BakedBlock{}
	if bi.def.kind == .air || bi.def.kind == .liquid {
		if bi.def.kind == .liquid {
			bm.water = bm.add_layer('block/water_still')
			bm.lava = bm.add_layer('block/lava_still')
		}
	} else {
		name := if bi.java_override != '' {
			bi.java_override
		} else if bi.flags & blocks.bf_unknown == 0 {
			bi.def.java_name()
		} else {
			bi.name.all_after(':')
		}
		bs := bm.load_state(name)
		mut refs := []ModelRef{}
		mut choices := 0
		if bs.valid {
			if bs.variants.len > 0 {
				mut best := -1
				mut best_score := -1
				for i, variant in bs.variants {
					mut ok := true
					for k, v in variant.key {
						if !matches(bi.java_props, k, [v]) {
							ok = false
							break
						}
					}
					if ok && variant.key.len > best_score {
						best_score = variant.key.len
						best = i
					}
				}
				if best < 0 { best = 0 }
				refs << bs.variants[best].models
				choices = refs.len
			}
			for part in bs.parts {
				mut matched := !part.has_when
				for conj in part.when {
					mut all := true
					for k, vals in conj {
						if !matches(bi.java_props, k, vals) {
							all = false
							break
						}
					}
					if all {
						matched = true
						break
					}
				}
				if matched { refs << part.models[0] }
			}
		}
		if refs.len == 0 { baked.missing = true }
		if choices > 1 && refs.len == choices {
			for ref in refs {
				mut one := BakedBlock{}
				bm.bake_model(ref, mut one)
				baked.alts << Alt{ quads: one.quads, weight: ref.weight }
				baked.total_weight += ref.weight
				if one.missing { baked.missing = true }
			}
			baked.quads = baked.alts[0].quads
		} else {
			for ref in refs { bm.bake_model(ref, mut baked) }
		}
		if baked.quads.len == 0 {
			baked.missing = true
			for d in 0 .. 6 {
				mut q := BakedQuad{ cull: i8(d), dir: i8(d), boundary: true }
				for v in 0 .. 4 {
					fv := face_verts[d][v]
					for a in 0 .. 3 { q.pos[v][a] = f32(fv[a]) }
					q.uv[v][0] = if fv[3] == 2 || fv[3] == 3 { 1 } else { 0 }
					q.uv[v][1] = if fv[3] == 1 || fv[3] == 2 { 1 } else { 0 }
				}
				baked.quads << q
			}
		}
	}
	bm.table[u16(id)] = baked
}

pub fn (mut bm BlockModels) bake(id blocks.BlockId) {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	if u16(id) !in bm.table { bm.bake_locked(id) }
}

pub fn (mut bm BlockModels) build() {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	for id in 0 .. bm.registry.count() {
		if u16(id) !in bm.table { bm.bake_locked(blocks.BlockId(id)) }
	}
	bm.water = bm.add_layer('block/water_still')
	bm.lava = bm.add_layer('block/lava_still')
}

pub fn (mut bm BlockModels) baked(id blocks.BlockId) ?BakedBlock {
	bm.mutex.@lock()
	defer { bm.mutex.unlock() }
	if u16(id) !in bm.table { return none }
	return bm.table[u16(id)]
}

pub fn (mut bm BlockModels) icon(id blocks.BlockId) Icon {
	mut icon := Icon{}
	b := bm.baked(id) or {
		bi := bm.registry.info(id)
		if bi.liquid() {
			l := if bi.name.ends_with('lava') { bm.lava } else { bm.water }
			icon.top = l
			icon.left = l
			icon.right = l
		}
		return icon
	}
	if b.quads.len == 0 {
		bi := bm.registry.info(id)
		if bi.liquid() {
			l := if bi.name.ends_with('lava') { bm.lava } else { bm.water }
			icon.top = l
			icon.left = l
			icon.right = l
		}
		return icon
	}
	mut boundaries := 0
	for q in b.quads { if q.boundary { boundaries++ } }
	cubeish := boundaries >= 3
	mut top := false
	mut left := false
	mut right := false
	for q in b.quads {
		if cubeish && !q.boundary { continue }
		if q.dir == 1 && !top {
			icon.top = q.layer
			top = true
		} else if q.dir == 3 && !left {
			icon.left = q.layer
			left = true
		} else if q.dir == 5 && !right {
			icon.right = q.layer
			right = true
		}
	}
	if !cubeish {
		icon.flat = true
		icon.top = b.quads[0].layer
		icon.left = icon.top
		icon.right = icon.top
	} else {
		if !top { icon.top = icon.left }
		if !left { icon.left = icon.top }
		if !right { icon.right = icon.left }
	}
	return icon
}
