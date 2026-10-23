#!/bin/bash
# con-turno.sh "<qué>" <orden...> — pide el turno de la tablet (sesión escritorio-tactil), ejecuta la orden y SUELTA el turno
# siempre al terminar (también si falla o se interrumpe). Turnos cortos: un paso por llamada.
# Por defecto solo el recurso «pantalla» (toques, capturas, apps, shell); RECURSO=sistema|ambos para lo demás.
T=$(cd "$(dirname "$0")/../turno" && pwd)/uke-turno
que=$1; shift
"$T" pedir --recurso "${RECURSO:-pantalla}" escritorio-tactil "$que" "${ESPERA:-5400}" || exit 1
trap '"$T" soltar --recurso "${RECURSO:-pantalla}" escritorio-tactil' EXIT
"$@"
