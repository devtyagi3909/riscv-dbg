# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
TB := $(ROOT)/tb

NUM_JOBS ?= 2
OPENOCD_PREFIX ?= $(ROOT)/.cache/openocd

.PHONY: all compliance dm-mem firmware full-model jtag-dmi openocd

all: dm-mem jtag-dmi compliance

full-model:
	$(MAKE) -C $(TB) -j1 download_deps
	$(MAKE) -C $(TB) verilate

firmware:
	$(MAKE) -C $(TB) prog/test.hex

openocd:
	NUM_JOBS=$(NUM_JOBS) OPENOCD_PREFIX=$(OPENOCD_PREFIX) \
		$(ROOT)/ci/get-openocd.sh

jtag-dmi:
	JTAG_BUILD_DIR=$(ROOT)/build/jtag-verilator \
		$(ROOT)/ci/run-jtag-verilator.sh

dm-mem:
	DM_MEM_BUILD_DIR=$(ROOT)/build/dm-mem-verilator \
		$(ROOT)/ci/run-dm-mem-verilator.sh

compliance: full-model firmware openocd
	cd $(TB) && \
		OPENOCD=$(OPENOCD_PREFIX)/bin/openocd \
		OPENOCD_SCRIPT=dm_compliance_test.cfg \
		./veri-run-openocd.py
