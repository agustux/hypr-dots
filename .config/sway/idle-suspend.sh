#!/bin/sh
for f in /sys/class/power_supply/*/type; do
  [ "$(cat "$f")" = Mains ] && [ "$(cat "${f%type}online")" = 1 ] && exit
done
systemctl suspend
