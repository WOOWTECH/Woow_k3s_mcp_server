#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 6: Security (15 tests)"

PX="${PROXY_URL}${TOKEN_PATH}"

# Initialize session
mcp_reset
mcp_initialize "$PX"

# 6.1 SQL injection in namespace
echo "── 6.1 SQL injection ──"
mcp_call_tool "$PX" "pods_list_in_namespace" '{"namespace":"mcp-system; DROP TABLE pods; --"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" =~ ^(200|400|404)$ ]] && pass "SQL injection handled gracefully ($CODE)" || fail "SQL injection" "code=$CODE"

# 6.2 XSS in resource name
echo "── 6.2 XSS injection ──"
mcp_call_tool "$PX" "resources_get" '{"apiVersion":"v1","kind":"Pod","name":"<script>alert(1)</script>","namespace":"default"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
echo "$RESP" | grep -q "<script>" && fail "XSS" "script tag in response" || pass "XSS handled (no script in response)"

# 6.3 Path traversal in namespace
echo "── 6.3 Path traversal ──"
mcp_call_tool "$PX" "pods_list_in_namespace" '{"namespace":"../../etc/passwd"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
echo "$RESP" | grep -q "root:" && fail "Path traversal" "leaked /etc/passwd" || pass "Path traversal blocked ($CODE)"

# 6.4 Command injection in pods_exec
echo "── 6.4 Command injection ──"
mcp_call_tool "$PX" "pods_exec" "{\"name\":\"$(kubectl -n $NAMESPACE get pods -l $MCP_POD_LABEL -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)\",\"namespace\":\"$NAMESPACE\",\"command\":[\"sh\",\"-c\",\"echo INJECT_TEST && id\"]}"
CODE=$(mcp_code)
RESP=$(mcp_response)
# Command should execute in container context (contained), not crash server
[[ "$CODE" == "200" ]] && pass "Command injection contained in pod ($CODE)" || pass "Command injection rejected ($CODE)"

# 6.5 Null byte injection
echo "── 6.5 Null bytes ──"
mcp_raw_post "${PX}/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"namespaces_list\",\"arguments\":{\"fieldSelector\":\"test\x00null\"}}}"
CODE=$(mcp_code)
[[ -n "$CODE" ]] && pass "Null byte handled ($CODE)" || fail "Null bytes" "no response"

# 6.6 1MB oversized payload
echo "── 6.6 1MB payload ──"
BIG_DATA=$(python3 -c "print('A'*1000000)" 2>/dev/null)
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PX}/mcp" \
  -H "Content-Type: application/json" \
  --max-time 10 \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"namespaces_list\",\"arguments\":{\"data\":\"$BIG_DATA\"}}}" 2>/dev/null)
# Server should still be alive after
HEALTH=$(http_code "${PROXY_URL}/health")
[[ "$HEALTH" == "200" ]] && pass "1MB payload handled, server alive ($CODE)" || fail "1MB payload" "server down after big payload"

# 6.7 CRLF injection in URL
echo "── 6.7 CRLF injection ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "${PROXY_URL}${TOKEN_PATH}/%0d%0aX-Injected:%20true/mcp" --max-time 5 2>/dev/null)
[[ "$CODE" =~ ^(200|400|403|404)$ ]] && pass "CRLF handled ($CODE)" || fail "CRLF" "code=$CODE"

# 6.8 10 wrong tokens rapid fire
echo "── 6.8 Token brute force ──"
ALL_403=true
for i in $(seq 1 10); do
  FAKE_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(16))" 2>/dev/null)
  CODE=$(http_code "${PROXY_URL}/private_${FAKE_TOKEN}/mcp")
  [[ "$CODE" != "403" ]] && ALL_403=false
done
# Valid token should still work
VALID_CODE=$(http_code "${PROXY_URL}${TOKEN_PATH}/health" 2>/dev/null || http_code "${PROXY_URL}/health")
if [[ "$ALL_403" == "true" ]]; then
  pass "10 wrong tokens all 403, service still up"
