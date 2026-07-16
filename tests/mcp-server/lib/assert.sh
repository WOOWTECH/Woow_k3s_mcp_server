#!/usr/bin/env bash
PASS=0; FAIL=0; SKIP=0; TOTAL=0
RESULTS_LOG="${RESULTS_LOG:-/tmp/mcp-server-results.log}"

pass() { ((PASS++)); ((TOTAL++)); echo "  ✅ PASS: $1"; echo "PASS|$1" >> "$RESULTS_LOG"; }
fail() { ((FAIL++)); ((TOTAL++)); echo "  ❌ FAIL: $1 — $2"; echo "FAIL|$1|$2" >> "$RESULTS_LOG"; }
skip() { ((SKIP++)); ((TOTAL++)); echo "  ⏭️  SKIP: $1 — $2"; echo "SKIP|$1|$2" >> "$RESULTS_LOG"; }

section() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  $1"
  echo "╚══════════════════════════════════════════════════════════╝"
}

summary() {
  echo ""
  echo "  ── Results: $PASS pass / $FAIL fail / $SKIP skip (total $TOTAL) ──"
}

http_code() { curl -s -o /dev/null -w "%{http_code}" "$@" 2>&1; }
