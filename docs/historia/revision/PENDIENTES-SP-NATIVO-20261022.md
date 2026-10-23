# PENDIENTES — Super Productivity nativo (traspaso a apps-tablet, 22-oct-2026)

**Dónde está todo:** `~/proyectos/super-productivity-nativo` (git, rama master; último commit del proyecto al traspaso: `b5f6d76`). Detalle completo en `docs/DISENO.md` y `docs/PENDIENTES.md` de ese repo; guía de fetch real en `docs/GUIA-NEXTCLOUD.md`. Sin credenciales en git. Fuentes de sp-nativo copiadas en la tablet: `/root/spn` (solo build; sin backup ni binarios en /home/omarchy).

## Decisión abierta del dueño: sp-nativo vs sp-web
| | sp-nativo (Qt Quick) | sp-web (WebKitGTK 6.0 → app.super-productivity.com) |
|---|---|---|
| Aspecto | «se ve muy mal» (dueño) | idéntico a la web oficial |
| RSS en la tablet | 143 MB (ventana real, antes de la UI táctil nueva); 135–139 MB en el portátil offscreen con la UI nueva | 806 MB RSS / 602 MB PSS a 60 s (8 procesos: web 458, launcher 211, red 138) |
| Sync | cliente propio del formato de SP; escritor verificado contra SP 19.1.0 aislado | el de la propia web (hay que teclear WebDAV en Ajustes > Sincronización; no viaja en backups) |
| Estado | funcional, parado | funcional, medido solo en la tablet (el portátil no tiene webkitgtk-6.0) |
El dueño pidió sp-web («copia tal cual, lanzador que consuma menos»); la medición no demuestra que consuma menos que el Electron (no medido). Primer paso: que el dueño elija con estos números; si sp-web, medir con datos reales + sync y empaquetar (PKGBUILD/.desktop en `sp-web/`, `sp-web.desktop` existe, falta icono).

## Hecho y verificado (commits en el repo del proyecto)
- Formato real de sync/backup de SP v19.2.0 investigado (`docs/DISENO.md`).
- Lector de backup / `sync-data.json` plano y gzip (`pf_C2__`), `check --json`, `fetch` WebDAV de solo lectura (probado con mock), 21 tests.
- Escritor `set-done` (op `HU`, `ds`, `modified`, `doneOn`), `allowWrite`, `.bak`, `If-Match`; **SP oficial 19.1.0 aislado lo acepta sin conflicto** (informe `VERIFICACION-ESCRITURA-20261021.md` en la carpeta de notas de la sesión).
- UI táctil en memoria: subtareas plegables, editar/crear/borrar, temporizador, Hoy, foco 25/5, deshacer, `exportBackup` atómico.

## Pendiente (con primer paso)
1. Fetch real de solo lectura contra el Nextcloud del dueño — `build/sp-nativo setup` y `fetch` (guía). El dueño la teclea; nadie le pidió credenciales.
2. Escritura real contra Nextcloud — sin empezar, requiere aprobación; casos sin verificar: misma entidad, 412 visto desde SP, padre con subtareas/TODAY/etiquetas/tiempo, SP 19.2.0, cifrado, v3.
3. UI sp-nativo: círculo gris en offscreen GPU, vista Hoy sin datos reales, `deleteTask` deja ids en planner/section/boards, dedo sin probar.
4. Medir Electron oficial (aislar perfil: exportar `XDG_CONFIG_HOME/DATA/CACHE` dentro del sandbox y lanzar `/app/bin/run.sh`; `--user-data-dir` NO aísla y una vez tocó el perfil real —sin pérdida de datos—, backups en `~/backups/sp-real-20261021/`).
5. PKGBUILD aarch64 (vacío) — despliegue lo autoriza el dueño.
