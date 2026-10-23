#!/bin/sh
# UKE FORK: compila (si hace falta) y ejecuta ime-helper (detector de campos de texto, ver ime-helper.c)
set -eu
umask 077
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/tablet"
binary="$cache_dir/ime-helper"
mkdir -p "$cache_dir"
exec 9>"$cache_dir/ime-build.lock"
flock 9
source_hash=$(sha256sum "$source_dir/ime-helper.c" "$source_dir/input-method-unstable-v2.xml" "$source_dir/ime-backend.sh")
saved_hash=""
if [ -f "$cache_dir/ime-source.hash" ]; then saved_hash=$(cat "$cache_dir/ime-source.hash"); fi
if [ ! -x "$binary" ] || [ "$source_hash" != "$saved_hash" ]; then
  wayland-scanner client-header "$source_dir/input-method-unstable-v2.xml" "$cache_dir/input-method.h"
  wayland-scanner private-code "$source_dir/input-method-unstable-v2.xml" "$cache_dir/input-method.c"
  cc -std=c11 -O2 -Wall -Wextra -Werror -I"$cache_dir" \
    "$source_dir/ime-helper.c" "$cache_dir/input-method.c" \
    $(pkg-config --cflags --libs wayland-client) -o "$binary.tmp"
  mv "$binary.tmp" "$binary"
  printf '%s\n' "$source_hash" > "$cache_dir/ime-source.hash"
fi
flock -u 9
exec 9>&-
[ "${1:-}" = "--build" ] && exit 0
exec "$binary"
