# Connecting Flames to Remote & Local Hermes Instances: Complete Guide

This guide provides comprehensive instructions for connecting the **Flames** mobile companion app to any **Hermes Agent** instance—whether running locally on your workstation/laptop (macOS, Linux, Windows WSL), self-hosted on a private cloud VPS, or behind a secure tunnel.

It covers initial pairing, chat streaming, and how to harness all mobile capabilities: **Pocket Node Telemetry**, **Bidirectional Remote RPC Tools**, **Mobile Skills Hub**, **Memory Vault (FTS5)**, and **Voice Mode**.

---

## 1. Architecture Overview

Flames operates in two complementary modes depending on your configuration:

```
┌─────────────────────────────────────────────────────────────┐
│                        FLAMES MOBILE                        │
│                                                             │
│  [Tab 1: Chat]      [Tab 2: Skills]     [Tab 3: Node]       │
│  ReAct Agent Loop    Mobile Plugins      Live Telemetry     │
│  Streaming Markdown  Tool Permissions    Ambient Watchdog   │
│                                                             │
│  [Tab 4: Memory]     [Tab 5: Settings]                      │
│  SQLite FTS5 Vault   Multi-Server Profiles                  │
└───────────────┬─────────────────────────────┬───────────────┘
                │ REST (OpenAI-compatible)    │ WebSocket RPC
                │ /v1/chat/completions        │ /rpc or gateway port
                ▼                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    HERMES AGENT SERVER                      │
│                                                             │
│  • API Server Platform (port 8642)                          │
│  • Gateway & Hardware Node Coordinator (port 8644)         │
│  • Persona / Profiles (Default, Dev, Ops, Research, etc.)   │
│  • Memory Layer (Honcho / SQLite)                           │
└─────────────────────────────────────────────────────────────┘
```

1. **Direct Standalone Mode (REST API)**:
   - Flames acts as an autonomous mobile agent.
   - Communicates with Hermes's OpenAI-compatible API Server endpoint (`/v1/chat/completions`).
   - Executes local device tools directly on the smartphone (camera, calendar, contacts, clipboard, notifications).
2. **Gateway Remote Node Mode (WebSocket RPC)**:
   - Flames registers as an active **Pocket Node** peripheral for the Hermes gateway.
   - Remote Hermes instances (running in terminal, desktop, or cloud CI) can send RPC commands to the phone—e.g. taking a photo, querying GPS location, triggering vibration, reading battery status, or toggling the flashlight.

---

## 2. Setting Up the Host (Hermes Server)

Before connecting from Flames, configure your Hermes host instance.

### Scenario A: Local Workstation / Laptop (Same WiFi / LAN)

1. **Find your computer's local IP address**:
   - macOS: `ipconfig getifaddr en0` (or `en1`)
   - Linux: `hostname -I | awk '{print $1}'`
   - Windows (PowerShell): `(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi*').IPAddress`
   *(Example: `192.168.1.100`)*

2. **Enable the API Server & Gateway Platforms**:
   Edit your host's `~/.hermes/config.yaml`:
   ```yaml
   platforms:
     api_server:
       enabled: true
       host: 0.0.0.0    # Required: Binds to LAN interface instead of 127.0.0.1
       port: 8642
     gateway:
       enabled: true
       host: 0.0.0.0
       port: 8644
   ```

3. **Configure Authentication Secret**:
   In `~/.hermes/.env`:
   ```bash
   API_SERVER_KEY=your-secure-auth-token-here
   ```

4. **Restart Hermes**:
   ```bash
   hermes gateway restart
   ```

5. **Verify Host Readiness**:
   ```bash
   curl -i http://localhost:8642/health
   # Response should return 200 OK: {"status": "ok", "platform": "hermes-agent"}
   ```

---

### Scenario B: Remote Cloud VPS (Production HTTPS + WSS)

When hosting on a remote server (e.g. Ubuntu VPS on AWS, Oracle Cloud, Hetzner, DigitalOcean):
- Protect administrative web UIs behind local binding or VPN.
- Expose the API Server and WebSocket RPC through **Nginx** or **Caddy** with TLS/SSL encryption.

