#!/bin/sh
# Aviso sonoro para las pruebas con el dueño: lapiz-cue.sh start (3 avisos) | end (2 avisos) | test. Usa PipeWire del usuario omarchy, volumen bajo.
U=omarchy; UID_=$(id -u $U)
play() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$UID_ pw-play --volume 0.4 /usr/share/sounds/freedesktop/stereo/$1 2>/dev/null; }
case "$1" in
  start) for i in 1 2 3; do play message.oga; sleep 0.3; done ;;
  end) for i in 1 2; do play complete.oga; sleep 0.3; done ;;
  *) play message.oga ;;
esac
