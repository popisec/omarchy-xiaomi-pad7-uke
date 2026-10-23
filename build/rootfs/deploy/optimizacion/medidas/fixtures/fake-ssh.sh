#!/bin/bash
# ssh de mentira para selftest.sh: ejecuta el comando en local con PATH de stubs y SYSFS apuntando al arbol falso.
exec bash -c "$*"
