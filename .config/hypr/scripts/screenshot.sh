#!/usr/bin/env bash
# usage: screenshot.sh region|window|output [output-name]
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d-%H%M%S).png"

slurp_opts=(
  -b '#1e1e2e80'   # base overlay
  -c '#74c7ecff'   # sapphire border
  -s '#74c7ec22'   # sapphire fill
  -w 2
  -F 'JetBrainsMono Nerd Font'
  -d               # WxH
)

case "$1" in
  region)
    geom=$(slurp "${slurp_opts[@]}") || exit 0 ;;
  window)
    if [ -n "$SWAYSOCK" ]; then
      boxes=$(swaymsg -t get_tree | jq -r '.. | select(.pid? and .visible?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"')
    else
      ws=$(hyprctl monitors -j | jq -c '[.[].activeWorkspace.id]')
      boxes=$(hyprctl clients -j | jq -r --argjson ws "$ws" \
        '.[] | select(.workspace.id as $w | $ws | index($w)) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    fi
    geom=$(slurp "${slurp_opts[@]}" -r <<< "$boxes") || exit 0 ;;
  output)
    out=${2:-$(swaymsg -t get_outputs -r | jq -r '.[] | select(.focused) | .name')} ;;
  *) exit 1 ;;
esac

if [ "$1" = output ]; then
  grim -o "$out" "$file" || exit 1
else
  grim -g "$geom" "$file" || exit 1
fi

wl-copy --type image/png < "$file"
notify-send -a Screenshot -i "$file" "Screenshot saved" "$file"
