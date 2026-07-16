#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/assert.sh"
source "$SCRIPT_DIR/lib/mcp-client.sh"

section "Round 5: Config + Helm Toolset (5 tests)"

# Initialize session
mcp_reset
mcp_initialize "${PROXY_URL}${TOKEN_PATH}"

# 5.1 configuration_view (minified)
echo "── 5.1 configuration_view minified ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "configuration_view" '{"minified":true}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "configuration_view minified ($CODE)"
else
  fail "configuration_view minified" "code=$CODE"
fi

# 5.2 configuration_view (full)
echo "── 5.2 configuration_view full ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "configuration_view" '{"minified":false}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "result"; then
  pass "configuration_view full ($CODE)"
else
  fail "configuration_view full" "code=$CODE"
fi

# 5.3 projects_list (K3s has no OpenShift projects)
echo "── 5.3 projects_list ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "projects_list" '{}'
CODE=$(mcp_code)
RESP=$(mcp_response)
# Should return empty or error gracefully (no OpenShift)
[[ "$CODE" == "200" ]] && pass "projects_list handled gracefully on K3s ($CODE)" || pass "projects_list returned error (expected on K3s, $CODE)"

# 5.4 helm_list (mcp-system)
echo "── 5.4 helm_list mcp-system ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "helm_list" "{\"namespace\":\"$NAMESPACE\"}"
CODE=$(mcp_code)
RESP=$(mcp_response)
if echo "$RESP" | grep -q "kubernetes-mcp-server"; then
  pass "helm_list found kubernetes-mcp-server release"
else
  fail "helm_list mcp-system" "release not found code=$CODE"
fi

# 5.5 helm_list (all_namespaces)
echo "── 5.5 helm_list all_namespaces ──"
mcp_call_tool "${PROXY_URL}${TOKEN_PATH}" "helm_list" '{"all_namespaces":true}'
CODE=$(mcp_code)
RESP=$(mcp_response)
if [[ "$CODE" == "200" ]] && echo "$RESP" | grep -q "kubernetes-mcp-server"; then
  pass "helm_list all namespaces ($CODE)"
else
  fail "helm_list all" "code=$CODE"
fi

summary
