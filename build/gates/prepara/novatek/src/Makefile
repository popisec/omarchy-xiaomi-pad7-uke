# Módulo externo: copia VERBATIM del driver in-tree
# /var/tmp/uke-k1/drivers/input/touchscreen/novatek-nt36xxx-spi.c
#
# OJO: el K6 que corre la tablet lleva este driver BUILT-IN
# (CONFIG_TOUCHSCREEN_NOVATEK_NT36XXX_SPI=y), así que este .ko NO se puede
# insmod sobre K6: el bus SPI ya tiene registrado un driver con el mismo
# nombre ("novatek-nt36xxx-spi") y driver_register devuelve -EBUSY.
# Para un .ko cargable sobre K6 usar ../ext/ (nombre distinto).
obj-m := novatek-nt36xxx-spi.o
