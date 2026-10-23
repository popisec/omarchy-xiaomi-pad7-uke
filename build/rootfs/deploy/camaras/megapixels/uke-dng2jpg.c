// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * uke-dng2jpg.c — revela el DNG que escribe Megapixels 1.8.3 en la uke (sin dcraw/libraw en la tablet). 22-oct-2026.
 * Uso: uke-dng2jpg entrada.dng [mas.dng ...] salida.ppm   (con varios DNG de la misma rafaga, se PROMEDIAN: menos ruido)
 * Lee la SubIFD con el RAW (CFA, 10 bits secuenciales MSB primero o 8/16 bits), aplica el nivel de negro/blanco del DNG, balance de
 * blancos gris en tonos medios por superpixeles 2x2 (como raw-develop.py del PC), demosaico bilineal a resolucion completa, recorte
 * neutro de altas luces, CCM generica (aproximada, sin calibrar), exposicion (p99 de la luminancia -> 0,92) y curva sRGB.
 * Compilar: cc -O2 -o uke-dng2jpg uke-dng2jpg.c $(pkg-config --cflags --libs libtiff-4) -lm
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tiffio.h>

#define TAG_CFAPATTERN 33422

static int die(const char *m) { fprintf(stderr, "uke-dng2jpg: %s\n", m); return 1; }

/* suma en acc el RAW normalizado (0..1 sobre el negro) de la SubIFD ya seleccionada */
static int add_raw(TIFF *tif, uint32_t w, uint32_t h, uint16_t bps, float black, float white, float *acc)
{
	tmsize_t sl = TIFFScanlineSize(tif);
	uint8_t *line = malloc(sl + 8);
	if (!line)
		return -1;
	for (uint32_t y = 0; y < h; y++) {
		if (TIFFReadScanline(tif, line, y, 0) < 0) {
			free(line);
			return -1;
		}
		for (uint32_t x = 0; x < w; x++) {
			uint32_t v;
			if (bps == 8) {
				v = line[x];
			} else if (bps == 16) {
				v = ((uint16_t *)line)[x];
			} else {	/* 10 bits secuenciales, MSB primero */
				uint64_t bit = (uint64_t)x * 10, by = bit >> 3, sh = bit & 7;
				uint32_t two = ((uint32_t)line[by] << 8) | line[by + 1];
				v = (two >> (6 - sh)) & 0x3ff;
			}
			acc[(size_t)y * w + x] += ((float)v - black) / (white - black);
		}
	}
	free(line);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 3)
		return die("uso: uke-dng2jpg entrada.dng [mas.dng ...] salida.ppm");
	const char *outp = argv[argc - 1];
	TIFF *tif = TIFFOpen(argv[1], "r");
	if (!tif)
		return die("no se puede abrir el DNG");
	uint16_t orient = 1;
	TIFFGetField(tif, TIFFTAG_ORIENTATION, &orient);	/* IFD0 (miniatura): Megapixels guarda aqui la rotacion de la camara */
	printf("%u\n", orient);	/* stdout: orientacion EXIF para el postproceso (1, 3, 6, 8) */
	uint16_t nsub = 0; uint64_t *subs = NULL;
	if (TIFFGetField(tif, TIFFTAG_SUBIFD, &nsub, &subs) && nsub > 0) {
		if (!TIFFSetSubDirectory(tif, subs[0]))
			return die("SubIFD ilegible");
	}
	uint32_t w = 0, h = 0; uint16_t bps = 0, phot = 0;
	TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &w);
	TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &h);
	TIFFGetField(tif, TIFFTAG_BITSPERSAMPLE, &bps);
	TIFFGetField(tif, TIFFTAG_PHOTOMETRIC, &phot);
	if (phot != PHOTOMETRIC_CFA || w < 4 || h < 4 || (bps != 8 && bps != 10 && bps != 16))
		return die("no es un CFA de 8/10/16 bits");
	uint8_t cfa[4] = { 1, 0, 2, 1 };	/* GRBG por defecto */
	{
		uint16_t n = 0; uint8_t *p = NULL;
		if (TIFFGetField(tif, TAG_CFAPATTERN, &n, &p) && n == 4 && p)
			memcpy(cfa, p, 4);
	}
	float black = 0, white = (float)((1u << bps) - 1);
	{
		uint16_t n = 0; float *b = NULL; uint32_t *wl = NULL;
		if (TIFFGetField(tif, TIFFTAG_BLACKLEVEL, &n, &b) && n >= 1 && b)
			black = b[0];
		if (TIFFGetField(tif, TIFFTAG_WHITELEVEL, &n, &wl) && n >= 1 && wl)
			white = (float)wl[0];
	}
	float *raw = calloc((size_t)w * h, sizeof(float));
	if (!raw || add_raw(tif, w, h, bps, black, white, raw))
		return die("error leyendo el RAW");
	int nfr = 1;
	/* rafaga: el resto de DNG (misma camara y modo) se suman y se promedia; UKE_NO_STACK=1 lo desactiva */
	for (int a = 2; a < argc - 1 && !getenv("UKE_NO_STACK"); a++) {
		TIFF *t2 = TIFFOpen(argv[a], "r");
		uint16_t n2 = 0; uint64_t *s2 = NULL; uint32_t w2 = 0, h2 = 0; uint16_t b2 = 0;
		if (!t2)
			continue;
		if (TIFFGetField(t2, TIFFTAG_SUBIFD, &n2, &s2) && n2 > 0)
			TIFFSetSubDirectory(t2, s2[0]);
		TIFFGetField(t2, TIFFTAG_IMAGEWIDTH, &w2); TIFFGetField(t2, TIFFTAG_IMAGELENGTH, &h2); TIFFGetField(t2, TIFFTAG_BITSPERSAMPLE, &b2);
		if (w2 == w && h2 == h && b2 == bps && !add_raw(t2, w, h, bps, black, white, raw))
			nfr++;
		TIFFClose(t2);
	}
	for (size_t i = 0; i < (size_t)w * h; i++) {
		float f = raw[i] / nfr;
		raw[i] = f < 0 ? 0 : f;
	}
	fprintf(stderr, "uke-dng2jpg: %d tramas promediadas\n", nfr);
	TIFFClose(tif);
