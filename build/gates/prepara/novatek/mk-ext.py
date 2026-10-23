#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mk-ext.py — genera la variante EXT del driver in-tree del NT36xxx.

POR QUE EXISTE. El K6 que corre la tablet lleva el driver BUILT-IN
(CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI=y) y el dtbo s258 tiene DOS nodos
"novatek,NVT-ts-spi" con reg=<0> en spi@a90000:
  - el nodo VENDOR (fragment@35)   -> gana el chipselect 0 -> es spi0.0
  - el nodo constructor (frag@1200) -> "chipselect 0 already in use"
El nodo vendor NO tiene `interrupts`, solo `novatek,irq-gpio = <&tlmm 54
0x2001>`; el driver in-tree exige spi->irq y muere con -EINVAL ("no IRQ
specified", medido en K2/K4). Resultado: el tactil NO probea hoy.

Este generador produce una copia del driver con 4 cambios quirurgicos:
  1. driver.name distinto ("novatek-nt36xxx-spi-ext") para poder registrarlo
     sobre un kernel que ya tiene el built-in (si no, -EBUSY).
  2. Fallback de IRQ: si spi->irq == 0, `devm_gpiod_get(dev, "novatek,irq",
     GPIOD_IN)` -> gpiolib prueba "novatek,irq-gpios" y "novatek,irq-gpio"
     (gpiolib-of.c:705, for_each_gpio_property_name) -> gpiod_to_irq().
     GPIOD_IN ademas muxea el pin a GPIO en el TLMM (msm_gpio_direction_input).
  3. max_x/max_y como module params (default 2136x3200 = marco nativo medido
     en Android: abs_x_max=2136/abs_y_max=3200, rx40 x tx60) porque el nodo
     vendor NO trae touchscreen-size-x/y y el default in-tree (1600x2136)
     tiraria todos los toques fuera de rango.
  4. Log de la procedencia del IRQ y de los ejes.

NO implementa el lapiz (el nodo vendor trae novatek,pen-support y el driver
avisa). Ver P2-lapiz.md seccion (d).
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "src" / "novatek-nt36xxx-spi.c"
DST = HERE / "ext" / "novatek-nt36xxx-spi-ext.c"

text = SRC.read_text()

def sub1(old, new, why):
    global text
    n = text.count(old)
    if n != 1:
        sys.exit("mk-ext: %r aparece %d veces (esperado 1) — base cambiada: %s" % (old[:60], n, why))
    text = text.replace(old, new)

# --- 0. cabecera -----------------------------------------------------------
sub1(
    " * SPI driver for Novatek NT36xxx-family touch controllers\n",
    " * SPI driver for Novatek NT36xxx-family touch controllers — VARIANTE EXT\n"
    " * (generada por mk-ext.py; ver P2-lapiz.md). NO es el driver in-tree:\n"
    " *  - driver.name = novatek-nt36xxx-spi-ext (convive con el built-in)\n"
    " *  - acepta el nodo vendor del dtbo s258 (novatek,irq-gpio -> gpiod_to_irq)\n"
    " *  - max_x/max_y por module param (default 2136x3200)\n",
    "cabecera")

# --- 1. tamanos por defecto (medidos en Android) ---------------------------
sub1(
    "#define NVT_SPI_DEF_X_SIZE\t\t1600\n#define NVT_SPI_DEF_Y_SIZE\t\t2136\n",
    "#define NVT_SPI_DEF_X_SIZE\t\t2136\t/* Android: abs_x_max=2136 (rx=40) */\n"
    "#define NVT_SPI_DEF_Y_SIZE\t\t3200\t/* Android: abs_y_max=3200 (tx=60) */\n",
    "tamanos")

# --- 2. module params ------------------------------------------------------
sub1(
    "MODULE_PARM_DESC(point_layout,\n"
    "\t\t \"Finger record layout guess: 0=A(head+6B), 1=B(7B classic), 2=C(5B LE)\");\n",
    "MODULE_PARM_DESC(point_layout,\n"
    "\t\t \"Finger record layout guess: 0=A(head+6B), 1=B(7B classic), 2=C(5B LE)\");\n"
    "\n"
    "/*\n"
    " * Ejes: el nodo VENDOR del dtbo s258 no trae touchscreen-size-x/y, asi que\n"
    " * touchscreen_parse_properties() deja el absinfo que pongamos aqui. Valores\n"
    " * nativos medidos en Android (nvt_ts_probe: abs_x_max=2136, abs_y_max=3200;\n"
    " * rx_num=40 x tx_num=60). Cambiables en caliente para el triaje:\n"
    " *   /sys/module/novatek_nt36xxx_spi_ext/parameters/max_x\n"
    " */\n"
    "static unsigned int max_x = NVT_SPI_DEF_X_SIZE;\n"
    "static unsigned int max_y = NVT_SPI_DEF_Y_SIZE;\n"
    "module_param_named(max_x, max_x, uint, 0644);\n"
    "module_param_named(max_y, max_y, uint, 0644);\n"
    "MODULE_PARM_DESC(max_x, \"ABS_MT_POSITION_X max+1 si el DT no lo trae (default 2136)\");\n"
    "MODULE_PARM_DESC(max_y, \"ABS_MT_POSITION_Y max+1 si el DT no lo trae (default 3200)\");\n",
    "module params")

# --- 2b. frame_dump -------------------------------------------------------
sub1(
    "MODULE_PARM_DESC(max_y, \"ABS_MT_POSITION_Y max+1 si el DT no lo trae (default 3200)\");\n",
    "MODULE_PARM_DESC(max_y, \"ABS_MT_POSITION_Y max+1 si el DT no lo trae (default 3200)\");\n"
    "\n"
    "/*\n"
    " * Volcado de frames crudos (256 B) para el triaje EN TABLET:\n"
    " *   modprobe novatek-nt36xxx-spi-ext frame_dump=40\n"
    " * o  echo 40 > /sys/module/novatek_nt36xxx_spi_ext/parameters/frame_dump\n"
    " * Sirve para (1) confirmar el layout de dedo (point_layout) y (2) empezar\n"
    " * el RE de los records del LAPIZ (el .ko vendor no los decodifica: se los\n"
    " * pasa crudos a xiaomi_touch.ko).\n"
    " */\n"
    "static unsigned int frame_dump;\n"
    "static unsigned int frame_dump_done;\n"
    "module_param_named(frame_dump, frame_dump, uint, 0644);\n"
    "MODULE_PARM_DESC(frame_dump, \"Vuelca en dmesg los primeros N frames no-idle (0=off)\");\n",
    "frame_dump param")

# --- 3. struct: guardar el irq --------------------------------------------
sub1(
    "struct nvt_spi_data {\n\tstruct spi_device *spi;\n",
    "struct nvt_spi_data {\n\tstruct spi_device *spi;\n\tint irq;\t\t\t/* spi->irq o el de novatek,irq-gpio */\n",
    "struct irq")

# --- 3b. volcado del frame en el IRQ --------------------------------------
sub1(
    """	if (!nvt_spi_frame_cksum_ok(data, ev))
		return IRQ_HANDLED;
""",
    """	if (frame_dump && frame_dump_done < frame_dump) {
		frame_dump_done++;
		dev_info(dev, \"frame no-idle %u/%u (head %16ph):\", frame_dump_done,
			 frame_dump, ev);
		print_hex_dump(KERN_INFO, \"nvt: \", DUMP_PREFIX_OFFSET, 16, 1,
			       ev, NVT_SPI_EVENT_DATA_LEN, false);
	}

	if (!nvt_spi_frame_cksum_ok(data, ev))
		return IRQ_HANDLED;
""",
    "frame dump")

# --- 4. start/stop usan data->irq ------------------------------------------
sub1("\tenable_irq(data->spi->irq);\n", "\tenable_irq(data->irq);\n", "start")
sub1("\tdisable_irq(data->spi->irq);\n", "\tdisable_irq(data->irq);\n", "stop")

# --- 5. probe: fallback de IRQ --------------------------------------------
sub1(
    """	if (!spi->irq) {
		dev_err(dev, "no IRQ specified\\n");
		return -EINVAL;
	}
""",
    """	/*
	 * IRQ: el nodo CONSTRUCTOR (fragment@1200) trae `interrupts` y esto ya
	 * valdria; el nodo VENDOR del dtbo s258 (el que gana el CS 0) trae
	 * `novatek,irq-gpio = <&tlmm 54 0x2001>` y spi->irq == 0. El vendor
	 * .ko lo resuelve con gpio_to_irq (dmesg Android: novatek,irq-gpio=387
	 * -> tlmm 54, int_trigger_type=1 = RISING). Aqui igual: gpiolib prueba
	 * "novatek,irq-gpios" y luego "novatek,irq-gpio" (gpiolib-of.c:705).
	 * GPIOD_IN ademas muxea el pin a funcion GPIO en el TLMM.
	 */
	irq = spi->irq;
	irq_from_gpio = false;
	if (!irq) {
		struct gpio_desc *irq_gpio =
			devm_gpiod_get(dev, "novatek,irq", GPIOD_IN);

		if (IS_ERR(irq_gpio)) {
			dev_err(dev, "no IRQ: ni `interrupts` ni novatek,irq-gpio (%ld)\\n",
				PTR_ERR(irq_gpio));
			return -EINVAL;
		}
		irq = gpiod_to_irq(irq_gpio);
		if (irq < 0) {
			dev_err(dev, "gpiod_to_irq(novatek,irq-gpio) = %d\\n", irq);
			return irq;
		}
		irq_from_gpio = true;
		dev_info(dev, "IRQ %d desde novatek,irq-gpio (nodo vendor s258)\\n", irq);
	}
""",
    "fallback irq")

sub1(
    "\tstruct input_dev *input;\n\tint error;\n",
    "\tstruct input_dev *input;\n\tint error, irq;\n\tbool irq_from_gpio;\n",
    "declaraciones probe")

sub1(
    "\tdata->spi = spi;\n",
    "\tdata->spi = spi;\n\tdata->irq = irq;\n",
    "guardar irq")

# --- 6. request_irq con data->irq y trigger correcto ----------------------
sub1(
    """	error = devm_request_threaded_irq(dev, spi->irq, NULL, nvt_spi_irq,
					  IRQF_ONESHOT | IRQF_NO_AUTOEN |
						irq_get_trigger_type(spi->irq),
					  input->name, data);
""",
    """	error = devm_request_threaded_irq(dev, data->irq, NULL, nvt_spi_irq,
					  IRQF_ONESHOT | IRQF_NO_AUTOEN |
						(irq_from_gpio ? IRQ_TYPE_EDGE_RISING :
								 irq_get_trigger_type(spi->irq)),
					  input->name, data);
""",
    "request irq")

# --- 7. absinfo con los params --------------------------------------------
sub1(
    """	input_set_abs_params(input, ABS_MT_POSITION_X,
			     0, NVT_SPI_DEF_X_SIZE - 1, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y,
			     0, NVT_SPI_DEF_Y_SIZE - 1, 0, 0);
""",
    """	input_set_abs_params(input, ABS_MT_POSITION_X,
			     0, max_x - 1, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y,
			     0, max_y - 1, 0, 0);
""",
    "absinfo")

# --- 8. nombre de driver distinto + log final -----------------------------
sub1(
    '\t\t.name\t\t= "novatek-nt36xxx-spi",\n',
    '\t\t.name\t\t= "novatek-nt36xxx-spi-ext",\n',
    "driver.name")

sub1(
    'MODULE_DESCRIPTION("Novatek NT36xxx SPI touchscreen driver (protocol verified vs vendor module)");\n',
    'MODULE_DESCRIPTION("Novatek NT36xxx SPI touchscreen driver, variante EXT cargable sobre el built-in (mk-ext.py)");\n',
    "description")

# el log de probe: anadir el irq efectivo
sub1(
    '\tdev_info(dev,\n\t\t "NT36xxx SPI probe ok: irq %d (trigger 0x%lx), %ux%u, transporte verificado vs nt36532_touch.ko; layout de dedo SIN verificar (point_layout=%u)\\n",\n\t\t spi->irq, (unsigned long)irq_get_trigger_type(spi->irq),\n',
    '\tdev_info(dev,\n\t\t "NT36xxx SPI probe ok (EXT): irq %d (gpio=%d, trigger 0x%lx), %ux%u, transporte verificado vs nt36532_touch.ko; layout de dedo SIN verificar (point_layout=%u)\\n",\n\t\t data->irq, irq_from_gpio, (unsigned long)irq_get_trigger_type(data->irq),\n',
    "log probe")

DST.parent.mkdir(parents=True, exist_ok=True)
DST.write_text(text)
print("mk-ext.py OK ->", DST)
