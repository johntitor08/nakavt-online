#!/bin/sh
# Oyunu açar.
D="$(dirname "$(readlink -f "$0")")"
exec flatpak run org.godotengine.Godot --path "$D" "$@"
