#!/usr/bin/env bash
# MCP JSON-RPC client library for testing
# Uses temp files for state persistence across subshells

MCP_STATE_DIR=$(mktemp -d)
MCP_SESSION_FILE="$MCP_STATE_DIR/session"
MCP_RESPONSE_FILE="$MCP_STATE_DIR/response"
MCP_HTTP_CODE_FILE="$MCP_STATE_DIR/http_code"
MCP_REQUEST_ID_FILE="$MCP_STATE_DIR/req_id"
echo "0" > "$MCP_REQUEST_ID_FILE"

_mcp_next_id() {
  local id
  id=$(cat "$MCP_REQUEST_ID_FILE")
  id=$((id + 1))
  echo "$id" > "$MCP_REQUEST_ID_FILE"
  echo "$id"
}

# Initialize MCP session
# Usage: mcp_initialize <base_url>
# Sets: MCP_SESSION_FILE, MCP_RESPONSE_FILE, MCP_HTTP_CODE_FILE
mcp_initialize() {
  local url="$1"
  local hdr_file
  hdr_file=$(mktemp)
  local body_file
  body_file=$(mktemp)
  local rid
  rid=$(_mcp_next_id)

  curl -s -D "$hdr_file" -o "$body_file" \
    -X POST "${url}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream, application/json" \
    --max-time 15 \
    -d "{\"jsonrpc\":\"2.0\",\"id\":${rid},\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"mcp-test-suite\",\"version\":\"1.0\"}}}" 2>/dev/null

  grep -i "mcp-session-id" "$hdr_file" 2>/dev/null | tr -d '\r\n' | sed 's/.*: *//' > "$MCP_SESSION_FILE"
  _mcp_extract_data "$body_file" > "$MCP_RESPONSE_FILE"
  grep "^HTTP/" "$hdr_file" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r\n' > "$MCP_HTTP_CODE_FILE"

  rm -f "$hdr_file" "$body_file"
}

# Call an MCP tool
# Usage: mcp_call_tool <base_url> <tool_name> [args_json]
mcp_call_tool() {
  local url="$1"
  local tool="$2"
  local args="${3:-\{\}}"
  local hdr_file
  hdr_file=$(mktemp)
  local body_file
  body_file=$(mktemp)
  local json_file
  json_file=$(mktemp)
  local rid
  rid=$(_mcp_next_id)
  local session
  session=$(cat "$MCP_SESSION_FILE" 2>/dev/null)

  # Write JSON to file to avoid shell quoting issues
  cat > "$json_file" << JSONEOF
{"jsonrpc":"2.0","id":${rid},"method":"tools/call","params":{"name":"${tool}","arguments":${args}}}
JSONEOF

  local session_args=()
  [[ -n "$session" ]] && session_args=(-H "Mcp-Session-Id: ${session}")

  curl -s -D "$hdr_file" -o "$body_file" \
    -X POST "${url}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream, application/json" \
    "${session_args[@]}" \
    --max-time 30 \
    -d @"$json_file" 2>/dev/null

  _mcp_extract_data "$body_file" > "$MCP_RESPONSE_FILE"
  grep "^HTTP/" "$hdr_file" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r\n' > "$MCP_HTTP_CODE_FILE"

  rm -f "$hdr_file" "$body_file" "$json_file"
}

# List all tools
# Usage: mcp_list_tools <base_url>
mcp_list_tools() {
  local url="$1"
  local hdr_file
  hdr_file=$(mktemp)
  local body_file
  body_file=$(mktemp)
  local rid
  rid=$(_mcp_next_id)
  local session
  session=$(cat "$MCP_SESSION_FILE" 2>/dev/null)

  local session_args=()
  [[ -n "$session" ]] && session_args=(-H "Mcp-Session-Id: ${session}")

  curl -s -D "$hdr_file" -o "$body_file" \
    -X POST "${url}/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: text/event-stream, application/json" \
    "${session_args[@]}" \
    --max-time 15 \
    -d "{\"jsonrpc\":\"2.0\",\"id\":${rid},\"method\":\"tools/list\"}" 2>/dev/null

  _mcp_extract_data "$body_file" > "$MCP_RESPONSE_FILE"
  grep "^HTTP/" "$hdr_file" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r\n' > "$MCP_HTTP_CODE_FILE"

  rm -f "$hdr_file" "$body_file"
}

# Send raw POST (for protocol compliance tests)
# Usage: mcp_raw_post <url> <body> [content_type]
mcp_raw_post() {
  local url="$1"
  local body="$2"
  local ct="${3:-application/json}"
  local hdr_file
  hdr_file=$(mktemp)
  local body_file
  body_file=$(mktemp)

  curl -s -D "$hdr_file" -o "$body_file" \
    -X POST "${url}" \
    -H "Content-Type: ${ct}" \
    -H "Accept: text/event-stream, application/json" \
    --max-time 10 \
    -d "$body" 2>/dev/null

  _mcp_extract_data "$body_file" > "$MCP_RESPONSE_FILE"
  grep "^HTTP/" "$hdr_file" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r\n' > "$MCP_HTTP_CODE_FILE"

  rm -f "$hdr_file" "$body_file"
}

# Extract data from SSE or plain response
_mcp_extract_data() {
  local file="$1"
  [[ ! -f "$file" ]] && return
  local data
  data=$(grep "^data: " "$file" 2>/dev/null | sed 's/^data: //')
  if [[ -n "$data" ]]; then
    echo "$data"
  else
    cat "$file" 2>/dev/null
  fi
}

# Read last response
mcp_response() {
  cat "$MCP_RESPONSE_FILE" 2>/dev/null
}

# Read last HTTP code
mcp_code() {
  cat "$MCP_HTTP_CODE_FILE" 2>/dev/null
}

# Read session ID
mcp_session() {
  cat "$MCP_SESSION_FILE" 2>/dev/null
}

# Reset session state
mcp_reset() {
  > "$MCP_SESSION_FILE"
  > "$MCP_RESPONSE_FILE"
  > "$MCP_HTTP_CODE_FILE"
  echo "0" > "$MCP_REQUEST_ID_FILE"
}

# Cleanup on exit
_mcp_cleanup() {
  rm -rf "$MCP_STATE_DIR" 2>/dev/null
}
trap _mcp_cleanup EXIT
