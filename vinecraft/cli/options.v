module cli

pub const usage = 'Vinecraft - single-player Bedrock-style voxel game

Usage: vinecraft [options]
  --resource-pack <zip|dir|url>  Resource pack; may be repeated, earlier packs win
  --world <dir>                  Bedrock world directory
  --seed <n>                     Seed for a new world
  --render-distance <chunks>     2..32 (default 10)
  --threads <n>                  Worker threads (default: cores - 1)
  --size <w>x<h>                 Window size (default 1280x720)
  --fullscreen                   Start fullscreen
  --no-vsync                     Disable vsync
  --pos <x> <y> <z>              Start position
  --yaw <deg> --pitch <deg>      Start orientation
  --time <ticks>                 Start time of day
  --script \"<a;b;c>\"             Scripted actions
  --frames <n>                   Exit after n frames
  --no-save                      Do not save the world
  --write-builtin-pack <zip>     Write the built-in resource pack and exit
  --verbose                      Debug logging
  --help

Script actions: wait N | idle | ground | setblock X Y Z NAME [k=v..] | nudge DX DY DZ |
mark | assert_marked NAME | shot FILE | tp X Y Z | look YAW PITCH | break | place |
select N | time T | freeze | fly on|off | walk FWD STRAFE FRAMES | jump FRAMES |
inv | radius N | save | debug | log MSG | assert_block X Y Z NAME |
assert_target NAME | assert_ground | quit

Controls: WASD move, Space jump (double-tap: toggle flight), Shift sneak/descend,
Ctrl or double-tap W sprint, mouse look, LMB break, RMB place, MMB pick block,
1-9 / wheel hotbar, E inventory, F3 debug, F1 hide HUD, F2 screenshot,
F11 fullscreen, -/= render distance, PgUp/PgDn time of day, T freeze time, Esc menu.
'

// Options describes the game's command line configuration.
pub struct Options {
pub mut:
	packs           []string
	world_dir       string = 'worlds/NewWorld'
	seed            ?i64
	render_distance int = 10
	threads         int
	width           int = 1280
	height          int = 720
	fullscreen      bool
	vsync           bool = true
	start_pos       ?[3]f64
	yaw             ?f32
	pitch           ?f32
	time            ?i64
	script          string
	max_frames      int = -1
	no_save         bool
	verbose         bool
	export_pack     string
	help            bool
}

struct Cursor {
	args []string
mut:
	i int
}

fn (mut c Cursor) value(name string) !string {
	if c.i + 1 >= c.args.len { return error('missing value for ${name}') }
	c.i++
	return c.args[c.i]
}

pub fn parse(args []string) !Options {
	mut opt := Options{}
	mut c := Cursor{ args: args }
	for c.i < args.len {
		a := args[c.i]
		match a {
			'--help', '-h' {
				opt.help = true
				return opt
			}
			'--resource-pack', '--pack' { opt.packs << c.value('--resource-pack')! }
			'--world' { opt.world_dir = c.value(a)! }
			'--seed' { opt.seed = c.value(a)!.i64() }
			'--render-distance' { opt.render_distance = c.value(a)!.int() }
			'--threads' { opt.threads = c.value(a)!.int() }
			'--size' {
				size := c.value(a)!.split('x')
				if size.len != 2 { return error('bad --size') }
				opt.width = size[0].int()
				opt.height = size[1].int()
			}
			'--fullscreen' { opt.fullscreen = true }
			'--no-vsync' { opt.vsync = false }
			'--pos' {
				x := c.value(a)!.f64()
				y := c.value(a)!.f64()
				z := c.value(a)!.f64()
				opt.start_pos = [x, y, z]!
			}
			'--yaw' { opt.yaw = c.value(a)!.f32() }
			'--pitch' { opt.pitch = c.value(a)!.f32() }
			'--time' { opt.time = c.value(a)!.i64() }
			'--script' { opt.script = c.value(a)! }
			'--frames' { opt.max_frames = c.value(a)!.int() }
			'--no-save' { opt.no_save = true }
			'--write-builtin-pack' { opt.export_pack = c.value(a)! }
			'--verbose' { opt.verbose = true }
			else { return error('unknown option ${a} (see --help)') }
		}
		c.i++
	}
	return opt
}
