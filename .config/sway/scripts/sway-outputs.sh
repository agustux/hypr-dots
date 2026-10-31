#!/bin/sh
J=$(swaymsg -t get_outputs -r)

primary=$(printf '%s' "$J" | jq -r '[.[].name] as $n
  | (($n | map(select(test("^(eDP|LVDS)"))) | .[0]) // $n[0])')

mode=$(printf '%s' "$J" | jq -r --arg o "$primary" '
  .[] | select(.name == $o) | .modes as $m
  | $m[0].width as $nw | $m[0].height as $nh
  | ([$m[] | select(.width <= 1920
        and (((.width / .height) - ($nw / $nh)) | fabs) < 0.01
        and .refresh >= 59500 and .refresh <= 60500)]
     | sort_by((.refresh - 60000) | fabs) | .[0]) as $best
  | if $best then "\($best.width)x\($best.height)@\($best.refresh / 1000)Hz"
    elif $nw > 1920 then "--custom 1920x\(($nh * 1920 / $nw) | round)@60Hz"
    else "" end')

# $mode intentionally unquoted (may contain --custom)
[ -n "$mode" ] && swaymsg output "$primary" mode $mode position 0 0 scale 1

# Mirror other outputs (sway has no native mirroring)
pkill -x wl-mirror
for o in $(printf '%s' "$J" | jq -r --arg p "$primary" '.[] | select(.name != $p) | .name'); do
  swaymsg output "$o" enable
  setsid wl-mirror --fullscreen-output "$o" "$primary" >/dev/null 2>&1 &
done
