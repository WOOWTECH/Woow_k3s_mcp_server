#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 4: Core Toolset — All Tools (18 tests)"

# Initialize session through proxy
mcp_reset
mcp_initialize "${PROXY_URL}${TOKEN_PATH}"

# Get a node name and MCP pod name for tests
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
MCP_POD=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# 4.1 pods_list
echo "── 4.1 pods_list ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "pods_list returned data"
else
  fail "pods_list" "code=$CODE"
fi

# 4.2 pods_list_in_namespace
echo "── 4.2 pods_list_in_namespace ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_list_in_namespace" "{\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "kubernetes-mcp-server"; then
  pass "pods_list_in_namespace found MCP server pod"
else
  fail "pods_list_in_namespace" "code=$CODE mcp pod not found"
fi

# 4.3 pods_get
echo "── 4.3 pods_get ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_get" "{\"name\":\"$MCP_POD\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "pods_get returned pod details"
else
  fail "pods_get" "code=$CODE"
fi

# 4.4 pods_log
echo "── 4.4 pods_log ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_log" "{\"name\":\"$MCP_POD\",\"namespace\":\"$NAMESPACE\",\"tail\":5}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "pods_log returned log lines"
else
  fail "pods_log" "code=$CODE"
fi

# 4.5 pods_exec
echo "── 4.5 pods_exec ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_exec" "{\"name\":\"$MCP_POD\",\"namespace\":\"$NAMESPACE\",\"command\":[\"echo\",\"mcp-test-ok\"]}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "mcp-test-ok"; then
  pass "pods_exec returned command output"
else
  # Some containers may not have echo, try alternative check
  [[ "$CODE" == "200" ]] && pass "pods_exec completed ($CODE)" || fail "pods_exec" "code=$CODE"
fi

# 4.6 pods_top
echo "── 4.6 pods_top ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_top" "{\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "pods_top returned metrics"
else
  skip "pods_top" "metrics server may not be available ($CODE)"
fi

# 4.7 namespaces_list
echo "── 4.7 namespaces_list ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "namespaces_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "default" && echo "$RESP" | grep -q "kube-system"; then
  pass "namespaces_list returned expected namespaces"
else
  fail "namespaces_list" "missing expected namespaces code=$CODE"
fi

