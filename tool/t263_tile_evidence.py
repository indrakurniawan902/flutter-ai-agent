#!/usr/bin/env python3
"""T26.3 evidence driver: prove the Quick Settings tile toggle reports the
state the device ACTUALLY settled on, over a REAL bridge.

REQUIRES A REAL CONNECTED PHONE. The tile state is device-resident (Kotlin
behind a MethodChannel), so the bridge health must show `devices_routable == 1`
while the dart harness
(test/integration/t263_tile_toggle_bridge_test.dart) keeps a `flutter_client`
device routable. Without a phone this script prints the bridge health body and
exits non-zero -- it never fabricates a result. The host-JVM proof of the same
state logic is tool/run_kotlin_tile_tests.sh.

The driver:

  1. waits for the harness READY file (default /tmp/t263_harness_ready);
  2. polls /health until devices_routable == 1;
  3. MCP handshake (initialize -> notifications/initialized -> tools/list);
  4. resolves `manage_background_service` / `launch_system_setting` from the
     published manifest (the bridge may prefix them on collision);
  5. PHASE A (tile bound): reads the starting tile state, then runs SIX
     interleaved toggle/get pairs and asserts every toggle alternates and every
     get agrees with the toggle that preceded it;
  6. PHASE B (tile unbound): opens notification_listener, accessibility and
     app_details settings screens (these background the app, which unbinds the
     tile service in the card's repro), then runs SIX more interleaved pairs
     with the SAME assertions. This is the leg the pre-card code fails;
  7. prints the raw JSON of every call, the phase verdicts and
     `T263_RESULT=PASS|FAIL`, exiting non-zero on FAIL. A `tile_state_unchanged`
     toggle is a FAILURE: a toggle that did not move must never claim it did.

The device token belongs to the dart harness; this script never reads, prints,
logs or writes it.

Stdlib only, so the system python3 can run it.
"""

import http.client
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

HEALTH_URL = os.environ.get(
    "FLAMES_T263_HEALTH_URL", "http://127.0.0.1:8899/health"
)
MCP_HOST = os.environ.get("FLAMES_T263_MCP_HOST", "127.0.0.1")
MCP_PORT = int(os.environ.get("FLAMES_T263_MCP_PORT", "8899"))
MCP_PATH = "/mcp"
CALL_TIMEOUT_S = 60.0

READY_FILE = os.environ.get("FLAMES_T263_READY_FILE", "/tmp/t263_harness_ready")
READY_TIMEOUT_S = float(os.environ.get("FLAMES_T263_READY_TIMEOUT", "300"))
ROUTABLE_TIMEOUT_S = float(os.environ.get("FLAMES_T263_ROUTABLE_TIMEOUT", "30"))

BACKGROUND_TOOL = "manage_background_service"
SETTINGS_TOOL = "launch_system_setting"
PHASE_PAIRS = 6
SETTINGS_BEFORE_PHASE_B = ["notification_listener", "accessibility", "app_details"]


def die(code, message):
    print("T263 FAIL: %s" % message, file=sys.stderr)
    sys.exit(code)


def health():
    with urllib.request.urlopen(HEALTH_URL, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))


def wait_for_ready_file():
    deadline = time.time() + READY_TIMEOUT_S
    path = Path(READY_FILE)
    while time.time() < deadline:
        if path.exists():
            print("T263 ready file present: %s" % READY_FILE)
            return
        time.sleep(0.5)
    print(
        "T263 WARNING: ready file %s never appeared within %.0fs"
        % (READY_FILE, READY_TIMEOUT_S)
    )


