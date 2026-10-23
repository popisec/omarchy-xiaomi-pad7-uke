// SPDX-License-Identifier: GPL-2.0
/*
 * uke_vcm.c -- driver minimo del VCM CN3927V de la trasera de la uke (22-oct-2026, ciclo 18). Sin V4L2: parametros de modulo.
 *
 * El CN3927V no tiene driver mainline ni hoja de datos publica (busqueda 19 y 22-oct). Hipotesis: protocolo DW9714 (DAC de 10 bits,
 * escritura de 2 bytes: [PD|FLAG|D9..D4] [D3..D0|S3..S0]). Al cargar: enciende vio (l20) y vdd (l14), escanea el bus por LECTURA de
 * 1 byte (no escribe nada) y deja la lista de direcciones que responden en `found`. Escribir el DAC es explicito (`dac=`), y solo a
 * la direccion `tgt` (por defecto la del DT, 0x0c), nunca al sensor (0x10) ni al rango de EEPROM (0x50-0x57).
 * Al descargar baja el DAC a 0 en pasos (aparcar la lente sin golpe) y apaga los rieles.
 */
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

struct uke_vcm {
	struct i2c_client *client;
	struct regulator *vdd, *vio;
	struct mutex lock;
	int cur;
};
static struct uke_vcm *uke_vcm;

static char found[256];
module_param_string(found, found, sizeof(found), 0444);
MODULE_PARM_DESC(found, "direcciones (7 bits) que respondieron a una lectura de 1 byte al cargar");
static int tgt = -1;
module_param(tgt, int, 0644);
MODULE_PARM_DESC(tgt, "direccion a la que se escribe el DAC (-1 = la del DT)");
static int slew;
module_param(slew, int, 0644);
MODULE_PARM_DESC(slew, "bits S3..S0 del segundo byte (DW9714: modo de paso; 0 = directo)");
static int lastret;
module_param(lastret, int, 0444);
MODULE_PARM_DESC(lastret, "resultado de la ultima escritura del DAC (2 = ACK)");

static int uke_vcm_write(struct uke_vcm *v, int dac)
{
	struct i2c_msg m;
	u8 b[2];
	int a = tgt >= 0 ? tgt : v->client->addr;

	if (a == 0x10 || (a >= 0x50 && a <= 0x57) || a < 0x08 || a > 0x77)
		return -EPERM;
	dac = clamp(dac, 0, 1023);
	b[0] = (dac >> 4) & 0x3f;
	b[1] = ((dac & 0xf) << 4) | (slew & 0xf);
	m.addr = a;
	m.flags = 0;
	m.len = 2;
	m.buf = b;
	lastret = i2c_transfer(v->client->adapter, &m, 1);
	if (lastret == 1)
		v->cur = dac;
	dev_info(&v->client->dev, "uke-vcm: dac=%d -> 0x%02x [%02x %02x] ret=%d\n", dac, a, b[0], b[1], lastret);
	return lastret == 1 ? 0 : (lastret < 0 ? lastret : -EIO);
}

static int uke_dac;
static int dac_set(const char *val, const struct kernel_param *kp)
{
	int d, ret = kstrtoint(val, 0, &d);

	if (ret)
		return ret;
	if (!uke_vcm)
		return -ENODEV;
	mutex_lock(&uke_vcm->lock);
	ret = uke_vcm_write(uke_vcm, d);
	if (!ret)
		uke_dac = d;
	mutex_unlock(&uke_vcm->lock);
	return ret;
}
static const struct kernel_param_ops dac_ops = { .set = dac_set, .get = param_get_int };
module_param_cb(dac, &dac_ops, &uke_dac, 0644);
MODULE_PARM_DESC(dac, "posicion de la lente 0..1023 (escribir = mover; 0 = infinito/reposo en DW9714)");

static void uke_vcm_scan(struct uke_vcm *v)
{
	int a, n = 0;
	u8 b;
	struct i2c_msg m = { .flags = I2C_M_RD, .len = 1, .buf = &b };

	found[0] = 0;
	for (a = 0x08; a <= 0x77; a++) {
		m.addr = a;
		if (i2c_transfer(v->client->adapter, &m, 1) == 1)
			n += scnprintf(found + n, sizeof(found) - n, "0x%02x=%02x ", a, b);
	}
	dev_info(&v->client->dev, "uke-vcm: escaneo por lectura: %s\n", n ? found : "(nada)");
}

static int uke_vcm_probe(struct i2c_client *client)
{
	struct uke_vcm *v;
	int ret;

	v = devm_kzalloc(&client->dev, sizeof(*v), GFP_KERNEL);
	if (!v)
		return -ENOMEM;
	v->client = client;
	mutex_init(&v->lock);
	v->vdd = devm_regulator_get(&client->dev, "vdd");
	if (IS_ERR(v->vdd))
		return dev_err_probe(&client->dev, PTR_ERR(v->vdd), "vdd (l14)\n");
	v->vio = devm_regulator_get(&client->dev, "vio");
	if (IS_ERR(v->vio))
		return dev_err_probe(&client->dev, PTR_ERR(v->vio), "vio (l20)\n");
	if (regulator_set_voltage(v->vio, 1800000, 1800000))
		dev_warn(&client->dev, "uke-vcm: vio 1,8 V no fijado\n");
	ret = regulator_enable(v->vio);
	if (ret)
		return ret;
	ret = regulator_enable(v->vdd);
	if (ret) {
		regulator_disable(v->vio);
		return ret;
	}
	usleep_range(12000, 15000);
	dev_info(&client->dev, "uke-vcm: vdd=%d uV vio=%d uV, addr DT 0x%02x\n", regulator_get_voltage(v->vdd),
		 regulator_get_voltage(v->vio), client->addr);
	uke_vcm_scan(v);
	i2c_set_clientdata(client, v);
	uke_vcm = v;
	return 0;
}

static void uke_vcm_remove(struct i2c_client *client)
{
	struct uke_vcm *v = i2c_get_clientdata(client);

	mutex_lock(&v->lock);
	while (v->cur > 0) {	/* aparcar la lente en pasos de 64 */
		if (uke_vcm_write(v, max(v->cur - 64, 0)))
			break;
		msleep(5);
	}
	uke_vcm = NULL;
	mutex_unlock(&v->lock);
	regulator_disable(v->vdd);
	regulator_disable(v->vio);
}

static const struct of_device_id uke_vcm_of[] = {
	{ .compatible = "uke,cn3927v-vcm" },
	{ }
};
MODULE_DEVICE_TABLE(of, uke_vcm_of);

static struct i2c_driver uke_vcm_driver = {
	.driver = { .name = "uke-vcm", .of_match_table = uke_vcm_of },
	.probe = uke_vcm_probe,
	.remove = uke_vcm_remove,
};
module_i2c_driver(uke_vcm_driver);
MODULE_DESCRIPTION("uke: VCM CN3927V de la trasera (protocolo DW9714 por hipotesis), parametros dac/tgt/slew");
MODULE_LICENSE("GPL");
