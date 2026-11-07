module assets

const model_cube = r'{"elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{
"down":{"texture":"#down","cullface":"down"},"up":{"texture":"#up","cullface":"up"},
"north":{"texture":"#north","cullface":"north"},"south":{"texture":"#south","cullface":"south"},
"west":{"texture":"#west","cullface":"west"},"east":{"texture":"#east","cullface":"east"}}}]}'
const model_cube_all = r'{"parent":"minecraft:block/cube","textures":{"particle":"#all","down":"#all","up":"#all","north":"#all","east":"#all","south":"#all","west":"#all"}}'
const model_cube_column = r'{"parent":"minecraft:block/cube","textures":{"particle":"#side","down":"#end","up":"#end","north":"#side","east":"#side","south":"#side","west":"#side"}}'
const model_cube_bottom_top = r'{"parent":"minecraft:block/cube","textures":{"particle":"#side","down":"#bottom","up":"#top","north":"#side","east":"#side","south":"#side","west":"#side"}}'
const model_leaves = r'{"parent":"minecraft:block/cube_all","elements":[{"from":[0,0,0],"to":[16,16,16],"faces":{
"down":{"texture":"#all","cullface":"down","tintindex":0},"up":{"texture":"#all","cullface":"up","tintindex":0},
"north":{"texture":"#all","cullface":"north","tintindex":0},"south":{"texture":"#all","cullface":"south","tintindex":0},
"west":{"texture":"#all","cullface":"west","tintindex":0},"east":{"texture":"#all","cullface":"east","tintindex":0}}}]}'
const model_cross = r'{"ambientocclusion":false,"textures":{"particle":"#cross"},"elements":[
{"from":[0.8,0,8],"to":[15.2,16,8],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"north":{"uv":[0,0,16,16],"texture":"#cross"},"south":{"uv":[0,0,16,16],"texture":"#cross"}}},
{"from":[8,0,0.8],"to":[8,16,15.2],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"west":{"uv":[0,0,16,16],"texture":"#cross"},"east":{"uv":[0,0,16,16],"texture":"#cross"}}}]}'
const model_tinted_cross = r'{"ambientocclusion":false,"textures":{"particle":"#cross"},"elements":[
{"from":[0.8,0,8],"to":[15.2,16,8],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"north":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0},"south":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0}}},
{"from":[8,0,0.8],"to":[8,16,15.2],"rotation":{"origin":[8,8,8],"axis":"y","angle":45,"rescale":true},"shade":false,"faces":{"west":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0},"east":{"uv":[0,0,16,16],"texture":"#cross","tintindex":0}}}]}'
const model_slab = r'{"textures":{"particle":"#side"},"elements":[{"from":[0,0,0],"to":[16,8,16],"faces":{
"down":{"texture":"#bottom","cullface":"down"},"up":{"texture":"#top"},"north":{"texture":"#side","cullface":"north"},
"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side","cullface":"west"},"east":{"texture":"#side","cullface":"east"}}}]}'
const model_slab_top = r'{"textures":{"particle":"#side"},"elements":[{"from":[0,8,0],"to":[16,16,16],"faces":{
"down":{"texture":"#bottom"},"up":{"texture":"#top","cullface":"up"},"north":{"texture":"#side","cullface":"north"},
"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side","cullface":"west"},"east":{"texture":"#side","cullface":"east"}}}]}'
const model_stairs = r'{"textures":{"particle":"#side"},"elements":[
{"from":[0,0,0],"to":[16,8,16],"faces":{"down":{"texture":"#bottom","cullface":"down"},"up":{"texture":"#top"},
"north":{"texture":"#side","cullface":"north"},"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side","cullface":"west"},"east":{"texture":"#side","cullface":"east"}}},
{"from":[8,8,0],"to":[16,16,16],"faces":{"up":{"texture":"#top","cullface":"up"},"north":{"texture":"#side","cullface":"north"},
"south":{"texture":"#side","cullface":"south"},"west":{"texture":"#side"},"east":{"texture":"#side","cullface":"east"}}}]}'
const model_torch = r'{"textures":{"particle":"#torch"},"elements":[{"from":[7,0,7],"to":[9,10,9],"shade":false,"faces":{
"down":{"uv":[7,13,9,15],"texture":"#torch"},"up":{"uv":[7,6,9,8],"texture":"#torch"},
"north":{"uv":[7,6,9,16],"texture":"#torch"},"south":{"uv":[7,6,9,16],"texture":"#torch"},
"west":{"uv":[7,6,9,16],"texture":"#torch"},"east":{"uv":[7,6,9,16],"texture":"#torch"}}}]}'
const model_torch_wall = r'{"textures":{"particle":"#torch"},"elements":[{"from":[-1,3.5,7],"to":[1,13.5,9],"rotation":{"origin":[0,3.5,8],"axis":"z","angle":-22.5},"shade":false,"faces":{
"down":{"uv":[7,13,9,15],"texture":"#torch"},"up":{"uv":[7,6,9,8],"texture":"#torch"},
"north":{"uv":[7,6,9,16],"texture":"#torch"},"south":{"uv":[7,6,9,16],"texture":"#torch"},
"west":{"uv":[7,6,9,16],"texture":"#torch"},"east":{"uv":[7,6,9,16],"texture":"#torch"}}}]}'
const model_cactus = r'{"textures":{"particle":"#side"},"elements":[{"from":[1,0,1],"to":[15,16,15],"faces":{
"down":{"texture":"#bottom","cullface":"down"},"up":{"texture":"#top","cullface":"up"},"north":{"texture":"#side"},
"south":{"texture":"#side"},"west":{"texture":"#side"},"east":{"texture":"#side"}}}]}'
