#!/usr/bin/env bash
# timer_stopwatch.sh
# Usage: ./timer_stopwatch.sh timer HH:MM:SS(.mmm)
#        ./timer_stopwatch.sh stopwatch
# Controls (while running):
#  Space     = pause/resume
#  l         = lap (stopwatch only)
#  s / Enter = stop
#  q         = quit immediately

set -euo pipefail

# ---------------------------------------------------------------------------
# format_milliseconds: converts a raw millisecond count into HH:MM:SS.mmm
# ---------------------------------------------------------------------------
format_milliseconds() {
  local total_milliseconds=$1

  local hours=$(( total_milliseconds / 3600000 ))
  total_milliseconds=$(( total_milliseconds % 3600000 ))

  local minutes=$(( total_milliseconds / 60000 ))
  total_milliseconds=$(( total_milliseconds % 60000 ))

  local seconds=$(( total_milliseconds / 1000 ))
  local milliseconds=$(( total_milliseconds % 1000 ))

  printf "%02d:%02d:%02d.%03d" "$hours" "$minutes" "$seconds" "$milliseconds"
}

# ---------------------------------------------------------------------------
# read_single_key: reads one keypress with an optional timeout (in seconds).
# Also handles escape sequences so arrow keys don't bleed into input.
# ---------------------------------------------------------------------------
read_single_key() {
  local timeout=${1:-0.05}
  local key=""
  IFS= read -rsn1 -t "$timeout" key 2>/dev/null || key=""

  # If we got an escape character, try to read the rest of the sequence
  if [[ $key == $'\e' ]]; then
    local escape_sequence=""
    IFS= read -rsn2 -t 0.001 escape_sequence 2>/dev/null || escape_sequence=""
    key+="$escape_sequence"
  fi

  printf '%s' "$key"
}

# ---------------------------------------------------------------------------
# parse_time_argument: converts HH:MM:SS(.mmm) to total milliseconds.
# Prints "invalid" if the format doesn't match.
# ---------------------------------------------------------------------------
parse_time_argument() {
  local time_string=$1

  if [[ $time_string =~ ^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])(\.([0-9]{1,3}))?$ ]]; then
    local hours=${BASH_REMATCH[1]}
    local minutes=${BASH_REMATCH[2]}
    local seconds=${BASH_REMATCH[3]}
    local milliseconds=${BASH_REMATCH[5]:-0}

    # Pad milliseconds to 3 digits (e.g. ".5" → "500", ".05" → "050")
    while [ ${#milliseconds} -lt 3 ]; do
      milliseconds="${milliseconds}0"
    done

    echo $(( (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds ))
  else
    echo "invalid"
  fi
}

# ---------------------------------------------------------------------------
# print_controls: shows the available keys for the current mode
# ---------------------------------------------------------------------------
print_controls() {
  if [ "$MODE" = "timer" ]; then
    printf "Space=Pause/Resume  Enter/s=Stop  q=Quit\n"
  else
    printf "Space=Pause/Resume  l=Lap  Enter/s=Stop  q=Quit\n"
  fi
}

# ===========================================================================
# TIMER MODE
# ===========================================================================
if [ "${1:-}" = "timer" ]; then
  MODE=timer

  if [ -z "${2:-}" ]; then
    echo "Usage: $0 timer HH:MM:SS(.mmm)"
    exit 1
  fi

  target_milliseconds=$(parse_time_argument "$2")
  if [ "$target_milliseconds" = "invalid" ]; then
    echo "Invalid time format. Use HH:MM:SS(.mmm)"
    exit 1
  fi

  remaining_milliseconds=$target_milliseconds
  timer_start_ms=$(date +%s%3N)
  is_paused=0
  pause_started_at_ms=0   # initialized to avoid "unbound variable" if accessed early

  echo
  print_controls
  printf "\n"

  # Put the terminal in raw mode so we can read keypresses instantly
  stty -echo -icanon time 0 min 0
  trap 'stty sane; printf "\n"; exit' INT TERM

  last_displayed=""

  while true; do
    pressed_key=$(read_single_key 0.05)
    current_time_ms=$(date +%s%3N)

    if [ "$is_paused" -eq 0 ]; then
      elapsed_ms=$(( current_time_ms - timer_start_ms ))
      remaining_milliseconds=$(( target_milliseconds - elapsed_ms ))
      if [ "$remaining_milliseconds" -lt 0 ]; then
        remaining_milliseconds=0
      fi
    fi

    # Handle keypresses
    if [ -n "$pressed_key" ]; then
      case "$pressed_key" in
        " ")
          if [ "$is_paused" -eq 0 ]; then
            is_paused=1
            pause_started_at_ms=$(date +%s%3N)
          else
            is_paused=0
            # Shift the start reference forward by however long we were paused,
            # so elapsed time calculation stays correct after resuming
            local_now_ms=$(date +%s%3N)
            pause_duration_ms=$(( local_now_ms - pause_started_at_ms ))
            timer_start_ms=$(( timer_start_ms + pause_duration_ms ))
          fi
          ;;
        $'\n' | "s")
          stty sane
          printf "\rRemaining: %s\n" "$(format_milliseconds "$remaining_milliseconds")"
          exit 0
          ;;
        "q")
          stty sane
          printf "\nQuit.\n"
          exit 0
          ;;
      esac
    fi

    # Build the display string
    display_line="Remaining: $(format_milliseconds "$remaining_milliseconds")"
    if [ "$is_paused" -eq 1 ]; then
      display_line="$display_line [PAUSED]"
    fi

    # Only redraw when something changed to avoid flicker
    if [ "$display_line" != "$last_displayed" ]; then
      printf "\r\033[K%s" "$display_line"
      last_displayed="$display_line"
    fi

    # Time's up
    if [ "$remaining_milliseconds" -le 0 ]; then
      stty sane
      printf "\nTime's up!\n"

      # Start the alarm in a background loop
      (
        while true; do
          paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga
        done
      ) &
      alarm_pid=$!

      # Now that we have the PID, set a trap so Ctrl+C also kills the alarm
      trap 'kill "$alarm_pid" 2>/dev/null; wait "$alarm_pid" 2>/dev/null; printf "\n"; exit' INT TERM

      read -n1 -s -r -p "Press any key to stop the alarm..."

      kill "$alarm_pid" 2>/dev/null
      wait "$alarm_pid" 2>/dev/null

      exit 0
    fi
  done

