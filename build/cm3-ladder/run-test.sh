#!/bin/bash
# Prueba de la escalera UKE-CM3 sin tablet.
# Compila el harness y corre los 3 escenarios: hang / garbage / ok.
# Criterio: hang -> ultima linea del log = PRE canary, sin POST despues,
# y ultimo marcador = L14-pre-canary. garbage/ok -> completan y el POST
# con el valor distingue timeout (fw muerto) de arranque sano.
set -u
D="$(dirname "$0")"
cd "$D" || exit 1
fail=0
say() { printf '%s\n' "$*"; }

gcc -O2 -Wall -Wextra -o test-ladder test-ladder.c || exit 2

run_ok() {
  ./test-ladder ok kmsg-ok.log fb-ok.log
  rc=$?
  last_kmsg="$(tail -n 1 kmsg-ok.log)"
  last_fb="$(tail -n 1 fb-ok.log)"
  say "--- escenario OK ---"
  say "rc=$rc"
  say "ultima kmsg: $last_kmsg"
  say "ultimo fb:   $last_fb"
  if [ "$rc" = 0 ] && echo "$last_kmsg" | grep -q "POST poll-init-result.*val=0x100"; then
    say "OK: arranque sano completa y el POST muestra la magia esperada"
  else
    say "FAIL: escenario ok no completo como se esperaba"; fail=1
  fi
}

run_garbage() {
  ./test-ladder garbage kmsg-garbage.log fb-garbage.log
  rc=$?
  say "--- escenario GARBAGE (readl vuelve con basura) ---"
  say "rc=$rc"
  grep -E "POST canary|POST poll|timed out" kmsg-garbage.log
  say "ultimo fb: $(tail -n 1 fb-garbage.log)"
  if [ "$rc" = 1 ] \
    && grep -q "POST canary-init-result.*val=0xdeadbeef" kmsg-garbage.log \
    && grep -q "GMU firmware initialization timed out" kmsg-garbage.log \
    && grep -q "L15-post-poll" fb-garbage.log; then
    say "OK: basura distinguida del cuelgue (timeout con mensaje, proceso vivo)"
  else
    say "FAIL: garbage no dio la firma esperada"; fail=1
  fi
}

run_hang() {
  ./test-ladder hang kmsg-hang.log fb-hang.log &
  pid=$!
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    say "FAIL: el hijo hang termino solo (deberia seguir colgado)"; fail=1
    return
  fi
  last_kmsg="$(tail -n 1 kmsg-hang.log)"
  last_fb="$(tail -n 1 fb-hang.log)"
  n_post_canary="$(grep -c "POST canary" kmsg-hang.log || true)"
  say "--- escenario HANG (readl canario no vuelve) ---"
  say "hijo sigue vivo tras 1s: si (colgado donde debe)"
  say "ultima kmsg: $last_kmsg"
  say "ultimo fb:   $last_fb"
  say "lineas POST canary: $n_post_canary"
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  if echo "$last_kmsg" | grep -q "PRE canary-init-result" \
    && [ "$last_fb" = "L14-pre-canary" ] \
    && [ "$n_post_canary" = 0 ]; then
    say "OK: la ultima linea impresa es la del acceso colgado (L14 canary)"
  else
    say "FAIL: la ultima linea no senala el acceso"; fail=1
  fi
}

run_ok
run_garbage
run_hang

say "=== $([ "$fail" = 0 ] && echo 'TODAS LAS PRUEBAS PASAN' || echo 'FALLOS: revisar arriba') ==="
exit "$fail"
