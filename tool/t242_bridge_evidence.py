#!/usr/bin/env python3
"""T24.2 bounded-executor evidence driver.

Drives the REAL device bridge over MCP (streamable HTTP JSON-RPC) while the
dart harness (test/integration/t242_tool_timeout_bridge_test.dart) keeps a
`flutter_client` device routable, then calls the two tools the card was filed
for and prints the raw JSON-RPC results verbatim -- that output IS the evidence:

  1. wait for the harness READY file (default /tmp/t242_harness_ready);
  2. poll /health until devices_routable == 1;
  3. MCP handshake (initialize -> notifications/initialized -> tools/list);
  4. call `get_health_data {"metric":"steps"}` and `export_document_pdf`;
  5. assert NEITHER call reports `device_timeout`, and that both settle well
     under the bridge's 30s device budget.

The harness injects the Android-14 silent-read condition (readRecords returns a
Future that never settles), which is the pathological path that used to hang
until the bridge's 30s budget expired and then dropped the socket (4001).

Stdlib only, so the system python3 can run it.
"""

import http.client
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

HEALTH_URL = "http://127.0.0.1:8899/health"
MCP_HOST = "127.0.0.1"
MCP_PORT = 8899
MCP_PATH = "/mcp"

READY_FILE = os.environ.get("FLAMES_T242_READY_FILE", "/tmp/t242_harness_ready")
# The harness is a `flutter test` run, so the first launch can spend well over a
# minute compiling before it reaches the socket. Allow a generous window.
READY_TIMEOUT_S = float(os.environ.get("FLAMES_T242_READY_TIMEOUT", "300"))
ROUTABLE_TIMEOUT_S = 60.0
# Generous client budget: the point is that the TOOL answers, not that the
# client gives up first. The bridge's own device budget is 30s.
CALL_TIMEOUT_S = 55.0
DEVICE_BUDGET_S = 30.0

HEALTH_ARGS = {"metric": "steps"}
PDF_ARGS = {
    "title": "T24.2 verify",
    "markdownContent": "# T24.2\n\nBound executor verification.\n",
}


def die(code, message):
    print("T242 FAIL: %s" % message, file=sys.stderr)
    sys.exit(code)


def wait_for_ready_file():
    deadline = time.time() + READY_TIMEOUT_S
    path = Path(READY_FILE)
    while time.time() < deadline:
        if path.exists():
            print("T242 ready file present: %s" % READY_FILE)
            return
        time.sleep(0.5)
    die(2, "ready file %s never appeared within %.0fs" % (READY_FILE, READY_TIMEOUT_S))


def wait_for_routable_device():
    deadline = time.time() + ROUTABLE_TIMEOUT_S
    last = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(HEALTH_URL, timeout=5) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            last = body
            if body.get("devices_routable") == 1:
                print(
                    "T242 bridge routable: devices_connected=%s devices_routable=%s "
                    "tools_published=%s"
                    % (
                        body.get("devices_connected"),
                        body.get("devices_routable"),
                        body.get("tools_published"),
                    )
                )
                return
        except Exception as exc:  # noqa: BLE001 - retry until deadline
            last = str(exc)
        time.sleep(0.5)
    die(3, "no routable device within %.0fs; last health=%r" % (ROUTABLE_TIMEOUT_S, last))


class McpClient:
    """Minimal streamable-HTTP MCP client (plain JSON and SSE responses)."""

    def __init__(self):
        self.session_id = None
        self.next_id = 1

    def _post(self, payload):
        conn = http.client.HTTPConnection(MCP_HOST, MCP_PORT, timeout=CALL_TIMEOUT_S)
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        try:
            conn.request("POST", MCP_PATH, body=json.dumps(payload), headers=headers)
            resp = conn.getresponse()
            raw = resp.read().decode("utf-8", errors="replace")
            sid = resp.getheader("Mcp-Session-Id")
            status = resp.status
        finally:
            conn.close()
        if sid:
            self.session_id = sid
        return status, raw

    @staticmethod
    def _parse(raw):
        raw = raw.strip()
        if not raw:
            return None
        if raw.startswith("{") or raw.startswith("["):
            return json.loads(raw)
        payloads = []
        for line in raw.splitlines():
            line = line.strip()
            if line.startswith("data:"):
                payloads.append(line[len("data:"):].strip())
        for payload in reversed(payloads):
            if not payload or payload == "[DONE]":
                continue
            try:
                return json.loads(payload)
            except json.JSONDecodeError:
                continue
        if not payloads:
            return json.loads(raw)
        return None

    def request(self, method, params=None):
        payload = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            payload["params"] = params
        self.next_id += 1
        status, raw = self._post(payload)
        if status >= 400:
            die(4, "MCP %s returned HTTP %s: %s" % (method, status, raw[:500]))
        parsed = self._parse(raw)
        if parsed is None:
            die(4, "MCP %s returned unparseable body: %r" % (method, raw[:500]))
        if not isinstance(parsed, dict):
            die(4, "MCP %s returned non-object body: %r" % (method, raw[:500]))
        if "error" in parsed:
            die(4, "MCP %s error: %s" % (method, json.dumps(parsed["error"])))
        return parsed

    def notify(self, method, params=None):
        payload = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        status, raw = self._post(payload)
        if status >= 400:
            die(4, "MCP %s returned HTTP %s: %s" % (method, status, raw[:500]))