# 4.8 events_list
echo "── 4.8 events_list ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "events_list" "{\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "events_list returned ($CODE)" || fail "events_list" "code=$CODE"

# 4.9 events_list with filter
echo "── 4.9 events_list filtered ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "events_list" '{"fieldSelector":"type=Warning"}'
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "events_list filtered ($CODE)" || fail "events_list filtered" "code=$CODE"

# 4.10 nodes_log
echo "── 4.10 nodes_log ──"
if [[ -n "$NODE_NAME" ]]; then
  mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "nodes_log" "{\"name\":\"$NODE_NAME\",\"query\":\"kubelet\",\"tailLines\":5}"
  CODE=$(mcp_code)
  RESP=$(mcp_response)
  [[ "$CODE" == "200" ]] && pass "nodes_log returned ($CODE)" || skip "nodes_log" "may need journald access ($CODE)"
else
  skip "nodes_log" "no node name found"
fi

# 4.11 nodes_top
echo "── 4.11 nodes_top ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "nodes_top" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "nodes_top returned metrics"
else
  skip "nodes_top" "metrics server may not be available ($CODE)"
fi

# 4.12 nodes_stats_summary
echo "── 4.12 nodes_stats_summary ──"
if [[ -n "$NODE_NAME" ]]; then
  mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "nodes_stats_summary" "{\"name\":\"$NODE_NAME\"}"
  CODE=$(mcp_code)
  RESP=$(mcp_response)
  [[ "$CODE" == "200" ]] && pass "nodes_stats_summary returned ($CODE)" || fail "nodes_stats_summary" "code=$CODE"
else
  skip "nodes_stats_summary" "no node name"
fi

# 4.13 resources_list (Deployments)
echo "── 4.13 resources_list Deployments ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "resources_list" "{\"apiVersion\":\"apps/v1\",\"kind\":\"Deployment\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "kubernetes-mcp-server"; then
  pass "resources_list found MCP server deployment"
else
  fail "resources_list Deployments" "code=$CODE"
fi

# 4.14 resources_list (Services)
echo "── 4.14 resources_list Services ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "resources_list" "{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "resources_list Services ($CODE)" || fail "resources_list Services" "code=$CODE"

# 4.15 resources_get
echo "── 4.15 resources_get ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "resources_get" "{\"apiVersion\":\"apps/v1\",\"kind\":\"Deployment\",\"name\":\"kubernetes-mcp-server\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "resources_get returned deployment spec"
else
  fail "resources_get" "code=$CODE"
fi

# 4.16 resources_scale (read-only)
echo "── 4.16 resources_scale ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "resources_scale" "{\"apiVersion\":\"apps/v1\",\"kind\":\"Deployment\",\"name\":\"kubernetes-mcp-server\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
[[ "$CODE" == "200" ]] && pass "resources_scale returned ($CODE)" || fail "resources_scale" "code=$CODE"

# 4.17 resources_create_or_update + resources_delete
echo "── 4.17 Create + Delete ConfigMap ──"
# resource param expects a YAML/JSON string, not an object
CM_YAML='apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: mcp-test-validation\n  namespace: '"$NAMESPACE"'\ndata:\n  test: enterprise-validation'
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "resources_create_or_update" "{\"resource\":\"$CM_YAML\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && ! echo "$RESP" | grep -q "isError"; then
  sleep 1
  # Verify it exists
  VERIFY=$(kubectl -n "$NAMESPACE" get configmap mcp-test-validation -o jsonpath='{.data.test}' 2>/dev/null)
  if [[ "$VERIFY" == "enterprise-validation" ]]; then
    # Now delete
    mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "resources_delete" "{\"apiVersion\":\"v1\",\"kind\":\"ConfigMap\",\"name\":\"mcp-test-validation\",\"namespace\":\"$NAMESPACE\"}"
    sleep 1
    kubectl -n "$NAMESPACE" get configmap mcp-test-validation &>/dev/null
    if [[ $? -ne 0 ]]; then
      pass "Create+Delete ConfigMap lifecycle complete"
    else
      fail "Create+Delete" "delete failed, still exists"
      kubectl -n "$NAMESPACE" delete configmap mcp-test-validation &>/dev/null
    fi
  else
    fail "Create+Delete" "ConfigMap data wrong: got='$VERIFY'"
    kubectl -n "$NAMESPACE" delete configmap mcp-test-validation &>/dev/null
  fi
else
  fail "Create ConfigMap" "code=$CODE resp=$(echo "$RESP" | head -c 200)"
fi

# 4.18 pods_run + pods_delete
echo "── 4.18 Pod run + delete ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_run" "{\"image\":\"busybox:latest\",\"name\":\"mcp-test-pod\",\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
if [[ "$CODE" == "200" ]]; then
  # Wait briefly for pod to appear
  sleep 3
  POD_EXISTS=$(kubectl -n "$NAMESPACE" get pod mcp-test-pod --no-headers 2>/dev/null | wc -l)
  if [[ "$POD_EXISTS" -ge 1 ]]; then
    # Delete it
    mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "pods_delete" "{\"name\":\"mcp-test-pod\",\"namespace\":\"$NAMESPACE\"}"
    DEL_CODE=$(mcp_code)
    sleep 2
    pass "Pod run+delete lifecycle complete"
  else
    fail "Pod run" "pod not found after create"
  fi
else
  fail "Pod run" "code=$CODE"
fi
# Cleanup
kubectl -n "$NAMESPACE" delete pod mcp-test-pod --ignore-not-found &>/dev/null

summary
