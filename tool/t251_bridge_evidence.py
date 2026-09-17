#!/usr/bin/env python3
"""T25.1 geofence -> runPrompt evidence driver.

Drives the REAL device bridge over MCP (streamable HTTP JSON-RPC) while the
dart harness (test/integration/t251_geofence_dispatch_bridge_test.dart) keeps
a `flutter_client` device routable:

  1. wait for the harness READY file (default /tmp/t251_harness_ready);
  2. poll /health until devices_routable == 1;
  3. MCP handshake (initialize -> notifications/initialized -> tools/list);
  4. resolve the geofence tool names from the published manifest (the bridge
     may expose them as device_<name> on collision);
  5. call register_geofence for region t251 bound to runPrompt;
  6. call trigger_ambient_check at the region center;
  7. print each raw JSON-RPC result verbatim (that output IS the evidence);
  8. exit 0 only when dispatchedActions contains an entry with
     action == "runPrompt" and executed == true.

The device token at ~/flames_flutter_client_token.txt belongs to the dart
harness; this script never reads, prints, logs or writes it.

Stdlib only, so the system python3 can run it.
"""

import http.client
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

HEALTH_URL = "http://127.0.0.1:8899/health"
MCP_HOST = "127.0.0.1"
MCP_PORT = 8899
MCP_PATH = "/mcp"

READY_FILE = os.environ.get("FLAMES_T251_READY_FILE", "/tmp/t251_harness_ready")
READY_TIMEOUT_S = 30.0
ROUTABLE_TIMEOUT_S = 30.0
CALL_TIMEOUT_S = 30.0

REGION_ARGS = {
    "id": "t251",
    "latitude": -6.2,
    "longitude": 106.8,
    "radiusMeters": 100,
    "action": "runPrompt",
    "actionPayload": "T251 evidence prompt",
    "actionOn": "enter",
}
CHECK_ARGS = {"latitude": -6.2, "longitude": 106.8}


def die(code, message):
    print("T251 FAIL: %s" % message, file=sys.stderr)
    sys.exit(code)


def wait_for_ready_file():
    deadline = time.time() + READY_TIMEOUT_S
    path = Path(READY_FILE)
    while time.time() < deadline:
        if path.exists():
            print("T251 ready file present: %s" % READY_FILE)
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
                    "T251 bridge routable: devices_connected=%s devices_routable=%s tools_published=%s"
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
        # SSE frames may open with `event:`, `id:` or `retry:` lines before the
        # payload, so scan every line for a `data:` field instead of assuming
        # the body starts with one.
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


def call_tool(client, name, arguments, label):
    result = client.request(
        "tools/call", {"name": name, "arguments": arguments}
    )
    print("T251 %s raw JSON-RPC result (%s):" % (label, name))
    print(json.dumps(result, indent=2, sort_keys=True))
    return result


def result_payload_text(result):
    """Flattens an MCP tools/call result into text for structural checks."""
    parts = []
    content = result.get("result", {}).get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
    if not parts:
        parts.append(json.dumps(result))
    return "\n".join(parts)


def find_dispatch(payload_text):
    """Finds a dispatchedActions entry with action=runPrompt, executed=true."""
    candidates = []
    try:
        decoded = json.loads(payload_text)
    except json.JSONDecodeError:
        decoded = None
    if decoded is not None:
        candidates.append(decoded)
    for match in re.finditer(r"\{.*\}", payload_text, re.DOTALL):
        try:
            candidates.append(json.loads(match.group(0)))
        except json.JSONDecodeError:
            continue
    for candidate in candidates:
        stack = [candidate]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                actions = node.get("dispatchedActions")
                if isinstance(actions, list):
                    for entry in actions:
                        if (
                            isinstance(entry, dict)
                            and entry.get("action") == "runPrompt"
                            and entry.get("executed") is True
                        ):
                            return entry
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
    return None


def main():
    wait_for_ready_file()
    wait_for_routable_device()

    client = McpClient()
    init = client.request(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "t251-bridge-evidence", "version": "1.0.0"},
        },
    )
    print("T251 MCP initialize raw JSON-RPC result:")
    print(json.dumps(init, indent=2, sort_keys=True))
    client.notify("notifications/initialized")

    tools = client.request("tools/list", {})
    tool_list = tools.get("result", {}).get("tools", [])
    names = [t.get("name") for t in tool_list if isinstance(t, dict)]
    print("T251 manifest tool names: %s" % json.dumps(sorted(names)))

    register_name = resolve_tool_name(names, "register_geofence")
    trigger_name = resolve_tool_name(names, "trigger_ambient_check")
    if not register_name or not trigger_name:
        die(
            4,
            "geofence tools missing from manifest; register=%r trigger=%r names=%s"
            % (register_name, trigger_name, json.dumps(sorted(names))),
        )
    print("T251 resolved tools: register=%s trigger=%s" % (register_name, trigger_name))

    register_result = call_tool(client, register_name, REGION_ARGS, "register_geofence")
    trigger_result = call_tool(client, trigger_name, CHECK_ARGS, "trigger_ambient_check")

    dispatch = find_dispatch(result_payload_text(trigger_result))
    if dispatch is None:
        die(
            5,
            "trigger result has no dispatchedActions entry with "
            "action=runPrompt and executed=true",
        )

    print("T251 dispatch entry: %s" % json.dumps(dispatch, sort_keys=True))
    print("T251 PASS: runPrompt action executed over the real bridge")
    sys.exit(0)


if __name__ == "__main__":
    main()