def resolve_tool_name(names, base):
    if base in names:
        return base
    prefixed = "device_%s" % base
    if prefixed in names:
        return prefixed
    matches = [n for n in names if n == base or n.endswith("_%s" % base)]
    if matches:
        return matches[0]
    return None


def payload_text(result):
    """Flattens an MCP tools/call result into text."""
    parts = []
    content = result.get("result", {}).get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
    if not parts:
        parts.append(json.dumps(result))
    return "\n".join(parts)


def tool_names(tools_result):
    """Extracts the published tool names from a tools/list result."""
    tool_list = tools_result.get("result", {}).get("tools", [])
    names = []
    for entry in tool_list:
        if isinstance(entry, dict):
            name = entry.get("name")
            if isinstance(name, str):
                names.append(name)
    return names


def call_and_time(client, name, arguments, label):
    started = time.time()
    result = client.request("tools/call", {"name": name, "arguments": arguments})
    elapsed = time.time() - started
    print("T242 %s raw JSON-RPC result (%s), elapsed=%.2fs:" % (label, name, elapsed))
    print(json.dumps(result, indent=2, sort_keys=True))
    text = payload_text(result)
    if "device_timeout" in text:
        die(5, "%s returned device_timeout -- the hang is NOT fixed" % label)
    if elapsed >= DEVICE_BUDGET_S:
        die(5, "%s took %.2fs, at/over the %.0fs device budget" % (label, elapsed, DEVICE_BUDGET_S))
    print("T242 %s OK: no device_timeout, elapsed=%.2fs" % (label, elapsed))
    return text, elapsed


def main():
    wait_for_ready_file()
    wait_for_routable_device()

    client = McpClient()
    init = client.request(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "t242-bridge-evidence", "version": "1.0.0"},
        },
    )
    print("T242 MCP initialize raw JSON-RPC result:")
    print(json.dumps(init, indent=2, sort_keys=True))
    client.notify("notifications/initialized")

    tools = client.request("tools/list", {})
    names = tool_names(tools)
    print("T242 manifest tool names: %s" % json.dumps(sorted(names)))

    health_name = resolve_tool_name(names, "get_health_data")
    pdf_name = resolve_tool_name(names, "export_document_pdf")
    if not health_name or not pdf_name:
        die(
            4,
            "tools missing from manifest; health=%r pdf=%r names=%s"
            % (health_name, pdf_name, json.dumps(sorted(names))),
        )
    print("T242 resolved tools: health=%s pdf=%s" % (health_name, pdf_name))

    health_text, health_s = call_and_time(client, health_name, HEALTH_ARGS, "get_health_data")
    pdf_text, pdf_s = call_and_time(client, pdf_name, PDF_ARGS, "export_document_pdf")

    # Both must be structured answers, not silence.
    if "health_" not in health_text and "steps" not in health_text:
        die(6, "get_health_data produced no structured health payload: %r" % health_text[:300])
    if "documents/doc_" not in pdf_text and "Document exported" not in pdf_text:
        die(6, "export_document_pdf produced no saved path: %r" % pdf_text[:300])

    print(
        "T242 PASS: both tools answered without device_timeout "
        "(get_health_data=%.2fs, export_document_pdf=%.2fs, device budget=%.0fs)"
        % (health_s, pdf_s, DEVICE_BUDGET_S)
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