def wait_for_routable_device():
    deadline = time.time() + ROUTABLE_TIMEOUT_S
    last = None
    while time.time() < deadline:
        try:
            body = health()
            last = body
            if body.get("devices_routable") == 1:
                print(
                    "T263 bridge routable: devices_connected=%s "
                    "devices_routable=%s tools_published=%s"
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
    print("T263 bridge health body: %s" % json.dumps(last, sort_keys=True))
    die(
        3,
        "no routable device within %.0fs -- a REAL connected phone running the "
        "t263 harness is required because the tile state is device-resident "
        "(health must show devices_routable=1); last health=%r"
        % (ROUTABLE_TIMEOUT_S, last),
    )


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
            try:
                raw = resp.read().decode("utf-8", errors="replace")
            except http.client.IncompleteRead as exc:
                raw = (exc.partial or b"").decode("utf-8", errors="replace")
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
        for line in reversed(raw.splitlines()):
            line = line.strip()
            if line.startswith("data:"):
                payload = line[len("data:"):].strip()
                if payload and payload != "[DONE]":
                    try:
                        return json.loads(payload)
                    except json.JSONDecodeError:
                        continue
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
        return parsed

    def notify(self, method, params=None):
        payload = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        status, raw = self._post(payload)
        if status >= 400:
            die(4, "MCP %s returned HTTP %s: %s" % (method, status, raw[:500]))


def flatten(result):
    """Flattens an MCP tools/call result into text (t261 helper)."""
    parts = []
    content = (result or {}).get("result", {}).get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
    if not parts:
        parts.append(json.dumps(result))
    return "\n".join(parts)


def resolve_tool_name(names, base):
    match = [n for n in names if n == base or n.endswith("_" + base)]
    return match[0] if match else None


def tool_payload(result):
    """Parses the JSON string a device tool returned inside the MCP envelope."""
    text = flatten(result)
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return {"raw": text}
    if isinstance(parsed, dict):
        return parsed
    return {"raw": text}


def call_tool(client, name, arguments, label):
    print("T263 CALL %s (%s) arguments=%s"
          % (label, name, json.dumps(arguments, sort_keys=True)))
    result = client.request(
        "tools/call", {"name": name, "arguments": arguments}
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return tool_payload(result)


def get_tile_state(client, name, label):
    payload = call_tool(client, name, {"action": "get_tile_state"}, label)
    state = payload.get("tile_state")
    if state not in ("active", "inactive", "unavailable"):
        die(5, "%s returned no usable tile_state: %r" % (label, payload))
    return state


def toggle_tile_state(client, name, label):
    payload = call_tool(client, name, {"action": "toggle_tile_state"}, label)
    status = payload.get("status")
    if status == "tile_state_unchanged":
        die(
            5,
            "%s: toggle did not move the tile (reason=%r, state=%r) -- a "
            "toggle that did not take must never claim it did"
            % (label, payload.get("reason"), payload.get("tile_state")),
        )
    if status != "tile_state_toggled":
        die(5, "%s returned unexpected status: %r" % (label, payload))
    state = payload.get("tile_state")
    if state not in ("active", "inactive"):
        die(5, "%s returned no usable tile_state: %r" % (label, payload))
    return state


def run_phase(client, tool_name, phase_label, start_state):
    """Runs six interleaved toggle/get pairs; returns (passed, states)."""
    expected = "inactive" if start_state == "active" else "active"
    observed = []
    passed = True
    for index in range(1, PHASE_PAIRS + 1):
        toggled = toggle_tile_state(
            client, tool_name, "%s pair %d toggle" % (phase_label, index)
        )
        read_back = get_tile_state(
            client, tool_name, "%s pair %d get" % (phase_label, index)
        )
        print(
            "T263 %s pair %d: expected=%s toggle=%s get=%s"
            % (phase_label, index, expected, toggled, read_back)
        )
        if toggled != expected:
            print(
                "T263 %s pair %d MISMATCH: toggle=%s expected=%s"
                % (phase_label, index, toggled, expected)
            )
            passed = False
        if read_back != toggled:
            print(
                "T263 %s pair %d DISAGREEMENT: get=%s but the toggle that "
                "preceded it reported=%s" % (phase_label, index, read_back, toggled)
            )
            passed = False
        observed.append(toggled)
        expected = "inactive" if toggled == "active" else "active"
    print("T263 %s sequence: %s" % (phase_label, observed))
    return passed, observed


def main():
    wait_for_ready_file()
    wait_for_routable_device()

    body = health()
    print(
        "T263 BRIDGE devices_connected=%s devices_routable=%s tools_published=%s"
        % (
            body.get("devices_connected"),
            body.get("devices_routable"),
            body.get("tools_published"),
        )
    )

    client = McpClient()
    client.request(
        "initialize",
        {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "t263-bridge-evidence", "version": "1.0.0"},
        },
    )
    client.notify("notifications/initialized")
    tools = client.request("tools/list", {})
    entries = tools.get("result", {}).get("tools", [])
    names = [e["name"] for e in entries if isinstance(e, dict) and "name" in e]
    print("T263 MANIFEST tool_count=%d" % len(names))

    background_name = resolve_tool_name(names, BACKGROUND_TOOL)
    settings_name = resolve_tool_name(names, SETTINGS_TOOL)
    if not background_name or not settings_name:
        die(
            4,
            "tools missing from manifest; background=%r settings=%r names=%s"
            % (background_name, settings_name, json.dumps(sorted(names))),
        )
    print(
        "T263 RESOLVED background=%s settings=%s"
        % (background_name, settings_name)
    )

    # PHASE A: the tile is bound; six pairs must alternate.
    start_state = get_tile_state(client, background_name, "phase A start")
    print("T263 PHASE_A starting tile_state=%s" % start_state)
    phase_a_passed, _ = run_phase(
        client, background_name, "PHASE_A", start_state
    )

    # PHASE B: open the three settings screens (backgrounds the app, which
    # unbinds the tile service), then six more pairs must alternate.
    for setting in SETTINGS_BEFORE_PHASE_B:
        call_tool(
            client,
            settings_name,
            {"setting_type": setting},
            "phase B background via %s" % setting,
        )
    phase_b_start = get_tile_state(client, background_name, "phase B start")
    print("T263 PHASE_B starting tile_state=%s" % phase_b_start)
    phase_b_passed, _ = run_phase(
        client, background_name, "PHASE_B", phase_b_start
    )

    print("PHASE_A=%s" % ("PASS" if phase_a_passed else "FAIL"))
    print("PHASE_B=%s" % ("PASS" if phase_b_passed else "FAIL"))
    overall = phase_a_passed and phase_b_passed
    print("T263_RESULT=%s" % ("PASS" if overall else "FAIL"))
    return 0 if overall else 1


if __name__ == "__main__":
    sys.exit(main())
