# Cámaras de la uke — material de la etapa C0 (19-oct-2026)

Plan: [`build/gates/revision/CAMARAS-PLAN-20261019.md`](../../../gates/revision/CAMARAS-PLAN-20261019.md). Informes de etapa: `CAMARAS-C0-20261019.md`, `CAMARAS-C1-20261019.md` (misma carpeta).
> **Nada de esto se ha cargado ni flasheado.** `build.sh` y `check-cam.py` son solo PC; `c1-baseline.sh` solo lee por ssh; `deploy.sh --go --push` copia ficheros (necesita orden del dueño) y **no carga nada**.

```bash
build/rootfs/deploy/camaras/build.sh          # ~3 min: overlays, fdtoverlay acumulativo, check-cam, 8 módulos, manifiesto (RESULTADO: OK)
build/rootfs/deploy/camaras/build.sh --quick  # sin módulos
build/rootfs/deploy/camaras/deploy.sh --check # verifica MANIFEST.sha256; sin conexión
build/rootfs/deploy/camaras/c1-baseline.sh    # línea base de solo lectura de la tablet
python3 -I build/rootfs/deploy/camaras/dt-dump.py build/android/dt-full-uke-android base/soc/qcom,cci0@ac15000 -r   # nodo del DT de Android
```
Los módulos se construyen con `make -C senemos-build M=<stage>` (el árbol de build se huella antes y después). Binarios y `odm-camera.tar` no van a git.
Cargadores de overlay: reutilizan `build/rootfs/deploy/bt/module/uke-ovl.h` (`UKE_OVL_INC`). Orden de carga y descarga por etapa: ver el plan §4.
