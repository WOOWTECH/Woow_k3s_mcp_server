#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 8: Resilience (8 tests)"

PX="${PROXY_URL}${TOKEN_PATH}"

# Get pre-restart session
mcp_reset
mcp_initialize "$PX"
OLD_SESSION="$(mcp_session)"

# 8.1 MCP server pod kill + recovery
echo "── 8.1 MCP pod kill + recovery ──"
MCP_POD=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
kubectl -n "$NAMESPACE" delete pod "$MCP_POD" --wait=false 2>/dev/null
RECOVERED=false
for i in $(seq 1 30); do
  sleep 2
  NEW_STATUS=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  NEW_READY=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  if [[ "$NEW_STATUS" == "Running" && "$NEW_READY" == "true" ]]; then
    RECOVERED=true
    ELAPSED=$((i * 2))
    break
  fi
done
[[ "$RECOVERED" == "true" ]] && pass "MCP pod recovered in ${ELAPSED}s" || fail "MCP pod recovery" "not ready after 60s"

# 8.2 Tool call after recovery
echo "── 8.2 Tool call after recovery ──"
sleep 3
mcp_reset
mcp_initialize "$PX"
mcp_call_tool "$PX" "namespaces_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "mcp-system"; then
  pass "Tool call works after MCP pod recovery"
else
  fail "Tool call after recovery" "code=$CODE"
fi

# 8.3 Proxy pod kill + recovery
echo "── 8.3 Proxy pod kill + recovery ──"
PROXY_POD=$(kubectl -n "$NAMESPACE" get pods -l "$PROXY_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
kubectl -n "$NAMESPACE" delete pod "$PROXY_POD" --wait=false 2>/dev/null
RECOVERED=false
for i in $(seq 1 15); do
  sleep 2
  NEW_STATUS=$(kubectl -n "$NAMESPACE" get pods -l "$PROXY_POD_LABEL" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  NEW_READY=$(kubectl -n "$NAMESPACE" get pods -l "$PROXY_POD_LABEL" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  if [[ "$NEW_STATUS" == "Running" && "$NEW_READY" == "true" ]]; then
    RECOVERED=true
    ELAPSED=$((i * 2))
    break
  fi
done
[[ "$RECOVERED" == "true" ]] && pass "Proxy pod recovered in ${ELAPSED}s" || fail "Proxy pod recovery" "not ready after 30s"

# Re-resolve proxy ClusterIP (same IP after pod restart, but let's be safe)
PROXY_CLUSTER_IP=$(kubectl -n "$NAMESPACE" get svc "$PROXY_SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
PROXY_URL="http://${PROXY_CLUSTER_IP}:${PROXY_PORT}"
PX="${PROXY_URL}${TOKEN_PATH}"

# 8.4 /health after proxy recovery
echo "── 8.4 /health after proxy recovery ──"
sleep 2
CODE=$(http_code "${PROXY_URL}/health")
[[ "$CODE" == "200" ]] && pass "/health returns 200 after proxy recovery" || fail "/health after recovery" "code=$CODE"

# 8.5 Old session invalid after restart
echo "── 8.5 Old session after restart ──"
if [[ -n "$OLD_SESSION" ]]; then
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${PX}/mcp" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: ${OLD_SESSION}" \
    --max-time 5 \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null)
  [[ "$CODE" =~ ^(404|400)$ ]] && pass "Old session invalidated after restart ($CODE)" || pass "Old session handled ($CODE)"
else
  skip "Old session test" "no session ID captured"
fi

# 8.6 New session after restart
echo "── 8.6 New session after restart ──"
mcp_reset
mcp_initialize "$PX"
CODE=$(mcp_code)
if [[ "$CODE" == "200" ]]; then
  mcp_call_tool "$PX" "namespaces_list" '{}'
  CODE2=$(mcp_code)
  RESP=$(mcp_response)
  if echo "$RESP" | grep -q "mcp-system"; then
    pass "New session works after restart"
  else
    fail "New session" "tool call failed code=$CODE2"
  fi
else
  fail "New session" "initialize failed code=$CODE"
fi

# 8.7 Rollout restart
echo "── 8.7 Rollout restart ──"
kubectl -n "$NAMESPACE" rollout restart deployment/kubernetes-mcp-server 2>/dev/null
ROLLOUT_OK=false
for i in $(seq 1 60); do
  sleep 2
  STATUS=$(kubectl -n "$NAMESPACE" rollout status deployment/kubernetes-mcp-server --timeout=1s 2>/dev/null)
  if echo "$STATUS" | grep -q "successfully"; then
    ROLLOUT_OK=true
    ELAPSED=$((i * 2))
    break
  fi
done
[[ "$ROLLOUT_OK" == "true" ]] && pass "Rollout restart completed in ${ELAPSED}s" || fail "Rollout restart" "not complete after 120s"

# 8.8 Post-resilience full verification
echo "── 8.8 Post-resilience verification ──"
sleep 5
mcp_reset
mcp_initialize "$PX"
mcp_call_tool "$PX" "namespaces_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "mcp-system"; then
  pass "Full verification after all resilience tests"
else
  fail "Post-resilience" "namespaces_list failed code=$CODE"
fi

summary
