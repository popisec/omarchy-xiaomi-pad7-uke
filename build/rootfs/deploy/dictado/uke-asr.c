/* uke-asr — reconocedor OFFLINE (sherpa-onnx, Parakeet TDT 0.6B v3 int8) para el dictado de la uke. 22-oct-2026.
 * Carga el modelo UNA vez y transcribe los wav (16 kHz mono) que se le pasen:
 *   uke-asr <dir_modelo> <hilos>                 -> lee rutas de wav por stdin (una por linea); "q" o EOF = salir.
 *                                                   stdout: "listo <s_carga>" y, por cada wav, "texto <frase>"
 *   uke-asr <dir_modelo> <hilos> a.wav b.wav ... -> banco: "<nombre>\t<s_proceso>\t<frase>" por wav
 * uke-dictar lo arranca al EMPEZAR a grabar, asi la carga (~1-2 s) se solapa con el habla.
 * Compilar: cc -O2 -o uke-asr uke-asr.c -I. -L<lib> -lsherpa-onnx-c-api -Wl,-rpath,<lib>  (c-api.h de sherpa-onnx v1.13.8) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "c-api.h"

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static const char *decode(const SherpaOnnxOfflineRecognizer *rec, const char *wav, char *out, size_t n) {
    const SherpaOnnxWave *w = SherpaOnnxReadWave(wav);
    out[0] = 0;
    if (!w) return NULL;
    const SherpaOnnxOfflineStream *s = SherpaOnnxCreateOfflineStream(rec);
    SherpaOnnxAcceptWaveformOffline(s, w->sample_rate, w->samples, w->num_samples);
    SherpaOnnxDecodeOfflineStream(rec, s);
    const SherpaOnnxOfflineRecognizerResult *r = SherpaOnnxGetOfflineStreamResult(s);
    snprintf(out, n, "%s", r && r->text ? r->text : "");
    for (char *p = out; *p; p++) if (*p == '\n' || *p == '\r' || *p == '\t') *p = ' ';
    if (r) SherpaOnnxDestroyOfflineRecognizerResult(r);
    SherpaOnnxDestroyOfflineStream(s);
    SherpaOnnxFreeWave(w);
    return out;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "uso: %s <dir_modelo> <hilos> [wav...]\n", argv[0]); return 2; }
    char enc[1024], dec[1024], joi[1024], tok[1024];
    snprintf(enc, sizeof enc, "%s/encoder.int8.onnx", argv[1]);
    snprintf(dec, sizeof dec, "%s/decoder.int8.onnx", argv[1]);
    snprintf(joi, sizeof joi, "%s/joiner.int8.onnx", argv[1]);
    snprintf(tok, sizeof tok, "%s/tokens.txt", argv[1]);
    SherpaOnnxOfflineRecognizerConfig c;
    memset(&c, 0, sizeof c);
    c.feat_config.sample_rate = 16000;
    c.feat_config.feature_dim = 80;
    c.model_config.transducer.encoder = enc;
    c.model_config.transducer.decoder = dec;
    c.model_config.transducer.joiner = joi;
    c.model_config.tokens = tok;
    c.model_config.model_type = "nemo_transducer";
    c.model_config.num_threads = atoi(argv[2]);
    c.model_config.provider = "cpu";
    c.decoding_method = "greedy_search";
    setvbuf(stdout, NULL, _IOLBF, 0);
    double t0 = now();
    const SherpaOnnxOfflineRecognizer *rec = SherpaOnnxCreateOfflineRecognizer(&c);
    if (!rec) { puts("err no se pudo cargar el modelo"); return 1; }
    static char txt[65536];
    if (argc > 3) {
        fprintf(stderr, "carga %.2f s\n", now() - t0);
        for (int i = 3; i < argc; i++) {
            double a = now();
            decode(rec, argv[i], txt, sizeof txt);
            const char *b = strrchr(argv[i], '/'); b = b ? b + 1 : argv[i];
            char name[256]; snprintf(name, sizeof name, "%s", b); char *dot = strrchr(name, '.'); if (dot) *dot = 0;
            printf("%s\t%.3f\t%s\n", name, now() - a, txt);
        }
    } else {
        printf("listo %.2f\n", now() - t0);
        char line[4096];
        while (fgets(line, sizeof line, stdin)) {
            line[strcspn(line, "\n")] = 0;
            if (!strcmp(line, "q")) break;
            if (!decode(rec, line, txt, sizeof txt)) { puts("err no se pudo leer el wav"); continue; }
            printf("texto %s\n", txt);
        }
    }
    SherpaOnnxDestroyOfflineRecognizer(rec);
    return 0;
}
