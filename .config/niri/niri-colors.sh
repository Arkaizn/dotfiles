#!/bin/bash
source ~/.cache/wal/colors.sh

CONFIG=~/.config/niri/config/layout.kdl

# Handle regular colors (lines with // @colorN)
IFS="=" grep -E 'color..?=' < ~/.cache/wal/colors.sh | \
  tr -d "'" | \
  while read color value; do
    sed -E "s/\"[^\"]+\"(.*@$color)\$/\"$value\"\\1/" -i "$CONFIG"
  done

# Handle gradient from= and to= (lines with // @from=colorN @to=colorN)
FROM_COLOR=$(grep -oP '@from=\K\w+' "$CONFIG" | head -1)
TO_COLOR=$(grep -oP '@to=\K\w+' "$CONFIG" | head -1)

if [[ -n "$FROM_COLOR" && -n "$TO_COLOR" ]]; then
  FROM_VALUE="${!FROM_COLOR}"
  TO_VALUE="${!TO_COLOR}"
  sed -E "s/from=\"[^\"]+\"(.*@from=$FROM_COLOR)/from=\"$FROM_VALUE\"\1/" -i "$CONFIG"
  sed -E "s/to=\"[^\"]+\"(.*@to=$TO_COLOR)/to=\"$TO_VALUE\"\1/" -i "$CONFIG"
fi