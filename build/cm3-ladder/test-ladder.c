/*
 * Prueba de la disciplina de la escalera UKE-CM3, sin tablet.
 *
 * Modela EXACTAMENTE lo que hace el parche uke-cm3-ladder.diff en
 * a6xx_gmu_start(): por cada acceso MMIO, linea PRE (log, con fflush+fsync
 * inmediato = printk a logbuf) + marcador sincrono pre-* (fichero con
 * O_APPEND + fsync tras cada escritura = uke_poke al framebuffer, que
 * escribe sincrono y falla cerrado), acceso, marcador post-*, linea POST
 * con el valor leido.
 *
 * Tres escenarios sobre el mismo codigo de escalera:
 *   hang    -> el readl canario no vuelve nunca (bus stall). El padre
 *              comprueba que la ultima linea del log es el PRE y el ultimo
 *              marcador es el pre-*. Exito = el acceso queda identificado.
 *   garbage -> el readl vuelve con basura: el poll agota y vuelve -ETIMEDOUT
 *              (completa, no se cuelga). Exito = POST muestra el valor malo
 *              y el veredicto es TIMEOUT, distinguible del hang.
 *   ok      -> el readl devuelve la magia esperada. Exito = POST poll ret=0.
 *
 * Lo que prueba: que SI un readl se cuelga, la ultima linea impresa es la
 * del acceso (la disciplina PRE-antes-del-acceso funciona).
 * Lo que NO prueba (limite honesto, ver INFORME-CM3.md): el timing de flush
 * de printk bajo un stall real de AXI; por eso el parche empareja cada
 * printk con un uke_poke sincrono (ronda 9 del proyecto hermano).
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>

static FILE *kmsg;   /* stdout del hijo redirigido a kmsg.log */
static int fb_fd;    /* marcadores sincronos, uno por linea + fsync */

static void klog(const char *tag, const char *msg, unsigned int reg,
		 int has_val, unsigned int val)
{
	if (has_val)
		fprintf(kmsg, "UKE-CM3: %s %s reg=0x%05x val=%#x\n",
			tag, msg, reg, val);
	else
		fprintf(kmsg, "UKE-CM3: %s %s reg=0x%05x\n", tag, msg, reg);
	fflush(kmsg);
	fsync(fileno(kmsg)); /* printk mete el registro en logbuf YA */
}

static void poke(const char *tag)
{
	char b[64];
	int n = snprintf(b, sizeof(b), "%s\n", tag);
	if (write(fb_fd, b, (size_t)n) != n)
		_exit(99);
	fsync(fb_fd); /* uke_poke pinta la fila el mismo, sincrono */
}

/* ---- MMIO fingido ---- */
#define REG_DTCM_MAGIC 0x1c400
#define REG_SYSRESET   0x1f800
#define REG_LOGWPTR    0x1f9ce
#define REG_INITRES    0x1f81c

static int mode; /* 0=ok 1=garbage 2=hang */
static unsigned int fake_initres;

static unsigned int fake_readl(unsigned int reg)
{
	if (reg == REG_DTCM_MAGIC)
		return 0x20010004 + 1; /* rama mask=0x1ff expect=0x100 */
	if (reg == REG_INITRES) {
		if (mode == 2)
			for (;;)
				pause(); /* bus stall: no vuelve nunca */
		return fake_initres;
	}
	return 0;
}

static void fake_writel(unsigned int reg, unsigned int v)
{
	(void)reg;
	(void)v; /* posted: siempre "vuelve" */
}

/* ---- la escalera (misma secuencia que a6xx_gmu_start + canario L14) ---- */
static int ladder(void)
{
	unsigned int val, mask = 0x1ff, expect = 0x100, last = 0;
	int i, ret = -110; /* -ETIMEDOUT */

	klog("PRE", "dtcm-magic", REG_DTCM_MAGIC, 0, 0);
	poke("L10-pre-dtcm");
	val = fake_readl(REG_DTCM_MAGIC);
	poke("L10-post-dtcm");
	klog("POST", "dtcm-magic", REG_DTCM_MAGIC, 1, val);

	klog("PRE", "sysreset-assert", REG_SYSRESET, 0, 0);
	poke("L11-pre-rst1");
	fake_writel(REG_SYSRESET, 1);
	poke("L11-post-rst1");

	klog("PRE", "logwptr-a7", REG_LOGWPTR, 0, 0);
	poke("L12-pre-logw");
	fake_writel(REG_LOGWPTR, 0);
	poke("L12-post-logw");

	klog("PRE", "sysreset-release", REG_SYSRESET, 0, 0);
	poke("L13-pre-rst0");
	fake_writel(REG_SYSRESET, 0);
	poke("L13-post-rst0");

	klog("PRE", "canary-init-result", REG_INITRES, 0, 0);
	poke("L14-pre-canary");
	val = fake_readl(REG_INITRES); /* <-- el acceso sospechoso */
	poke("L14-post-canary");
	klog("POST", "canary-init-result", REG_INITRES, 1, val);

	klog("PRE", "poll-init-result", REG_INITRES, 0, 0);
	poke("L15-pre-poll");
	for (i = 0; i < 1000; i++) { /* readl_poll_timeout acotado */
		last = fake_readl(REG_INITRES);
		if ((last & mask) == expect) {
			ret = 0;
			break;
		}
	}
	poke("L15-post-poll");
	klog("POST", "poll-init-result", REG_INITRES, 1, last);
	if (ret)
		fprintf(kmsg, "GMU firmware initialization timed out\n");
	fflush(kmsg);
	fsync(fileno(kmsg));
	return ret;
}

int main(int argc, char **argv)
{
	if (argc != 4) {
		fprintf(stderr, "uso: %s <mode:ok|garbage|hang> <kmsg> <fb>\n",
			argv[0]);
		return 2;
	}
	if (!strcmp(argv[1], "ok")) {
		mode = 0;
		fake_initres = 0x100;
	} else if (!strcmp(argv[1], "garbage")) {
		mode = 1;
		fake_initres = 0xdeadbeef;
	} else if (!strcmp(argv[1], "hang")) {
		mode = 2;
		fake_initres = 0;
	} else {
		return 2;
	}

	kmsg = fopen(argv[2], "w");
	if (!kmsg)
		return 3;
	fb_fd = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fb_fd < 0)
		return 3;
	return ladder() ? 1 : 0; /* 1=timeout-con-mensaje, 0=ok */
}
