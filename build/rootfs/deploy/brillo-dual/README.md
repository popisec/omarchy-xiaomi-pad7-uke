# brillo-dual

Resultado: **no hay nada que desplegar**. En ouke4 el driver `ktz8866` ya escribe los DOS chips
desde `/sys/class/backlight/uke-backlight`. Ver `build/gates/revision/KTZ-DUAL-20261018.md`.

- `./deploy.sh check`  — solo lectura (regs 0x04/0x05/0x08 de i2c-2 y i2c-5; deben ser iguales).
- `./deploy.sh apply`  — prueba activa: escribe brightness 600 y 200 por sysfs, compara ambos chips y restaura. **Requiere autorizacion del dueno.**
- `./deploy.sh revert` — restaura el brillo guardado (/run/brillo-dual.saved).

Riesgo de `apply`: ninguno persistente (es lo que hace hypridle/brightnessctl); peor caso, brillo bajo; se recupera con `brightnessctl -d uke-backlight set 372` o reiniciando.
