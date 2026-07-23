#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${DM_MEM_BUILD_DIR:-${ROOT}/build/dm-mem-verilator}"
readonly FILE_LIST="${BUILD_DIR}/sources.flist"

# Fields: name BusWidth MaxRegisterAccessWidth HartSel AarSize ExpectSupported
readonly TEST_CASES=(
  "bus32_max32_aar32 32 32 0 2 1"
  "bus32_max32_aar64 32 32 1 3 0"
  "bus32_max64_aar32 32 64 0 2 1"
  "bus32_max64_aar64 32 64 1 3 1"
  "bus64_max32_aar32 64 32 1 2 1"
  "bus64_max32_aar64 64 32 0 3 0"
  "bus64_max64_aar64 64 64 1 3 1"
)

mkdir -p "${BUILD_DIR}"
cd "${ROOT}"

bender checkout
bender script flist-plus \
  --relative-path \
  -t riscv-dbg:dm_mem_test \
  -t tech_cells_generic:tech_cells_generic_exclude_deprecated \
  > "${FILE_LIST}"

for test_case in "${TEST_CASES[@]}"; do
  read -r name bus_width max_access_width hart_sel aar_size expect_supported <<< "${test_case}"
  case_build_dir="${BUILD_DIR}/${name}"
  mkdir -p "${case_build_dir}"

  verilator \
    --binary \
    --timing \
    -Wno-fatal \
    -DCOMMON_CELLS_ASSERTS_OFF \
    --top-module tb_dm_mem \
    --Mdir "${case_build_dir}/obj_dir" \
    -GBusWidth="${bus_width}" \
    -GMaxRegisterAccessWidth="${max_access_width}" \
    -GHartSel="${hart_sel}" \
    -GAarSize="${aar_size}" \
    -GExpectSupported="${expect_supported}" \
    -f "${FILE_LIST}"

  "${case_build_dir}/obj_dir/Vtb_dm_mem"
done
