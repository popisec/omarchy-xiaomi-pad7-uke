# REGLA: un solo lector de /dev/ttyACM0

**Por qué:** dos `cat /dev/ttyACM0` a la vez se reparten los bytes del puerto
(el kernel entrega cada byte a un solo lector). Resultado: líneas partidas o
intercaladas en el log y evidencia del cuelgue falseada. Y si nadie lee y el
buffer se llena, los `write()` del kernel se bloquean y el cuelgue ni se registra.

**Antes de lanzar:** comprobar si ya hay uno vivo.

```sh
pgrep -af 'uke-console-cap\.sh'   # debe dar 0 líneas; si da 1, NO lanzar otro
```

**Al lanzar (desligado, como siempre):**

```sh
cd ~/proyectos/ubuntu-permanente \
  && setsid nohup bin/uke-console-cap.sh >/dev/null 2>&1 < /dev/null & disown
```

**Si hay duplicado:** diagnosticar primero (`ps -o pid,ppid,lstart,etime,args`,
hijos con `ps --ppid`, y `/proc/<cat>/io` → `rchar` creciendo = lee de verdad).
Sobrevive el de la sesión viva (si empatan, el más reciente). SIGTERM al script
**y** a su `cat` hijo (si muere solo el padre, el `cat` queda huérfano y sigue
leyendo). Verificar con `pgrep` que queda exactamente uno y que el log crece.

**Incidente 28-sep-2026:** PIDs 5347 (13:03, sesión anterior) y 77586 (13:56,
sesión viva) leyendo a la vez el mismo log desde las 14:11:46 (ambos `cat`
reabrieron el puerto en el mismo segundo tras re-enumerar USB). Los dos leían
de verdad (`rchar` creciendo en ambos). Se mató el viejo con SIGTERM (murió a
la primera, sin SIGKILL). Posible pérdida/intercalado de líneas entre las
14:11 y las 15:01: tratar ese tramo del log con desconfianza.
