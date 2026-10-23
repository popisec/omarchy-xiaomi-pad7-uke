# Makefile — atajos a los scripts que ya existen
#
# Este repo tiene 125 scripts en build/gates/ y un deploy.sh por tema. Este
# Makefile NO sustituye a nada: solo da nombres corto a lo que ya hay, para no
# tener que recordar el nombre del fichero.
#
#   make help
#
# Regla del proyecto (REGLAS.md): nada se flashea sin pasar los gates, un
# cambio por ciclo, y el backup del par boot+dtbo con su sha256 registrado
# ANTES de escribir. Los objetivos de este Makefile que tocan la tablet
# delegan en scripts que ya llevan esos gates dentro.

SHELL := /bin/bash
R     := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
# Los despliegues: algunos cuelgan de un subdirectorio (audio/, lapiz/...), asi
# que se buscan con find, no con un glob de primer nivel.
THEMES := $(sort $(notdir $(patsubst %/,%,$(dir $(shell find build/rootfs/deploy -name deploy.sh)))))
# Los scripts de build del linaje historico «palawan» (archivados).
KERNELS := $(patsubst docs/historia/gates-palawan/build-%.sh,%,$(wildcard docs/historia/gates-palawan/build-k*.sh))

.DEFAULT_GOAL := help
.PHONY: help check links dup shell lint manifests privacidad assets themes deploy-check \
        kernel build-ks ci clean-pyc

## ---------------------------------------------------------------- ayuda ----

help: ## Esta ayuda
	@echo "Omarchy en la Xiaomi Pad 7 «uke» — atajos a los scripts del repo"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-18s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Temas de despliegue disponibles: $(words $(THEMES))"
	@echo "Kernels con script de build: $(words $(KERNELS))"

## ------------------------------------------------------------- calidad ----

check: links dup shell manifests privacidad ## Higiene del repo: referencias, duplicados, sintaxis, manifiestos y privacidad (no tocan la tablet)
	@echo "CHECK OK"

links: ## Las referencias a ficheros del repo existen
	python3 tools/check-links.py

dup: ## No hay ficheros duplicados
	python3 tools/dupcheck.py

shell: ## Sintaxis bash de todos los scripts
	@err=0; for f in $$(git ls-files '*.sh'); do bash -n "$$f" || { echo "SYNTAX: $$f"; err=1; }; done; \
		exit $$err

manifests: ## Los manifiestos de los despliegues cuadran en sus ficheros de fuente
	python3 tools/check-manifests.py

privacidad: ## Sin datos del entorno del autor ni binarios disfrazados
	python3 tools/check-privacidad.py

assets: ## Los assets de los releases no llevan material prohibido (necesita GITHUB_TOKEN)
	@bash tools/check-assets.sh

lint: shell ## shellcheck (informativo)
	@command -v shellcheck >/dev/null || { echo "shellcheck no instalado"; exit 0; }
	@find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -r shellcheck -S warning || true

ci: links dup shell manifests privacidad ## La parte local de la CI (la CI ademas corre gitleaks, los assets y los gates), en local

## ------------------------------------------------------------- despliegue --

themes: ## Lista los temas de despliegue
	@for t in $(THEMES); do printf "  %-20s %s\n" "$$t" "$$(awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; exit}' build/rootfs/deploy/$$t/deploy.sh | cut -c1-90)"; done

deploy-check: ## check de TODOS los despliegues (no escribe en la tablet)
	@bash tools/deploy-check.sh

# deploy-<tema>  (p.ej. make deploy-tactil)
deploy-%: ## deploy.sh check del tema <tema> (p.ej. tactil, audio, bt)
	@bash build/rootfs/deploy/$*/deploy.sh check

## ---------------------------------------------------------------- kernel ---

build-ks: ## Lista los scripts de build del linaje historico (archivados)
	@for k in $(KERNELS); do echo "$$k"; done

kernel-%: ## Compila el kernel <k> del linaje HISTORICO palawan (p.ej. make kernel-k49)
	@bash docs/historia/gates-palawan/build-$*.sh

## ----------------------------------------------------------------- varios --

clean-pyc: ## Borra los __pycache__ locales
	find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
