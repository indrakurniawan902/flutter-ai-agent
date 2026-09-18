#!/usr/bin/env python3
"""T26.2 health-read error contract evidence driver.

Drives the REAL device bridge over MCP (streamable HTTP JSON-RPC) while the
dart harness (test/integration/t262_health_read_bridge_test.dart) keeps a
`t262_harness` device routable, then calls `get_health_data` three times and
prints every raw JSON-RPC result verbatim -- that output IS the evidence:

  1. wait for the harness READY file (default build/t262_harness_ready);
  2. poll /health until devices_routable == 1;
  3. MCP handshake (initialize -> notifications/initialized -> tools/list);
  4. call `get_health_data` for each of the three cases below;
  5. assert the platform error is surfaced in `detail`, the partial success
     still carries summary.total, and an omitted metric names the argument;
  6. exit non-zero unless all three assertions hold.

ENCODING (one bridge run, three cases; the harness keys its fake wrapper off
the requested range and prints the same legend):
  endDate year 2001 -> platform-error map      (health_platform_error)
  endDate year 2002 -> partial-success payload (summary.total=1234,
                       records_unavailable=true)
  anything else     -> plain empty success payload

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

HEALTH_URL = os.environ.get("FLAMES_T262_HEALTH_URL", "http://127.0.0.1:8899/health")
MCP_HOST = "127.0.0.1"
MCP_PORT = int(os.environ.get("FLAMES_T262_MCP_PORT", "8899"))
MCP_PATH = "/mcp"

REPO_ROOT = Path(__file__).resolve().parents[1]
READY_FILE = os.environ.get(
    "FLAMES_T262_READY_FILE", str(REPO_ROOT / "build" / "t262_harness_ready")
)
# The harness is a `flutter test` run, so the first launch can spend well over a
# minute compiling before it reaches the socket. Allow a generous window.
READY_TIMEOUT_S = float(os.environ.get("FLAMES_T262_READY_TIMEOUT", "1200"))
ROUTABLE_TIMEOUT_S = 60.0
CALL_TIMEOUT_S = 55.0

ENCODING = (
    "endDate year 2001 -> platform-error map; "
    "endDate year 2002 -> partial success (summary.total=1234, "
    "records_unavailable=true); anything else -> empty success"
)

ERROR_ARGS = {"metric": "steps", "endDate": "2001-06-15T00:00:00Z"}
PARTIAL_ARGS = {"metric": "steps", "endDate": "2002-06-15T00:00:00Z"}
OMITTED_ARGS = {}


def die(code, message):
    print("T262 FAIL: %s" % message, file=sys.stderr)
    sys.exit(code)


def wait_for_ready_file():
    deadline = time.time() + READY_TIMEOUT_S
    path = Path(READY_FILE)
    while time.time() < deadline:
        if path.exists():
            print("T262 ready file present: %s" % READY_FILE)
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
                    "T262 bridge routable: devices_connected=%s devices_routable=%s "
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


def decode_payload(result):
    """Parses the tool result text as JSON; None when it is not JSON."""
    try:
        return json.loads(payload_text(result))
    except json.JSONDecodeError:
        return None


def find_key(node, key):
    """Depth-first search for `key` anywhere in a decoded JSON structure."""
    if isinstance(node, dict):
        if key in node:
            return node[key]
        for value in node.values():
            found = find_key(value, key)
            if found is not None:
                return found
    elif isinstance(node, list):
        for item in node:
            found = find_key(item, key)
            if found is not None:
                return found
    return None


def extract_detail(result):
    """Returns the bridge's `detail` string for a rejected call."""
    text = payload_text(result)
    decoded = decode_payload(result)
    if decoded is not None:
        detail = find_key(decoded, "detail")
        if isinstance(detail, str) and detail:
            return detail
    match = re.search(r'"detail"\s*:\s*"((?:[^"\\]|\\.)*)"', text)
    if match:
        try:
            return json.loads('"%s"' % match.group(1))
        except json.JSONDecodeError:
            return match.group(1)
    return text


