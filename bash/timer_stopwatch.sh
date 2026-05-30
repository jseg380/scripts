#!/usr/bin/env bash
# timer_stopwatch.sh
# Usage: ./timer_stopwatch.sh timer HH:MM:SS.mmm
#        ./timer_stopwatch.sh stopwatch
# Controls (while running):
#  Space = pause/resume
#  l     = lap (stopwatch only)
#  s or Enter = stop (finish)
#  q     = quit immediately

set -euo pipefail

# format milliseconds to HH:MM:SS.mmm
fmt() {
  local ms=$1
  local total_ms=$ms
  local hrs=$(( total_ms/3600000 )); total_ms=$(( total_ms%3600000 ))
  local mins=$(( total_ms/60000 )); total_ms=$(( total_ms%60000 ))
  local secs=$(( total_ms/1000 )); local msecs=$(( total_ms%1000 ))
  printf "%02d:%02d:%02d.%03d" "$hrs" "$mins" "$secs" "$msecs"
}

# read single key (non-blocking if timeout provided)
read_key() {
  local timeout=${1:-0.0}
  IFS= read -rsn1 -t "$timeout" key 2>/dev/null || key=""
  # handle escape sequences (arrow keys)
  if [[ $key == $'\e' ]]; then
    IFS= read -rsn2 -t 0.001 seq 2>/dev/null || seq=""
    key+="$seq"
  fi
  printf '%s' "$key"
}

# parse timer arg HH:MM:SS(.mmm optional)
parse_time_arg() {
  local arg=$1
  # Accept HH:MM:SS or H:M:S.mmm
  if [[ $arg =~ ^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])(\.([0-9]{1,3}))?$ ]]; then
    local h=${BASH_REMATCH[1]}
    local m=${BASH_REMATCH[2]}
    local s=${BASH_REMATCH[3]}
    local ms=${BASH_REMATCH[5]:-0}
    # normalize milliseconds to 3 digits
    while [ ${#ms} -lt 3 ]; do ms="${ms}0"; done
    echo $(( (h*3600 + m*60 + s)*1000 + ms ))
  else
    echo "invalid" 
  fi
}

# draw help line
controls_line() {
  if [ "$MODE" = "timer" ]; then
    printf "Space=Pause/Resume  Enter/s=Stop  q=Quit\n"
  else
    printf "Space=Pause/Resume  l=Lap  Enter/s=Stop  q=Quit\n"
  fi
}

# main loop
if [ "${1:-}" = "timer" ]; then
  MODE=timer
  if [ -z "${2:-}" ]; then
    echo "Usage: $0 timer HH:MM:SS(.mmm)"
    exit 1
  fi
  total_ms=$(parse_time_arg "$2")
  if [ "$total_ms" = "invalid" ]; then
    echo "Invalid time format. Use HH:MM:SS(.mmm)"
    exit 1
  fi
  remaining_ms=$total_ms
  start_ms=$(date +%s%3N)
  paused=0
  laps=()
  echo
  controls_line
  printf "\n"
  # terminal raw for key reads
  stty -echo -icanon time 0 min 0
  trap 'stty sane; printf "\n"; exit' INT TERM
  last_draw=""
  while true; do
    key=$(read_key 0.05)
    now_ms=$(date +%s%3N)
    if [ "$paused" -eq 0 ]; then
      elapsed=$(( now_ms - start_ms ))
      remaining_ms=$(( total_ms - elapsed ))
      if [ $remaining_ms -le 0 ]; then
        remaining_ms=0
      fi
    fi

    # key handling
    if [ -n "$key" ]; then
      case "$key" in
        " ") # pause/resume
          if [ "$paused" -eq 0 ]; then
            paused=1
            pause_at=$(date +%s%3N)
          else
            paused=0
            # shift start_ms forward by paused duration
            resume_at=$(date +%s%3N)
            pause_dur=$(( resume_at - pause_at ))
            start_ms=$(( start_ms + pause_dur ))
          fi
          ;;
        $'\n'|"s") # stop/finish
          if [ "$paused" -eq 0 ]; then
            now_ms=$(date +%s%3N)
            elapsed=$(( now_ms - start_ms ))
            remaining_ms=$(( total_ms - elapsed ))
            if [ $remaining_ms -lt 0 ]; then remaining_ms=0; fi
          fi
          stty sane
          printf "\rRemaining: %s\n" "$(fmt $remaining_ms)"
          exit 0
          ;;
        "q")
          stty sane
          printf "\nQuit.\n"
          exit 0
          ;;
      esac
    fi

    # update display
    disp="Remaining: $(fmt $remaining_ms)"
    if [ "$paused" -eq 1 ]; then
      pad=" [PAUSED]"
      disp="$disp$pad"
    fi

    # only redraw if changed
    if [ "$disp" != "$last_draw" ]; then
      printf "\r\033[K%s" "$disp"
      last_draw="$disp"
    fi

    if [ $remaining_ms -le 0 ]; then
      stty sane
      printf "\nTime's up!\n"

      # play in an infinite loop in background
      (
        while :; do
          paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga
          sleep 0.1
        done
      ) &
      _ALARM_PID=$!

      # Re-set the trap NOW that we know $_ALARM_PID, so Ctrl+C cleans up
      trap 'kill "$_ALARM_PID" 2>/dev/null; wait "$_ALARM_PID" 2>/dev/null; printf "\n"; exit' INT TERM

      # wait for a single key press to stop the alarm
      read -n1 -s -r -p "Press any key to stop the alarm..."
      kill "$_ALARM_PID" 2>/dev/null
      wait "$_ALARM_PID" 2>/dev/null

      exit 0
    fi
  done

