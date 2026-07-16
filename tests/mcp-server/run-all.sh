#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/report.sh"

RESULTS_LOG="/tmp/mcp-server-results.log"
export RESULTS_LOG
> "$RESULTS_LOG"

START_TIME=$(date +%s)
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  K3s MCP Server — Enterprise Test Suite (10 Rounds)     ║"
echo "║  $(date -u +"%Y-%m-%d %H:%M:%S UTC")                          ║"
echo "╚══════════════════════════════════════════════════════════╝"

TOTAL_PASS=0; TOTAL_FAIL=0; TOTAL_SKIP=0

run_round() {
  local script="$1"
  local name="$2"
  echo ""
  echo "▶ Starting: $name"
  PASS=0; FAIL=0; SKIP=0; TOTAL=0
  source "$SCRIPT_DIR/lib/assert.sh"
  bash "$script"
  TOTAL_PASS=$((TOTAL_PASS + PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
  TOTAL_SKIP=$((TOTAL_SKIP + SKIP))
  echo "  ── $name: $PASS pass / $FAIL fail / $SKIP skip ──"
}

run_round "$SCRIPT_DIR/round1-infra.sh"        "Round 1: Infrastructure"
run_round "$SCRIPT_DIR/round2-protocol.sh"     "Round 2: MCP Protocol"
run_round "$SCRIPT_DIR/round3-proxy.sh"        "Round 3: Proxy Auth"
run_round "$SCRIPT_DIR/round4-tools-core.sh"   "Round 4: Core Toolset"
run_round "$SCRIPT_DIR/round5-tools-extra.sh"  "Round 5: Config+Helm"
run_round "$SCRIPT_DIR/round6-security.sh"     "Round 6: Security"
run_round "$SCRIPT_DIR/round7-performance.sh"  "Round 7: Performance"
run_round "$SCRIPT_DIR/round8-resilience.sh"   "Round 8: Resilience"
run_round "$SCRIPT_DIR/round9-edge-cases.sh"   "Round 9: Edge Cases"
run_round "$SCRIPT_DIR/round10-e2e.sh"         "Round 10: E2E HTTPS"

# Playwright (optional)
echo ""
echo "▶ Starting: Playwright Browser Tests"
if command -v npx &> /dev/null; then
  cd "$SCRIPT_DIR" && npx playwright test --config playwright/playwright.config.mjs 2>&1 | tail -20
  PW_EXIT=$?
  if [[ $PW_EXIT -eq 0 ]]; then
    echo "PASS|Playwright Browser Suite" >> "$RESULTS_LOG"
    ((TOTAL_PASS++))
  else
    echo "FAIL|Playwright Browser Suite|exit=$PW_EXIT" >> "$RESULTS_LOG"
    ((TOTAL_FAIL++))
  fi
else
  echo "SKIP|Playwright|npx not found" >> "$RESULTS_LOG"
  ((TOTAL_SKIP++))
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              FINAL RESULTS                              ║"
echo "║  ✅ Pass: $TOTAL_PASS  |  ❌ Fail: $TOTAL_FAIL  |  ⏭️ Skip: $TOTAL_SKIP     ║"
echo "║  Duration: ${DURATION}s                                        ║"
echo "╚══════════════════════════════════════════════════════════╝"

# Generate HTML report
REPORT_FILE="$SCRIPT_DIR/report-$(date +%Y-%m-%d).html"
generate_html_report "$RESULTS_LOG" "$REPORT_FILE"
echo "📊 Report: $REPORT_FILE"

# Grade
TOTAL_TESTS=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))
if [[ $TOTAL_TESTS -gt 0 ]]; then
  PASS_RATE=$((TOTAL_PASS * 100 / TOTAL_TESTS))
  echo ""
  if [[ $PASS_RATE -ge 95 ]]; then
    echo "🏆 ENTERPRISE READY ($PASS_RATE%)"
  elif [[ $PASS_RATE -ge 90 ]]; then
    echo "✅ PRODUCTION READY ($PASS_RATE%)"
  elif [[ $PASS_RATE -ge 80 ]]; then
    echo "⚠️ BETA QUALITY ($PASS_RATE%)"
  else
    echo "❌ NEEDS WORK ($PASS_RATE%)"
  fi
fi

exit $TOTAL_FAIL
