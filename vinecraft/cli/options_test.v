module cli

fn test_parses_game_options() {
	opt := parse(['--world', 'world', '--seed', '-7', '--resource-pack', 'a.zip', '--pack', 'b',
		'--size', '640x360', '--pos', '-1', '2.5', '3', '--no-save', '--frames', '12']) or { panic(err) }
	assert opt.world_dir == 'world'
	assert opt.seed or { 0 } == -7
	assert opt.packs == ['a.zip', 'b']
	assert opt.width == 640 && opt.height == 360
	assert opt.start_pos or { [f64(0), 0, 0]! } == [f64(-1), 2.5, 3]!
	assert opt.no_save && opt.max_frames == 12
}

fn test_rejects_missing_and_unknown_options() {
	parse(['--world']) or {
		assert err.msg().contains('missing value')
		return
	}
	assert false
}

fn test_rejects_unknown_option() {
	parse(['--not-an-option']) or {
		assert err.msg().contains('unknown option')
		return
	}
	assert false
}
