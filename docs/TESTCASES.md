# Comprehensive Test Cases: Flutter Mobile AI Agent (MVP)

**Document:** `docs/TESTCASES.md`  
**Project:** Flutter AI Agent (Personal Action-Oriented Mobile Agent)  
**Author:** PM Bot (`default`)  
**Stakeholder:** Eryushin (Indra)  
**Architecture:** Cubit + Clean Architecture (`presentation → domain ← data`)  
**Standard:** Positive & Negative Scenarios with Observable Verification Criteria

---

## Table of Contents
1. [Module 1: Configuration & Encrypted Storage (Settings)](#module-1-configuration--encrypted-storage-settings)
2. [Module 2: Network, SSE Streaming Client & LLM Communication](#module-2-network-sse-streaming-client--llm-communication)
3. [Module 3: ReAct Agent Loop & Orchestration](#module-3-react-agent-loop--orchestration)
4. [Module 4: Tier 1 Ambient Context Tools (Safe / Auto-Execute)](#module-4-tier-1-ambient-context-tools-safe--auto-execute)
5. [Module 5: Tier 2 Sensor & Perception Tools (Permission-Gated)](#module-5-tier-2-sensor--perception-tools-permission-gated)
6. [Module 6: Tier 3 State-Modifying Tools & HITL Guardrails](#module-6-tier-3-state-modifying-tools--hitl-guardrails)
7. [Module 7: Presentation, UI/UX & Edge Cases](#module-7-presentation-uiux--edge-cases)
8. [Module 8: Local Workspace, Intelligence & Ambient Event Triggers (Fase 3)](#module-8-local-workspace-intelligence--ambient-event-triggers-fase-3)

---

## Module 1: Configuration & Encrypted Storage (Settings)

### TC-SET-01: Save Valid Configuration
- **Type**: Positive
- **Objective**: Verify that valid endpoint parameters (Base URL, API Key, Model, Temperature) are stored securely and retrieved accurately.
- **Preconditions**: App is running; user navigates to `SettingsScreen`.
- **Steps**:
  1. Input Base URL: `https://indra-9router.my.id/v1`.
  2. Input API Key: `sk-valid-key-12345`.
  3. Input Model: `ag-glm`.
  4. Set Temperature: `0.7`.
  5. Tap `Save Settings`.
  6. Restart the application.
- **Expected Outcome**:
  - SnackBar / Toast confirms: `"Settings saved successfully"`.
  - Credentials stored in `flutter_secure_storage` (Android KeyStore backed).
  - On restart, `SettingsCubit` automatically reloads saved values.
  - API Key field displays masked characters (`••••••••`).

### TC-SET-02: Invalid Base URL Format
- **Type**: Negative
- **Objective**: Prevent saving malformed or unsupported URLs.
- **Preconditions**: User is on `SettingsScreen`.
- **Steps**:
  1. Input Base URL: `not-a-valid-url` or `ftp://indra-9router.my.id`.
  2. Input valid API Key and Model.
  3. Tap `Save Settings`.
- **Expected Outcome**:
  - Form validation triggers inline error: `"Please enter a valid HTTP/HTTPS URL"`.
  - Save operation is aborted; storage is not modified.

### TC-SET-03: Empty API Key Submission
- **Type**: Negative
- **Objective**: Prevent runtime crashes caused by missing authentication headers.
- **Preconditions**: User on `SettingsScreen`.
- **Steps**:
  1. Clear the API Key input field.
  2. Tap `Save Settings`.
- **Expected Outcome**:
  - Validation error: `"API Key cannot be empty"`.
  - Action blocked; existing stored key remains untouched.

### TC-SET-04: Out-of-Range Temperature Value
- **Type**: Negative
- **Objective**: Ensure temperature adheres to OpenAI schema bounds ($0.0 \le T \le 2.0$).
- **Preconditions**: User on `SettingsScreen`.
- **Steps**:
  1. Input Temperature: `-0.5` or `2.8`.
  2. Tap `Save Settings`.
- **Expected Outcome**:
  - Slider or input bounds clamp value to $[0.0, 2.0]$ with an inline warning.

---

## Module 2: Network, SSE Streaming Client & LLM Communication

### TC-NET-01: Successful Server-Sent Events (SSE) Stream
- **Type**: Positive
- **Objective**: Verify incoming SSE stream chunks (`data: {...}`) are parsed sequentially into chat tokens and rendered in real time.
- **Preconditions**: Valid endpoint configured; active internet connection.
- **Steps**:
  1. Send prompt: `"Tuliskan fungsi Fibonacci dalam Dart."`
- **Expected Outcome**:
  - HTTP `POST /chat/completions` initiated with `stream: true`.
  - First token rendered in UI within $< 1.5$s.
  - Incoming tokens append smoothly to the active message bubble.
  - Stream completes upon receiving `data: [DONE]`.

### TC-NET-02: OpenAI Tool Calls Delta Stream Parsing
- **Type**: Positive
- **Objective**: Verify SSE chunks containing `delta.tool_calls` are accumulated correctly across multiple chunks.
- **Preconditions**: LLM endpoint returns streaming function call deltas.
- **Steps**:
  1. Send prompt requiring tool: `"Berapa sisa baterai HP saya?"`
  2. Inspect incoming stream parsing.
- **Expected Outcome**:
  - Chunks containing index, ID, function name (`device_status`), and argument fragments are assembled into a complete `ToolCall` object.
  - No incomplete JSON parse exceptions thrown.

### TC-NET-03: Connection Timeout / Unreachable Host
- **Type**: Negative
- **Objective**: Handle unreachable or non-responsive AI router gracefully without crashing.
- **Preconditions**: Base URL points to an offline host (e.g. `https://10.255.255.1`).
- **Steps**:
  1. Send prompt: `"Halo"`.
- **Expected Outcome**:
  - Connection timeout triggers after 10 seconds.
  - `LLMRepository` catches `DioException.connectionTimeout` and returns `Left(ServerFailure('Connection timed out'))`.
  - UI displays informative error banner: `"Gagal terhubung ke server AI. Periksa jaringan Anda."`

### TC-NET-04: HTTP 401 Unauthorized (Invalid API Key)
- **Type**: Negative
- **Objective**: Validate error handling when API key is rejected by the gateway.
- **Preconditions**: API Key configured to `sk-invalid-dummy-key`.
- **Steps**:
  1. Send prompt: `"Halo"`.
- **Expected Outcome**:
  - Gateway responds with HTTP 401.
  - UI surfaces clear message: `"API Key tidak valid. Silakan perbarui di menu Pengaturan."`
  - ReAct loop terminates cleanly without retry spamming.

### TC-NET-05: HTTP 429 Rate Limit / Quota Exhaustion
- **Type**: Negative
- **Objective**: Handle upstream model rate limits or exhausted balances.
- **Preconditions**: Gateway returns HTTP 429 `rate_limit_exceeded`.
- **Steps**:
  1. Send prompt.
- **Expected Outcome**:
  - Handled as `RateLimitFailure`.
  - UI displays: `"Limit request tercapai atau kuota habis. Coba lagi dalam beberapa saat."`

### TC-NET-06: Mid-Stream Network Drop (Broken Pipe)
- **Type**: Negative
- **Objective**: Ensure app recovers when Wi-Fi drops while receiving token chunks.
- **Preconditions**: Stream actively receiving tokens.
- **Steps**:
  1. Prompt agent to write a long 500-word essay.
  2. Disconnect Wi-Fi / enable Airplane mode mid-stream.
- **Expected Outcome**:
  - Stream subscription emits error event.
  - Partially generated text is preserved in chat history with a visual tag `[Stream Interrupted]`.
  - Retry button is made available to the user.

---

## Module 3: ReAct Agent Loop & Orchestration

### TC-REC-01: Single-Turn ReAct Loop Execution
- **Type**: Positive
- **Objective**: Validate User $\to$ LLM $\to$ Tool Call $\to$ Tool Result $\to$ LLM $\to$ Final Text workflow.
- **Preconditions**: All ambient tools registered.
- **Steps**:
  1. Prompt: `"Berapa level baterai saya?"`
- **Expected Outcome**:
  - Turn 1: LLM returns `tool_calls: [{ name: "device_status", args: {} }]`.
  - Agent executes `device_status` native API.
  - Turn 2: Agent posts message history + `{ role: "tool", content: "{\"battery\": 85, \"charging\": true}" }`.
  - Turn 3: LLM generates final answer: `"Baterai Anda 85% dan sedang diisi daya."`
  - Total turn count = 2 requests to LLM.

### TC-REC-02: Multi-Turn Sequential Tool Chaining
- **Type**: Positive
- **Objective**: Verify agent can call multiple tools sequentially to fulfill a compound instruction.
- **Preconditions**: Clipboard and Battery tools active.
- **Steps**:
  1. Copy `"Tinjau arsitektur agent"` to system clipboard.
  2. Prompt: `"Baca clipboard saya dan jika baterai di atas 20%, konfirmasi ke saya."`
- **Expected Outcome**:
  - Step 1: Agent calls `clipboard_read` $\to$ receives text.
  - Step 2: Agent calls `device_status` $\to$ receives battery level.
  - Step 3: Agent synthesizes both outputs and replies with combined answer.

### TC-REC-03: Unknown Tool Name Emitted by LLM
- **Type**: Negative
- **Objective**: Ensure agent does not crash if LLM hallucinates an unregistered tool.
- **Preconditions**: LLM returns `tool_calls: [{ name: "hack_nasa", args: {} }]`.
- **Steps**:
  1. Trigger test scenario with mocked LLM response.
- **Expected Outcome**:
  - `ToolRegistry` identifies unknown tool.
  - Returns structured error to LLM: `{ "error": "Tool 'hack_nasa' is not registered on this device." }`.
  - Agent acknowledges to user: `"Maaf, tool tersebut tidak tersedia di perangkat ini."`

### TC-REC-04: Malformed Tool Arguments JSON
- **Type**: Negative
- **Objective**: Handle malformed argument strings emitted by erratic models.
- **Preconditions**: LLM returns `args: "{ invalid_json: "` (unclosed brackets).
- **Steps**:
  1. Parse tool arguments.
- **Expected Outcome**:
  - JSON parser catches `FormatException`.
  - Tool execution aborted; error fed back into context: `{ "error": "Invalid argument syntax" }`.
  - LLM corrects itself or reports failure gracefully.

### TC-REC-05: ReAct Loop Runaway Guard (Infinite Loop Prevention)
- **Type**: Negative
- **Objective**: Prevent runaway recursive loops if model continuously re-invokes tools.
- **Preconditions**: Mock LLM continually returning tool calls.
- **Steps**:
  1. Allow loop to reach 5 consecutive tool execution turns.
- **Expected Outcome**:
  - Maximum turn guard triggers (limit = 5).
  - Loop forcibly halted with message: `"Percakapan dihentikan karena mencapai batas maksimal pemanggilan tools."`

---

## Module 4: Tier 1 Ambient Context Tools (Safe / Auto-Execute)

### TC-T1-01: Get Device Status (Battery & Network)
- **Type**: Positive
- **Objective**: Retrieve battery level, charging status, and active network connection without user intervention.
- **Preconditions**: Battery is at 74%, connected to Wi-Fi.
- **Steps**:
  1. Prompt: `"Cek status perangkat saya."`
- **Expected Outcome**:
  - `device_status` executes immediately (Tier 1 safe).
  - Output JSON: `{ "battery_level": 74, "is_charging": false, "network": "wifi" }`.
  - Output rendered clearly in chat.

### TC-T1-02: Device Status in Airplane Mode
- **Type**: Negative
- **Objective**: Validate behavior when network connectivity is completely severed.
- **Preconditions**: Device in Airplane mode; cached offline prompt execution.
- **Steps**:
  1. Execute `device_status`.
- **Expected Outcome**:
  - Tool returns `{ "network": "none", "battery_level": ... }`.
  - Handled cleanly without null pointer exceptions.

### TC-T1-03: System Information Inspection
- **Type**: Positive
- **Objective**: Read device hardware specifications and OS version.
- **Preconditions**: Standard Android device.
- **Steps**:
  1. Prompt: `"Informasi OS dan model HP saya apa?"`
- **Expected Outcome**:
  - Tool `system_info` returns:
    - `os_version`: e.g. `"Android 14 (API 34)"`
    - `device_model`: e.g. `"Pixel 7"`
    - `app_version`: `"0.1.0"`

### TC-T1-04: Clipboard Two-Way Interaction
- **Type**: Positive
- **Objective**: Verify reading from and writing to system clipboard.
- **Steps**:
  1. Copy text `"Token-12345"` to clipboard.
  2. Prompt: `"Baca isi clipboard saya."`
  3. Verify agent answers `"Token-12345"`.
  4. Prompt: `"Tulis 'Hermes-Device-Node' ke clipboard."`
  5. Open another app (e.g. Notes) and paste.
- **Expected Outcome**:
  - Read returns exact string.
  - Write replaces system clipboard with `"Hermes-Device-Node"`.

### TC-T1-05: Clipboard Read on Empty Clipboard
- **Type**: Negative
- **Objective**: Handle reading when system clipboard has no text content.
- **Preconditions**: Clipboard is empty or contains non-text media (e.g. binary file).
- **Steps**:
  1. Clear clipboard.
  2. Prompt: `"Baca clipboard saya."`
- **Expected Outcome**:
  - Tool returns `{ "status": "empty", "content": null }`.
  - Agent responds: `"Clipboard Anda saat ini kosong."`

---

## Module 5: Tier 2 Sensor & Perception Tools (Permission-Gated)

### TC-T2-01: GPS Location Retrieval (Permission Granted)
- **Type**: Positive
- **Objective**: Retrieve accurate latitude, longitude, and reverse geocoded city name.
- **Preconditions**: Location permission granted; device GPS enabled.
- **Steps**:
  1. Prompt: `"Di kota mana saya berada sekarang?"`
- **Expected Outcome**:
  - `get_location` called with `accuracy: high`.
  - Returns coordinates and resolved location (e.g. `Jakarta, Indonesia`).
  - Agent answers accurately based on location payload.

### TC-T2-02: GPS Location Retrieval (Permission Denied)
- **Type**: Negative
- **Objective**: Handle OS permission rejection gracefully.
- **Preconditions**: Location permission revoked in Android App Settings.
- **Steps**:
  1. Prompt: `"Cari tahu lokasi saya sekarang."`
  2. OS permission dialog appears $\to$ Tap **"Don't allow"**.
- **Expected Outcome**:
  - Tool catches rejection and returns `{ "error": "Location permission was denied by user." }`.
  - Agent replies politely: `"Saya tidak dapat mengakses lokasi karena izin tidak diberikan. Anda dapat mengaktifkannya di Pengaturan HP."`
  - No unhandled runtime crash.

### TC-T2-03: GPS Hardware Disabled (Location Services Off)
- **Type**: Negative
- **Objective**: Validate response when system location master switch is toggled OFF.
- **Preconditions**: Location permission granted, but GPS turned off in Android Quick Settings.
- **Steps**:
  1. Prompt: `"Cek posisi saya."`
- **Expected Outcome**:
  - Tool returns `{ "error": "Location services are disabled on device." }`.
  - Agent suggests user turn on Location in Quick Settings.

### TC-T2-04: Camera Vision Capture (Happy Path)
- **Type**: Positive
- **Objective**: Capture photo via camera, auto-compress, and send base64 string to vision-capable model.
- **Preconditions**: Camera permission granted; vision-enabled model active.
- **Steps**:
  1. Prompt: `"Ambil foto label ini dan baca teksnya."`
  2. Camera screen launches $\to$ Take picture $\to$ Tap checkmark.
- **Expected Outcome**:
  - Image captured and compressed locally to $\le 1024 \times 1024$ resolution, JPEG quality 80%.
  - Memory footprint stays below 120MB.
  - Base64 payload formatted as standard data URI (`data:image/jpeg;base64,...`).
  - Model analyzes and transcribes label accurately.

### TC-T2-05: Camera Vision User Cancellation
- **Type**: Negative
- **Objective**: Handle user backing out of camera without taking a photo.
- **Preconditions**: User prompts for photo.
- **Steps**:
  1. Camera viewfinder opens.
  2. User presses Android Back button / closes viewfinder without snapping photo.
- **Expected Outcome**:
  - `image_picker` returns `null`.
  - Tool returns `{ "status": "cancelled", "message": "Photo capture cancelled by user." }`.
  - Agent acknowledges: `"Pengambilan foto dibatalkan."`

---

## Module 6: Tier 3 State-Modifying Tools & HITL Guardrails

### TC-T3-01: Calendar Event Creation (HITL Approved)
- **Type**: Positive
- **Objective**: Ensure state-modifying action pauses the loop, requires explicit confirmation, and writes to device calendar only upon approval.
- **Preconditions**: Calendar read/write permissions granted.
- **Steps**:
  1. Prompt: `"Jadwalkan rapat teknis besok jam 09:00 sampai 10:00 dengan judul 'Tech Sync'."`
  2. Observe UI state.
  3. Verify parameters in `ActionApprovalSheet`.
  4. Tap **"Approve"**.
- **Expected Outcome**:
  - ReAct loop pauses in state `AgentState.waitingApproval`.
  - `ActionApprovalSheet` renders with:
    - Tool: `calendar_create_event`
    - Title: `"Tech Sync"`
    - Start: `[Tomorrow] 09:00`
    - End: `[Tomorrow] 10:00`
  - Prior to tap: No calendar event created.
  - After tap: Event inserted into device default calendar; tool returns `{ "success": true, "eventId": "..." }`.
  - Final confirmation displayed: `"Rapat 'Tech Sync' berhasil dijadwalkan."`

### TC-T3-02: Calendar Event Creation (HITL Rejected)
- **Type**: Negative
- **Objective**: Ensure rejecting the HITL sheet prevents any database insertion and notifies the LLM.
- **Preconditions**: User prompts calendar event creation.
- **Steps**:
  1. Prompt: `"Jadwalkan meeting makan siang jam 12:00 besok."`
  2. `ActionApprovalSheet` appears.
  3. Tap **"Reject"** or swipe sheet down to dismiss.
- **Expected Outcome**:
  - No event is created in the calendar.
  - Tool returns `{ "error": "Action rejected by user" }`.
  - Loop resumes and LLM replies: `"Penjadwalan dibatalkan sesuai instruksi Anda."`

### TC-T3-03: Calendar Invalid Date Range
- **Type**: Negative
- **Objective**: Prevent creating events where end time precedes start time.
- **Preconditions**: User or LLM generates invalid timestamps.
- **Steps**:
  1. Prompt: `"Jadwalkan event dari jam 15:00 sampai 14:00 besok."`
- **Expected Outcome**:
  - Validation catches `endTime < startTime`.
  - Sheet warns user or tool rejects parameter before database write.

### TC-T3-04: Schedule Delayed Reminder (Exact Alarm Approved)
- **Type**: Positive
- **Objective**: Schedule local notification after $N$ minutes using system alarm manager.
- **Preconditions**: Notification permission granted.
- **Steps**:
  1. Prompt: `"Ingatkan saya kirim laporan 10 menit lagi."`
  2. `ActionApprovalSheet` appears $\to$ Tap **"Approve"**.
- **Expected Outcome**:
  - Alarm scheduled via `flutter_local_notifications`.
  - System notification fires exactly 10 minutes later with title `"Pengingat"` and body `"kirim laporan"`.

### TC-T3-05: Schedule Reminder on Android 13+ (Notifications Denied)
- **Type**: Negative
- **Objective**: Handle Android 13 `POST_NOTIFICATIONS` permission denial.
- **Preconditions**: Notifications disabled for the app.
- **Steps**:
  1. Prompt: `"Ingatkan saya meeting 5 menit lagi."`
  2. Approve HITL sheet.
- **Expected Outcome**:
  - Tool detects missing `POST_NOTIFICATIONS` permission.
  - Returns `{ "error": "Notification permission not granted." }`.
  - UI prompts user to enable notifications in System Settings.

---

## Module 7: Presentation, UI/UX & Edge Cases

### TC-UI-01: Dark Theme & Anti-Slop Design Conformance
- **Type**: Positive
- **Objective**: Ensure styling strictly complies with [[flutter-mobile-design]] guidelines.
- **Preconditions**: App launched.
- **Verification Points**:
  - Background surface strictly dark `#0F172A`.
  - Primary accent color Teal `#008080`.
  - Zero decorative gradient fills on cards.
  - Zero emoji icons in UI chrome (`Icons.*` material icons used exclusively).
  - High contrast ratio (WCAG AAA compliant text readability).

### TC-UI-02: Interactive Tool Call Pill Card States
- **Type**: Positive
- **Objective**: Verify tool card transitions across its complete lifecycle.
- **Lifecycle States**:
  1. **Running**: Displays `[Tool: tool_name] (Running...)` with a subtle pulsing indicator.
  2. **Success**: Card turns solid border; tap expands to show JSON payload.
  3. **Awaiting Approval**: Amber accent border with interactive "Review Action" CTA.
  4. **Failed / Rejected**: Subtle error tint with error summary.

### TC-UI-03: Markdown & Code Syntax Highlighting
- **Type**: Positive
- **Objective**: Render formatted Markdown headers, lists, and syntax-highlighted Dart/Python code blocks.
- **Steps**:
  1. Request code example from agent.
- **Expected Outcome**:
  - Code block rendered inside dedicated container with copy-code button.
  - Keywords, strings, and comments colorized properly.

### TC-UI-04: Extreme Token Burst / Long Chat Stress Test
- **Type**: Negative
- **Objective**: Ensure continuous chat history of 100+ messages does not cause memory leaks or frame drops (jank).
- **Steps**:
  1. Generate 100 consecutive message exchanges with tool calls.
  2. Scroll rapidly through `ListView`.
- **Expected Outcome**:
  - ListView maintains steady 60 fps without stutter.
  - Memory consumption remains $\le 150$MB via widget recycling (`ListView.builder`).

---

## Module 8: Local Workspace, Intelligence & Ambient Event Triggers (Fase 3)

### TC-INTEL-01: Document Workspace File Inspection with Line Pagination
- **Type**: Positive
- **Objective**: Verify that `FileWorkspaceService` inspects local documents (PDF, CSV, TXT, MD) and supports pagination via `offset` and `maxLines`.
- **Preconditions**: Storage permissions granted; text document exists in device storage.
- **Steps**:
  1. Call tool `read_device_file` with `path: "/sdcard/workspace/report.txt"`, `offset: 0`, `maxLines: 50`.
  2. Call tool `list_device_files` with `directoryPath: "/sdcard/workspace"`, `recursive: false`.
- **Expected Outcome**:
  - First 50 lines returned formatted as clean string with line count header.
  - Directory listing returns JSON list of file entries with file names, sizes, and timestamps.

### TC-INTEL-02: File Workspace Missing File & Security Boundary Handling
- **Type**: Negative
- **Objective**: Gracefully handle missing files, unsupported binary formats, or path traversal attempts without agent crash.
- **Preconditions**: Tool `read_device_file` invoked.
- **Steps**:
  1. Call `read_device_file` with path `"/nonexistent/file.txt"`.
  2. Call `read_device_file` with relative traversal path `"../../etc/shadow"`.
- **Expected Outcome**:
  - Tool returns `Left(StorageFailure)` indicating file was not found or access was restricted.
  - ReAct agent loop reports the failure clearly to user without throwing unhandled exceptions.

### TC-INTEL-03: Notification Triage & Automatic OTP Extraction with Privacy Masking
- **Type**: Positive
- **Objective**: Retrieve incoming device notifications via `NotificationListenerService` and accurately extract OTP codes while protecting PII.
- **Preconditions**: Notification access permission granted in Android System Settings.
- **Steps**:
  1. Receive mock SMS notification: `"Your verification code for Acme Corp is 839201. Valid for 5 minutes."`
  2. Call tool `extract_latest_otp` with `appFilter: "sms"`.
  3. Call tool `read_recent_notifications` with `limit: 5`.
- **Expected Outcome**:
  - `extract_latest_otp` extracts code `"839201"`, sender `"Acme Corp"`, and timestamp.
  - Sensitive notification bodies (credit card numbers, personal identifiers) are masked with `[REDACTED]`.

### TC-INTEL-04: Notification Listener Permission Denial Recovery
- **Type**: Negative
- **Objective**: Handle Android Notification Listener permission denial with clear guidance for user to enable in settings.
- **Preconditions**: Notification listener permission is disabled.
- **Steps**:
  1. Agent invokes `extract_latest_otp`.
- **Expected Outcome**:
  - Tool checks permission, detects ungranted status, and returns `Left(PermissionFailure('Notification listener permission not granted'))`.
  - UI surfaces prompt for user to grant notification listener access in system settings.

### TC-INTEL-05: Local Persistent Memory CRUD & SQLite FTS5 BM25 Auto-Injection
- **Type**: Positive
- **Objective**: Verify that `LocalMemoryService` stores memories in SQLite FTS5, performs BM25 ranking, and automatically injects relevant context into `AgentCubit`.
- **Preconditions**: Database initialized with FTS5 schema.
- **Steps**:
  1. Tool `save_memory` stores key `"user_project"`, content `"Building Flutter AI Agent on Linux ARM"`, tags `["project", "dev"]`.
  2. User asks prompt: `"What project am I building?"`
  3. Inspect `AgentCubit.sendMessage()`.
- **Expected Outcome**:
  - `searchMemories("What project am I building?", 3)` returns stored memory with highest BM25 score.
  - `AgentCubit` auto-injects memory into system prompt: `Relevant User & Device Memories: - user_project [project, dev]: Building Flutter AI Agent on Linux ARM`.
  - LLM response accurately reflects stored context.

### TC-INTEL-06: Geofence Region Transition Detection & Notification Dispatch
- **Type**: Positive
- **Objective**: Trigger proactive ambient events when device transitions across registered geofence boundaries.
- **Preconditions**: Location service active; geofence registered.
- **Steps**:
  1. Tool `register_geofence` adds region `"Office"` at coordinates `(-6.2, 106.8)` with radius `200m`.
  2. Device position updates from outside $(> 500m)$ to inside $(< 100m)$.
- **Expected Outcome**:
  - `AmbientTriggerService` fires `AmbientEventType.geofenceEnter` event.
  - Event emitted on `eventStream` and system notification dispatched: `"Geofence Entered: Welcome to Office"`.

### TC-INTEL-07: Battery Watchdog Thresholds & Charging Suppression
- **Type**: Positive
- **Objective**: Verify battery watchdog alerts at low ($\le 15\%$) and critical ($\le 5\%$) levels while suppressing alerts during charging.
- **Preconditions**: Battery monitoring enabled.
- **Steps**:
  1. Battery level drops to $12\%$ while `isCharging = false` $\to$ Check triggered events.
  2. Charger plugged in (`isCharging = true`) while battery is $12\%$ $\to$ Check triggered events.
- **Expected Outcome**:
  - Step 1 triggers `AmbientEventType.batteryLow` event and dispatches power saver notification.
  - Step 2 suppresses trigger; no duplicate notifications or warnings dispatched while charging.

### TC-INTEL-08: Cooldown Window & Trigger Flood Prevention
- **Type**: Negative
- **Objective**: Prevent repetitive notification spam by enforcing cooldown timers between consecutive ambient triggers.
- **Preconditions**: Cooldown set to 15 minutes.
- **Steps**:
  1. Trigger initial `batteryLow` event at timestamp $T$.
  2. Trigger second `batteryLow` event at timestamp $T + 2\text{ minutes}$.
- **Expected Outcome**:
  - First trigger fires successfully.
  - Second trigger is deduplicated and suppressed by cooldown manager; zero spam notifications.

### TC-INTEL-09: End-to-End Intelligence Pipeline
- **Type**: Positive
- **Objective**: Verify full multi-stage autonomous pipeline: File reading $\to$ Notification triage $\to$ Local memory retrieval $\to$ Ambient proactive prompt.
- **Preconditions**: All Fase 3 services registered in `ToolRegistry` and DI container.
- **Steps**:
  1. User prompts agent to inspect `/workspace/incident_report.txt`.
  2. Agent calls `read_device_file`, parses error report requiring 2FA OTP.
  3. Agent calls `extract_latest_otp` to triage SMS notifications, recovering code `948210`.
  4. Agent calls `save_memory` to store OTP in SQLite FTS5.
  5. User queries stored token; `AgentCubit` auto-retrieves memory into prompt.
  6. Battery drops to $12\%$; `AmbientTriggerService` pipes proactive alert to `AgentCubit.sendMessage()`.
- **Expected Outcome**:
  - Complete 4-stage pipeline executes seamlessly with 100% green verification in `e2e_fase3_intelligence_test.dart`.

---

## Module 9: Streaming Voice & Audio Interface (Fase 4)

### TC-VOICE-01: Voice Input & Real-Time Transcription (T9.1)
- **Type**: Positive
- **Objective**: Capture microphone audio and stream transcribed speech into text.
- **Preconditions**: Microphone permission granted; `VoiceInputService` initialized.
- **Steps**:
  1. User taps mic button or holds to speak.
  2. Waveform visualizer animates with sound level stream.
  3. User finishes speaking; transcription is auto-dispatched to `AgentCubit.sendMessage()`.
- **Expected Outcome**:
  - Spoken words transcribed accurately.
  - Message bubble appears in ChatScreen.

### TC-VOICE-02: Microphone Permission Denied Handling (T9.1)
- **Type**: Negative
- **Objective**: Ensure graceful error handling when microphone permission is denied.
- **Preconditions**: Microphone permission denied in system settings.
- **Steps**:
  1. User taps mic button.
- **Expected Outcome**:
  - SnackBar error displayed with permission advice.
  - Waveform visualizer does not remain stuck; recording mode cancelled.

### TC-VOICE-03: Streaming Voice Output & Audio Playback Queue (T9.2)
- **Type**: Positive
- **Objective**: Stream and synthesize agent responses using TTS and queue playback sequentially.
- **Preconditions**: Speaker unmuted; `VoiceOutputService` active.
- **Steps**:
  1. Agent finishes response generation (`AgentSuccess`).
  2. Text synthesized via `/audio/speech` TTS endpoint.
  3. Audio chunks queued in `_audioQueue` and played smoothly through `audioplayers`.
- **Expected Outcome**:
  - Audio plays out loud clearly.
  - Consecutive audio chunks transition seamlessly without clipping.

### TC-VOICE-04: Barge-In Interruption on User Interaction (T9.2)
- **Type**: Positive
- **Objective**: Immediately halt speaking audio when user taps microphone to speak.
- **Preconditions**: Agent currently speaking audio response.
- **Steps**:
  1. User taps mic button in input bar.
- **Expected Outcome**:
  - `VoiceOutputService.interrupt()` called instantly.
  - Audio playback stops immediately; audio queue and streaming buffer cleared.
  - Voice recording starts cleanly without audio feedback loop.

### TC-VOICE-05: Speaker Mute/Unmute Toggle in ChatScreen AppBar (T9.2)
- **Type**: Positive
- **Objective**: Allow user to silence/enable audio output on demand.
- **Preconditions**: ChatScreen open.
- **Steps**:
  1. User taps speaker toggle in AppBar (`chat_speaker_toggle`).
  2. Icon switches from `volume_up` to `volume_off`.
  3. Subsequent agent responses remain silent.
  4. User taps speaker toggle again; icon switches back to `volume_up` and volume is restored.
- **Expected Outcome**:
  - Immediate mute toggle without restarting conversation.

### TC-VOICE-06: TTS Synthesis Failure & Error Resilience (T9.2)
- **Type**: Negative
- **Objective**: Prevent app crash when TTS endpoint times out or returns error.
- **Preconditions**: Network disconnected or invalid API key.
- **Steps**:
  1. Call `speakText()` when TTS endpoint unreachable.
- **Expected Outcome**:
  - Returns `Left(Failure)` (`ServerFailure` or `ConnectionFailure`).
  - Error piped to `errorStream`; player queue safely reset to `idle`.

### TC-VOICE-07: Android Quick Settings Tile 1-Tap Activation (T9.3)
- **Type**: Positive
- **Objective**: Verify 1-tap activation from notification drawer Quick Tile activates agent voice mode.
- **Preconditions**: Quick Settings Tile configured in Android notification shade.
- **Steps**:
  1. Tap Flames Agent QS Tile.
  2. Quick tile toggles state to active and collapses shade, launching app with `voice_input` action.
  3. `ChatScreen` receives pending action and initiates voice listening.
- **Expected Outcome**:
  - `FlamesQuickTile` toggles to `active`.
  - Pending action consumed without duplicate triggers.

### TC-VOICE-08: Foreground Service Persistent Notification with Action Buttons (T9.3)
- **Type**: Positive
- **Objective**: Foreground service maintains persistent notification with action controls (Voice Input, Quick Status, Stop).
- **Preconditions**: Foreground service started via `BackgroundService`.
- **Steps**:
  1. Start foreground service with title and content.
  2. Emit action intent (e.g. `quick_status` or `stop`).
- **Expected Outcome**:
  - Notification displayed with action buttons.
  - Action dispatched to `actionStream` or terminates foreground execution cleanly on stop.

### TC-VOICE-09: Safe WakeLock & Bounded Battery Protection (T9.3)
- **Type**: Negative / Boundary
- **Objective**: Prevent battery drain by enforcing bounded timeout on PARTIAL_WAKE_LOCK.
- **Preconditions**: Background operation started.
- **Steps**:
  1. Request WakeLock with timeout exceeding maximum threshold (e.g. 120,000ms).
  2. Request WakeLock with negative or sub-minimum timeout.
- **Expected Outcome**:
  - Timeout clamped within safe bounds (1s - 60s, default 30s).
  - WakeLock automatically released upon timeout or service destruction.

### TC-VOICE-10: Service Lifecycle & Quick Tile State Toggle (T9.3)
- **Type**: Positive
- **Objective**: Verify `manage_background_service` tool properly reports and toggles foreground service and tile states.
- **Preconditions**: Tool registered in `ToolRegistry`.
- **Steps**:
  1. Execute tool with `{"action": "status"}`.
  2. Execute tool with `{"action": "toggle_tile"}`.
  3. Execute tool with `{"action": "start", "title": "Custom Title"}`.
- **Expected Outcome**:
  - Returns structured JSON containing `is_running`, `tile_state`, and `is_wakelock_held`.
  - Tile state toggles between active and inactive.

---

## Summary Matrix

| Module | Positive Cases | Negative Cases | Total Cases |
|---|---|---|---|
| **Module 1: Configuration & Storage** | 1 | 3 | 4 |
| **Module 2: Network & SSE Streaming** | 2 | 4 | 6 |
| **Module 3: ReAct Agent Loop** | 2 | 3 | 5 |
| **Module 4: Tier 1 Ambient Tools** | 3 | 2 | 5 |
| **Module 5: Tier 2 Sensor Tools** | 2 | 3 | 5 |
| **Module 6: Tier 3 HITL Tools** | 2 | 3 | 5 |
| **Module 7: Presentation & UI/UX** | 3 | 1 | 4 |
| **Module 8: Local Workspace & Intelligence (Fase 3)** | 6 | 3 | 9 |
| **Module 9: Streaming Voice & Audio (Fase 4)** | 7 | 3 | 10 |
| **Grand Total** | **28** | **25** | **53** |

---
_Standardized for Hermes Bot Team: PM Bot (`default`), Dev Bot (`dev`), Ops Bot (`ops`)._
