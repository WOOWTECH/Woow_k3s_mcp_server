#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"

section "Round 1: Infrastructure Health (12 tests)"

# 1.1 MCP server pod Running
echo "── 1.1 MCP server pod Running ──"
POD_STATUS=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
READY=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
[[ "$POD_STATUS" == "Running" && "$READY" == "true" ]] && pass "MCP server pod Running+Ready" || fail "MCP server pod" "phase=$POD_STATUS ready=$READY"

# 1.2 Proxy pod Running
echo "── 1.2 Proxy pod Running ──"
POD_STATUS=$(kubectl -n "$NAMESPACE" get pods -l "$PROXY_POD_LABEL" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
READY=$(kubectl -n "$NAMESPACE" get pods -l "$PROXY_POD_LABEL" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
[[ "$POD_STATUS" == "Running" && "$READY" == "true" ]] && pass "Proxy pod Running+Ready" || fail "Proxy pod" "phase=$POD_STATUS ready=$READY"

# 1.3 MCP server Service exists
echo "── 1.3 MCP server Service ──"
SVC_IP=$(kubectl -n "$NAMESPACE" get svc "$MCP_SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
SVC_PORT=$(kubectl -n "$NAMESPACE" get svc "$MCP_SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[[ -n "$SVC_IP" && "$SVC_PORT" == "$MCP_PORT" ]] && pass "MCP Service exists ($SVC_IP:$SVC_PORT)" || fail "MCP Service" "ip=$SVC_IP port=$SVC_PORT"

# 1.4 Proxy Service exists
echo "── 1.4 Proxy Service ──"
SVC_IP=$(kubectl -n "$NAMESPACE" get svc "$PROXY_SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
SVC_PORT=$(kubectl -n "$NAMESPACE" get svc "$PROXY_SVC" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)
[[ -n "$SVC_IP" && "$SVC_PORT" == "$PROXY_PORT" ]] && pass "Proxy Service exists ($SVC_IP:$SVC_PORT)" || fail "Proxy Service" "ip=$SVC_IP port=$SVC_PORT"

# 1.5 MCP server Endpoint populated
echo "── 1.5 MCP Endpoint populated ──"
EP_COUNT=$(kubectl -n "$NAMESPACE" get endpoints "$MCP_SVC" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo 0)
[[ "$EP_COUNT" -ge 1 ]] && pass "MCP Endpoint has $EP_COUNT addresses" || fail "MCP Endpoint" "count=$EP_COUNT"

# 1.6 Proxy Endpoint populated
echo "── 1.6 Proxy Endpoint populated ──"
EP_COUNT=$(kubectl -n "$NAMESPACE" get endpoints "$PROXY_SVC" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo 0)
[[ "$EP_COUNT" -ge 1 ]] && pass "Proxy Endpoint has $EP_COUNT addresses" || fail "Proxy Endpoint" "count=$EP_COUNT"

# 1.7 ServiceAccount exists
echo "── 1.7 ServiceAccount ──"
SA=$(kubectl -n "$NAMESPACE" get sa kubernetes-mcp-viewer -o name 2>/dev/null)
[[ -n "$SA" ]] && pass "SA kubernetes-mcp-viewer exists" || fail "ServiceAccount" "not found"

# 1.8 ClusterRoleBinding exists
echo "── 1.8 ClusterRoleBinding ──"
CRB_ROLE=$(kubectl get clusterrolebinding -l "app.kubernetes.io/name=kubernetes-mcp-server" -o jsonpath='{.items[*].roleRef.name}' 2>/dev/null)
if echo "$CRB_ROLE" | grep -q "cluster-admin"; then
  pass "ClusterRoleBinding bound to cluster-admin"
else
  # Try by name pattern
  CRB_ROLE=$(kubectl get clusterrolebinding --no-headers 2>/dev/null | grep "mcp" | head -1)
  [[ -n "$CRB_ROLE" ]] && pass "ClusterRoleBinding found: $CRB_ROLE" || fail "ClusterRoleBinding" "role=$CRB_ROLE"
fi

# 1.9 Proxy /health returns 200
echo "── 1.9 Proxy health endpoint ──"
CODE=$(http_code "http://${PROXY_CLUSTER_IP}:${PROXY_PORT}/health")
BODY=$(curl -s "http://${PROXY_CLUSTER_IP}:${PROXY_PORT}/health" 2>/dev/null)
[[ "$CODE" == "200" && "$BODY" == "ok" ]] && pass "Proxy /health returns 200 ok" || fail "Proxy /health" "code=$CODE body=$BODY"

# 1.10 Server logs clean
echo "── 1.10 Server logs clean ──"
MCP_POD=$(kubectl -n "$NAMESPACE" get pods -l "$MCP_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
ERROR_LINES=$(kubectl -n "$NAMESPACE" logs "$MCP_POD" --tail=100 2>/dev/null | grep -icE "(ERROR|FATAL|panic)" || true)
[[ "$ERROR_LINES" -eq 0 ]] && pass "Server logs clean (0 errors in last 100 lines)" || fail "Server logs" "$ERROR_LINES error lines"

# 1.11 Resource limits applied
echo "── 1.11 Resource limits ──"
CPU_REQ=$(kubectl -n "$NAMESPACE" get deployment kubernetes-mcp-server -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
MEM_LIM=$(kubectl -n "$NAMESPACE" get deployment kubernetes-mcp-server -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)
[[ "$CPU_REQ" == "100m" && "$MEM_LIM" == "256Mi" ]] && pass "Resource limits correct (cpu_req=$CPU_REQ mem_lim=$MEM_LIM)" || fail "Resource limits" "cpu_req=$CPU_REQ mem_lim=$MEM_LIM"

# 1.12 Nginx config mounted
echo "── 1.12 Nginx config mounted ──"
PROXY_POD=$(kubectl -n "$NAMESPACE" get pods -l "$PROXY_POD_LABEL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
HAS_PROXY_PASS=$(kubectl -n "$NAMESPACE" exec "$PROXY_POD" -- cat /etc/nginx/nginx.conf 2>/dev/null | grep -c "proxy_pass http://kubernetes-mcp-server" || true)
[[ "$HAS_PROXY_PASS" -ge 1 ]] && pass "Nginx config mounted with correct proxy_pass" || fail "Nginx config" "proxy_pass not found"

summary
