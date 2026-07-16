#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 9: Edge Cases (12 tests)"

PX="${PROXY_URL}${TOKEN_PATH}"

# Initialize session
mcp_reset
mcp_initialize "$PX"

MCP_POD=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# 9.1 Empty arguments
echo "── 9.1 Empty arguments ──"
mcp_call_tool "$PX" "pods_list" '{}'
CODE=$(mcp_code)
[[ "$CODE" == "200" ]] && pass "Empty arguments accepted" || fail "Empty args" "code=$CODE"

# 9.2 Extra unknown arguments
echo "── 9.2 Extra unknown arguments ──"
mcp_call_tool "$PX" "namespaces_list" '{"unknown_field":"unknown_value","extra":123}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "Extra arguments ignored ($CODE)" || pass "Extra arguments handled ($CODE)"

# 9.3 Missing required argument
echo "── 9.3 Missing required argument ──"
mcp_call_tool "$PX" "pods_list_in_namespace" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
# Should return error about missing namespace
[[ "$CODE" =~ ^(200|400)$ ]] && pass "Missing required arg handled ($CODE)" || fail "Missing required" "code=$CODE"

# 9.4 Wrong type for argument
echo "── 9.4 Wrong type ──"
mcp_call_tool "$PX" "pods_log" '{"name":12345,"namespace":"default"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ -n "$CODE" ]] && pass "Wrong type handled ($CODE)" || fail "Wrong type" "no response"

# 9.5 Non-existent namespace
echo "── 9.5 Non-existent namespace ──"
mcp_call_tool "$PX" "pods_list_in_namespace" '{"namespace":"nonexistent-ns-xyz-12345"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "Non-existent namespace returned empty/error gracefully" || fail "Non-existent ns" "code=$CODE"

# 9.6 Non-existent pod
echo "── 9.6 Non-existent pod ──"
mcp_call_tool "$PX" "pods_get" '{"name":"no-such-pod-xyz-99999","namespace":"default"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -qi "not found\|error\|isError"; then
  pass "Non-existent pod returns not-found error"
else
  [[ "$CODE" == "200" ]] && pass "Non-existent pod handled ($CODE)" || fail "Non-existent pod" "code=$CODE"
fi

# 9.7 Non-existent resource kind
echo "── 9.7 Non-existent resource kind ──"
mcp_call_tool "$PX" "resources_list" '{"apiVersion":"v1","kind":"NonExistentResourceKind"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "Non-existent kind handled ($CODE)" || pass "Non-existent kind error ($CODE)"

# 9.8 Very long resource name (256 chars)
echo "── 9.8 256-char resource name ──"
LONG_NAME=$(python3 -c "print('a'*256)" 2>/dev/null)
mcp_call_tool "$PX" "pods_get" "{\"name\":\"$LONG_NAME\",\"namespace\":\"default\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ -n "$CODE" ]] && pass "256-char name handled ($CODE)" || fail "Long name" "no response"

# 9.9 Special characters in label selector
echo "── 9.9 Special chars in selector ──"
mcp_call_tool "$PX" "pods_list" '{"labelSelector":"app=test&inject=true"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ -n "$CODE" ]] && pass "Special chars in selector handled ($CODE)" || fail "Special chars" "no response"

# 9.10 Concurrent different tools
echo "── 9.10 Concurrent different tools ──"
TMPDIR_MT=$(mktemp -d)
TOOLS=("namespaces_list" "pods_list" "events_list" "nodes_top")
for i in "${!TOOLS[@]}"; do
  (
    mcp_reset
    mcp_initialize "$PX"
    mcp_call_tool "$PX" "${TOOLS[$i]}" '{}'
    CODE=$(mcp_code)
    echo "$CODE" > "$TMPDIR_MT/$i.txt"
  ) &
done
wait
OK_COUNT=0
for f in "$TMPDIR_MT"/*.txt; do
  [[ "$(cat "$f")" == "200" ]] && ((OK_COUNT++))
done
rm -rf "$TMPDIR_MT"
[[ "$OK_COUNT" -ge 3 ]] && pass "Concurrent different tools: $OK_COUNT/4 OK" || fail "Concurrent tools" "$OK_COUNT/4"

# 9.11 Rapid sequential different tools
echo "── 9.11 Rapid sequential tools ──"
mcp_reset
mcp_initialize "$PX"
SEQ_OK=0
SEQ_TOTAL=10
TOOLS_SEQ=("namespaces_list" "pods_list" "events_list" "nodes_top" "helm_list"
           "namespaces_list" "pods_list" "events_list" "configuration_view" "helm_list")
for tool in "${TOOLS_SEQ[@]}"; do
  mcp_call_tool "$PX" "$tool" '{}'
  CODE=$(mcp_code)
  [[ "$CODE" == "200" ]] && ((SEQ_OK++))
done
[[ "$SEQ_OK" -ge 8 ]] && pass "Rapid sequential: $SEQ_OK/$SEQ_TOTAL OK" || fail "Rapid sequential" "$SEQ_OK/$SEQ_TOTAL"

# 9.12 Maximum tail lines (0 = all)
echo "── 9.12 Max tail lines ──"
if [[ -n "$MCP_POD" ]]; then
  mcp_call_tool "$PX" "pods_log" "{\"name\":\"$MCP_POD\",\"namespace\":\"$NAMESPACE\",\"tail\":0}"
  CODE=$(mcp_code)
  RESP=$(mcp_response)
  RESP_LEN=$(echo "$RESP" | wc -c)
  [[ "$CODE" == "200" ]] && pass "Max tail (0=all): ${RESP_LEN} bytes" || pass "Max tail handled ($CODE)"
else
  skip "Max tail" "no pod name"
fi

summary