**Nginx Configuration Template (`/etc/nginx/sites-available/hermes`)**:
```nginx
server {
    server_name hermes.yourdomain.com;
    listen 443 ssl http2;

    ssl_certificate /etc/letsencrypt/live/hermes.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hermes.yourdomain.com/privkey.pem;

    # 1. REST API Server (Chat completions & Models)
    location ^~ /v1/ {
        proxy_pass http://127.0.0.1:8642;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 600s;
    }

    # 2. Multiplexed Bot Profiles (Optional: /p/<profile>/v1/)
    location ^~ /p/ {
        proxy_pass http://127.0.0.1:8642;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 600s;
    }

    # 3. Pocket Node WebSocket RPC
    location ^~ /rpc {
        proxy_pass http://127.0.0.1:8644;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400s; # Long-lived WebSocket connection
    }

    # 4. Block unmapped endpoints
    location / {
        return 404;
    }
}
```

---

### Scenario C: Zero-Config Remote Tunnel (Cloudflare Tunnel / Tailscale)

If you don't have a public IP or want to bypass port forwarding:
1. **Cloudflare Tunnel**:
   ```bash
   cloudflared tunnel --url http://localhost:8642
   # Generates: https://<random-subdomain>.trycloudflare.com
   ```
2. **Tailscale**:
   - Install Tailscale on your host machine and mobile phone.
   - Use the MagicDNS hostname or Tailscale IP (e.g. `http://100.x.y.z:8642/v1`).

---

## 3. Configuring Flames via Server Profiles

Flames supports multiple server profiles, allowing instant switching between workstations, team bots, and cloud deployments.

### Adding a Profile in Flames

1. Open **Flames** on your phone.
2. Tap the **Settings** tab (Gear icon) → **Server Profiles** card.
3. Tap **+ Add Profile**:
   - **Profile Name**: Human-readable label (e.g., `Mac Studio`, `VPS Production`, `Home Lab`).
   - **Gateway / Base URL**:
     - Local LAN: `http://192.168.1.100:8642/v1`
     - Remote Cloud: `https://hermes.yourdomain.com/v1`
   - **Auth Token / API Key**: Value of `API_SERVER_KEY` set in host `.env`.
   - **Model Name**: The target model supported by the host (e.g., `hermes-agent`, `claude-3-5-sonnet`, `qwen-2.5-coder`, `gpt-4o`).
   - **Temperature**: Model sampling temperature (e.g., `0.7` for general chat, `0.2` for coding).
4. Tap **Save Profile**.

### Zero-Config QR Pairing

If your Hermes host supports QR pairing generation:
1. Generate the pairing payload on your host (via Hermes Web Dashboard or CLI pairing command).
2. On Flames, tap the **QR Scanner icon** in the top bar.
3. Align the camera with the QR code.
4. Flames automatically extracts `gatewayUrl`, `token`, `profileName`, and activates the profile.

---

## 4. Using Pocket Node Telemetry (Tab 3)

The **Pocket Node** tab turns your phone into an active hardware node in the Hermes agent cluster.

### Live Telemetry & Node Health
- **Live Status Pill**: Displays real-time WebSocket connection state (`Connected`, `Connecting`, `Disconnected`).
- **Broadcast Ping & Latency**: Tap **Broadcast Ping** to send an instantaneous RPC heartbeat to the gateway. The pill measures round-trip latency in milliseconds (ms).
- **Self-Diagnostics**: Displays active dependency injection status, SQLite FTS5 database health, and battery level telemetry.

### Remote Tool Execution via Hermes RPC
When Flames is connected via Gateway Mode, your remote Hermes instance can execute mobile tools using standard JSON-RPC 2.0 messages:

| Tool Method | Description | Example Remote Prompt on Hermes Host |
|---|---|---|
| `device.get_battery` | Queries battery level and charging state | *"Check my phone's current battery status."* |
| `device.get_location` | Reads current GPS latitude/longitude | *"Where is my mobile phone located right now?"* |
| `camera.take_photo` | Snaps a picture using rear/front camera | *"Take a photo with the phone camera and inspect it."* |
| `device.toggle_flashlight` | Turns phone torch ON/OFF | *"Turn on my phone flashlight."* |
| `device.vibrate` | Triggers haptic vibration pattern | *"Vibrate my phone to alert me."* |
| `device.send_notification` | Pushes high-priority native notification | *"Send a reminder notification to my phone screen."* |
| `clipboard.read_text` | Reads text currently on phone clipboard | *"Read the link I just copied on my phone."* |

