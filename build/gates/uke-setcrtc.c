/*
 * uke-setcrtc.c — dispara UN commit de modeset real sobre el conector DSI-1.
 *
 * POR QUE ESTE PROGRAMA Y NO modetest
 * -----------------------------------
 * El uapi de drm de este kernel (7.2-rc2) NO es el clasico de libdrm:
 *   - GETRESOURCES  -> struct drm_mode_card_res  (con *_ptr explicitos),
 *                      no existe struct drm_mode_get_resources
 *   - GETCONNECTOR  -> count_modes/modes_ptr (no count/modes)
 *   - SETCRTC       -> struct drm_mode_crtc con el MODO EN LINEA (no blob)
 *   - ADDFB         -> struct drm_mode_fb_cmd (sin pixel_format)
 *   - CREATE_DUMB   -> sin pixel_format
 * `modetest` de la distro habla el uapi viejo: por eso abria card1 y no
 * listaba ningun conector (el "problema D-1"). Este programa habla el correcto.
 *
 * El id del conector se lee de sysfs (`/sys/class/drm/card1-DSI-1/connector_id`),
 * que no depende de ningun uapi.
 *
 * Secuencia minima que enciende un panel:
 *   GETRESOURCES -> CRTCs
 *   GETCONNECTOR -> modos del panel (3200x2136)
 *   CREATE_DUMB  -> fb de 32 bpp del tamaño del modo
 *   ADDFB        -> fb_id
 *   SETCRTC      -> EL COMMIT (aqui muere el SoC en L25..L32)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <stdint.h>

#include <drm/drm.h>
#include <drm/drm_mode.h>

#define STEP(...) do { printf(__VA_ARGS__); fflush(stdout); } while (0)

static int leer_uint(const char *path, unsigned *out)
{
	FILE *f = fopen(path, "r");
	if (!f) return -1;
	int rc = fscanf(f, "%u", out);
	fclose(f);
	return rc == 1 ? 0 : -1;
}

int main(int argc, char **argv)
{
	const char *dev   = argc > 1 ? argv[1] : "/dev/dri/card1";
	const char *sysds = argc > 2 ? argv[2] : "/sys/class/drm/card1-DSI-1";

	unsigned conn_id = 0, crtc_id = 0;
	char p[256];

	STEP("[setcrtc] === 1/5 id del conector desde sysfs ===\n");
	snprintf(p, sizeof(p), "%s/connector_id", sysds);
	if (leer_uint(p, &conn_id) < 0) { STEP("[setcrtc] ERROR no leo %s: %s\n", p, strerror(errno)); return 1; }
	snprintf(p, sizeof(p), "%s/crtc", sysds);
	leer_uint(p, &crtc_id);                    /* puede ser -1/notpresent */
	STEP("[setcrtc] DSI-1 connector_id=%u  crtc(asignado en sysfs)=%u\n", conn_id, crtc_id);

	STEP("[setcrtc] === 2/5 abrir %s ===\n", dev);
	int fd = open(dev, O_RDWR | O_CLOEXEC);
	if (fd < 0) { STEP("[setcrtc] ERROR open: %s\n", strerror(errno)); return 1; }

	/* CRTCs disponibles (si sysfs no dio uno, cogemos el primero) */
	struct drm_mode_card_res res;
	memset(&res, 0, sizeof(res));
	if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
		STEP("[setcrtc] ERROR GETRESOURCES: %s\n", strerror(errno)); return 1;
	}
	STEP("[setcrtc] recursos: crtcs=%u connectors=%u encoders=%u fbs=%u\n",
	     res.count_crtcs, res.count_connectors, res.count_encoders, res.count_fbs);
	if (!res.count_crtcs) { STEP("[setcrtc] ERROR: 0 crtcs\n"); return 1; }

	__u32 *crtcs = calloc(res.count_crtcs, sizeof(__u32));
	struct drm_mode_card_res g = { .count_crtcs = res.count_crtcs,
	                               .crtc_id_ptr = (uint64_t)(uintptr_t)crtcs };
	if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &g) < 0) {
		STEP("[setcrtc] ERROR GETRESOURCES#2: %s\n", strerror(errno)); return 1;
	}
	for (unsigned i = 0; i < res.count_crtcs; i++)
		STEP("[setcrtc]   crtc[%u] = id %u\n", i, crtcs[i]);

	if (crtc_id == 0 || crtc_id == ~0u) {
		crtc_id = crtcs[0];
		STEP("[setcrtc] uso crtcs[0] = %u\n", crtc_id);
	}

	STEP("[setcrtc] === 3/5 modos del conector %u ===\n", conn_id);
	/* primero, cuantos hay */
	struct drm_mode_get_connector q;
	memset(&q, 0, sizeof(q));
	q.connector_id = conn_id;
	q.count_modes  = 1;
	struct drm_mode_modeinfo tmp;
	memset(&tmp, 0, sizeof(tmp));
	q.modes_ptr = (uint64_t)(uintptr_t)&tmp;
	if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &q) < 0) {
		STEP("[setcrtc] ERROR GETCONNECTOR#1: %s\n", strerror(errno)); return 1;
	}
	unsigned nm = q.count_modes;
	STEP("[setcrtc] el conector declara %u modo(s)\n", nm);
	if (!nm) { STEP("[setcrtc] ERROR: 0 modos\n"); return 1; }

	struct drm_mode_modeinfo *modes = calloc(nm, sizeof(*modes));
	memset(&q, 0, sizeof(q));
	q.connector_id = conn_id;
	q.count_modes  = nm;
	q.modes_ptr    = (uint64_t)(uintptr_t)modes;
	if (ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &q) < 0) {
		STEP("[setcrtc] ERROR GETCONNECTOR#2: %s\n", strerror(errno)); return 1;
	}
	for (unsigned i = 0; i < nm; i++)
		STEP("[setcrtc]   modo[%u]: %ux%u clock=%u type=%x\n",
		     i, modes[i].hdisplay, modes[i].vdisplay, modes[i].clock, modes[i].type);

	/* el mas grande: el que de verdad enciende el panel nativo */
	unsigned best = 0;
	for (unsigned i = 1; i < nm; i++)
		if ((unsigned)modes[i].hdisplay * modes[i].vdisplay >
		    (unsigned)modes[best].hdisplay * modes[best].vdisplay)
			best = i;
	__u32 w = modes[best].hdisplay, h = modes[best].vdisplay;
	STEP("[setcrtc] uso modo[%u] = %ux%u\n", best, w, h);

	STEP("[setcrtc] === 4/5 framebuffer tonto %ux%u ===\n", w, h);
	struct drm_mode_create_dumb dumb;
	memset(&dumb, 0, sizeof(dumb));
	dumb.width = w; dumb.height = h; dumb.bpp = 32;
	if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb) < 0) {
		STEP("[setcrtc] ERROR CREATE_DUMB: %s\n", strerror(errno)); return 1;
	}
	STEP("[setcrtc] dumb: handle=%u pitch=%u size=%llu\n", dumb.handle, dumb.pitch, (unsigned long long)dumb.size);

	struct drm_mode_fb_cmd fb;
	memset(&fb, 0, sizeof(fb));
	fb.width = w; fb.height = h; fb.pitch = dumb.pitch;
	fb.bpp = 32; fb.depth = 24; fb.handle = dumb.handle;
	if (ioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb) < 0) {
		STEP("[setcrtc] ERROR ADDFB: %s\n", strerror(errno)); return 1;
	}
	STEP("[setcrtc] fb_id=%u\n", fb.fb_id);

	void *map = mmap(NULL, dumb.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, dumb.handle);
	if (map != MAP_FAILED) { memset(map, 0, dumb.size); STEP("[setcrtc] fb mapeada\n"); }
	else STEP("[setcrtc] aviso: mmap fallo (%s)\n", strerror(errno));

	/* ---- EL COMMIT ---- */
	if (getenv("UKE_DRY")) {
		STEP("[setcrtc] DRY: llego hasta SETCRTC sin lanzarlo. Todo lo de antes OK.\n");
		return 0;
	}
	STEP("[setcrtc] === 5/5 SETCRTC  <-- AQUI SUENA LA MUERTE ===\n");
	__u32 conns[1] = { conn_id };
	struct drm_mode_crtc sc;
	memset(&sc, 0, sizeof(sc));
	sc.crtc_id             = crtc_id;
	sc.fb_id               = fb.fb_id;
	sc.x = 0; sc.y = 0;
	sc.count_connectors    = 1;
	sc.set_connectors_ptr  = (uint64_t)(uintptr_t)conns;
	sc.mode_valid          = 1;
	sc.mode                = modes[best];
	STEP("[setcrtc] crtc=%u fb=%u conn=%u modo=%ux%u\n",
	     sc.crtc_id, sc.fb_id, conn_id, w, h);
	fflush(stdout);

	int rc = ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &sc);
	STEP("[setcrtc] <<< SETCRTC rc=%d (%s)  ==> SOBREVIVIO\n",
	     rc, rc < 0 ? strerror(errno) : "ok");
	return rc < 0 ? 2 : 0;
}