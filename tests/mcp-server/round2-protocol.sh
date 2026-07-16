#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 2: MCP Protocol Compliance (15 tests)"

BASE="$MCP_DIRECT_URL"

# 2.1 POST /mcp initialize
echo "── 2.1 MCP initialize ──"
mcp_reset
mcp_initialize "$BASE"
CODE=$(mcp_code)
RESP=$(mcp_response)
SESSION=$(mcp_session)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "protocolVersion"; then
  pass "MCP initialize OK (session=${SESSION:-(none)})"
else
  fail "MCP initialize" "code=$CODE resp=$(echo "$RESP" | head -c 200)"
fi

# 2.2 tools/list returns tools
echo "── 2.2 tools/list ──"
mcp_list_tools "$BASE"
CODE=$(mcp_code)
RESP=$(mcp_response)
TOOL_COUNT=$(echo "$RESP" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(len(d.get('result',{}).get('tools',[])))" 2>/dev/null || echo 0)
[[ "$TOOL_COUNT" -ge 20 ]] && pass "tools/list returned $TOOL_COUNT tools" || fail "tools/list" "count=$TOOL_COUNT code=$CODE"

# 2.3 tools/call pods_list
echo "── 2.3 tools/call pods_list ──"
mcp_call_tool "$BASE" "pods_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "pods_list returned data"
else
  fail "pods_list" "code=$CODE"
fi

# 2.4 tools/call namespaces_list
echo "── 2.4 tools/call namespaces_list ──"
mcp_call_tool "$BASE" "namespaces_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "mcp-system"; then
  pass "namespaces_list contains mcp-system"
else
  fail "namespaces_list" "mcp-system not found code=$CODE"
fi

# 2.5 GET /sse without session
echo "── 2.5 GET /sse no session ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "${BASE}/sse" --max-time 5 2>/dev/null)
# Server may return 200 (SSE endpoint exists) or 400/404 - both acceptable
[[ "$CODE" =~ ^(200|400|404|405)$ ]] && pass "GET /sse no session ($CODE)" || fail "GET /sse no session" "code=$CODE"

# 2.6 GET /sse invalid session
echo "── 2.6 GET /sse invalid session ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "${BASE}/sse" -H "Mcp-Session-Id: 00000000-0000-0000-0000-000000000000" --max-time 5 2>/dev/null)
[[ "$CODE" =~ ^(200|400|404)$ ]] && pass "GET /sse invalid session ($CODE)" || fail "GET /sse invalid session" "code=$CODE"

# 2.7 OPTIONS /mcp
echo "── 2.7 OPTIONS /mcp ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "${BASE}/mcp" --max-time 5 2>/dev/null)
[[ "$CODE" =~ ^(200|204|405)$ ]] && pass "OPTIONS /mcp ($CODE)" || fail "OPTIONS /mcp" "code=$CODE"

# 2.8 PUT /mcp
echo "── 2.8 PUT /mcp ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${BASE}/mcp" --max-time 5 2>/dev/null)
[[ "$CODE" =~ ^(400|405)$ ]] && pass "PUT /mcp rejected ($CODE)" || fail "PUT /mcp" "code=$CODE"

# 2.9 DELETE /mcp without session
echo "── 2.9 DELETE /mcp ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${BASE}/mcp" --max-time 5 2>/dev/null)
[[ "$CODE" =~ ^(400|405)$ ]] && pass "DELETE /mcp rejected ($CODE)" || fail "DELETE /mcp" "code=$CODE"

# 2.10 Invalid JSON-RPC method
echo "── 2.10 Invalid method ──"
mcp_raw_post "${BASE}/mcp" '{"jsonrpc":"2.0","id":999,"method":"nonexistent/method"}'
CODE=$(mcp_code)
[[ "$CODE" =~ ^(400|404|200)$ ]] && pass "Invalid method handled ($CODE)" || fail "Invalid method" "code=$CODE"

# 2.11 Missing jsonrpc field
echo "── 2.11 Missing jsonrpc field ──"
mcp_raw_post "${BASE}/mcp" '{"id":1,"method":"initialize"}'
CODE=$(mcp_code)
[[ "$CODE" =~ ^(400|200)$ ]] && pass "Missing jsonrpc handled ($CODE)" || fail "Missing jsonrpc" "code=$CODE"

# 2.12 Malformed JSON body
echo "── 2.12 Malformed JSON ──"
mcp_raw_post "${BASE}/mcp" '{not valid json!!!'
CODE=$(mcp_code)
[[ "$CODE" =~ ^(400|415)$ ]] && pass "Malformed JSON rejected ($CODE)" || fail "Malformed JSON" "code=$CODE"

# 2.13 Empty body
echo "── 2.13 Empty body ──"
mcp_raw_post "${BASE}/mcp" ''
CODE=$(mcp_code)
[[ "$CODE" =~ ^(400|411|415)$ ]] && pass "Empty body rejected ($CODE)" || fail "Empty body" "code=$CODE"

# 2.14 Wrong Content-Type
echo "── 2.14 Wrong Content-Type ──"
mcp_raw_post "${BASE}/mcp" '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "text/plain"
CODE=$(mcp_code)
[[ -n "$CODE" ]] && pass "Wrong Content-Type handled ($CODE)" || fail "Wrong Content-Type" "no response"

# 2.15 SSE response format
echo "── 2.15 SSE response format ──"
RESP_BODY=$(mktemp)
curl -s -o "$RESP_BODY" -X POST "${BASE}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream, application/json" \
  --max-time 10 \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' 2>/dev/null
HAS_EVENT=$(grep -c "^event:" "$RESP_BODY" 2>/dev/null || true)
HAS_DATA=$(grep -c "^data:" "$RESP_BODY" 2>/dev/null || true)
DATA_VALID=$(grep "^data:" "$RESP_BODY" 2>/dev/null | head -1 | sed 's/^data: //' | python3 -c "import sys,json; json.loads(sys.stdin.read()); print('yes')" 2>/dev/null || echo "no")
rm -f "$RESP_BODY"
if [[ "$HAS_DATA" -ge 1 && "$DATA_VALID" == "yes" ]]; then
  pass "SSE format valid (events=$HAS_EVENT data_lines=$HAS_DATA)"
else
  fail "SSE format" "event_lines=$HAS_EVENT data_lines=$HAS_DATA"
fi

summary
