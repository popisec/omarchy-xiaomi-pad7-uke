# Dudas para el dueño — escritorio táctil (sesión escritorio-tactil, 22-oct-2026)

Cada duda lleva lo que se hizo mientras tanto (por defecto reversible). Contesta en el chat de la sesión o aquí mismo.

1. **Clic sonoro del teclado: ¿encendido por defecto?** La tablet **no tiene motor de vibración** (estudio de cámaras:
   `ro.odm.mm.vibrator.motor_not_support=true`, ningún dispositivo de entrada con force-feedback; comprobado en
   `/sys/class/input/*/device/capabilities/ff` = 0). Hay clic sonoro opcional (botón 🔇/🔊 en la cabecera del teclado).
   **Por defecto: apagado**, porque cada pulsación despierta la cadena de audio (PipeWire + amplificadores) y carga QtMultimedia
   en el proceso del shell (medido: **+22 MB** de RSS al activarlo). No lo he oído yo: pruébalo con 🔊. ¿Lo quieres encendido?
2. **Autocorrección: ¿tan conservadora?** Solo corrige (a) tildes que faltan cuando la forma con tilde es ≥ 10× más
   frecuente («tambien» → «también», «cancion» → «canción», «aqui» → «aquí», «ano» → «año») y (b) palabras inexistentes de
   ≥ 4 letras con un único candidato claro a una letra («hloa» → «hola», «graicas» → «gracias»). Retroceso justo después la
   deshace y esa palabra no se vuelve a corregir. Botón «Abc✓/✗» para apagarla. Nunca actúa en terminales, contraseñas, URL ni
   correos (lo dice el propio campo). ¿Más agresiva, igual o apagada por defecto?
3. **Escribir deslizando (swipe): no lo he hecho.** Necesita un decodificador de trazos contra el diccionario; lo «ligero»
   que se podría hacer aquí acertaría poco. ¿Lo quieres como proyecto aparte?
4. **Teclado siempre acoplado.** He quitado mover/redimensionar (cabecera arrastrable y asa ◢) para dar ese alto a las
   teclas (40 % de la pantalla en horizontal, 34 % en vertical). ¿Echas de menos el modo flotante?
5. **Una app por escritorio.** Cada app nueva se abre en su escritorio y ocupa toda la pantalla; dividir = pellizco de 3
   dedos hacia dentro (repite para volver a separarlas). Abrir una 2.ª ventana de la misma app (otra ventana de Firefox) también
   va a su propio escritorio. ¿Te vale o prefieres que las ventanas de la misma app compartan escritorio?
6. **Plugins quitados/desactivados** (reversibles con `deploy/escritorio-tactil/deploy.sh plugins-revert`):
   `crmne.hyprmoncfg` (ya estaba desactivado y daba errores; un solo monitor) se ha **movido** a
   `~omarchy/.local/share/uke-escritorio/plugins/`; `radimsem.omafind` **desactivado** (18 avisos QML por arranque, y su búsqueda
   necesita el modelo EmbeddingGemma, que no está instalado). ¿Borro ambos del todo?
7. **`omaplug` (gestor de plugins) busca actualizaciones solo** (`autoCheckUpdates: true`, sale a la red). Lo he dejado como
   está. ¿Lo apago para ahorrar batería y red?
8. **Fuera de mi encargo, pero lo he medido**: el demonio del táctil/lápiz `uke-touchd-pen.py` (root) gasta **~6–12 % de
   un núcleo en reposo** (190 s de CPU en 26 min). Es el mayor consumidor del escritorio en reposo. ¿Abro una sesión para
   revisarlo?
