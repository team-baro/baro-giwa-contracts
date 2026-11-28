#!/usr/bin/env bash
set -euo pipefail

forge coverage --skip script --report lcov >/dev/null

awk -F: '
  /^SF:/ { include_source = ($0 ~ /^SF:(\.\/)?src\//) }
  include_source && /^LF:/ { lines_found += $2 }
  include_source && /^LH:/ { lines_hit += $2 }
  include_source && /^BRF:/ { branches_found += $2 }
  include_source && /^BRH:/ { branches_hit += $2 }
  END {
    line_rate = lines_found == 0 ? 0 : (100 * lines_hit / lines_found)
    branch_rate = branches_found == 0 ? 0 : (100 * branches_hit / branches_found)
    printf "Production line coverage: %.2f%% (%d/%d)\n", line_rate, lines_hit, lines_found
    printf "Production branch coverage: %.2f%% (%d/%d)\n", branch_rate, branches_hit, branches_found
    if (line_rate < 80 || branch_rate < 40) exit 1
  }
' lcov.info

