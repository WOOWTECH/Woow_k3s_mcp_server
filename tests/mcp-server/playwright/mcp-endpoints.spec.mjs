import { test, expect } from '@playwright/test';

// Use external HTTPS URL (browser can't reach ClusterIP)
// Set MCP_TOKEN before running this spec - never hardcode a real token here.
//   export MCP_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(16))")
const MCP_TOKEN = process.env.MCP_TOKEN;
if (!MCP_TOKEN) {
  throw new Error('MCP_TOKEN env var is required (see comment above)');
}
const TOKEN_PATH = `/private_${MCP_TOKEN}`;
const EXTERNAL_HOST = process.env.MCP_EXTERNAL_HOST || 'https://k8s-mcp.woowtech.io';
const BASE_URL = `${EXTERNAL_HOST}${TOKEN_PATH}`;

test.describe('MCP HTTP Endpoints - Browser Context', () => {

  // P.1 fetch /health returns "ok"
  test('P.1 - fetch /health returns ok', async ({ page }) => {
    // Use page.request (Playwright API context) instead of browser fetch
    const resp = await page.request.get(`${EXTERNAL_HOST}/health`);
    expect(resp.status()).toBe(200);
    expect(await resp.text()).toBe('ok');
  });

  // P.2 fetch wrong token returns 403
  test('P.2 - fetch wrong token returns 403', async ({ page }) => {
    const resp = await page.request.post(`${EXTERNAL_HOST}/private_WRONGTOKEN/mcp`);
    expect(resp.status()).toBe(403);
  });

  // P.3 POST /mcp initialize via fetch
  test('P.3 - POST /mcp initialize via fetch', async ({ page }) => {
    const resp = await page.request.post(`${BASE_URL}/mcp`, {
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream, application/json',
      },
      data: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: {
          protocolVersion: '2025-03-26',
          capabilities: {},
          clientInfo: { name: 'playwright-test', version: '1.0' },
        },
      }),
    });

    expect(resp.status()).toBe(200);
    const text = await resp.text();
    const sessionId = resp.headers()['mcp-session-id'];
    // Parse SSE data lines
    const dataLines = text.split('\n').filter(l => l.startsWith('data: ')).map(l => l.slice(6));
    expect(dataLines.length).toBeGreaterThanOrEqual(1);
    const parsed = JSON.parse(dataLines[0]);
    expect(parsed.result.protocolVersion).toBeTruthy();
  });

  // P.4 tools/list returns tools
  test('P.4 - tools/list returns 20+ tools', async ({ page }) => {
    // Initialize first
    const initResp = await page.request.post(`${BASE_URL}/mcp`, {
      headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream, application/json' },
      data: JSON.stringify({
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'pw-test', version: '1.0' } },
      }),
    });
    const sessionId = initResp.headers()['mcp-session-id'];

    // List tools
    const headers = { 'Content-Type': 'application/json', 'Accept': 'text/event-stream, application/json' };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;

    const listResp = await page.request.post(`${BASE_URL}/mcp`, {
      headers,
      data: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
    });

    expect(listResp.status()).toBe(200);
    const text = await listResp.text();
    const dataLines = text.split('\n').filter(l => l.startsWith('data: ')).map(l => l.slice(6));
    let toolCount = 0;
    for (const line of dataLines) {
      const parsed = JSON.parse(line);
      if (parsed.result?.tools) toolCount = parsed.result.tools.length;
    }
    expect(toolCount).toBeGreaterThanOrEqual(20);
  });

  // P.5 SSE response format validation
  test('P.5 - SSE response format validation', async ({ page }) => {
    const resp = await page.request.post(`${BASE_URL}/mcp`, {
      headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream, application/json' },
      data: JSON.stringify({
        jsonrpc: '2.0', id: 1, method: 'initialize',
        params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'sse-test', version: '1.0' } },
      }),
    });

    const contentType = resp.headers()['content-type'];
    expect(contentType).toContain('text/event-stream');

    const text = await resp.text();
    expect(text).toContain('event:');
    expect(text).toContain('data:');

    const dataLines = text.split('\n').filter(l => l.startsWith('data: '));
    expect(dataLines.length).toBeGreaterThanOrEqual(1);
    const parsed = JSON.parse(dataLines[0].slice(6));
    expect(parsed.jsonrpc).toBe('2.0');
  });

  // P.6 Full MCP session lifecycle
  test('P.6 - Full session: init -> list -> call -> verify', async ({ page }) => {
    const makeRequest = async (sessionId, body) => {
      const headers = { 'Content-Type': 'application/json', 'Accept': 'text/event-stream, application/json' };
      if (sessionId) headers['Mcp-Session-Id'] = sessionId;
      const resp = await page.request.post(`${BASE_URL}/mcp`, { headers, data: JSON.stringify(body) });
      const text = await resp.text();
      const dataLines = text.split('\n').filter(l => l.startsWith('data: ')).map(l => l.slice(6));
      let parsed = null;
      for (const line of dataLines) {
        try { parsed = JSON.parse(line); } catch {}
      }
      return { status: resp.status(), sessionId: resp.headers()['mcp-session-id'], parsed };
    };

    // Step 1: Initialize
    const init = await makeRequest(null, {
      jsonrpc: '2.0', id: 1, method: 'initialize',
      params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'lifecycle-test', version: '1.0' } },
    });
    expect(init.status).toBe(200);
    expect(init.parsed.result.protocolVersion).toBeTruthy();

    // Step 2: List tools
    const list = await makeRequest(init.sessionId, { jsonrpc: '2.0', id: 2, method: 'tools/list' });
    expect(list.parsed.result.tools.length).toBeGreaterThanOrEqual(20);

    // Step 3: Call a tool
    const call = await makeRequest(init.sessionId, {
      jsonrpc: '2.0', id: 3, method: 'tools/call',
      params: { name: 'namespaces_list', arguments: {} },
    });
    expect(call.parsed.result).toBeTruthy();
    expect(JSON.stringify(call.parsed)).toContain('mcp-system');
  });
});