---

## 5. Using Mobile Skills Hub (Tab 2)

The **Skills Hub** manages modular capabilities available to the local ReAct agent loop.

### Pre-Installed Core Skills
- **Calendar Manager**: Query today's events, schedule meetings with local timezone awareness.
- **Contact & Phone Launcher**: Dial phone numbers or launch WhatsApp chats directly.
- **Ambient Context**: Battery watchdog, location geofencing, system metrics.
- **Local Memory Access**: Query and save items into on-device memory.

### Security Tiers
- **Tier 1 (Ambient / Safe)**: Executes automatically without prompting (e.g. reading battery status).
- **Tier 2 (Sensor / Permission-gated)**: Requests Android runtime permissions on first use (e.g. Camera, Location, Contacts).
- **Tier 3 (State-Modifying / HITL)**: Requires explicit user approval via a bottom sheet before execution (e.g. sending messages, modifying calendar, deleting data).

### Skill Toggles
Toggle any skill switch to enable or disable it. When disabled, the skill's tools and instructions are excluded from the system prompt.

---

## 6. Using Memory Vault (Tab 4)

Flames includes an embedded **SQLite FTS5 (Full-Text Search)** memory engine.

- **Automatic Recall**: During chat conversations, Flames automatically runs full-text semantic matching against your query and seeds relevant memories into the agent context.
- **Instant Search**: Search across thousands of stored memories in real time using the search bar.
- **Manual Add**: Tap the **+** button to manually store credentials, notes, preferences, or project instructions.
- **Delete / Purge**: Delete outdated or sensitive records individually.

---

## 7. Voice Mode & Speech Output

Flames features low-latency voice interaction:

1. **Push-to-Talk (STT)**:
   - Press and hold the **Mic** button in the Chat screen to record audio.
   - Releases automatically to transcribe speech into text.
   - Uses native Android `SpeechRecognizer` (ensure Google Speech Services or system language pack is installed).
2. **Text-to-Speech (TTS)**:
   - When enabled, agent responses stream audio directly via the OpenAI-compatible `/audio/speech` endpoint on your Hermes host or configured router.
   - Automatically handles audio buffering and playback queueing.

---

## 8. Android Background Reliability Tips

To ensure ambient triggers (Battery Watchdog, Notification Listener) and WebSocket RPC stay active in the background:

1. **Disable Battery Optimization**:
   - Go to Android **Settings** → **Apps** → **Flames** → **Battery**.
   - Select **Unrestricted** (prevents Android Doze mode from freezing the process).
2. **Notification Listener Access**:
   - Flames requires Notification Listener permission to capture 2FA OTP codes and triaged alerts.
   - If prompted, grant **Notification Access** in Android Settings.
3. **OEM Aggressive Killers (Xiaomi MIUI/HyperOS, Samsung OneUI, Oppo/Vivo)**:
   - Lock Flames in the Recent Apps overview.
   - Enable "Autostart" in app settings if available on your OEM ROM.

---

## 9. Troubleshooting

| Symptom | Probable Cause | Resolution |
|---|---|---|
| **Connection Refused (`ECONNREFUSED`)** | Hermes host bound to `127.0.0.1` instead of `0.0.0.0` | In `~/.hermes/config.yaml`, set `platforms.api_server.host: 0.0.0.0` and restart gateway. |
| **`401 Unauthorized`** | Token mismatch | Ensure the API Key in Flames profile matches `API_SERVER_KEY` in `~/.hermes/.env`. |
| **`404 Not Found`** | Missing path prefix | Ensure the URL includes `/v1` (e.g. `http://192.168.1.100:8642/v1`). |
| **WebSocket RPC Disconnected** | Port or WSS proxy error | Verify gateway port `8644` is open or proxied with `Upgrade: websocket` headers. |
| **Speech recognition fails** | No offline speech pack | Check Google App settings or install English/Indonesian offline voice packs. |
| **TTS fails with 404** | Router doesn't route `/audio/speech` | Confirm backend router proxies `/v1/audio/speech` to an active TTS provider (OpenAI, ElevenLabs, etc.). |
