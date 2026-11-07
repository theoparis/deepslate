module main

import os
import vinecraft.app
import vinecraft.assets
import vinecraft.cli

fn main() {
	opt := cli.parse(os.args[1..]) or {
		eprintln(err)
		exit(2)
	}
	if opt.help {
		print(cli.usage)
		return
	}
	if opt.export_pack != '' {
		assets.export_builtin_pack_zip(opt.export_pack) or {
			eprintln('error: ${err}')
			exit(1)
		}
		println('wrote ${opt.export_pack}')
		return
	}
	code := app.run(opt)
	if code != 0 { exit(code) }
}
