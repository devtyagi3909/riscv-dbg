#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="${MULTIHART_BUILD_DIR:-${ROOT}/build/multihart-verilator}"

"${ROOT}/ci/run-single-top-verilator.sh" \
  "${BUILD_DIR}/three-hart" tb_dm_top_multihart_resume \
  -GNrHarts=3 -GSelectableHarts="3'b101"

"${ROOT}/ci/run-single-top-verilator.sh" \
  "${BUILD_DIR}/singleton" tb_dm_top_multihart_resume \
  -GNrHarts=1 -GSelectableHarts="1'b1"

"${ROOT}/ci/run-single-top-verilator.sh" \
  "${BUILD_DIR}/four-hart" tb_dm_top_multihart_resume \
  -GNrHarts=4 -GSelectableHarts="4'b1111"
