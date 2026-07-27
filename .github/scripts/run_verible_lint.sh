#!/usr/bin/env bash
# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

set -euo pipefail

while IFS= read -r -d '' file; do
  if [[ -f "${file}" ]]; then
    printf '%s\0' "${file}"
  fi
done < <(git ls-files -z '*.sv' '*.svh' '*.v') \
  | xargs -0 verible-verilog-lint \
      --lint_fatal \
      --parse_fatal \
      --waiver_files .github/verible.waiver
