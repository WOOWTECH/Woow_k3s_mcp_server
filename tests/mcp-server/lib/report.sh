#!/usr/bin/env bash
generate_html_report() {
  local log="$1" outfile="$2"
  local total=0 pass=0 fail=0 skip=0
  while IFS='|' read -r status name detail; do
    ((total++))
    case "$status" in PASS) ((pass++));; FAIL) ((fail++));; SKIP) ((skip++));; esac
  done < "$log"

  cat > "$outfile" << HTMLEOF
<!DOCTYPE html><html><head><meta charset="utf-8"><title>K3s MCP Server Test Report</title>
<style>
body{font-family:system-ui;max-width:900px;margin:40px auto;padding:0 20px;background:#0d1117;color:#c9d1d9}
h1{color:#58a6ff}.summary{display:flex;gap:20px;margin:20px 0}
.card{padding:16px 24px;border-radius:8px;font-size:24px;font-weight:bold}
.card.pass{background:#0d2818;color:#3fb950}.card.fail{background:#2d1117;color:#f85149}
.card.skip{background:#1c1d21;color:#8b949e}.card.total{background:#161b22;color:#58a6ff}
table{width:100%;border-collapse:collapse;margin-top:20px}
th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #21262d}
th{background:#161b22}.s-pass{color:#3fb950}.s-fail{color:#f85149}.s-skip{color:#8b949e}
</style></head><body>
<h1>K3s MCP Server — Enterprise Test Report</h1>
<p>Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")</p>
<div class="summary">
<div class="card total">Total: ${total}</div>
<div class="card pass">Pass: ${pass}</div>
<div class="card fail">Fail: ${fail}</div>
<div class="card skip">Skip: ${skip}</div>
</div><table><tr><th>Status</th><th>Test</th><th>Detail</th></tr>
HTMLEOF
  while IFS='|' read -r status name detail; do
    local cls="s-$(echo "$status" | tr 'A-Z' 'a-z')"
    echo "<tr><td class=\"${cls}\">${status}</td><td>${name}</td><td>${detail:-—}</td></tr>" >> "$outfile"
  done < "$log"
  echo "</table></body></html>" >> "$outfile"
}
