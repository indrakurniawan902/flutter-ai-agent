#!/usr/bin/env python3
"""T26.1 evidence driver: call the two NFC tools over the REAL bridge and print
the raw JSON-RPC results + elapsed time.

Before the fix both must answer with the REGISTRY bound
(`tool_timeout: <name> did not answer within 10s`). After the fix both must
answer with the DEVICE's own window message (`NFC scan timed out`) after the
full 20s card-presentation window.

Stdlib only. Never prints any token.
"""
import http.client
import json
import os
import sys
import time

HOST = os.environ.get("FLAMES_T261_MCP_HOST", "127.0.0.1")
PORT = int(os.environ.get("FLAMES_T261_MCP_PORT", "8899"))
PATH = "/mcp"
CALL_TIMEOUT_S = 60.0
HEALTH_URL = os.environ.get(
    "FLAMES_T261_HEALTH_URL", "http://127.0.0.1:8899/health"
)


class McpClient:
    def __init__(self):
        self.session_id = None
        self.next_id = 1

    def _post(self, payload):
        conn = http.client.HTTPConnection(HOST, PORT, timeout=CALL_TIMEOUT_S)
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        try:
            conn.request("POST", PATH, body=json.dumps(payload), headers=headers)
            resp = conn.getresponse()
            try:
                raw = resp.read().decode("utf-8", errors="replace")
            except http.client.IncompleteRead as exc:
                # A long device call can outlive the chunked stream; keep what
                # arrived instead of losing the whole response.
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
        return status, self._parse(raw), raw

    def notify(self, method, params=None):
        payload = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        return self._post(payload)


def flatten(result):
    parts = []
    content = (result or {}).get("result", {}).get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
    if not parts:
        parts.append(json.dumps(result))
    return "\n".join(parts)


def health():
    import urllib.request
    with urllib.request.urlopen(HEALTH_URL, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))


READY_FILE = os.environ.get("FLAMES_T261_READY_FILE", "/tmp/t261_harness_ready")
READY_TIMEOUT_S = float(os.environ.get("FLAMES_T261_READY_TIMEOUT", "300"))
ROUTABLE_TIMEOUT_S = float(os.environ.get("FLAMES_T261_ROUTABLE_TIMEOUT", "60"))


def wait_for_ready_file():
    from pathlib import Path

    deadline = time.time() + READY_TIMEOUT_S
    path = Path(READY_FILE)
    while time.time() < deadline:
        if path.exists():
            print("T261 ready file present: %s" % READY_FILE)
            return
        time.sleep(0.5)
    print("T261 WARNING: ready file %s never appeared within %.0fs"
          % (READY_FILE, READY_TIMEOUT_S))


def wait_for_routable_device():
    deadline = time.time() + ROUTABLE_TIMEOUT_S
    last = None
    while time.time() < deadline:
        try:
            body = health()
            last = body
            if body.get("devices_routable") == 1:
                return
        except Exception as exc:  # noqa: BLE001 - retry until deadline
            last = str(exc)
        time.sleep(0.5)
    print("T261 WARNING: no routable device within %.0fs; last health=%r"
          % (ROUTABLE_TIMEOUT_S, last))


def main():
    wait_for_ready_file()
    wait_for_routable_device()
    body = health()
    print("BRIDGE devices_connected=%s devices_routable=%s tools_published=%s"
          % (body.get("devices_connected"), body.get("devices_routable"),
             body.get("tools_published")))

    client = McpClient()
    client.request("initialize", {
        "protocolVersion": "2024-11-05", "capabilities": {},
        "clientInfo": {"name": "t261-bridge-evidence", "version": "1.0.0"}})
    client.notify("notifications/initialized")
    _, tools, _ = client.request("tools/list", {})
    entries = tools.get("result", {}).get("tools", [])
    names = [e["name"] for e in entries]
    print("MANIFEST tool_count=%d" % len(names))

    wanted = ["nfc_read_tag", "nfc_read_emoney_balance"]
    resolved = []
    for want in wanted:
        match = [n for n in names if n == want or n.endswith("_" + want)]
        resolved.append(match[0] if match else None)
    print("RESOLVED %s" % json.dumps(dict(zip(wanted, resolved))))

    results = {}
    for want, name in zip(wanted, resolved):
        if not name:
            print("MISSING tool %s" % want)
            results[want] = {"error": "not published"}
            continue
        started = time.time()
        _, res, raw = client.request("tools/call", {"name": name, "arguments": {}})
        elapsed = time.time() - started
        text = flatten(res)
        print("CALL %s elapsed=%.2fs" % (name, elapsed))
        print(json.dumps(res, indent=2, sort_keys=True))
        results[want] = {"elapsed": round(elapsed, 2), "text": text}

    print("SUMMARY %s" % json.dumps(results, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
