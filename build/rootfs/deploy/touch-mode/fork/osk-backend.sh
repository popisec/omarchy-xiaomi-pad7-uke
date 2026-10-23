#!/bin/sh
# UKE FORK: compila (si hace falta) y ejecuta osk-daemon (input method v2 + teclado virtual, ver osk-daemon.c)
set -eu
umask 077
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/tablet"
binary="$cache_dir/osk-daemon"
mkdir -p "$cache_dir"
exec 9>"$cache_dir/osk-build.lock"
flock 9
source_hash=$(sha256sum "$source_dir/osk-daemon.c" "$source_dir/predict.h" "$source_dir/virtual-keyboard-unstable-v1.xml" "$source_dir/input-method-unstable-v2.xml" "$source_dir/osk-backend.sh")
saved_hash=""
if [ -f "$cache_dir/osk-source.hash" ]; then saved_hash=$(cat "$cache_dir/osk-source.hash"); fi
if [ ! -x "$binary" ] || [ "$source_hash" != "$saved_hash" ]; then
  wayland-scanner client-header "$source_dir/virtual-keyboard-unstable-v1.xml" "$cache_dir/virtual-keyboard.h"
  wayland-scanner private-code "$source_dir/virtual-keyboard-unstable-v1.xml" "$cache_dir/virtual-keyboard.c"
  wayland-scanner client-header "$source_dir/input-method-unstable-v2.xml" "$cache_dir/input-method.h"
  wayland-scanner private-code "$source_dir/input-method-unstable-v2.xml" "$cache_dir/input-method.c"
  cc -std=c11 -O2 -Wall -Wextra -Werror -I"$cache_dir" \
    "$source_dir/osk-daemon.c" "$cache_dir/virtual-keyboard.c" "$cache_dir/input-method.c" \
    $(pkg-config --cflags --libs wayland-client xkbcommon) -o "$binary.tmp"
  mv "$binary.tmp" "$binary"
  printf '%s\n' "$source_hash" > "$cache_dir/osk-source.hash"
fi
flock -u 9
exec 9>&-
[ "${1:-}" = "--build" ] && exit 0
export OSK_DICT="${OSK_DICT:-$source_dir/dict/es.txt}"
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/uke-touch-mode"
export OSK_USERDICT="${OSK_USERDICT:-${XDG_STATE_HOME:-$HOME/.local/state}/uke-touch-mode/palabras.txt}"
exec "$binary"
