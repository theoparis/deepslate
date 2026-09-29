#!/bin/sh
# End-to-end test: generate a world, edit it, save, restart and verify the edits came back
# from the Bedrock-format LevelDB. Usage: smoke.sh <deepslate binary> <scratch dir>
set -eu
BIN="$1"; DIR="$2"
rm -rf "$DIR"; mkdir -p "$DIR"
run() {
  xvfb-run -a -s "-screen 0 1024x768x24" "$BIN" --size 640x360 --render-distance 4 --threads 3 --time 6000 "$@" > "$DIR/log.txt" 2>&1 || true
  cat "$DIR/log.txt"
}
# 1st launch: fall to the ground, hover 2 blocks up, dig the block below, put stone back.
run --world "$DIR/w" --seed 7 --script \
  "tp 100.5 150 100.5;idle;ground;assert_ground;nudge 0 2 0;fly on;look 0 90;wait 5;mark;break;wait 3;assert_marked air;select 2;place;wait 3;assert_marked stone;shot $DIR/a.png;save;quit" >/dev/null
if grep -q "FAIL" "$DIR/log.txt"; then echo "first launch failed"; exit 1; fi
read -r X Y Z <<EOF2
$(sed -n 's/.*script: MARK \([-0-9]*\) \([-0-9]*\) \([-0-9]*\)/\1 \2 \3/p' "$DIR/log.txt")
EOF2
echo "edited block: $X $Y $Z"
test -n "$X"
# 2nd launch: no seed given, the world (and edits) must come from disk, nothing regenerated.
run --world "$DIR/w" --script "idle;wait 3;assert_block $X $Y $Z stone;shot $DIR/b.png;quit" >/dev/null
if grep -q "FAIL" "$DIR/log.txt"; then echo "second launch failed"; exit 1; fi
grep -q "loaded world" "$DIR/log.txt"
grep -qE "0 generated, [1-9][0-9]* loaded from disk" "$DIR/log.txt"
test -s "$DIR/a.png"; test -s "$DIR/b.png"
test -f "$DIR/w/level.dat"; test -s "$DIR/w/db/CURRENT"
echo "smoke OK"
