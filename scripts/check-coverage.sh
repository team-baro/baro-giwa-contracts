#!/usr/bin/env bash
set -euo pipefail

forge coverage --skip script --report lcov >/dev/null

awk -F: '
  /^LF:/ { lines_found += $2 }
  /^LH:/ { lines_hit += $2 }
  /^BRF:/ { branches_found += $2 }
  /^BRH:/ { branches_hit += $2 }
  END {
    line_rate = lines_found == 0 ? 0 : (100 * lines_hit / lines_found)
    branch_rate = branches_found == 0 ? 0 : (100 * branches_hit / branches_found)
    printf "Line coverage: %.2f%% (%d/%d)\n", line_rate, lines_hit, lines_found
    printf "Branch coverage: %.2f%% (%d/%d)\n", branch_rate, branches_hit, branches_found
    if (line_rate < 80 || branch_rate < 40) exit 1
  }
' lcov.info