# ===========================================================================
# STOPWATCH MODE
# ===========================================================================
elif [ "${1:-}" = "stopwatch" ]; then
  MODE=stopwatch

  stopwatch_start_ms=$(date +%s%3N)
  is_paused=0
  pause_started_at_ms=0
  lap_count=0
  lap_times=()

  echo
  print_controls
  printf "\n"

  stty -echo -icanon time 0 min 0
  trap 'stty sane; printf "\n"; exit' INT TERM

  last_displayed=""

  while true; do
    pressed_key=$(read_single_key 0.05)
    current_time_ms=$(date +%s%3N)

    if [ "$is_paused" -eq 0 ]; then
      elapsed_ms=$(( current_time_ms - stopwatch_start_ms ))
    else
      # While paused, freeze elapsed at the moment we paused
      elapsed_ms=$(( pause_started_at_ms - stopwatch_start_ms ))
    fi

    # Handle keypresses
    if [ -n "$pressed_key" ]; then
      case "$pressed_key" in
        " ")
          if [ "$is_paused" -eq 0 ]; then
            is_paused=1
            pause_started_at_ms=$(date +%s%3N)
          else
            is_paused=0
            local_now_ms=$(date +%s%3N)
            pause_duration_ms=$(( local_now_ms - pause_started_at_ms ))
            stopwatch_start_ms=$(( stopwatch_start_ms + pause_duration_ms ))
          fi
          ;;
        "l")
          lap_count=$(( lap_count + 1 ))
          lap_label="Lap $lap_count: $(format_milliseconds "$elapsed_ms")"
          lap_times+=("$lap_label")
          printf "\n%s\n" "$lap_label"
          last_displayed=""   # force the main line to redraw cleanly after the lap line
          ;;
        $'\n' | "s")
          stty sane
          printf "\nFinal: %s\n" "$(format_milliseconds "$elapsed_ms")"
          if [ "${#lap_times[@]}" -gt 0 ]; then
            printf "Laps:\n"
            for lap_entry in "${lap_times[@]}"; do
              printf "  %s\n" "$lap_entry"
            done
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

    display_line="Elapsed: $(format_milliseconds "$elapsed_ms")"
    if [ "$is_paused" -eq 1 ]; then
      display_line="$display_line [PAUSED]"
    fi

    if [ "$display_line" != "$last_displayed" ]; then
      printf "\r\033[K%s" "$display_line"
      last_displayed="$display_line"
    fi
  done

# ===========================================================================
# USAGE / UNKNOWN MODE
# ===========================================================================
else
  cat <<EOF
Usage:
  $0 timer HH:MM:SS(.mmm)   run a countdown timer
  $0 stopwatch               run a stopwatch

Controls while running:
  Space     = pause/resume
  l         = lap (stopwatch only)
  Enter / s = stop
  q         = quit immediately
EOF
  exit 1
fi