def is_rejected(result):
    return "tool_rejected" in payload_text(result)


def call_tool(client, name, arguments, label):
    started = time.time()
    result = client.request("tools/call", {"name": name, "arguments": arguments})
    elapsed = time.time() - started
    print("T262 %s raw JSON-RPC result (%s), elapsed=%.2fs:" % (label, name, elapsed))
    print(json.dumps(result, indent=2, sort_keys=True))
    return result


def assert_platform_error(result):
    if not is_rejected(result):
        die(5, "case 1 is not tool_rejected: %s" % payload_text(result)[:300])
    detail = extract_detail(result)
    if "health_platform_error" not in detail:
        die(5, "case 1 detail lacks health_platform_error: %r" % detail)
    if "IllegalArgumentException" not in detail:
        die(5, "case 1 detail lacks IllegalArgumentException: %r" % detail)
    if "no response from Health Connect" in detail:
        die(5, "case 1 detail still carries the blanket text: %r" % detail)
    print("T262 case 1 OK: platform error surfaced, detail=%r" % detail)


def assert_partial_success(result):
    if is_rejected(result):
        die(5, "case 2 was rejected: detail=%r" % extract_detail(result))
    decoded = decode_payload(result)
    if decoded is None:
        die(5, "case 2 payload is not JSON: %r" % payload_text(result)[:300])
    summary = find_key(decoded, "summary")
    if not isinstance(summary, dict) or summary.get("total") != 1234:
        die(5, "case 2 summary.total is not 1234: summary=%r" % (summary,))
    if find_key(decoded, "records_unavailable") is not True:
        die(5, "case 2 lacks records_unavailable=true: %s" % payload_text(result)[:300])
    print(
        "T262 case 2 OK: summary.total=1234 with records_unavailable=true, "
        "records_error=%r" % (find_key(decoded, "records_error"),)
    )


def assert_omitted_metric(result):
    if not is_rejected(result):
        die(5, "case 3 is not tool_rejected: %s" % payload_text(result)[:300])
    detail = extract_detail(result)
    if "requires 'metric'" not in detail:
        die(5, "case 3 detail lacks \"requires 'metric'\": %r" % detail)
    if "steps" not in detail or "weight" not in detail:
        die(5, "case 3 detail lacks the allowed values: %r" % detail)
    if re.search(r"unsupported_metric:\s*\(", detail):
        die(5, "case 3 detail matches the blank-name regression shape: %r" % detail)
    if "  (" in detail:
        die(5, "case 3 detail has the blank-name double space: %r" % detail)
    print("T262 case 3 OK: omitted metric names the argument, detail=%r" % detail)


def main():
    print("T262 encoding: %s" % ENCODING)
    wait_for_ready_file()
    wait_for_routable_device()

    client = McpClient()
    init = client.request(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "t262-bridge-evidence", "version": "1.0.0"},
        },
    )
    print("T262 MCP initialize raw JSON-RPC result:")
    print(json.dumps(init, indent=2, sort_keys=True))
    client.notify("notifications/initialized")

    tools = client.request("tools/list", {})
    names = tool_names(tools)
    print("T262 manifest tool names: %s" % json.dumps(sorted(names)))

    health_name = resolve_tool_name(names, "get_health_data")
    if not health_name:
        die(4, "get_health_data missing from manifest; names=%s" % json.dumps(sorted(names)))
    print("T262 resolved tool: get_health_data=%s" % health_name)

    assert_platform_error(call_tool(client, health_name, ERROR_ARGS, "case1_platform_error"))
    assert_partial_success(call_tool(client, health_name, PARTIAL_ARGS, "case2_partial_success"))
    assert_omitted_metric(call_tool(client, health_name, OMITTED_ARGS, "case3_omitted_metric"))

    print("T262 PASS: platform error surfaced, partial summary preserved, "
          "omitted metric names the argument")
    sys.exit(0)


if __name__ == "__main__":
    main()