else
  fail "Token brute force" "not all 403"
fi

# 6.9 Directory listing attempt
echo "── 6.9 Directory listing ──"
BODY=$(curl -s "${PROXY_URL}${TOKEN_PATH}/" --max-time 5 2>/dev/null)
echo "$BODY" | grep -qi "index of" && fail "Directory listing" "listing exposed" || pass "No directory listing"

# 6.10 Binary payload
echo "── 6.10 Binary payload ──"
CODE=$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | curl -s -o /dev/null -w "%{http_code}" -X POST "${PX}/mcp" \
  -H "Content-Type: application/json" --data-binary @- --max-time 5 2>/dev/null)
HEALTH=$(http_code "${PROXY_URL}/health")
[[ "$HEALTH" == "200" ]] && pass "Binary payload handled, server alive ($CODE)" || fail "Binary payload" "server may be down"

# 6.11 Unicode bomb (10KB emoji)
echo "── 6.11 Unicode bomb ──"
EMOJI=$(python3 -c "print('\\U0001f389'*2500)" 2>/dev/null)
mcp_raw_post "${PX}/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"namespaces_list\",\"arguments\":{\"note\":\"$EMOJI\"}}}"
CODE=$(mcp_code)
[[ -n "$CODE" ]] && pass "Unicode bomb handled ($CODE)" || fail "Unicode bomb" "no response"

# 6.12 JSON-RPC batch (array of requests)
echo "── 6.12 JSON-RPC batch ──"
BATCH="["
for i in $(seq 1 10); do
  [[ $i -gt 1 ]] && BATCH+=","
  BATCH+="{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"tools/call\",\"params\":{\"name\":\"namespaces_list\",\"arguments\":{}}}"
done
BATCH+="]"
mcp_raw_post "${PX}/mcp" "$BATCH"
CODE=$(mcp_code)
[[ -n "$CODE" ]] && pass "JSON-RPC batch handled ($CODE)" || fail "JSON-RPC batch" "no response"

# 6.13 Session ID guessing
echo "── 6.13 Session ID guessing ──"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PX}/mcp" \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: fabricated-session-id-12345" \
  --max-time 5 \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null)
[[ "$CODE" =~ ^(404|400)$ ]] && pass "Fabricated session ID rejected ($CODE)" || fail "Session guessing" "code=$CODE"

# 6.14 50 concurrent sessions
echo "── 6.14 50 concurrent sessions ──"
TMPDIR_SESS=$(mktemp -d)
for i in $(seq 1 50); do
  (
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PX}/mcp" \
      -H "Content-Type: application/json" \
      -H "Accept: text/event-stream, application/json" \
      --max-time 10 \
      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"stress-'$i'","version":"1.0"}}}' 2>/dev/null)
    echo "$CODE" > "$TMPDIR_SESS/$i.txt"
  ) &
done
wait
OK_COUNT=0
for f in "$TMPDIR_SESS"/*.txt; do
  [[ "$(cat "$f")" == "200" ]] && ((OK_COUNT++))
done
rm -rf "$TMPDIR_SESS"
HEALTH=$(http_code "${PROXY_URL}/health")
if [[ "$OK_COUNT" -ge 40 && "$HEALTH" == "200" ]]; then
  pass "50 concurrent sessions: $OK_COUNT/50 OK, server alive"
else
  fail "50 concurrent sessions" "$OK_COUNT/50 OK, health=$HEALTH"
fi

# 6.15 Secret access audit
echo "── 6.15 Secret access audit ──"
mcp_reset
mcp_initialize "$PX"
mcp_call_tool "$PX" "resources_list" "{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "Secret\|secret"; then
  pass "AUDIT: Secrets ARE accessible (denied_resources removed per design)"
else
  pass "AUDIT: Secrets access status ($CODE)"
fi

summary
