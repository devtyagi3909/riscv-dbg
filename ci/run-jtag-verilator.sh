#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${JTAG_BUILD_DIR:-${ROOT}/build/jtag-verilator}"
readonly FILE_LIST="${BUILD_DIR}/sources.flist"

mkdir -p "${BUILD_DIR}"
cd "${ROOT}"

bender checkout
bender script flist-plus \
  --relative-path \
  -t riscv-dbg:simulation \
  -t riscv-dbg:test \
  -t tech_cells_generic:tech_cells_generic_exclude_deprecated \
  > "${FILE_LIST}"

verilator \
  --binary \
  --timing \
  -Wno-fatal \
  -DCOMMON_CELLS_ASSERTS_OFF \
  --top-module tb_jtag_dmi \
  --Mdir "${BUILD_DIR}/obj_dir" \
  -f "${FILE_LIST}"

"${BUILD_DIR}/obj_dir/Vtb_jtag_dmi"
