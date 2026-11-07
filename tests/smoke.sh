#!/bin/sh
# Exercise the real Sokol game, then reopen the edited Bedrock world.
set -eu
BIN="$1"
mkdir -p "$2"
DIR=$(mktemp -d "$2/vinecraft-smoke.XXXXXX")
trap 'rm -rf "$DIR"' EXIT HUP INT TERM
run() {
  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a -s '-screen 0 1024x768x24' "$BIN" --size 640x360 --render-distance 2 --threads 4 --time 6000 "$@" > "$DIR/log.txt" 2>&1
  else
    "$BIN" --size 640x360 --render-distance 2 --threads 4 --time 6000 "$@" > "$DIR/log.txt" 2>&1
  fi
  cat "$DIR/log.txt"
}
run --world "$DIR/w" --seed 7 --script \
  "tp 100.5 150 100.5;idle;ground;assert_ground;nudge 0 2 0;fly on;look 0 90;wait 5;mark;break;wait 3;assert_marked air;select 2;place;wait 3;assert_marked stone;shot $DIR/a.png;save;quit"
read -r X Y Z <<EOF2
$(awk '/script: MARK / { print $3, $4, $5; exit }' "$DIR/log.txt")
EOF2
test -n "$X" && test -n "$Y" && test -n "$Z"
run --world "$DIR/w" --script "idle;assert_block $X $Y $Z stone;shot $DIR/b.png;quit"
test -s "$DIR/a.png" && test -s "$DIR/b.png"
test -f "$DIR/w/level.dat" && test -s "$DIR/w/db/CURRENT"
echo 'smoke OK'
