module blocks

pub fn builtin_defs() []BlockDef {
	return [
		BlockDef{
			name:     'air'
			display:  'Air'
			kind:     .air
			tint:     .none
			flags:    1032
			emit:     0
			color:    0
			java:     ''
			tex:      ['', '', '']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'stone'
			display:  'Stone'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['stone', 'stone', 'stone']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'stone', style: .stone, c1: 8224125, c2: 0 }]
		},
		BlockDef{
			name:     'granite'
			display:  'Granite'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    10120022
			java:     ''
			tex:      ['granite', 'granite', 'granite']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'granite', style: .stone, c1: 10120022, c2: 11567216 }]
		},
		BlockDef{
			name:     'diorite'
			display:  'Diorite'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    12434877
			java:     ''
			tex:      ['diorite', 'diorite', 'diorite']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'diorite', style: .stone, c1: 12434877, c2: 14737632 }]
		},
		BlockDef{
			name:     'andesite'
			display:  'Andesite'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8947848
			java:     ''
			tex:      ['andesite', 'andesite', 'andesite']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'andesite', style: .stone, c1: 8947848, c2: 10132122 }]
		},
		BlockDef{
			name:     'dirt'
			display:  'Dirt'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8806467
			java:     ''
			tex:      ['dirt', 'dirt', 'dirt']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'dirt', style: .dirt, c1: 8806467, c2: 0 }]
		},
		BlockDef{
			name:     'coarse_dirt'
			display:  'Coarse Dirt'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7820602
			java:     ''
			tex:      ['coarse_dirt', 'coarse_dirt', 'coarse_dirt']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'coarse_dirt', style: .gravel, c1: 7820602, c2: 8806467 }]
		},
		BlockDef{
			name:     'grass_block'
			display:  'Grass Block'
			kind:     .grass
			tint:     .grass
			flags:    3
			emit:     0
			color:    7979098
			java:     ''
			tex:      ['grass_block_top', 'grass_block_side', 'dirt']!
			overlay:  'grass_block_side_overlay'
			creative: true
			recipes:  [TexRecipe{ name: 'grass_block_top', style: .grass_top, c1: 9224026, c2: 0 },
				TexRecipe{ name: 'grass_block_side', style: .grass_side, c1: 8806467, c2: 0 },
				TexRecipe{ name: 'grass_block_side_overlay', style: .grass_overlay, c1: 9224026, c2: 0 },
				TexRecipe{ name: 'dirt', style: .dirt, c1: 8806467, c2: 0 }]
		},
		BlockDef{
			name:     'sand'
			display:  'Sand'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    14405539
			java:     ''
			tex:      ['sand', 'sand', 'sand']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'sand', style: .sand, c1: 14405539, c2: 0 }]
		},
		BlockDef{
			name:     'red_sand'
			display:  'Red Sand'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    12544558
			java:     ''
			tex:      ['red_sand', 'red_sand', 'red_sand']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'red_sand', style: .sand, c1: 12544558, c2: 0 }]
		},
		BlockDef{
			name:     'gravel'
			display:  'Gravel'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8617854
			java:     ''
			tex:      ['gravel', 'gravel', 'gravel']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'gravel', style: .gravel, c1: 8617854, c2: 10262678 }]
		},
		BlockDef{
			name:     'clay'
			display:  'Clay'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    10528437
			java:     ''
			tex:      ['clay', 'clay', 'clay']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'clay', style: .noise, c1: 10528437, c2: 0 }]
		},
		BlockDef{
			name:     'snow'
			display:  'Snow'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    16448250
			java:     'snow_block'
			tex:      ['snow', 'snow', 'snow']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'snow', style: .snow, c1: 16448250, c2: 0 }]
		},
		BlockDef{
			name:     'ice'
			display:  'Ice'
			kind:     .cube_all
			tint:     .none
			flags:    33
			emit:     0
			color:    10469375
			java:     ''
			tex:      ['ice', 'ice', 'ice']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'ice', style: .ice, c1: 10469375, c2: 0 }]
		},
		BlockDef{
			name:     'packed_ice'
			display:  'Packed Ice'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    9286896
			java:     ''
			tex:      ['packed_ice', 'packed_ice', 'packed_ice']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'packed_ice', style: .ice, c1: 9286896, c2: 0 }]
		},
		BlockDef{
			name:     'bedrock'
			display:  'Bedrock'
			kind:     .cube_all
			tint:     .none
			flags:    131
			emit:     0
			color:    3815994
			java:     ''
			tex:      ['bedrock', 'bedrock', 'bedrock']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'bedrock', style: .bedrock, c1: 3815994, c2: 0 }]
		},
		BlockDef{
			name:     'cobblestone'
			display:  'Cobblestone'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8026746
			java:     ''
			tex:      ['cobblestone', 'cobblestone', 'cobblestone']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'cobblestone', style: .gravel, c1: 8026746, c2: 10066329 }]
		},
		BlockDef{
			name:     'mossy_cobblestone'
			display:  'Mossy Cobblestone'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    6979424
			java:     ''
			tex:      ['mossy_cobblestone', 'mossy_cobblestone', 'mossy_cobblestone']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'mossy_cobblestone', style: .gravel, c1: 6979424, c2: 7376992 }]
		},
		BlockDef{
			name:     'sandstone'
			display:  'Sandstone'
			kind:     .bottom_top
			tint:     .none
			flags:    3
			emit:     0
			color:    14471328
			java:     ''
			tex:      ['sandstone_top', 'sandstone', 'sandstone_bottom']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'sandstone_top', style: .sand, c1: 14471328, c2: 0 },
				TexRecipe{ name: 'sandstone', style: .sandstone, c1: 14471328, c2: 0 },
				TexRecipe{ name: 'sandstone_bottom', style: .sand, c1: 14471328, c2: 0 }]
		},
		BlockDef{
			name:     'red_sandstone'
			display:  'Red Sandstone'
			kind:     .bottom_top
			tint:     .none
			flags:    3
			emit:     0
			color:    12083754
			java:     ''
			tex:      ['red_sandstone_top', 'red_sandstone', 'red_sandstone_bottom']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'red_sandstone_top', style: .sand, c1: 12083754, c2: 0 },
				TexRecipe{ name: 'red_sandstone', style: .sandstone, c1: 12083754, c2: 0 },
				TexRecipe{ name: 'red_sandstone_bottom', style: .sand, c1: 12083754, c2: 0 }]
		},
		BlockDef{
			name:     'deepslate'
			display:  'Deepslate'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_top', 'deepslate', 'deepslate_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_top', style: .deepslate, c1: 5263445, c2: 0 },
				TexRecipe{ name: 'deepslate', style: .deepslate, c1: 5263445, c2: 0 }]
		},
		BlockDef{
			name:     'tuff'
			display:  'Tuff'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7105891
			java:     ''
			tex:      ['tuff', 'tuff', 'tuff']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'tuff', style: .tuff, c1: 7105891, c2: 0 }]
		},
		BlockDef{
			name:     'obsidian'
			display:  'Obsidian'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    1380134
			java:     ''
			tex:      ['obsidian', 'obsidian', 'obsidian']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'obsidian', style: .obsidian, c1: 1380134, c2: 0 }]
		},
		BlockDef{
			name:     'glowstone'
			display:  'Glowstone'
			kind:     .cube_all
			tint:     .none
			flags:    67
			emit:     15
			color:    15777888
			java:     ''
			tex:      ['glowstone', 'glowstone', 'glowstone']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'glowstone', style: .glowstone, c1: 15777888, c2: 0 }]
		},
		BlockDef{
			name:     'coal_ore'
			display:  'Coal Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['coal_ore', 'coal_ore', 'coal_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'coal_ore', style: .ore, c1: 8224125, c2: 2631720 }]
		},
		BlockDef{
			name:     'deepslate_coal_ore'
			display:  'Deepslate Coal Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_coal_ore', 'deepslate_coal_ore', 'deepslate_coal_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_coal_ore', style: .ore, c1: 4868688, c2: 2631720 }]
		},
		BlockDef{
			name:     'iron_ore'
			display:  'Iron Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['iron_ore', 'iron_ore', 'iron_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'iron_ore', style: .ore, c1: 8224125, c2: 14200723 }]
		},
		BlockDef{
			name:     'deepslate_iron_ore'
			display:  'Deepslate Iron Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_iron_ore', 'deepslate_iron_ore', 'deepslate_iron_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_iron_ore', style: .ore, c1: 4868688, c2: 14200723 }]
		},
		BlockDef{
			name:     'gold_ore'
			display:  'Gold Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['gold_ore', 'gold_ore', 'gold_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'gold_ore', style: .ore, c1: 8224125, c2: 16576075 }]
		},
		BlockDef{
			name:     'deepslate_gold_ore'
			display:  'Deepslate Gold Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_gold_ore', 'deepslate_gold_ore', 'deepslate_gold_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_gold_ore', style: .ore, c1: 4868688, c2: 16576075 }]
		},
		BlockDef{
			name:     'copper_ore'
			display:  'Copper Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['copper_ore', 'copper_ore', 'copper_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'copper_ore', style: .ore, c1: 8224125, c2: 14714970 }]
		},
		BlockDef{
			name:     'deepslate_copper_ore'
			display:  'Deepslate Copper Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_copper_ore', 'deepslate_copper_ore', 'deepslate_copper_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_copper_ore', style: .ore, c1: 4868688, c2: 14714970 }]
		},
		BlockDef{
			name:     'lapis_ore'
			display:  'Lapis Lazuli Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['lapis_ore', 'lapis_ore', 'lapis_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'lapis_ore', style: .ore, c1: 8224125, c2: 2117824 }]
		},
		BlockDef{
			name:     'deepslate_lapis_ore'
			display:  'Deepslate Lapis Lazuli Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_lapis_ore', 'deepslate_lapis_ore', 'deepslate_lapis_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_lapis_ore', style: .ore, c1: 4868688, c2: 2117824 }]
		},
		BlockDef{
			name:     'redstone_ore'
			display:  'Redstone Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['redstone_ore', 'redstone_ore', 'redstone_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'redstone_ore', style: .ore, c1: 8224125, c2: 13635600 }]
		},
		BlockDef{
			name:     'deepslate_redstone_ore'
			display:  'Deepslate Redstone Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_redstone_ore', 'deepslate_redstone_ore', 'deepslate_redstone_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_redstone_ore', style: .ore, c1: 4868688, c2: 13635600 }]
		},
		BlockDef{
			name:     'diamond_ore'
			display:  'Diamond Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['diamond_ore', 'diamond_ore', 'diamond_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'diamond_ore', style: .ore, c1: 8224125, c2: 6155509 }]
		},
		BlockDef{
			name:     'deepslate_diamond_ore'
			display:  'Deepslate Diamond Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5263445
			java:     ''
			tex:      ['deepslate_diamond_ore', 'deepslate_diamond_ore', 'deepslate_diamond_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'deepslate_diamond_ore', style: .ore, c1: 4868688, c2: 6155509 }]
		},
		BlockDef{
			name:     'emerald_ore'
			display:  'Emerald Ore'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8224125
			java:     ''
			tex:      ['emerald_ore', 'emerald_ore', 'emerald_ore']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'emerald_ore', style: .ore, c1: 8224125, c2: 1564002 }]
		},
		BlockDef{
			name:     'coal_block'
			display:  'Block of Coal'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    1052688
			java:     ''
			tex:      ['coal_block', 'coal_block', 'coal_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'coal_block', style: .noise, c1: 1052688, c2: 0 }]
		},
		BlockDef{
			name:     'iron_block'
			display:  'Block of Iron'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    14474460
			java:     ''
			tex:      ['iron_block', 'iron_block', 'iron_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'iron_block', style: .noise, c1: 14474460, c2: 0 }]
		},
		BlockDef{
			name:     'gold_block'
			display:  'Block of Gold'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    16175934
			java:     ''
			tex:      ['gold_block', 'gold_block', 'gold_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'gold_block', style: .noise, c1: 16175934, c2: 0 }]
		},
		BlockDef{
			name:     'diamond_block'
			display:  'Block of Diamond'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    6483428
			java:     ''
			tex:      ['diamond_block', 'diamond_block', 'diamond_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'diamond_block', style: .noise, c1: 6483428, c2: 0 }]
		},
		BlockDef{
			name:     'emerald_block'
			display:  'Block of Emerald'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    2804568
			java:     ''
			tex:      ['emerald_block', 'emerald_block', 'emerald_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'emerald_block', style: .noise, c1: 2804568, c2: 0 }]
		},
		BlockDef{
			name:     'lapis_block'
			display:  'Block of Lapis Lazuli'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    2051238
			java:     ''
			tex:      ['lapis_block', 'lapis_block', 'lapis_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'lapis_block', style: .noise, c1: 2051238, c2: 0 }]
		},
		BlockDef{
			name:     'redstone_block'
			display:  'Block of Redstone'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    11213322
			java:     ''
			tex:      ['redstone_block', 'redstone_block', 'redstone_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'redstone_block', style: .noise, c1: 11213322, c2: 0 }]
		},
		BlockDef{
			name:     'copper_block'
			display:  'Block of Copper'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    12741454
			java:     ''
			tex:      ['copper_block', 'copper_block', 'copper_block']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'copper_block', style: .noise, c1: 12741454, c2: 0 }]
		},
		BlockDef{
			name:     'bricks'
			display:  'Bricks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    9855055
			java:     ''
			tex:      ['bricks', 'bricks', 'bricks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'bricks', style: .bricks, c1: 9855055, c2: 11577504 }]
		},
		BlockDef{
			name:     'stone_bricks'
			display:  'Stone Bricks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    8026746
			java:     ''
			tex:      ['stone_bricks', 'stone_bricks', 'stone_bricks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'stone_bricks', style: .stone_bricks, c1: 8026746, c2: 6710886 }]
		},
		BlockDef{
			name:     'mossy_stone_bricks'
			display:  'Mossy Stone Bricks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7241318
			java:     ''
			tex:      ['mossy_stone_bricks', 'mossy_stone_bricks', 'mossy_stone_bricks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'mossy_stone_bricks', style: .stone_bricks, c1: 7241318, c2: 5601092 }]
		},
		BlockDef{
			name:     'sponge'
			display:  'Sponge'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    13092682
			java:     ''
			tex:      ['sponge', 'sponge', 'sponge']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'sponge', style: .noise, c1: 13092682, c2: 0 }]
		},
		BlockDef{
			name:     'glass'
			display:  'Glass'
			kind:     .cube_all
			tint:     .none
			flags:    17
			emit:     0
			color:    12644592
			java:     ''
			tex:      ['glass', 'glass', 'glass']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'glass', style: .glass, c1: 12644592, c2: 0 }]
		},
		BlockDef{
			name:     'bookshelf'
			display:  'Bookshelf'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    9071418
			java:     ''
			tex:      ['oak_planks', 'bookshelf', 'oak_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'oak_planks', style: .planks, c1: 9071418, c2: 0 },
				TexRecipe{ name: 'bookshelf', style: .bookshelf, c1: 9071418, c2: 0 }]
		},
		BlockDef{
			name:     'crafting_table'
			display:  'Crafting Table'
			kind:     .bottom_top
			tint:     .none
			flags:    3
			emit:     0
			color:    10121280
			java:     ''
			tex:      ['crafting_table_top', 'crafting_table_side', 'oak_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'crafting_table_top', style: .crafting, c1: 10121280, c2: 0 },
				TexRecipe{ name: 'crafting_table_side', style: .crafting, c1: 10121280, c2: 0 },
				TexRecipe{ name: 'oak_planks', style: .planks, c1: 10121280, c2: 0 }]
		},
		BlockDef{
			name:     'tnt'
			display:  'TNT'
			kind:     .bottom_top
			tint:     .none
			flags:    3
			emit:     0
			color:    12595240
			java:     ''
			tex:      ['tnt_top', 'tnt_side', 'tnt_bottom']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'tnt_top', style: .tnt, c1: 12595240, c2: 0 },
				TexRecipe{ name: 'tnt_side', style: .tnt, c1: 12595240, c2: 0 },
				TexRecipe{ name: 'tnt_bottom', style: .tnt, c1: 12595240, c2: 0 }]
		},
		BlockDef{
			name:     'pumpkin'
			display:  'Pumpkin'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    13071897
			java:     ''
			tex:      ['pumpkin_top', 'pumpkin_side', 'pumpkin_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'pumpkin_top', style: .pumpkin, c1: 13071897, c2: 0 },
				TexRecipe{ name: 'pumpkin_side', style: .pumpkin, c1: 13071897, c2: 0 }]
		},
		BlockDef{
			name:     'hay_block'
			display:  'Hay Bale'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    13214234
			java:     ''
			tex:      ['hay_block_top', 'hay_block_side', 'hay_block_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'hay_block_top', style: .hay, c1: 13214234, c2: 0 },
				TexRecipe{ name: 'hay_block_side', style: .hay, c1: 13214234, c2: 0 }]
		},
		BlockDef{
			name:     'white_wool'
			display:  'White Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    15330540
			java:     ''
			tex:      ['white_wool', 'white_wool', 'white_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'white_wool', style: .noise, c1: 15330540, c2: 1 }]
		},
		BlockDef{
			name:     'orange_wool'
			display:  'Orange Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    15758867
			java:     ''
			tex:      ['orange_wool', 'orange_wool', 'orange_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'orange_wool', style: .noise, c1: 15758867, c2: 1 }]
		},
		BlockDef{
			name:     'magenta_wool'
			display:  'Magenta Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    12403891
			java:     ''
			tex:      ['magenta_wool', 'magenta_wool', 'magenta_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'magenta_wool', style: .noise, c1: 12403891, c2: 1 }]
		},
		BlockDef{
			name:     'light_blue_wool'
			display:  'Light Blue Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    3846105
			java:     ''
			tex:      ['light_blue_wool', 'light_blue_wool', 'light_blue_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'light_blue_wool', style: .noise, c1: 3846105, c2: 1 }]
		},
		BlockDef{
			name:     'yellow_wool'
			display:  'Yellow Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    16303399
			java:     ''
			tex:      ['yellow_wool', 'yellow_wool', 'yellow_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'yellow_wool', style: .noise, c1: 16303399, c2: 1 }]
		},
		BlockDef{
			name:     'lime_wool'
			display:  'Lime Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7387417
			java:     ''
			tex:      ['lime_wool', 'lime_wool', 'lime_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'lime_wool', style: .noise, c1: 7387417, c2: 1 }]
		},
		BlockDef{
			name:     'pink_wool'
			display:  'Pink Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    15568300
			java:     ''
			tex:      ['pink_wool', 'pink_wool', 'pink_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'pink_wool', style: .noise, c1: 15568300, c2: 1 }]
		},
		BlockDef{
			name:     'gray_wool'
			display:  'Gray Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    4080711
			java:     ''
			tex:      ['gray_wool', 'gray_wool', 'gray_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'gray_wool', style: .noise, c1: 4080711, c2: 1 }]
		},
		BlockDef{
			name:     'light_gray_wool'
			display:  'Light Gray Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    9342598
			java:     ''
			tex:      ['light_gray_wool', 'light_gray_wool', 'light_gray_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'light_gray_wool', style: .noise, c1: 9342598, c2: 1 }]
		},
		BlockDef{
			name:     'cyan_wool'
			display:  'Cyan Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    1411473
			java:     ''
			tex:      ['cyan_wool', 'cyan_wool', 'cyan_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'cyan_wool', style: .noise, c1: 1411473, c2: 1 }]
		},
		BlockDef{
			name:     'purple_wool'
			display:  'Purple Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7940780
			java:     ''
			tex:      ['purple_wool', 'purple_wool', 'purple_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'purple_wool', style: .noise, c1: 7940780, c2: 1 }]
		},
		BlockDef{
			name:     'blue_wool'
			display:  'Blue Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    3488157
			java:     ''
			tex:      ['blue_wool', 'blue_wool', 'blue_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'blue_wool', style: .noise, c1: 3488157, c2: 1 }]
		},
		BlockDef{
			name:     'brown_wool'
			display:  'Brown Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7489320
			java:     ''
			tex:      ['brown_wool', 'brown_wool', 'brown_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'brown_wool', style: .noise, c1: 7489320, c2: 1 }]
		},
		BlockDef{
			name:     'green_wool'
			display:  'Green Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5532955
			java:     ''
			tex:      ['green_wool', 'green_wool', 'green_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'green_wool', style: .noise, c1: 5532955, c2: 1 }]
		},
		BlockDef{
			name:     'red_wool'
			display:  'Red Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    10561314
			java:     ''
			tex:      ['red_wool', 'red_wool', 'red_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'red_wool', style: .noise, c1: 10561314, c2: 1 }]
		},
		BlockDef{
			name:     'black_wool'
			display:  'Black Wool'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    1316121
			java:     ''
			tex:      ['black_wool', 'black_wool', 'black_wool']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'black_wool', style: .noise, c1: 1316121, c2: 1 }]
		},
		BlockDef{
			name:     'white_concrete'
			display:  'White Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    15330540
			java:     ''
			tex:      ['white_concrete', 'white_concrete', 'white_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'white_concrete', style: .noise, c1: 15330540, c2: 0 }]
		},
		BlockDef{
			name:     'orange_concrete'
			display:  'Orange Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    15758867
			java:     ''
			tex:      ['orange_concrete', 'orange_concrete', 'orange_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'orange_concrete', style: .noise, c1: 15758867, c2: 0 }]
		},
		BlockDef{
			name:     'magenta_concrete'
			display:  'Magenta Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    12403891
			java:     ''
			tex:      ['magenta_concrete', 'magenta_concrete', 'magenta_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'magenta_concrete', style: .noise, c1: 12403891, c2: 0 }]
		},
		BlockDef{
			name:     'light_blue_concrete'
			display:  'Light Blue Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    3846105
			java:     ''
			tex:      ['light_blue_concrete', 'light_blue_concrete', 'light_blue_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'light_blue_concrete', style: .noise, c1: 3846105, c2: 0 }]
		},
		BlockDef{
			name:     'yellow_concrete'
			display:  'Yellow Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    16303399
			java:     ''
			tex:      ['yellow_concrete', 'yellow_concrete', 'yellow_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'yellow_concrete', style: .noise, c1: 16303399, c2: 0 }]
		},
		BlockDef{
			name:     'lime_concrete'
			display:  'Lime Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7387417
			java:     ''
			tex:      ['lime_concrete', 'lime_concrete', 'lime_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'lime_concrete', style: .noise, c1: 7387417, c2: 0 }]
		},
		BlockDef{
			name:     'pink_concrete'
			display:  'Pink Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    15568300
			java:     ''
			tex:      ['pink_concrete', 'pink_concrete', 'pink_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'pink_concrete', style: .noise, c1: 15568300, c2: 0 }]
		},
		BlockDef{
			name:     'gray_concrete'
			display:  'Gray Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    4080711
			java:     ''
			tex:      ['gray_concrete', 'gray_concrete', 'gray_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'gray_concrete', style: .noise, c1: 4080711, c2: 0 }]
		},
		BlockDef{
			name:     'light_gray_concrete'
			display:  'Light Gray Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    9342598
			java:     ''
			tex:      ['light_gray_concrete', 'light_gray_concrete', 'light_gray_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'light_gray_concrete', style: .noise, c1: 9342598, c2: 0 }]
		},
		BlockDef{
			name:     'cyan_concrete'
			display:  'Cyan Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    1411473
			java:     ''
			tex:      ['cyan_concrete', 'cyan_concrete', 'cyan_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'cyan_concrete', style: .noise, c1: 1411473, c2: 0 }]
		},
		BlockDef{
			name:     'purple_concrete'
			display:  'Purple Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7940780
			java:     ''
			tex:      ['purple_concrete', 'purple_concrete', 'purple_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'purple_concrete', style: .noise, c1: 7940780, c2: 0 }]
		},
		BlockDef{
			name:     'blue_concrete'
			display:  'Blue Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    3488157
			java:     ''
			tex:      ['blue_concrete', 'blue_concrete', 'blue_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'blue_concrete', style: .noise, c1: 3488157, c2: 0 }]
		},
		BlockDef{
			name:     'brown_concrete'
			display:  'Brown Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7489320
			java:     ''
			tex:      ['brown_concrete', 'brown_concrete', 'brown_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'brown_concrete', style: .noise, c1: 7489320, c2: 0 }]
		},
		BlockDef{
			name:     'green_concrete'
			display:  'Green Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    5532955
			java:     ''
			tex:      ['green_concrete', 'green_concrete', 'green_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'green_concrete', style: .noise, c1: 5532955, c2: 0 }]
		},
		BlockDef{
			name:     'red_concrete'
			display:  'Red Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    10561314
			java:     ''
			tex:      ['red_concrete', 'red_concrete', 'red_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'red_concrete', style: .noise, c1: 10561314, c2: 0 }]
		},
		BlockDef{
			name:     'black_concrete'
			display:  'Black Concrete'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    1316121
			java:     ''
			tex:      ['black_concrete', 'black_concrete', 'black_concrete']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'black_concrete', style: .noise, c1: 1316121, c2: 0 }]
		},
		BlockDef{
			name:     'oak_planks'
			display:  'Oak Planks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    10650189
			java:     ''
			tex:      ['oak_planks', 'oak_planks', 'oak_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'oak_planks', style: .planks, c1: 10650189, c2: 0 }]
		},
		BlockDef{
			name:     'oak_log'
			display:  'Oak Log'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    7033392
			java:     ''
			tex:      ['oak_log_top', 'oak_log', 'oak_log_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'oak_log_top', style: .log_top, c1: 7033392, c2: 10650189 },
				TexRecipe{ name: 'oak_log', style: .log_side, c1: 7033392, c2: 10650189 }]
		},
		BlockDef{
			name:     'oak_leaves'
			display:  'Oak Leaves'
			kind:     .cube_all
			tint:     .foliage
			flags:    529
			emit:     0
			color:    4764952
			java:     ''
			tex:      ['oak_leaves', 'oak_leaves', 'oak_leaves']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'oak_leaves', style: .leaves, c1: 4764952, c2: 0 }]
		},
		BlockDef{
			name:     'oak_slab'
			display:  'Oak Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    10650189
			java:     ''
			tex:      ['oak_planks', 'oak_planks', 'oak_planks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'oak_stairs'
			display:  'Oak Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    10650189
			java:     ''
			tex:      ['oak_planks', 'oak_planks', 'oak_planks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'spruce_planks'
			display:  'Spruce Planks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    7558448
			java:     ''
			tex:      ['spruce_planks', 'spruce_planks', 'spruce_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'spruce_planks', style: .planks, c1: 7558448, c2: 0 }]
		},
		BlockDef{
			name:     'spruce_log'
			display:  'Spruce Log'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    3877138
			java:     ''
			tex:      ['spruce_log_top', 'spruce_log', 'spruce_log_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'spruce_log_top', style: .log_top, c1: 3877138, c2: 7558448 },
				TexRecipe{ name: 'spruce_log', style: .log_side, c1: 3877138, c2: 7558448 }]
		},
		BlockDef{
			name:     'spruce_leaves'
			display:  'Spruce Leaves'
			kind:     .cube_all
			tint:     .spruce
			flags:    529
			emit:     0
			color:    6396257
			java:     ''
			tex:      ['spruce_leaves', 'spruce_leaves', 'spruce_leaves']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'spruce_leaves', style: .leaves, c1: 6396257, c2: 0 }]
		},
		BlockDef{
			name:     'spruce_slab'
			display:  'Spruce Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    7558448
			java:     ''
			tex:      ['spruce_planks', 'spruce_planks', 'spruce_planks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'spruce_stairs'
			display:  'Spruce Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    7558448
			java:     ''
			tex:      ['spruce_planks', 'spruce_planks', 'spruce_planks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'birch_planks'
			display:  'Birch Planks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    12891258
			java:     ''
			tex:      ['birch_planks', 'birch_planks', 'birch_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'birch_planks', style: .planks, c1: 12891258, c2: 0 }]
		},
		BlockDef{
			name:     'birch_log'
			display:  'Birch Log'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    14210509
			java:     ''
			tex:      ['birch_log_top', 'birch_log', 'birch_log_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'birch_log_top', style: .log_top, c1: 14210509, c2: 12891258 },
				TexRecipe{ name: 'birch_log', style: .log_side, c1: 14210509, c2: 12891258 }]
		},
		BlockDef{
			name:     'birch_leaves'
			display:  'Birch Leaves'
			kind:     .cube_all
			tint:     .birch
			flags:    529
			emit:     0
			color:    8431445
			java:     ''
			tex:      ['birch_leaves', 'birch_leaves', 'birch_leaves']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'birch_leaves', style: .leaves, c1: 8431445, c2: 0 }]
		},
		BlockDef{
			name:     'birch_slab'
			display:  'Birch Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    12891258
			java:     ''
			tex:      ['birch_planks', 'birch_planks', 'birch_planks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'birch_stairs'
			display:  'Birch Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    12891258
			java:     ''
			tex:      ['birch_planks', 'birch_planks', 'birch_planks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'jungle_planks'
			display:  'Jungle Planks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    10843727
			java:     ''
			tex:      ['jungle_planks', 'jungle_planks', 'jungle_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'jungle_planks', style: .planks, c1: 10843727, c2: 0 }]
		},
		BlockDef{
			name:     'jungle_log'
			display:  'Jungle Log'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    5653529
			java:     ''
			tex:      ['jungle_log_top', 'jungle_log', 'jungle_log_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'jungle_log_top', style: .log_top, c1: 5653529, c2: 10843727 },
				TexRecipe{ name: 'jungle_log', style: .log_side, c1: 5653529, c2: 10843727 }]
		},
		BlockDef{
			name:     'jungle_leaves'
			display:  'Jungle Leaves'
			kind:     .cube_all
			tint:     .foliage
			flags:    529
			emit:     0
			color:    3193611
			java:     ''
			tex:      ['jungle_leaves', 'jungle_leaves', 'jungle_leaves']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'jungle_leaves', style: .leaves, c1: 3193611, c2: 0 }]
		},
		BlockDef{
			name:     'acacia_planks'
			display:  'Acacia Planks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    11032114
			java:     ''
			tex:      ['acacia_planks', 'acacia_planks', 'acacia_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'acacia_planks', style: .planks, c1: 11032114, c2: 0 }]
		},
		BlockDef{
			name:     'acacia_log'
			display:  'Acacia Log'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    7038558
			java:     ''
			tex:      ['acacia_log_top', 'acacia_log', 'acacia_log_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'acacia_log_top', style: .log_top, c1: 7038558, c2: 11032114 },
				TexRecipe{ name: 'acacia_log', style: .log_side, c1: 7038558, c2: 11032114 }]
		},
		BlockDef{
			name:     'acacia_leaves'
			display:  'Acacia Leaves'
			kind:     .cube_all
			tint:     .foliage
			flags:    529
			emit:     0
			color:    5024300
			java:     ''
			tex:      ['acacia_leaves', 'acacia_leaves', 'acacia_leaves']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'acacia_leaves', style: .leaves, c1: 5024300, c2: 0 }]
		},
		BlockDef{
			name:     'dark_oak_planks'
			display:  'Dark Oak Planks'
			kind:     .cube_all
			tint:     .none
			flags:    3
			emit:     0
			color:    4335887
			java:     ''
			tex:      ['dark_oak_planks', 'dark_oak_planks', 'dark_oak_planks']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'dark_oak_planks', style: .planks, c1: 4335887, c2: 0 }]
		},
		BlockDef{
			name:     'dark_oak_log'
			display:  'Dark Oak Log'
			kind:     .column
			tint:     .none
			flags:    3
			emit:     0
			color:    2957843
			java:     ''
			tex:      ['dark_oak_log_top', 'dark_oak_log', 'dark_oak_log_top']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'dark_oak_log_top', style: .log_top, c1: 2957843, c2: 4335887 },
				TexRecipe{ name: 'dark_oak_log', style: .log_side, c1: 2957843, c2: 4335887 }]
		},
		BlockDef{
			name:     'dark_oak_leaves'
			display:  'Dark Oak Leaves'
			kind:     .cube_all
			tint:     .foliage
			flags:    529
			emit:     0
			color:    3110936
			java:     ''
			tex:      ['dark_oak_leaves', 'dark_oak_leaves', 'dark_oak_leaves']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'dark_oak_leaves', style: .leaves, c1: 3110936, c2: 0 }]
		},
		BlockDef{
			name:     'cobblestone_slab'
			display:  'Cobblestone Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    8026746
			java:     ''
			tex:      ['cobblestone', 'cobblestone', 'cobblestone']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'stone_stairs'
			display:  'Cobblestone Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    8026746
			java:     'cobblestone_stairs'
			tex:      ['cobblestone', 'cobblestone', 'cobblestone']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'stone_brick_slab'
			display:  'Stone Brick Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    8026746
			java:     ''
			tex:      ['stone_bricks', 'stone_bricks', 'stone_bricks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'stone_brick_stairs'
			display:  'Stone Brick Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    8026746
			java:     ''
			tex:      ['stone_bricks', 'stone_bricks', 'stone_bricks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'brick_slab'
			display:  'Brick Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    9855055
			java:     ''
			tex:      ['bricks', 'bricks', 'bricks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'brick_stairs'
			display:  'Brick Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    9855055
			java:     ''
			tex:      ['bricks', 'bricks', 'bricks']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'sandstone_slab'
			display:  'Sandstone Slab'
			kind:     .slab
			tint:     .none
			flags:    1
			emit:     0
			color:    14471328
			java:     ''
			tex:      ['sandstone_top', 'sandstone', 'sandstone_bottom']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'sandstone_stairs'
			display:  'Sandstone Stairs'
			kind:     .stairs
			tint:     .none
			flags:    1
			emit:     0
			color:    14471328
			java:     ''
			tex:      ['sandstone_top', 'sandstone', 'sandstone_bottom']!
			overlay:  ''
			creative: true
			recipes:  []
		},
		BlockDef{
			name:     'short_grass'
			display:  'Short Grass'
			kind:     .cross
			tint:     .grass
			flags:    280
			emit:     0
			color:    8108874
			java:     ''
			tex:      ['short_grass', 'short_grass', 'short_grass']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'short_grass', style: .plant, c1: 8108874, c2: 0 }]
		},
		BlockDef{
			name:     'fern'
			display:  'Fern'
			kind:     .cross
			tint:     .grass
			flags:    280
			emit:     0
			color:    7055946
			java:     ''
			tex:      ['fern', 'fern', 'fern']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'fern', style: .fern, c1: 7055946, c2: 0 }]
		},
		BlockDef{
			name:     'deadbush'
			display:  'Dead Bush'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    9071162
			java:     'dead_bush'
			tex:      ['dead_bush', 'dead_bush', 'dead_bush']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'dead_bush', style: .dead_bush, c1: 9071162, c2: 0 }]
		},
		BlockDef{
			name:     'dandelion'
			display:  'Dandelion'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    15786016
			java:     ''
			tex:      ['dandelion', 'dandelion', 'dandelion']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'dandelion', style: .flower, c1: 15786016, c2: 15786016 }]
		},
		BlockDef{
			name:     'poppy'
			display:  'Poppy'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    13639712
			java:     ''
			tex:      ['poppy', 'poppy', 'poppy']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'poppy', style: .flower, c1: 13639712, c2: 13639712 }]
		},
		BlockDef{
			name:     'blue_orchid'
			display:  'Blue Orchid'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    3191024
			java:     ''
			tex:      ['blue_orchid', 'blue_orchid', 'blue_orchid']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'blue_orchid', style: .flower, c1: 3191024, c2: 3191024 }]
		},
		BlockDef{
			name:     'allium'
			display:  'Allium'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    11559136
			java:     ''
			tex:      ['allium', 'allium', 'allium']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'allium', style: .flower, c1: 11559136, c2: 11559136 }]
		},
		BlockDef{
			name:     'azure_bluet'
			display:  'Azure Bluet'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    15263968
			java:     ''
			tex:      ['azure_bluet', 'azure_bluet', 'azure_bluet']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'azure_bluet', style: .flower, c1: 15263968, c2: 15263968 }]
		},
		BlockDef{
			name:     'red_tulip'
			display:  'Red Tulip'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    14696496
			java:     ''
			tex:      ['red_tulip', 'red_tulip', 'red_tulip']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'red_tulip', style: .flower, c1: 14696496, c2: 14696496 }]
		},
		BlockDef{
			name:     'pink_tulip'
			display:  'Pink Tulip'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    15769792
			java:     ''
			tex:      ['pink_tulip', 'pink_tulip', 'pink_tulip']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'pink_tulip', style: .flower, c1: 15769792, c2: 15769792 }]
		},
		BlockDef{
			name:     'oxeye_daisy'
			display:  'Oxeye Daisy'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    16053488
			java:     ''
			tex:      ['oxeye_daisy', 'oxeye_daisy', 'oxeye_daisy']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'oxeye_daisy', style: .flower, c1: 16053488, c2: 16053488 }]
		},
		BlockDef{
			name:     'cornflower'
			display:  'Cornflower'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    4219104
			java:     ''
			tex:      ['cornflower', 'cornflower', 'cornflower']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'cornflower', style: .flower, c1: 4219104, c2: 4219104 }]
		},
		BlockDef{
			name:     'lily_of_the_valley'
			display:  'Lily of the Valley'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    16316664
			java:     ''
			tex:      ['lily_of_the_valley', 'lily_of_the_valley', 'lily_of_the_valley']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'lily_of_the_valley', style: .flower, c1: 16316664, c2: 16316664 }]
		},
		BlockDef{
			name:     'brown_mushroom'
			display:  'Brown Mushroom'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    9071178
			java:     ''
			tex:      ['brown_mushroom', 'brown_mushroom', 'brown_mushroom']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'brown_mushroom', style: .mushroom, c1: 9071178, c2: 9071178 }]
		},
		BlockDef{
			name:     'red_mushroom'
			display:  'Red Mushroom'
			kind:     .cross
			tint:     .none
			flags:    272
			emit:     0
			color:    13643824
			java:     ''
			tex:      ['red_mushroom', 'red_mushroom', 'red_mushroom']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'red_mushroom', style: .mushroom, c1: 13643824, c2: 13643824 }]
		},
		BlockDef{
			name:     'oak_sapling'
			display:  'Oak Sapling'
			kind:     .cross
			tint:     .none
			flags:    280
			emit:     0
			color:    5021744
			java:     ''
			tex:      ['oak_sapling', 'oak_sapling', 'oak_sapling']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'oak_sapling', style: .plant, c1: 5021744, c2: 0 }]
		},
		BlockDef{
			name:     'reeds'
			display:  'Sugar Cane'
			kind:     .cross
			tint:     .grass
			flags:    272
			emit:     0
			color:    9486432
			java:     'sugar_cane'
			tex:      ['sugar_cane', 'sugar_cane', 'sugar_cane']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'sugar_cane', style: .reeds, c1: 9486432, c2: 0 }]
		},
		BlockDef{
			name:     'cactus'
			display:  'Cactus'
			kind:     .cactus
			tint:     .none
			flags:    17
			emit:     0
			color:    3046706
			java:     ''
			tex:      ['cactus_top', 'cactus_side', 'cactus_bottom']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'cactus_top', style: .cactus, c1: 3046706, c2: 1 },
				TexRecipe{ name: 'cactus_side', style: .cactus, c1: 3046706, c2: 0 },
				TexRecipe{ name: 'cactus_bottom', style: .cactus, c1: 3046706, c2: 1 }]
		},
		BlockDef{
			name:     'torch'
			display:  'Torch'
			kind:     .torch
			tint:     .none
			flags:    80
			emit:     14
			color:    16760896
			java:     ''
			tex:      ['torch', 'torch', 'torch']!
			overlay:  ''
			creative: true
			recipes:  [TexRecipe{ name: 'torch', style: .torch, c1: 16760896, c2: 0 }]
		},
		BlockDef{
			name:     'water'
			display:  'Water'
			kind:     .liquid
			tint:     .water
			flags:    1068
			emit:     0
			color:    4159204
			java:     ''
			tex:      ['water_still', 'water_still', 'water_still']!
			overlay:  ''
			creative: false
			recipes:  [TexRecipe{ name: 'water_still', style: .water, c1: 4159204, c2: 0 }]
		},
		BlockDef{
			name:     'lava'
			display:  'Lava'
			kind:     .liquid
			tint:     .none
			flags:    1100
			emit:     15
			color:    14704656
			java:     ''
			tex:      ['lava_still', 'lava_still', 'lava_still']!
			overlay:  ''
			creative: false
			recipes:  [TexRecipe{ name: 'lava_still', style: .lava, c1: 14704656, c2: 0 }]
		},
	]
}

pub fn find_def(name string) ?BlockDef {
	for d in builtin_defs() { if d.name == name { return d } }
	return none
}
