#!/usr/bin/env bash

# Imports
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
. "${ROOT_DIR}/lib/coreutils-compat.sh"

# Check the global value
SHOW_MUSIC=$(tmux show-option -gv @tokyo-night-tmux_show_music)

if [ "$SHOW_MUSIC" != "1" ]; then
  exit 0
fi

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $CURRENT_DIR/themes.sh

ACCENT_COLOR="${THEME[blue]}"
SECONDARY_COLOR="${THEME[background]}"
BG_COLOR="${THEME[background]}"
BG_BAR="${THEME[background]}"
TIME_COLOR="${THEME[black]}"

if [[ $1 =~ ^[[:digit:]]+$ ]]; then
  MAX_TITLE_WIDTH=$1
else
  MAX_TITLE_WIDTH=$(($(tmux display -p '#{window_width}' 2>/dev/null || echo 120) - 90))
fi

# playerctl
if command -v playerctl >/dev/null; then
  PLAYER_STATUS=$(playerctl -a metadata --format "{{status}};{{mpris:length}};{{position}};{{title}}" | grep -m1 "Playing")
  STATUS="playing"

  # There is no playing media, check for paused media
  if [ -z "$PLAYER_STATUS" ]; then
    PLAYER_STATUS=$(playerctl -a metadata --format "{{status}};{{mpris:length}};{{position}};{{title}}" | grep -m1 "Paused")
    STATUS="paused"
  fi

  TITLE=$(echo "$PLAYER_STATUS" | cut -d';' --fields=4)
  DURATION=$(echo "$PLAYER_STATUS" | cut -d';' --fields=2)
  POSITION=$(echo "$PLAYER_STATUS" | cut -d';' --fields=3)

  # Convert position and duration to seconds from microseconds
  DURATION=$((DURATION / 1000000))
  POSITION=$((POSITION / 1000000))

  if [ "$DURATION" -eq 0 ]; then
    DURATION=-1
    POSITION=0
  fi

# nowplaying-cli
elif command -v nowplaying-cli >/dev/null; then
  NPCLI_PROPERTIES=(title artist)
  mapfile -t NPCLI_OUTPUT < <(nowplaying-cli get "${NPCLI_PROPERTIES[@]}")
  declare -A NPCLI_VALUES
  for ((i = 0; i < ${#NPCLI_PROPERTIES[@]}; i++)); do
    # Handle null values
    [ "${NPCLI_OUTPUT[$i]}" = "null" ] && NPCLI_OUTPUT[$i]=""
    NPCLI_VALUES[${NPCLI_PROPERTIES[$i]}]="${NPCLI_OUTPUT[$i]}"
  done
  if [ -n "${NPCLI_VALUES[playbackRate]}" ] && [ "${NPCLI_VALUES[playbackRate]}" -gt 0 ]; then
    STATUS="playing"
  else
    STATUS="paused"
  fi

  # Combine artist and title with a separator
  if [ -n "${NPCLI_VALUES[artist]}" ]; then
    TITLE="${NPCLI_VALUES[title]} - ${NPCLI_VALUES[artist]}"
  else
    TITLE="${NPCLI_VALUES[title]}"
  fi

  if [ "${NPCLI_VALUES[isAlwaysLive]}" = "1" ]; then
    DURATION=-1
    POSITION=0
  else
    DURATION=$(printf "%.0f" "${NPCLI_VALUES[duration]}")
    POSITION=$(printf "%.0f" "${NPCLI_VALUES[elapsedTime]}")

    # fix for the bug in nowplaying-cli.
    # See https://github.com/janoamaral/tokyo-night-tmux/issues/107#issuecomment-2576211115
    if [[ $OSTYPE == "darwin"* ]]; then
      if [ $STATUS == "playing" ]; then
        echo "$POSITION" >/tmp/last_position
      fi

      if [ "$STATUS" = "paused" ]; then
        POSITION=$(cat /tmp/last_position)
      fi
    fi

  fi
fi

if [ -n "$TITLE" ]; then
  PLAY_STATE="░ $OUTPUT"
  OUTPUT="$PLAY_STATE $TITLE"

  # Only show the song title if we are over $MAX_TITLE_WIDTH characters
  if [ "${#OUTPUT}" -ge $MAX_TITLE_WIDTH ]; then
    OUTPUT="$PLAY_STATE ${TITLE:0:$MAX_TITLE_WIDTH-1}…"
  fi
else
  OUTPUT=''
fi

MAX_TITLE_WIDTH=65
if [ "${#OUTPUT}" -ge $MAX_TITLE_WIDTH ]; then
  OUTPUT="$PLAY_STATE ${TITLE:0:$MAX_TITLE_WIDTH-1}"
  # Remove trailing spaces
  OUTPUT="${OUTPUT%"${OUTPUT##*[![:space:]]}"}…"
fi

if [ -z "$OUTPUT" ]; then
  echo "$OUTPUT #[fg=green,bg=default]"
else
  # Replace the progress bar logic with a simple output of song details and time
  echo "#[nobold,fg=$ACCENT_COLOR,bg=$BG_BAR]$OUTPUT #[fg=$TIME_COLOR,bg=$BG_BAR]$TIME "
fi
