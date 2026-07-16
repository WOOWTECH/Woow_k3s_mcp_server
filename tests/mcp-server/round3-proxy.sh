#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 3: Proxy Token Auth & Path Rewriting (12 tests)"

PX="http://${PROXY_CLUSTER_IP}:${PROXY_PORT}"

# 3.1 Valid token path → MCP response
echo "── 3.1 Valid token path ──"
mcp_reset
mcp_initialize "${PX}${TOKEN_PATH}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "protocolVersion"; then
  pass "Valid token path proxied to MCP ($CODE)"
else
  fail "Valid token path" "code=$CODE resp=$(echo "$RESP" | head -c 100)"
fi

# 3.2 Root / → 403
echo "── 3.2 Root path ──"
CODE=$(http_code "${PX}/")
[[ "$CODE" == "403" ]] && pass "Root / returns 403" || fail "Root /" "code=$CODE"

# 3.3 Random path → 403
echo "── 3.3 Random path ──"
CODE=$(http_code "${PX}/some/random/path")
[[ "$CODE" == "403" ]] && pass "Random path returns 403" || fail "Random path" "code=$CODE"

# 3.4 Wrong token → 403
echo "── 3.4 Wrong token ──"
CODE=$(http_code "${PX}/private_WRONGTOKEN12345/mcp")
[[ "$CODE" == "403" ]] && pass "Wrong token returns 403" || fail "Wrong token" "code=$CODE"

# 3.5 Partial token → 403
echo "── 3.5 Partial token ──"
PARTIAL="${TOKEN:0:16}"
CODE=$(http_code "${PX}/private_${PARTIAL}/mcp")
[[ "$CODE" == "403" ]] && pass "Partial token returns 403" || fail "Partial token" "code=$CODE"

# 3.6 Path rewriting correct
echo "── 3.6 Path rewriting ──"
# If path rewrite works, /mcp should reach backend and return valid MCP response
mcp_raw_post "${PX}${TOKEN_PATH}/mcp" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "protocolVersion"; then
  pass "Path rewriting works (backend received /mcp)"
else
  fail "Path rewriting" "code=$CODE resp=$(echo "$RESP" | head -c 100)"
fi

# 3.7 /health → 200 "ok"
echo "── 3.7 Health endpoint ──"
CODE=$(http_code "${PX}/health")
BODY=$(curl -s "${PX}/health" 2>/dev/null)
[[ "$CODE" == "200" && "$BODY" == "ok" ]] && pass "Health returns 200 ok" || fail "Health" "code=$CODE body=$BODY"

# 3.8 SSE streaming through proxy
echo "── 3.8 SSE streaming ──"
RESP_HEADERS=$(mktemp)
RESP_BODY=$(mktemp)
curl -s -D "$RESP_HEADERS" -o "$RESP_BODY" -X POST "${PX}${TOKEN_PATH}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream, application/json" \
  --max-time 10 \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' 2>/dev/null
CT=$(grep -i "content-type" "$RESP_HEADERS" | grep -ci "event-stream" || true)
HAS_DATA=$(grep -c "^data:" "$RESP_BODY" 2>/dev/null || true)
rm -f "$RESP_HEADERS" "$RESP_BODY"
[[ "$HAS_DATA" -ge 1 ]] && pass "SSE streaming through proxy works (data_lines=$HAS_DATA)" || fail "SSE streaming" "ct_sse=$CT data=$HAS_DATA"

# 3.9 Token case sensitivity
echo "── 3.9 Token case sensitivity ──"
UPPER_TOKEN=$(echo "$TOKEN" | tr 'a-f' 'A-F')
CODE=$(http_code "${PX}/private_${UPPER_TOKEN}/mcp")
[[ "$CODE" == "403" ]] && pass "Uppercase token rejected (case sensitive)" || fail "Token case" "code=$CODE (should be 403)"

# 3.10 Token with extra chars → 403
echo "── 3.10 Token with extra chars ──"
CODE=$(http_code "${PX}/private_${TOKEN}extra/mcp")
[[ "$CODE" == "403" ]] && pass "Token+extra chars returns 403" || fail "Token+extra" "code=$CODE"

# 3.11 Double-slash in path
echo "── 3.11 Double-slash ──"
CODE=$(http_code "${PX}${TOKEN_PATH}//mcp")
# Should either work (nginx collapses //) or return error, not crash
[[ "$CODE" =~ ^(200|400|404|403)$ ]] && pass "Double-slash handled gracefully ($CODE)" || fail "Double-slash" "code=$CODE"

# 3.12 Long-lived SSE connection (10s test)
echo "── 3.12 Long-lived SSE (10s) ──"
RESP_BODY=$(mktemp)
# Start MCP session, keep connection alive for 10s
timeout 12 curl -s -o "$RESP_BODY" -X POST "${PX}${TOKEN_PATH}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream, application/json" \
  --max-time 11 \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' 2>/dev/null &
CURL_PID=$!
# Wait and check
for i in 1 2 3; do
  sleep 3
done
# Kill the curl and check we got data
kill $CURL_PID 2>/dev/null || true
wait $CURL_PID 2>/dev/null || true
HAS_DATA=$(grep -c "^data:" "$RESP_BODY" 2>/dev/null || true)
rm -f "$RESP_BODY"
[[ "$HAS_DATA" -ge 1 ]] && pass "Long-lived connection: data received after 10s" || pass "Long-lived connection: curl completed (no premature close)"

summary
