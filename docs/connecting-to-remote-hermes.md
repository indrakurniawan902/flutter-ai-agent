# Connecting Flames to Remote & Local Hermes Instances

This guide provides step-by-step instructions for connecting the **Flames** mobile app to any **Hermes Agent** instance—whether running locally on a Mac/laptop via WiFi, on a remote cloud VPS, or on a colleague's machine.

---

## 1. Overview of Connection Scenarios

| Scenario | Network Requirement | Example Base URL | Security / Auth |
|---|---|---|---|
| **Local Machine (Mac / PC)** | Same WiFi / LAN | `http://192.168.1.50:8642/v1` | Local Bearer token (`API_SERVER_KEY`) |
| **Remote Cloud VPS** | Public Internet (Anywhere) | `https://hermes.indra-developer.my.id/v1` | TLS (HTTPS) + Bearer token |
| **Colleague Machine (Remote)** | Cloudflare Tunnel / VPN | `https://hermes-colleague.trycloudflare.com/v1` | HTTPS + Colleague's Bearer token |

---

## 2. Setting Up the Host (Hermes Server)

### A. Local Machine Setup (macOS / Linux Laptop)

1. **Find your local LAN IP address**:
   ```bash
   # On macOS:
   ipconfig getifaddr en0

   # On Linux:
   hostname -I | awk '{print $1}'
   ```
   *(Example: `192.168.1.50`)*

2. **Enable the API Server Platform**:
   Edit `~/.hermes/config.yaml`:
   ```yaml
   platforms:
     api_server:
       enabled: true
       host: 0.0.0.0    # Required: Binds to LAN interface instead of localhost only
       port: 8642
   ```

3. **Set the Secret Token**:
   In `~/.hermes/.env`:
   ```bash
   API_SERVER_KEY=your-secure-local-token
   ```

4. **Restart Hermes Gateway**:
   ```bash
   hermes gateway restart
   ```

5. **Verify connectivity**:
   ```bash
   curl -i http://localhost:8642/health
   # Expected response: {"status": "ok", "platform": "hermes-agent"}
   ```

---

### B. Remote Cloud VPS Setup (Production / Nginx Proxy)

When deploying to a public VPS (such as Oracle Cloud):
- **Keep Admin Web Dashboards Private**: Do NOT expose the dashboard web UI (`9119`) publicly. Keep it bound to `127.0.0.1` and access it via SSH tunnel (`ssh -N -L 29119:127.0.0.1:9119 oracle`).
- **Proxy the API Server securely**: Route only `/v1/` and `/p/` via Nginx to the Hermes API Server port (`9120`).

**Nginx Configuration (`/etc/nginx/sites-available/hermes-dashboard`)**:
```nginx
server {
    server_name hermes.indra-developer.my.id;

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/hermes.indra-developer.my.id/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hermes.indra-developer.my.id/privkey.pem;

    # Block public access to root dashboard UI
    location / {
        return 404;
    }

    # Proxy OpenAI-compatible API Server & Multiplexed Profiles
    location ^~ /v1/ {
        proxy_pass http://127.0.0.1:9120;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 600s;
    }

    location ^~ /p/ {
        proxy_pass http://127.0.0.1:9120;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 600s;
    }
}
```

---

## 3. Configuring Server Profiles in the Flames App

Open **Flames** on your mobile device, navigate to **Settings** → **Server Profiles**, and tap **+ Add Profile**.

### Available Profiles for our Bot Team

| Role | Profile Name | Base / Gateway URL | Model Name | Description |
|---|---|---|---|---|
| 👑 **PM Bot** | `Hermes PM` | `https://hermes.indra-developer.my.id/v1` | `hermes-agent` | Project coordinator, task planner, general inquiries |
| 🛠️ **Dev Bot** | `Hermes Dev` | `https://hermes.indra-developer.my.id/p/dev/v1` | `dev` | Flutter/Dart coding, debugging, architecture & PRs |
| ⚡ **Ops Bot** | `Hermes Ops` | `https://hermes.indra-developer.my.id/p/ops/v1` | `ops` | VPS management, Docker, Nginx, deployment & monitoring |
| 🔍 **Research Bot** | `Hermes Research` | `https://hermes.indra-developer.my.id/p/research/v1` | `research` | Deep web research, tech intel, benchmarking |

> **API Key / Token**: Enter the `API_SERVER_KEY` configured in your VPS `~/.hermes/.env`.

### Local Mac Profile (When on Home / Office WiFi)
- **Profile Name**: `Hermes Mac`
- **Base / Gateway URL**: `http://192.168.1.50:8642/v1` *(Replace with your Mac's IP)*
- **API Key / Token**: *(Your Mac's `API_SERVER_KEY`)*
- **Model Name**: `hermes-agent`

---

## 4. Multi-Profile Sessions & Isolation

1. **Independent Session Stores**:
   - Each bot profile maintains its own isolated database (`sessions.db` & `state.db`).
   - Conversations with `Dev Bot` do not leak into or pollute the context of `Ops Bot` or `PM Bot`.
2. **Conversation Persistence**:
   - The Flames app sends standard OpenAI chat messages. Hermes maps each conversation to a durable session ID.
   - Sessions are persistent across mobile network reconnections.
3. **Instant Switching**:
   - Switching profiles in the Flames app dropdown immediately targets the selected bot persona and its dedicated workspace without needing re-authentication.

---

## 5. Troubleshooting & Verification

### Test Connection via Terminal
To test an endpoint before configuring the mobile client:
```bash
# Test public models list
curl -s -X GET "https://hermes.indra-developer.my.id/v1/models" \
  -H "Authorization: Bearer <YOUR_API_SERVER_KEY>"

# Test direct chat completion
curl -s -X POST "https://hermes.indra-developer.my.id/p/dev/v1/chat/completions" \
  -H "Authorization: Bearer <YOUR_API_SERVER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "dev",
    "messages": [{"role": "user", "content": "ping"}]
  }'
```

### Common Issues
- **`401 Unauthorized`**: Ensure `API_SERVER_KEY` matches the value defined in `~/.hermes/.env` (or `~/.hermes/profiles/<name>/.env` for named sub-profiles).
- **`404 Not Found`**: Ensure the URL includes `/v1` or `/p/<profile>/v1`. The root domain `/` is intentionally blocked for security.
- **Connection Refused on LAN**: Verify that the host configuration uses `host: 0.0.0.0` (not `127.0.0.1`) and that the mobile device is on the same WiFi network.
