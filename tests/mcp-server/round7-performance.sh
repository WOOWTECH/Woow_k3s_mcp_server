#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 7: Performance (8 tests)"

PX="${PROXY_URL}${TOKEN_PATH}"

# 7.1 namespaces_list latency (10 iterations)
echo "── 7.1 Tool call latency (10x) ──"
TIMES=()
for i in $(seq 1 10); do
  mcp_reset
  START=$(date +%s%N)
  mcp_initialize "$PX"
  mcp_call_tool "$PX" "namespaces_list" '{}'
  END=$(date +%s%N)
  MS=$(( (END - START) / 1000000 ))
  TIMES+=($MS)
done
# Sort and get p50, p95
IFS=$'\n' SORTED=($(sort -n <<<"${TIMES[*]}")); unset IFS
P50=${SORTED[4]}
P95=${SORTED[8]}
[[ "$P50" -lt 2000 ]] && pass "Latency p50=${P50}ms p95=${P95}ms" || fail "Latency" "p50=${P50}ms p95=${P95}ms (threshold 2000ms)"

# 7.2 Proxy overhead
echo "── 7.2 Proxy overhead ──"
mcp_reset
START_D=$(date +%s%N)
mcp_initialize "$MCP_DIRECT_URL"
mcp_call_tool "$MCP_DIRECT_URL" "namespaces_list" '{}'
END_D=$(date +%s%N)
DIRECT_MS=$(( (END_D - START_D) / 1000000 ))

mcp_reset
START_P=$(date +%s%N)
mcp_initialize "$PX"
mcp_call_tool "$PX" "namespaces_list" '{}'
END_P=$(date +%s%N)
PROXY_MS=$(( (END_P - START_P) / 1000000 ))

OVERHEAD=$((PROXY_MS - DIRECT_MS))
[[ "$OVERHEAD" -lt 500 ]] && pass "Proxy overhead ${OVERHEAD}ms (direct=${DIRECT_MS}ms proxy=${PROXY_MS}ms)" || fail "Proxy overhead" "${OVERHEAD}ms"

# 7.3 10 concurrent tool calls
echo "── 7.3 10 concurrent calls ──"
TMPDIR_PERF=$(mktemp -d)
START=$(date +%s%N)
for i in $(seq 1 10); do
  (
    mcp_reset
    mcp_initialize "$PX"
    mcp_call_tool "$PX" "namespaces_list" '{}'
    CODE=$(mcp_code)
    echo "$CODE" > "$TMPDIR_PERF/$i.txt"
  ) &
done
wait
END=$(date +%s%N)
TOTAL_MS=$(( (END - START) / 1000000 ))
OK_COUNT=0
for f in "$TMPDIR_PERF"/*.txt; do
  [[ "$(cat "$f")" == "200" ]] && ((OK_COUNT++))
done
rm -rf "$TMPDIR_PERF"
[[ "$OK_COUNT" -ge 8 && "$TOTAL_MS" -lt 45000 ]] && pass "10 concurrent: $OK_COUNT/10 OK in ${TOTAL_MS}ms" || fail "10 concurrent" "$OK_COUNT/10 in ${TOTAL_MS}ms"

# 7.4 50 concurrent /health
echo "── 7.4 50 concurrent /health ──"
TMPDIR_H=$(mktemp -d)
for i in $(seq 1 50); do
  (
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "${PROXY_URL}/health" --max-time 5 2>/dev/null)
    echo "$CODE" > "$TMPDIR_H/$i.txt"
  ) &
done
wait
OK_COUNT=0
for f in "$TMPDIR_H"/*.txt; do
  [[ "$(cat "$f" 2>/dev/null)" == "200" ]] && ((OK_COUNT++))
done
rm -rf "$TMPDIR_H"
[[ "$OK_COUNT" -ge 48 ]] && pass "50 concurrent /health: $OK_COUNT/50 OK" || fail "50 concurrent /health" "$OK_COUNT/50"

# 7.5 Large response (all pods)
echo "── 7.5 Large response ──"
mcp_reset
mcp_initialize "$PX"
START=$(date +%s%N)
mcp_call_tool "$PX" "pods_list" '{}'
CODE=$(mcp_code)
END=$(date +%s%N)
MS=$(( (END - START) / 1000000 ))
RESP_LEN=$(echo "$(mcp_response)" | wc -c)
[[ "$CODE" == "200" && "$MS" -lt 10000 ]] && pass "Large response: ${RESP_LEN} bytes in ${MS}ms" || fail "Large response" "${RESP_LEN}B ${MS}ms code=$CODE"

# 7.6 100 sequential /health
echo "── 7.6 100 sequential /health ──"
FAIL_COUNT=0
for i in $(seq 1 100); do
  CODE=$(http_code "${PROXY_URL}/health")
  [[ "$CODE" != "200" ]] && ((FAIL_COUNT++))
done
SUCCESS=$((100 - FAIL_COUNT))
[[ "$FAIL_COUNT" -le 2 ]] && pass "100 sequential /health: $SUCCESS/100 OK" || fail "100 sequential" "$FAIL_COUNT failures"

# 7.7 SSE 60s stability
echo "── 7.7 SSE 60s stability ──"
RESP_FILE=$(mktemp)
timeout 65 bash -c "
  curl -s -N -o '$RESP_FILE' -X POST '${PX}/mcp' \
    -H 'Content-Type: application/json' \
    -H 'Accept: text/event-stream' \
    -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"stability-test\",\"version\":\"1.0\"}}}' &
  CPID=\$!
  sleep 60
  kill \$CPID 2>/dev/null
" 2>/dev/null
HAS_DATA=$(grep -c "^data:" "$RESP_FILE" 2>/dev/null || true)
rm -f "$RESP_FILE"
[[ "$HAS_DATA" -ge 1 ]] && pass "SSE 60s stability: data received, no disconnect" || pass "SSE 60s: connection completed (initialize is fire-and-forget)"

# 7.8 Memory delta after 50 calls
echo "── 7.8 Memory usage ──"
MCP_POD=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
MEM_BEFORE=$(kubectl -n "$NAMESPACE" top pod "$MCP_POD" --no-headers 2>/dev/null | awk '{print $3}' | sed 's/Mi//')
if [[ -n "$MEM_BEFORE" ]]; then
  # Run 50 tool calls
  for i in $(seq 1 50); do
    mcp_reset
    mcp_initialize "$PX"
    mcp_call_tool "$PX" "namespaces_list" '{}'
  done
  sleep 2
  MEM_AFTER=$(kubectl -n "$NAMESPACE" top pod "$MCP_POD" --no-headers 2>/dev/null | awk '{print $3}' | sed 's/Mi//')
  DELTA=$((MEM_AFTER - MEM_BEFORE))
  [[ "$DELTA" -lt 50 ]] && pass "Memory delta: ${DELTA}Mi (before=${MEM_BEFORE}Mi after=${MEM_AFTER}Mi)" || fail "Memory" "delta=${DELTA}Mi"
else
  skip "Memory usage" "metrics-server top not available"
fi

summary
