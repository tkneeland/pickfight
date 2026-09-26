# usage: probe_all.sh <project> <outfile> [seconds]
P=$1; O=$2; S=${3:-600}; : > $O
for st in Flatlands Pillars Ferry Highrise Erosion Islands Furnace Gauntlet Cascade Slant Bowl Springboard Gale Carousel Rockfall Sinkhole Bulwark; do
  for sd in 1 2 3; do echo "$st $sd"; done
done | xargs -P 6 -n 2 sh -c 'godot --headless --path '"$P"' --fixed-fps 60 -s tools/ringout_probe.gd -- --stage=$0 --seconds='"$S"' --seed=$1 2>&1 | grep RINGOUT' >> $O
