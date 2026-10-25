#!/usr/bin/env bash

############ Variables ############
enable_battery=false
battery_charging=false

####### Check availability ########
for battery in /sys/class/power_supply/*BAT*; do
  if [[ -f "$battery/uevent" && -f "$battery/capacity" ]]; then
    enable_battery=true
    if [[ $(cat "$battery/status" 2>/dev/null) == "Charging" ]]; then
      battery_charging=true
    fi
    battery_path="$battery"
    break
  fi
done

############# Output #############
if [[ $enable_battery == true ]]; then
  if [[ $battery_charging == true ]]; then
    echo -n "(+) "
  fi
  echo -n "$(cat "$battery_path/capacity" 2>/dev/null)"%
  if [[ $battery_charging == false ]]; then
    echo -n " remaining"
  fi
fi

echo ''