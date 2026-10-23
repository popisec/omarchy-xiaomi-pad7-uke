// SPDX-License-Identifier: GPL-2.0
/*
 * uke_spfcore_probe — SONDA de diagnostico (E2c, AUDIO-E2b-DIAGNOSTICO-20261018.md). NO es un driver de audio.
 *
 * Imita lo que hace el `spf_core` de Android (vendor gpr-lite): se liga al servicio GPR vendor `spf_core` (reg 3, compat "qcom,spf_core",
 * que hoy no tiene driver) y envia APM_CMD_GET_SPF_STATE (0x01001021) al APM del ADSP con **src_port = 3** (el id de spf_core) en vez del
 * src_port = 1 que usa q6apm de mainline. Registra en dmesg TODO paquete que llegue a ese puerto (src/dest/opcode/token/primeras palabras)
 * y si llega APM_CMD_RSP_GET_SPF_STATE (0x02001007) lo marca. Un solo comando de estado, sin DMA ni relojes ni grafos.
 *
 * Parametros: cmdhdr=1 (por defecto) añade la cabecera apm_cmd_header de 16 B como hace q6apm; cmdhdr=0 envia el paquete GPR desnudo.
 * Carga: con apr cargado y SIN el overlay e2 (el servicio spf_core vendor existe sin el): insmod uke_spfcore_probe.ko. Descarga: rmmod.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/workqueue.h>
#include <linux/completion.h>
#include <linux/soc/qcom/apr.h>

#define APM_CMD_GET_SPF_STATE		0x01001021
#define APM_CMD_RSP_GET_SPF_STATE	0x02001007
#define APM_MODULE_INSTANCE_ID		0x00000001

static int cmdhdr = 1;
module_param(cmdhdr, int, 0444);
MODULE_PARM_DESC(cmdhdr, "1 = incluir apm_cmd_header (16 B) como q6apm; 0 = paquete desnudo");

struct probe_ctx {
	struct apr_device *gdev;
	struct work_struct work;
	struct completion done;
	int got_rsp;
	int rx;
};
static struct probe_ctx *ctx;

static int probe_cb(const struct gpr_resp_pkt *d, void *priv, int op)
{
	const struct gpr_hdr *h = &d->hdr;
	const u32 *p = d->payload;

	ctx->rx++;
	dev_info(&ctx->gdev->dev,
		 "RX #%d: src=%u:%u dest=%u:%u opcode=0x%08x token=0x%x payload=%d B w0=0x%08x w1=0x%08x\n",
		 ctx->rx, h->src_domain, h->src_port, h->dest_domain, h->dest_port, h->opcode, h->token,
		 d->payload_size, d->payload_size >= 4 ? p[0] : 0, d->payload_size >= 8 ? p[1] : 0);
	if (h->opcode == APM_CMD_RSP_GET_SPF_STATE) {
		ctx->got_rsp = 1;
		complete(&ctx->done);
	}
	return 0;
}

static void probe_work(struct work_struct *w)
{
	struct probe_ctx *c = container_of(w, struct probe_ctx, work);
	struct apr_device *gdev = c->gdev;
	int extra = cmdhdr ? 16 : 0;
	int size = sizeof(struct gpr_hdr) + extra;
	struct gpr_pkt *pkt;
	int rc;

	pkt = kzalloc(size, GFP_KERNEL);
	if (!pkt)
		return;
	pkt->hdr.version = GPR_PKT_VER;
	pkt->hdr.hdr_size = GPR_PKT_HEADER_WORD_SIZE;
	pkt->hdr.pkt_size = size;
	pkt->hdr.dest_domain = 2;		/* ADSP (GPR_DOMAIN_ID_ADSP) */
	pkt->hdr.src_domain = 3;		/* APPS (GPR_DOMAIN_ID_APPS) */
	pkt->hdr.src_port = gdev->svc_id;	/* 3 = spf_core */
	pkt->hdr.dest_port = APM_MODULE_INSTANCE_ID;
	pkt->hdr.token = 0;
	pkt->hdr.opcode = APM_CMD_GET_SPF_STATE;

	dev_info(&gdev->dev, "TX GET_SPF_STATE src=%u:%u dest=%u:%u cmdhdr=%d size=%d\n",
		 pkt->hdr.src_domain, pkt->hdr.src_port, pkt->hdr.dest_domain, pkt->hdr.dest_port, cmdhdr, size);
	rc = gpr_send_pkt(gdev, pkt);
	dev_info(&gdev->dev, "gpr_send_pkt rc=%d\n", rc);
	kfree(pkt);
	if (rc < 0)
		return;
	if (!wait_for_completion_timeout(&c->done, 5 * HZ))
		dev_info(&gdev->dev, "sin APM_CMD_RSP_GET_SPF_STATE tras 5 s (paquetes recibidos en el puerto: %d)\n", c->rx);
	else
		dev_info(&gdev->dev, "APM RESPONDE: APM_CMD_RSP_GET_SPF_STATE recibido con src_port=%u\n", gdev->svc_id);
}

static int probe_probe(struct apr_device *gdev)
{
	ctx = kzalloc(sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;
	ctx->gdev = gdev;
	init_completion(&ctx->done);
	INIT_WORK(&ctx->work, probe_work);
	dev_info(&gdev->dev, "sonda spf_core ligada (svc_id=%u domain=%u)\n", gdev->svc_id, gdev->domain_id);
	schedule_work(&ctx->work);
	return 0;
}

static void probe_remove(struct apr_device *gdev)
{
	cancel_work_sync(&ctx->work);
	kfree(ctx);
	ctx = NULL;
}

static const struct of_device_id probe_of[] = {
	{ .compatible = "qcom,spf_core" },
	{ }
};
MODULE_DEVICE_TABLE(of, probe_of);

static struct apr_driver probe_driver = {
	.probe = probe_probe,
	.remove = probe_remove,
	.gpr_callback = probe_cb,
	.driver = {
		.name = "uke-spfcore-probe",
		.of_match_table = probe_of,
	},
};
module_apr_driver(probe_driver);
MODULE_DESCRIPTION("uke: sonda GPR que imita spf_core de Android (diagnostico)");
MODULE_AUTHOR("omarchy-uke");
MODULE_LICENSE("GPL");
