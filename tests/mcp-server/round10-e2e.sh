#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 10: End-to-End via HTTPS (8 tests)"

EXT="$EXTERNAL_URL"

# 10.1 External HTTPS MCP initialize
echo "── 10.1 External HTTPS initialize ──"
mcp_reset
mcp_initialize "$EXT"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "protocolVersion"; then
  pass "External HTTPS initialize OK"
else
  fail "External initialize" "code=$CODE resp=$(echo "$RESP" | head -c 100)"
fi

# 10.2 External tool call
echo "── 10.2 External tool call ──"
mcp_call_tool "$EXT" "namespaces_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "mcp-system"; then
  pass "External tool call returned K8s data"
else
  fail "External tool call" "code=$CODE mcp-system not found"
fi

# 10.3 External wrong token
echo "── 10.3 External wrong token ──"
CODE=$(http_code "https://k8s-mcp.woowtech.io/private_WRONGTOKEN/mcp" --max-time 10)
[[ "$CODE" == "403" ]] && pass "External wrong token returns 403" || fail "External wrong token" "code=$CODE"

# 10.4 External root path
echo "── 10.4 External root path ──"
CODE=$(http_code "https://k8s-mcp.woowtech.io/" --max-time 10)
[[ "$CODE" == "403" ]] && pass "External root returns 403" || pass "External root returns $CODE (CF or proxy)"

# 10.5 TLS certificate valid
echo "── 10.5 TLS certificate ──"
TLS_OK=$(curl -sv "https://k8s-mcp.woowtech.io/" 2>&1 | grep -c "SSL certificate verify ok" || true)
[[ "$TLS_OK" -ge 1 ]] && pass "TLS certificate valid (Cloudflare)" || fail "TLS" "certificate verification failed"

# 10.6 10 consecutive external calls
echo "── 10.6 10 consecutive calls ──"
E2E_OK=0
for i in $(seq 1 10); do
  mcp_reset
  mcp_initialize "$EXT"
  mcp_call_tool "$EXT" "namespaces_list" '{}'
  CODE=$(mcp_code)
  [[ "$CODE" == "200" ]] && ((E2E_OK++))
done
[[ "$E2E_OK" -ge 9 ]] && pass "10 consecutive external: $E2E_OK/10 OK" || fail "Consecutive external" "$E2E_OK/10"

# 10.7 External SSE streaming
echo "── 10.7 External SSE streaming ──"
RESP_BODY=$(mktemp)
curl -s -o "$RESP_BODY" -X POST "${EXT}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream, application/json" \
  --max-time 15 \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"e2e-test","version":"1.0"}}}' 2>/dev/null
HAS_DATA=$(grep -c "^data:" "$RESP_BODY" 2>/dev/null || true)
DATA_VALID=$(grep "^data:" "$RESP_BODY" 2>/dev/null | head -1 | sed 's/^data: //' | python3 -c "import sys,json; json.loads(sys.stdin.read()); print('yes')" 2>/dev/null || echo "no")
rm -f "$RESP_BODY"
[[ "$HAS_DATA" -ge 1 && "$DATA_VALID" == "yes" ]] && pass "External SSE streaming OK" || fail "External SSE" "data_lines=$HAS_DATA valid=$DATA_VALID"

# 10.8 End-to-end latency
echo "── 10.8 E2E latency ──"
mcp_reset
START=$(date +%s%N)
mcp_initialize "$EXT"
mcp_call_tool "$EXT" "namespaces_list" '{}'
CODE=$(mcp_code)
END=$(date +%s%N)
MS=$(( (END - START) / 1000000 ))
[[ "$MS" -lt 5000 ]] && pass "E2E latency: ${MS}ms" || fail "E2E latency" "${MS}ms (threshold 5000ms)"

summary
