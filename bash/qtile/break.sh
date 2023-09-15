#!/bin/bash
# 
# Script to take a break after using the computer for 2 hours (not taking
# into account suspended time)
#

# This script assumes that the file '/tmp/start_session.tmp' has not been
# tampered with
limit="2h"

# Sleep for 2 hours
sleep "$limit"

notify-send -t 0 -i "/home/juanma/.config/safeeyes/icons/eye-health.svg" \
  "Take a break" "<span color='red'><b>You have been using the PC for $limit</b>\nTake a break of at least 30 min</span>"

sleep 5m

# Count for time elapsed in min after the limit
extra=5
while true
do
  notify-send -t 0 -i "/home/juanma/.config/safeeyes/icons/eye-health.svg" \
    "Take a break" "<span color='red'><b>$extra min more than $limit elapsed</b></span>"
  extra=$(( $extra + 1 ))

  sleep 1m
done
