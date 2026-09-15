# Comprehensive Test Cases: Flutter Mobile AI Agent (MVP)

**Document:** `docs/TESTCASES.md`  
**Project:** Flutter AI Agent (Personal Action-Oriented Mobile Agent)  
**Author:** PM Bot (`default`)  
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
8. [Module 8: Hermes Nous UI, Bottom Navigation & Micro-UI (Fase 5)](#module-8-hermes-nous-ui-bottom-navigation--micro-ui-fase-5)
9. [Module 9: Mobile Skills Hub, Share Target & Intent Launcher (Fase 6)](#module-9-mobile-skills-hub-share-target--intent-launcher-fase-6)
10. [Module 10: Android Build & 16 KB Page Size Compliance (Fase 7)](#module-10-android-build--16-kb-page-size-compliance-fase-7)

---

## Module 1: Configuration & Encrypted Storage (Settings)

### TC-SET-01: Save Valid Configuration
- **Type**: Positive
- **Objective**: Verify that valid endpoint parameters (Base URL, API Key, Model, Temperature) are stored securely and retrieved accurately.
- **Preconditions**: App is running; user navigates to `SettingsScreen`.
- **Steps**:
  1. Input Base URL: `https://example.com/v1`.
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
  1. Input Base URL: `not-a-valid-url` or `ftp://example.com`.
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

## Module 8: Hermes Nous UI, Bottom Navigation & Micro-UI (Fase 5)

### TC-NOUS-01: Full 5-Tab Persistent Navigation Shell Cycle
- **Type**: Positive
- **Objective**: Verify seamless navigation across all 5 primary tabs in `MainNavigationShell` via `FloatingBottomNavBar`.
- **Preconditions**: App launched with `HermesTheme.darkTheme`.
- **Steps**:
  1. Boot application $\to$ verify Tab 0 (`ChatScreen`) active.
  2. Tap `nav_item_skills` $\to$ verify Tab 1 (`SkillsHubScreen`) displayed with search field, category pills, and skill cards.
  3. Tap `nav_item_node` $\to$ verify Tab 2 (`PocketNodeScreen`) displayed with status chip, RPC telemetry card, and ambient switches.
  4. Tap `nav_item_vault` $\to$ verify Tab 3 (`MemoryVaultScreen`) displayed with FTS5 badge and search input.
  5. Tap `nav_item_settings` $\to$ verify Tab 4 (`SettingsScreen`) displayed with LLM configuration and server profiles.
  6. Tap `nav_item_chat` $\to$ return to Tab 0 (`ChatScreen`).
- **Expected Outcome**:
  - `IndexedStack` smoothly transitions between tabs without rebuilding unmounted screens.
  - Floating navigation bar updates active tab indicator accurately.
  - No flickering or memory leaks across repeated cycles.

### TC-NOUS-02: Cross-Tab State Retention & IndexedStack Preservation
- **Type**: Positive
- **Objective**: Confirm that user input, filters, and dynamic screen states are strictly preserved during tab switches.
- **Preconditions**: User has initialized app on Tab 0.
- **Steps**:
  1. In Tab 0 (`ChatScreen`): Type draft prompt `"Persistent prompt state testing"` in `chat_input_field`.
  2. In Tab 1 (`SkillsHubScreen`): Tap category filter pill `skills_filter_pill_device`.
  3. In Tab 3 (`MemoryVaultScreen`): Type query `"router"` into `memory_search_input`.
  4. In Tab 2 (`PocketNodeScreen`): Toggle ambient trigger switch.
  5. In Tab 4 (`SettingsScreen`): View server profiles list.
  6. Return to Tab 0, Tab 1, Tab 2, and Tab 3 sequentially.
- **Expected Outcome**:
  - Chat text field retains `"Persistent prompt state testing"`.
  - Skills category pill remains filtered on `device`.
  - Memory search field retains `"router"`.
  - Pocket node toggle switch preserves its modified boolean state.

### TC-NOUS-03: HeaderConsoleBar Telemetry & Gateway Status
- **Type**: Positive
- **Objective**: Verify HeaderConsoleBar renders GatewayStatusChip and AchievementTierBadge in chat header.
- **Preconditions**: Chat screen open.
- **Verification Points**:
  - `GatewayStatusChip` displays active port/status (e.g., `"Running 8644"`).
  - `PulsingDot` animates smoothly with emerald/teal hue (forward once in automated tests).
  - `AchievementTierBadge` renders tier rank (e.g., `"Olympian • 47/60 Badges"`) with lightning bolt material icon.
  - Zero overflow on narrow viewport widths down to 320px.

### TC-NOUS-04: Live Action Stepper Card Lifecycle & Accordion Inspection
- **Type**: Positive
- **Objective**: Verify multi-step tool execution pipelines render using `LiveActionStepperCard`.
- **Preconditions**: Multi-step tool pipeline dispatched by agent.
- **Steps**:
  1. Stream assistant response containing multi-step `actionSteps`.
  2. Observe progress pill indicating completion ratio (e.g., `"1/3 Completed"`).
  3. Observe step state indicators: Done (`Icons.check_circle_rounded`), In Progress (Teal spinner), Pending (`Icons.radio_button_unchecked`).
  4. Tap individual step row to toggle accordion expansion.
- **Expected Outcome**:
  - Accordion expands to reveal `Parameters` and `Output JSON` formatted in monospace JetBrains Mono font (`HermesTypography.monospaceCode`).
  - Tapping again smoothly collapses the section.
  - Zero emoji characters used in icons or headers.

### TC-NOUS-05: Generative Micro-UI: ActionConfirmationCard & SummaryCard
- **Type**: Positive
- **Objective**: Ensure interactive micro-UI cards render in chat stream and handle callbacks cleanly.
- **Preconditions**: Agent emits `ActionConfirmationData` and `SummaryCardData` in chat message.
- **Steps**:
  1. Verify `ActionConfirmationCard` renders title, message, parameters map, danger tier badge, and zero emojis.
  2. Tap primary authorization button (`action_confirmation_primary_btn`) $\to$ triggers `approveAction()` callback.
  3. Verify `SummaryCard` renders execution summary text, metric pills (Tools Run, Duration, Status), and copy button.
  4. Tap copy button (`summary_card_copy_btn`) $\to$ copies summary text to system clipboard and temporarily renders `"Copied"`.
- **Expected Outcome**:
  - Both cards render within chat message stream without layout overflow.
  - Buttons respond instantly to touch interactions and update their states.

### TC-NOUS-06: Tab Switching During Active Streaming / Tool Execution
- **Type**: Negative
- **Objective**: Ensure switching tabs while an active stream, ReAct loop, or micro-UI card is active does not corrupt state or crash.
- **Preconditions**: Chat session contains active conversation history and action stepper cards.
- **Steps**:
  1. Trigger multi-step action execution on Tab 0 (`ChatScreen`).
  2. Switch to Tab 1 (`SkillsHubScreen`) and Tab 4 (`SettingsScreen`).
  3. Switch back to Tab 0 (`ChatScreen`).
  4. Submit new prompt into input field.
- **Expected Outcome**:
  - Stream/loop does not throw `Bad state` or unhandled exceptions.
  - All existing messages, stepper cards, and headers remain intact upon returning to Tab 0.
  - Input field accepts new user messages cleanly.

### TC-NOUS-07: Anti-Slop & Zero-Emoji Conformance Across All 5 Tabs
- **Type**: Positive
- **Objective**: Ensure complete application adheres to dark surface `#0F172A`, electric teal `#008080`, and zero emoji in chrome.
- **Preconditions**: All 5 tabs visited in navigation shell.
- **Verification Points**:
  - Material icons (`Icons.*`) used exclusively across navigation bar, app bars, cards, buttons, and status chips.
  - No decorative gradients, pastel cards, or rainbow highlights.
  - High-contrast typography adhering to WCAG AA / AAA standards.

---

## Module 9: Mobile Skills Hub, Share Target & Intent Launcher (Fase 6)

### TC-SKILL-01: Active Skills Matching & System Prompt Injection
- **Type**: Positive
- **Objective**: Verify active skills are matched to incoming prompts and injected into the LLM system prompt via `SkillsRegistryService.buildSystemPrompt()`.
- **Preconditions**: `whatsapp_outreach` skill enabled with tools `['open_whatsapp_chat']`; `AgentCubit` wired with `skillsRegistryService`.
- **Steps**:
  1. Register `whatsapp_outreach` skill with instructions `"Always confirm recipient phone"`.
  2. Send prompt `"Send WhatsApp to Budi"`.
  3. Capture `messages` passed to `LlmRepository.streamCompletion`.
- **Expected Outcome**:
  - First message has `role: system` and contains `whatsapp_outreach` plus its instructions.
  - Disabled skills are excluded from the system prompt.
  - `ToolRegistry` exposes `open_whatsapp_chat` in OpenAI tool definitions.
  - E2E coverage: `test/integration/e2e_fase6_skills_test.dart` full pipeline test.

### TC-SKILL-02: Disabled Skill Disables Tools in ToolRegistry
- **Type**: Negative
- **Objective**: Ensure disabling a skill in `SkillsRegistryService` disables its tools via `syncWithToolRegistry` and blocks execution with a policy error.
- **Preconditions**: `browser_opener` skill owns `open_external_url`; tool registered in `ToolRegistry`.
- **Steps**:
  1. Call `setSkillEnabled('browser_opener', false)`.
  2. Call `syncWithToolRegistry(toolRegistry)`.
  3. Send prompt `"Open https://flutter.dev/docs"` where LLM emits `open_external_url`.
- **Expected Outcome**:
  - `isToolEnabled('open_external_url')` returns `false`.
  - `getOpenAiToolDefinitions()` excludes `open_external_url`.
  - `AgentCubit` does not enter `WaitingApproval`; tool message contains `"disabled by skill policy"`.
  - `UrlLauncherProvider.launchUrl` is never called.

### TC-SKILL-03: Re-Enabling Skill Restores Tool Access
- **Type**: Positive
- **Objective**: Verify re-enabling a skill restores its tools for the ReAct loop.
- **Preconditions**: `browser_opener` previously disabled as in TC-SKILL-02.
- **Steps**:
  1. Call `setSkillEnabled('browser_opener', true)`.
  2. Call `syncWithToolRegistry(toolRegistry)`.
  3. Send prompt `"Open https://flutter.dev/docs"` again.
- **Expected Outcome**:
  - `isToolEnabled('open_external_url')` returns `true`.
  - `getOpenAiToolDefinitions()` includes `open_external_url`.
  - `buildSystemPrompt()` contains `browser_opener`.
  - Agent auto-executes the tool and ends in `AgentSuccess`.

### TC-SHARE-01: External App Share Intake & Suggested Prompt Generation
- **Type**: Positive
- **Objective**: Verify OS share intents flow through `ShareTargetService` and `ShareTargetCubit` into a suggested chat prompt.
- **Preconditions**: `ShareMediaProvider.getInitialMedia()` returns one `SharedMediaType.text` entry.
- **Steps**:
  1. Init `ShareTargetCubit` with real `ShareTargetService`.
  2. Observe state transitions.
  3. Read `ShareTargetReceived.suggestedPrompt`.
- **Expected Outcome**:
  - State ends in `ShareTargetReceived` with one `SharedPayloadKind.text` payload.
  - `suggestedPrompt` contains the shared text via `SharedPayload.buildSuggestedPrompt()`.
  - URL shares map to `SharedPayloadKind.url` with prompt `"Summarize this shared link: <url>"`.
  - Blank paths are dropped by `mapMediaFiles`.

### TC-SHORTCUT-01: QuickActions OS App Shortcuts Registration & Dispatch
- **Type**: Positive
- **Objective**: Verify `QuickActionsService` registers default OS shortcuts and dispatches `actionStream` triggers.
- **Preconditions**: `QuickActionsProvider` mocked.
- **Steps**:
  1. Call `QuickActionsService.initialize()`.
  2. Capture `setShortcutItems` argument and provider init callback.
  3. Fire `action_voice_chat`, `action_ask_camera`, `action_scan_qr` through the callback and `handleAction`.
- **Expected Outcome**:
  - `setShortcutItems` called once with 3 items: `action_voice_chat`, `action_ask_camera`, `action_scan_qr`.
  - `actionStream` emits all three types in order.
  - `handleAction` pushes directly into `actionStream`.

### TC-INTENT-01: Tier 3 WhatsApp Intent Launch via HITL Approval
- **Type**: Positive
- **Objective**: Verify `open_whatsapp_chat` pauses in `WaitingApproval` and launches a `wa.me` link only after `approveAction()`.
- **Preconditions**: Contact tools registered; `UrlLauncherProvider.canLaunchUrl` returns `true`.
- **Steps**:
  1. Send prompt requiring `open_whatsapp_chat` with `phone: +6281234567890`, `message: Hello Budi`.
  2. Verify `WaitingApproval` and that no launch occurred yet.
  3. Call `approveAction()`.
- **Expected Outcome**:
  - Pending request holds `phone` and `message` parameters.
  - After approval, `launchUrl` called once with `https://wa.me/6281234567890?text=Hello%20Budi`, `LaunchMode.externalApplication`.
  - Final state is `AgentSuccess` with confirmation text.

### TC-INTENT-02: Tier 2 External URL Intent Auto Launch
- **Type**: Positive
- **Objective**: Verify `open_external_url` executes without HITL and opens the browser via `UrlLauncherProvider`.
- **Preconditions**: Shared URL `https://flutter.dev/docs`; skill `browser_opener` enabled.
- **Steps**:
  1. Feed `ShareTargetReceived.suggestedPrompt` into `AgentCubit.sendMessage`.
  2. LLM emits `open_external_url` with the shared URL.
- **Expected Outcome**:
  - No `WaitingApproval` state; loop proceeds to `AgentSuccess`.
  - `launchUrl` called with `Uri.parse('https://flutter.dev/docs')`, `LaunchMode.externalApplication`.
  - Tool message has `name: open_external_url` and content `"Opened URL: ..."`.

### TC-INTENT-03: Tier 3 HITL Rejection Blocks External Launch
- **Type**: Negative
- **Objective**: Ensure `rejectAction()` on `open_whatsapp_chat` prevents any external launch and reports rejection to the LLM.
- **Preconditions**: Agent paused in `WaitingApproval` for `open_whatsapp_chat`.
- **Steps**:
  1. Call `rejectAction()`.
  2. Inspect tool history and launcher mocks.
- **Expected Outcome**:
  - `launchUrl` and `canLaunchUrl` are never called.
  - Tool message contains `"rejected by user"` with `toolCallId` preserved.
  - Loop resumes; LLM final text acknowledges cancellation; state ends in `AgentSuccess`.

### TC-E2E-06: Full Share to WhatsApp Pipeline (Share, Skills, ReAct, HITL, Intent)
- **Type**: Positive
- **Objective**: Validate the complete Fase 6 chain: external share to suggested prompt to skill injection to ReAct reasoning to HITL gate to WhatsApp intent.
- **Preconditions**: All Fase 6 services wired with mocked providers; LLM stubbed for 2 turns.
- **Steps**:
  1. Receive `SharedPayload(text: 'Chat Budi about tomorrow meeting')` via `ShareTargetCubit`.
  2. Build suggested prompt and send into `AgentCubit` with `whatsapp_outreach` active.
  3. LLM returns `open_whatsapp_chat`; verify system prompt injection and `WaitingApproval`.
  4. Call `approveAction()` and verify `wa.me` launch.
- **Expected Outcome**:
  - Each stage observable: `ShareTargetReceived` to system prompt containing `whatsapp_outreach` to `WaitingApproval` to `launchUrl(wa.me, externalApplication)` to `AgentSuccess`.
  - Zero emoji in chrome and log strings; `flutter test test/integration/e2e_fase6_skills_test.dart` passes 5/5.

---

## Module 10: Android Build & 16 KB Page Size Compliance (Fase 7)

Scope note: Google Play's 16 KB page size requirement applies to 64-bit ABIs only
(`arm64-v8a`, `x86_64`). 32-bit `armeabi-v7a` binaries may stay 4 KB aligned.
Source: https://developer.android.com/guide/practices/page-sizes

### TC-16KB-01: Every 64-bit `.so` in the built APK is 16 KB aligned (PT_LOAD)
- **Type**: Positive
- **Objective**: Prove 16 KB support from the `.so` files actually bundled in our APK, not from a
  plugin repository. Claims about a plugin's own prebuilts are not accepted as evidence.
- **Preconditions**: `development` checked out.
- **Steps**:
  1. `sh tool/build_apk.sh` (on this aarch64 host the Android SDK's x86-64 host binaries need the
     `LD_LIBRARY_PATH` the script sets; a bare `flutter build apk` fails in `processDebugResources`).
  2. `unzip -o -q build/app/outputs/flutter-apk/app-debug.apk -d /tmp/t235_apk`
  3. For each `.so` under `/tmp/t235_apk/lib/arm64-v8a` and `lib/x86_64`:
     `readelf -lW <file>.so | grep LOAD`
- **Expected Outcome**:
  - Every `PT_LOAD` line ends with an `Align` of `0x4000` (16 KB) or larger, e.g. `0x10000` (64 KB).
  - `0x1000` (4 KB) on a 64-bit ABI is a failure.
- **Measured (2026-09-15, arm64-v8a, all PASS)**:
  ```
  libVkLayer_khronos_validation.so  0x10000
  libbarhopper_v3.so                0x4000
  libdartjni.so                     0x4000
  libflutter.so                     0x10000
  libimage_processing_util_jni.so   0x4000
  libonnxruntime.so                 0x4000
  libsherpa-onnx-c-api.so           0x4000
  libsherpa-onnx-cxx-api.so         0x4000
  libsqlite3.so                     0x4000
  libsurface_util_jni.so            0x4000
  ```
  `x86_64` is identical in verdict (all `0x4000`, `libflutter.so` at `0x10000`).

### TC-16KB-02: APK zip alignment is 16 KB (`zipalign`)
- **Type**: Positive
- **Objective**: Uncompressed shared libraries must sit on 16 KB zip boundaries.
- **Steps**: `zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk`
- **Expected Outcome**: last line `Verification successful`, exit code 0.
- **Measured**: `Verification successful`, exit 0.

### TC-16KB-03: GNU_RELRO segments are 16 KB aligned on 64-bit ABIs
- **Type**: Positive
- **Objective**: A RELRO range whose end is not 16 KB aligned can segfault at load time.
- **Steps**: `readelf -lW <file>.so | grep GNU_RELRO`, then `(VirtAddr + MemSiz) % 0x4000 == 0`.
- **Expected Outcome**: every 64-bit `.so` passes.
- **Measured**: all 64-bit `.so` PASS. Every RELRO segment in this APK spans its entire containing
  `LOAD` segment (`relro.memsz >= load.memsz`), and bionic's
  `_extend_gnu_relro_prot_end()` extends protection to that `LOAD` segment's page-aligned end, so
  the raw formula's non-zero remainder is benign. The literal formula flags Google's own
  `libflutter.so`, which demonstrably runs on 16 KB devices, which is why the corrected verdict is
  recorded rather than the raw one.

### TC-16KB-04: 32-bit `armeabi-v7a` misalignment is out of Play scope
- **Type**: Boundary
- **Objective**: Record, without hiding, that one 32-bit library is still 4 KB aligned.
- **Measured**: `libbarhopper_v3.so` (`armeabi-v7a`, 3244440 bytes, from
  `play-services-mlkit-barcode-scanning` via `mobile_scanner`) has all three `LOAD` segments at
  `0x1000`:
  ```
  LOAD 0x000000 0x00000000 0x00000000 0x30b690 0x30b690 R E 0x1000
  LOAD 0x30c000 0x0030c000 0x0030c000 0x061a8  0x07000  RW  0x1000
  LOAD 0x3121a8 0x003131a8 0x003131a8 0x059d8  0x27d05  RW  0x1000
  ```
- **Verdict**: NOT a Play blocker (64-bit ABIs are clean and every ABI the app ships is covered).
  If 32-bit support is ever dropped, this disappears with it.

### TC-BUILD-01: `flutter build apk` succeeds on development
- **Type**: Positive
- **Objective**: An APK must be buildable, otherwise no 16 KB claim can be audited at all.
- **Steps**: `sh tool/build_apk.sh`
- **Expected Outcome**: exit 0 and `build/app/outputs/flutter-apk/app-debug.apk` exists.
- **Measured**: exit 0; APK is 286135598 bytes.
- **Note**: on this aarch64 host the SDK's x86-64 host binaries (aapt2, cmake, ninja, zipalign) need
  `LD_LIBRARY_PATH` pointing at the x86-64 system libs; `tool/build_apk.sh` sets it and restarts the
  Gradle daemon so it inherits the environment. Three pre-existing defects also had to be fixed
  first: a wrong `NotificationListenerService` import in `MainActivity.kt`, a raw string in the
  accessibility service `android:description` attribute, and `contacts_service` 0.6.3's Gradle 4 era
  build script.

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
| **Module 8: Hermes Nous UI & Micro-UI** | 6 | 1 | 7 |
| **Module 9: Skills Hub, Share & Intents** | 7 | 2 | 9 |
| **Module 10: Android Build & 16 KB Compliance** | 4 | 0 | 4 |
| **Grand Total** | **32** | **22** | **54** |

---
_Standardized for Hermes Bot Team: PM Bot (`default`), Dev Bot (`dev`), Ops Bot (`ops`)._
