#!/bin/bash
# paso: desplegar el teclado (2.a ronda), reiniciar el shell y pasar regresion + pruebas nuevas
cd "$(dirname "$0")"
T=300 bash deploy.sh osk 2>&1 | tail -2
echo 'omarchy restart shell >/dev/null 2>&1; sleep 9; omarchy-shell omarkyy.tablet status | cut -c1-120' | /tmp/claude-1000/-home-usuario-proyectos-omarchy-uke/c1dd1fee-38cd-4e30-859c-32f97186a01f/scratchpad/tu
echo "== REGRESION"; timeout 300 bash osk-pred-test.sh 2>&1 | grep -E "PASS|FAIL|RESULT"
echo "== 2a RONDA"; timeout 400 bash osk-swipe-test.sh 2>&1 | grep -vE "^warn"