elif [ "${1:-}" = "stopwatch" ]; then
  MODE=stopwatch
  start_ms=$(date +%s%3N)
  paused=0
  lap_count=0
  laps=()
  echo
  controls_line
  printf "\n"
  stty -echo -icanon time 0 min 0
  trap 'stty sane; printf "\n"; exit' INT TERM
  last_draw=""
  while true; do
    key=$(read_key 0.05)
    now_ms=$(date +%s%3N)
    if [ "$paused" -eq 0 ]; then
      elapsed=$(( now_ms - start_ms ))
    else
      elapsed=$(( pause_at - start_ms ))
    fi

    # key handling
    if [ -n "$key" ]; then
      case "$key" in
        " ") # pause/resume
          if [ "$paused" -eq 0 ]; then
            paused=1
            pause_at=$(date +%s%3N)
          else
            paused=0
            resume_at=$(date +%s%3N)
            pause_dur=$(( resume_at - pause_at ))
            start_ms=$(( start_ms + pause_dur ))
          fi
          ;;
        "l") # lap
          lap_time=$elapsed
          lap_count=$((lap_count+1))
          laps+=("Lap $lap_count: $(fmt $lap_time)")
          # print lap line on next line
          printf "\n%s\n" "${laps[-1]}"
          last_draw="" # force redraw of main line
          ;;
        $'\n'|"s") # stop
          stty sane
          printf "\nFinal: %s\n" "$(fmt $elapsed)"
          if [ ${#laps[@]} -gt 0 ]; then
            printf "Laps:\n"
            for l in "${laps[@]}"; do printf "%s\n" "$l"; done
          fi
          exit 0
          ;;
        "q")
          stty sane
          printf "\nQuit.\n"
          exit 0
          ;;
      esac
    fi

    disp="Elapsed: $(fmt $elapsed)"
    if [ "$paused" -eq 1 ]; then
      disp="$disp [PAUSED]"
    fi

    if [ "$disp" != "$last_draw" ]; then
      printf "\r\033[K%s" "$disp"
      last_draw="$disp"
    fi
  done

else
  cat <<EOF
Usage:
  $0 timer HH:MM:SS(.mmm)   # run countdown timer
  $0 stopwatch              # run stopwatch

Controls while running:
  Space = pause/resume
  l     = lap (stopwatch only)
  Enter or s = stop/finish
  q     = quit immediately
EOF
  exit 1
fi