#define C(x, y) (cfa[((y) & 1) * 2 + ((x) & 1)])
	/* balance de blancos: superpixeles 2x2 en tonos medios. Umbral inferior RELATIVO (percentil 20 de la luminancia de los superpixeles,
	 * minimo 0,002): con 0,03 fijo, una escena oscura no dejaba ninguno (WB 1/1 y tinte verde, foto de la frontal 17:12) */
	static long lh[4096]; long ltot = 0;
	for (uint32_t y = 0; y + 1 < h; y += 2)
		for (uint32_t x = 0; x + 1 < w; x += 2) {
			float a = 0;
			for (int k = 0; k < 4; k++) a += raw[(size_t)(y + (k >> 1)) * w + x + (k & 1)];
			int b = (int)(a / 4 * 4095); lh[b < 0 ? 0 : b > 4095 ? 4095 : b]++; ltot++;
		}
	float lo = 0.002f; { long acc = 0; for (int b = 0; b < 4096; b++) { acc += lh[b]; if (acc >= ltot / 5) { float v = b / 4095.0f; if (v > lo) lo = v; break; } } }
	double s[3] = { 0, 0, 0 }; long cnt = 0;
	for (uint32_t y = 0; y + 1 < h; y += 2)
		for (uint32_t x = 0; x + 1 < w; x += 2) {
			float c3[3] = { 0, 0, 0 }; int g = 0; float mx = 0;
			for (int k = 0; k < 4; k++) {
				uint32_t xx = x + (k & 1), yy = y + (k >> 1); float v = raw[(size_t)yy * w + xx];
				int c = C(xx, yy); c3[c] += v; g += c == 1; if (v > mx) mx = v;
			}
			c3[1] /= g ? g : 1;
			float l = (c3[0] + 2 * c3[1] + c3[2]) / 4;
			if (l > lo && l < 0.85f && mx < 0.97f) { s[0] += c3[0]; s[1] += c3[1]; s[2] += c3[2]; cnt++; }
		}
	float gain[3] = { 1, 1, 1 };
	if (cnt > 100 && s[0] > 0 && s[2] > 0) { gain[0] = (float)(s[1] / s[0]); gain[2] = (float)(s[1] / s[2]); }
	fprintf(stderr, "uke-dng2jpg: %ux%u bps=%u negro=%.0f blanco=%.0f WB R=%.3f B=%.3f\n", w, h, bps, black, white, gain[0], gain[2]);
	for (uint32_t y = 0; y < h; y++)
		for (uint32_t x = 0; x < w; x++) {
			float *p = &raw[(size_t)y * w + x];
			*p = fminf(*p * gain[C(x, y)], 1.0f);
		}
	/* demosaico bilineal */
	float *rgb = malloc(sizeof(float) * 3 * w * h);
	if (!rgb)
		return die("sin memoria");
	for (uint32_t y = 0; y < h; y++)
		for (uint32_t x = 0; x < w; x++) {
			float acc[3] = { 0, 0, 0 }; int n[3] = { 0, 0, 0 };
			for (int dy = -1; dy <= 1; dy++)
				for (int dx = -1; dx <= 1; dx++) {
					int xx = (int)x + dx, yy = (int)y + dy;
					if (xx < 0 || yy < 0 || xx >= (int)w || yy >= (int)h)
						continue;
					int c = C(xx, yy);
					/* el color propio solo del centro; los demas de los vecinos (verde: solo en cruz) */
					if (c == C(x, y) && (dx || dy))
						continue;
					if (c == 1 && dx && dy)
						continue;
					acc[c] += raw[(size_t)yy * w + xx]; n[c]++;
				}
			float *o = &rgb[((size_t)y * w + x) * 3];
			for (int c = 0; c < 3; c++)
				o[c] = n[c] ? acc[c] / n[c] : 0;
			{	/* CCM suave = I + 0,4 (CCM generica de OmniVision - I): APROXIMADA, filas que suman 1; la generica entera amplificaba el sombreado de color sin calibrar. Igual que el preview (parche 0005) */
				static const float M[9] = { 1.248f, -0.180f, -0.068f, -0.112f, 1.208f, -0.096f, -0.020f, -0.248f, 1.268f };
				float r = o[0], g = o[1], b = o[2];
				o[0] = fmaxf(M[0] * r + M[1] * g + M[2] * b, 0);
				o[1] = fmaxf(M[3] * r + M[4] * g + M[5] * b, 0);
				o[2] = fmaxf(M[6] * r + M[7] * g + M[8] * b, 0);
			}
			float mn = fminf(o[0], fminf(o[1], o[2])), mxv = fmaxf(o[0], fmaxf(o[1], o[2]));
			float hl = (mn - 0.85f) / 0.15f;	/* cerca del blanco: neutro */
			if (hl > 0) { if (hl > 1) hl = 1; for (int c = 0; c < 3; c++) o[c] = o[c] * (1 - hl) + mxv * hl; }
		}
	free(raw);
	/* sombreado de color (APROXIMADO, sin calibracion plana): ajuste por minimos cuadrados de R/G y B/G en bloques de 64x64 a un modelo suave
	 * a + b*x + c*y + d*(x^2+y^2) (x, y en [-1, 1]), ignorando bloques oscuros, saturados o muy coloreados; se divide para dejar la
	 * cromaticidad media constante. Corrige el verde/magenta de la lente que la CCM amplificaba. Desactivable con UKE_NO_SHADING=1. */
	if (!getenv("UKE_NO_SHADING")) {
		const int B = 64; int bw = w / B, bh = h / B;
		double A[2][4][4] = { { { 0 } } }, Y[2][4] = { { 0 } }; long nb = 0;
		for (int by = 0; by < bh; by++)
			for (int bx = 0; bx < bw; bx++) {
				double s3[3] = { 0, 0, 0 };
				for (int y = by * B; y < (by + 1) * B; y += 2)
					for (int x = bx * B; x < (bx + 1) * B; x += 2)
						for (int c = 0; c < 3; c++) s3[c] += rgb[((size_t)y * w + x) * 3 + c];
				double nn = (B / 2) * (B / 2), r = s3[0] / nn, g = s3[1] / nn, b = s3[2] / nn;
				if (g < 0.01 || g > 0.8 || r <= 0 || b <= 0) continue;
				double rg = r / g, bg = b / g;
				if (rg < 0.5 || rg > 2 || bg < 0.5 || bg > 2) continue;
				double xx = (bx + 0.5) / bw * 2 - 1, yy = (by + 0.5) / bh * 2 - 1, f[4] = { 1, xx, yy, xx * xx + yy * yy };
				for (int i = 0; i < 4; i++) {
					for (int j = 0; j < 4; j++) { A[0][i][j] += f[i] * f[j]; A[1][i][j] += f[i] * f[j]; }
					Y[0][i] += f[i] * rg; Y[1][i] += f[i] * bg;
				}
				nb++;
			}
		if (nb > 40) {
			double coef[2][4];
			for (int k = 0; k < 2; k++) {	/* Gauss sobre la matriz normal 4x4 */
				double m[4][5];
				for (int i = 0; i < 4; i++) { for (int j = 0; j < 4; j++) m[i][j] = A[k][i][j] + (i == j ? 1e-6 : 0); m[i][4] = Y[k][i]; }
				for (int i = 0; i < 4; i++) {
					int pv = i; for (int r = i + 1; r < 4; r++) if (fabs(m[r][i]) > fabs(m[pv][i])) pv = r;
					for (int j = 0; j < 5; j++) { double tt = m[i][j]; m[i][j] = m[pv][j]; m[pv][j] = tt; }
					for (int r = 0; r < 4; r++) if (r != i) { double q = m[r][i] / m[i][i]; for (int j = 0; j < 5; j++) m[r][j] -= q * m[i][j]; }
				}
				for (int i = 0; i < 4; i++) coef[k][i] = m[i][4] / m[i][i];
			}
			fprintf(stderr, "uke-dng2jpg: sombreado R/G %.3f %+.3fx %+.3fy %+.3fr2  B/G %.3f %+.3fx %+.3fy %+.3fr2 (%ld bloques)\n",
				coef[0][0], coef[0][1], coef[0][2], coef[0][3], coef[1][0], coef[1][1], coef[1][2], coef[1][3], nb);
			for (uint32_t y = 0; y < h; y++)
				for (uint32_t x = 0; x < w; x++) {
					double xx = (x + 0.5) / w * 2 - 1, yy = (y + 0.5) / h * 2 - 1, r2 = xx * xx + yy * yy;
					double fr = (coef[0][0] + coef[0][1] * xx + coef[0][2] * yy + coef[0][3] * r2) / coef[0][0];
					double fb = (coef[1][0] + coef[1][1] * xx + coef[1][2] * yy + coef[1][3] * r2) / coef[1][0];
					float *o = &rgb[((size_t)y * w + x) * 3];
					if (fr > 0.3) o[0] /= fr;
					if (fb > 0.3) o[2] /= fb;
				}
		}
	}
	/* exposicion: p99 de la luminancia -> 0,92 (histograma de 4096 cubetas) */
	static long hist[4096]; size_t npx = (size_t)w * h;
	for (size_t i = 0; i < npx; i++) {
		float *o = &rgb[i * 3]; float l = 0.2126f * o[0] + 0.7152f * o[1] + 0.0722f * o[2];
		int b = (int)(l * 4095); hist[b < 0 ? 0 : b > 4095 ? 4095 : b]++;
	}
	long acc = 0; int p99 = 4095;
	for (int b = 0; b < 4096; b++) { acc += hist[b]; if (acc >= (long)(npx * 0.99)) { p99 = b; break; } }
	/* con la AE por software (parche 0004) la exposicion ya viene ajustada: solo un estirado suave (antes hasta 16x: fotos lavadas) */
	float k = 0.92f / ((p99 + 1) / 4096.0f); if (k > 1.4f) k = 1.4f; if (k < 0.7f) k = 0.7f;
	FILE *f = fopen(outp, "wb");
	if (!f)
		return die("no se puede escribir la salida");
	fprintf(f, "P6\n%u %u\n255\n", w, h);
	uint8_t lut[4097];
	for (int i = 0; i <= 4096; i++) {
		float v = i / 4096.0f;
		v = v <= 0.0031308f ? 12.92f * v : 1.055f * powf(v, 1 / 2.4f) - 0.055f;
		lut[i] = (uint8_t)(fminf(fmaxf(v, 0), 1) * 255 + 0.5f);
	}
	uint8_t *row = malloc((size_t)w * 3);
	for (uint32_t y = 0; y < h; y++) {
		for (uint32_t x = 0; x < w; x++)
			for (int c = 0; c < 3; c++) {
				float v = rgb[((size_t)y * w + x) * 3 + c] * k;
				int i = (int)(fminf(v, 1.0f) * 4096);
				row[x * 3 + c] = lut[i < 0 ? 0 : i];
			}
		fwrite(row, 1, (size_t)w * 3, f);
	}
	fclose(f);
	free(row); free(rgb);
	return 0;
}
