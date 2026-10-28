#!/bin/sh
# usage: dpms.sh on|off
case "$1" in on|off) ;; *) exit 1 ;; esac
if [ -n "$SWAYSOCK" ]; then
  swaymsg "output * power $1"
else
  hyprctl dispatch "hl.dsp.dpms({ action = \"$1\" })" # to avoid having to press a key twice to turn on the display.
fi
