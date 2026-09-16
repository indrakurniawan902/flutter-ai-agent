# Security Audit — T19.6 (Strix, white-box source-only)

Audit date: 2026-09-15
Run id: `flames-audit-t196_d765`
Tool: Strix `strix-agent` 1.6.2, scan mode `deep`, `--max-turns 1000`, `--max-budget 100`
Model: `openai/ag-glm` via the local 9router gateway (per Indra's standing choice; no other provider used)
Target: the full repository at the `development` integration branch, no diff scope (`diff_scope.active = false`)

## Verdict

**17 findings: 2 High, 13 Medium, 2 Low. 0 Critical.**

Overall risk posture reported by the scanner: **Elevated**. The application deliberately delegates device
authority to remote parties, and the controls that are supposed to bound that authority are missing, advisory,
or attached to only one of several paths that reach the same effect.

## Read this before trusting any finding

The VPS has no running app instance, no emulator and no `adb`. This was a **white-box, source-only** engagement.
Every finding is static. Each one carries the label *unconfirmed, not dynamically validated* in its own report,
and the scanner capped confidence at `medium` accordingly (one exception: `vuln-0017` is `confidence: high`
because it was reproduced against a local redirect server using the application's verbatim call shape).

Concretely, this means: **no finding below is claimed to be exploitable as written.** What is proven is that a
control is absent at a named `file:line` and that a complete source-to-sink trace exists. The step that would
turn each into a demonstrated exploit is named in that finding's `counterevidence` / `confidence_rationale`.

Nothing was fabricated to fill the gap. Where coverage could not be reached, it is listed in
[Coverage gaps](#coverage-gaps-explicit) rather than quietly dropped.

## Run state and coverage

| Field | Value |
|---|---|
| `run.json` status | `completed` |
| Started | 2026-09-15T04:45:50Z |
| Ended | 2026-09-15T08:04:12Z (≈3h18m wall clock) |
| Turns logged | 3231 |
| LLM requests / tokens | 3242 requests, 482,031,796 total tokens (8,122,321 output) |
| `coverage.json` completeness | `complete: false` |
| `exit_reason` | `finished_by_tool` (the agent ended the scan itself) |
| Budget stop | **No.** The run was not cut off by `--max-budget`; `status` is `completed`, not `stopped` |
| Surfaces reviewed | 174 |
| Outcomes | reported 54 · ruled_out 91 · no_issue_found 22 · not_applicable 3 · needs_follow_up 4 |
| Findings filed | 17 |
| Coverage gaps recorded | 21 |

`--max-turns 1000` was exceeded (3231 turns logged) and the run still terminated cleanly by its own decision, so
the turn cap did not truncate coverage. The one honest caveat on coverage is the 14 agents that did not finish
cleanly — see [Coverage gaps](#coverage-gaps-explicit).

### Audit object

The audit ran against a throwaway copy of the `development` tree at `/tmp/flames-audit-t196`
(`rsync` of the worktree, no live `.git` history). The frozen tree was commit `a8e532a`.

`development` kept moving during and after the scan. At the time this report was written the tip was `9b95d3f`
(T23.1/T23.2 external-camera removal, then T23.1 `flutter_ffi_uvc` adoption). The delta `a8e532a..9b95d3f` is
**additive-removal only** — it deletes the `external_camera` feature (services, preview screen/cubit/state, tool
registrations, tests) and touches the de-flavor docs/tests. It does **not** add a new network client, a new
exported component, a new agent tool class, or a new credential path.

Two facts matter for reading the findings against today's tip:

1. **Every file carrying a finding's root cause is untouched by the delta.** Verified with
   `git diff --name-only a8e532a development -- <each HIGH file>` -> empty for
   `lib/data/datasources/tools/chat/accessibility_inspector_service.dart`,
   `lib/domain/tools/chat/accessibility_inspector_service.dart`,
   `android/app/src/main/kotlin/ai/hermes/flames/FlamesAccessibilityService.kt`,
   `lib/domain/tools/pairing/pairing_parser.dart`,
   `lib/presentation/screen/pairing/qr_scanner_screen.dart`,
   `lib/presentation/screen/settings/settings_screen.dart`.
2. **`tool_registry.dart` and `AndroidManifest.xml` did change**, but only by removing the external-camera tool
   registrations and their manifest entries. The two HIGH anchors still resolve at the same content at the new
   tip: `ui_find_elements` registration at `tool_registry.dart:1532`, `isValidHttpUrl` at
   `pairing_parser.dart:54`, `_openQrScanner` at `chat_screen.dart:1199`, the `findElementsFormatted` sink at
   `accessibility_inspector_service.dart:136`, and the capture loop at `FlamesAccessibilityService.kt:72`.

The one honest caveat: the *line numbers* cited in the artifact files were computed against `a8e532a`. They were
re-verified against the tip and still land on the same code, but if the files shift again, re-grep the anchor
rather than trusting the number. The scanner's finding set was not re-run against `9b95d3f` — no new scan was
performed, and none of the delta's content would have changed a finding either way.

### Sync honesty

`development` and `origin/development` were both at the tip when this audit ran, and every file carrying a
finding's root cause is untouched by the commits that landed during the scan (see above). The card's note about
VPS-to-GitHub SSH being blocked did not apply on this run — the tip is pushed.

## Severity table

| # | ID | Severity | CVSS | CWE | Confidence | Finding | Primary location | Owner task |
|---|----|----------|------|-----|------------|---------|------------------|------------|
| 1 | vuln-0004 | **HIGH** | 8.1 | — (CWE-1426 class) | medium | Screen text read from any app is injected into the agent prompt as a tool result with no untrusted-data framing | `lib/data/datasources/tools/chat/accessibility_inspector_service.dart:136` | `t_f18878fa` |
| 2 | vuln-0012 | **HIGH** | 7.1 | CWE-346 | medium | Attacker-controlled QR pairing payload becomes the device's active gateway with no destination validation or origin confirmation | `lib/domain/tools/pairing/pairing_parser.dart:54` | `t_66b5dd46` |
| 3 | vuln-0005 | MEDIUM | 6.5 | CWE-863 | medium | Tools with device-state side effects are classified Tier 1 "Read-Only / Ambient" and auto-execute with no authorization gate | `lib/domain/tools/chat/tool_registry.dart:708` | accepted / backlog |
| 4 | vuln-0007 | MEDIUM | 5.3 | CWE-22 | medium | Unrestricted file read and unbounded directory enumeration via `read_device_file` / `list_device_files` | `lib/domain/tools/chat/tool_registry.dart` (file tools) | accepted / backlog |
| 5 | vuln-0009 | MEDIUM | 5.9 | CWE-319 | medium | Credentials can be transmitted over cleartext HTTP/WS because endpoint validators accept `http://` and `ws://` | `lib/domain/services/gateway/gateway_url.dart:14` | accepted / backlog |
| 6 | vuln-0014 | MEDIUM | 6.8 | CWE-22 | medium | Path traversal in share-intent file handling writes attacker-controlled content outside the app cache directory | `lib/domain/services/share/share_target_service.dart:104` | accepted / backlog |
| 7 | vuln-0003 | MEDIUM | 5.1 | CWE-862 | medium | Exported `MainActivity` accepts unvalidated action extra, letting any co-resident app start a mic voice turn and dispatch agent prompts | `android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt:73` | accepted / backlog |
| 8 | vuln-0017 | MEDIUM | 5.3 | CWE-522 | **high** | Gateway bearer token disclosed to an arbitrary origin via WebSocket handshake redirect | `lib/data/datasources/remote/gateway/gateway_socket.dart:59` | accepted / backlog |
| 9 | vuln-0008 | MEDIUM | 4.8 | CWE-863 | medium | Tier-2 OTP extraction tool bypasses the app's own sensitive-notification filter and transmits a live second-factor code off-device | `lib/domain/tools/chat/tool_registry.dart:871` | accepted / backlog |
| 10 | vuln-0015 | MEDIUM | 4.8 | CWE-306 | medium | Gateway WebSocket dispatches privileged tool-call frames before authentication completes | `lib/data/datasources/remote/gateway/gateway_client.dart:259` | accepted / backlog |
| 11 | vuln-0006 | MEDIUM | 4.3 | CWE-863 | medium | Tier-2 permission gate fails open for tools registered without a permission checker | `lib/domain/tools/chat/tool_registry.dart:250` | accepted / backlog |
| 12 | vuln-0001 | MEDIUM | 4.2 | CWE-321 | medium | Release build signed with the public Android debug keystore | `android/app/build.gradle.kts:35` | accepted / backlog |
| 13 | vuln-0010 | MEDIUM | 4.2 | — (CWE-1426 class) | medium | Notification text from any installed app reaches the agent prompt with no data/instruction separation and can drive auto-executing Tier-1 tools | `lib/presentation/screen/chat/cubit/agent_cubit.dart:906` | accepted / backlog |
| 14 | vuln-0016 | MEDIUM | 4.2 | CWE-863 | medium | Inbound gateway chat frame `role` field is unvalidated and can inject a system-role instruction into the LLM context | `lib/domain/entities/gateway/gateway_message.dart:358` | accepted / backlog |
| 15 | vuln-0011 | MEDIUM | 4.0 | CWE-940 | medium | Any co-resident app can auto-submit an agent turn through the exported share-target activity, with no user confirmation and an attacker-chosen URL fetch | `lib/presentation/screen/chat/chat_screen.dart:563` | accepted / backlog |
| 16 | vuln-0002 | LOW | 3.7 | CWE-312 | medium | Sensitive app data included in Android backups because `allowBackup` is unset | `android/app/src/main/AndroidManifest.xml:53` | accepted / backlog |
| 17 | vuln-0013 | LOW | 3.7 | CWE-918 | medium | SSRF via the `read_web_page` agent tool: unrestricted URL fetch reachable from model output and gateway RPC, no permission gate, no host validation | `lib/domain/tools/chat/url_reader_service.dart:58` | accepted / backlog |

Severity counts: **critical 0 · high 2 · medium 13 · low 2 · info 0**.

### Why there is no Critical

The scanner's severity model rates on *demonstrated* impact. With no running app, no finding could be driven to a
proven end-to-end exploit, so the ceiling is High. The two High findings are High on the strength of a complete
source-to-sink trace with the missing control named at a specific location — not on an executed payload.

### Fix cards

Per the card's instruction, CRITICAL and HIGH each get **one dedicated card** in WWA format, assigned to `dev`,
**with no `--parent` link** to this audit card (a parented fix card would sit in `todo` forever with
`claim_rejected: parents_not_done`). Medium/Low/Info are recorded here as *accepted / backlog* and deliberately
**do not** generate cards.

| Finding | Card |
|---|---|
| vuln-0004 (HIGH) | `t_f18878fa` |
| vuln-0012 (HIGH) | `t_66b5dd46` |

## HIGH findings in detail

### 1. vuln-0004 — Screen text reaches the model unframed (CVSS 8.1)

**Location:** `lib/data/datasources/tools/chat/accessibility_inspector_service.dart:135-142` (serialization sink),
`lib/domain/tools/chat/accessibility_inspector_service.dart:176-177` (message constants),
`android/app/src/main/kotlin/ai/hermes/flames/FlamesAccessibilityService.kt:71-72` (collection),
`lib/domain/tools/chat/tool_registry.dart:1719-1728` (tool description)

**Root cause.** The `ui_find_elements` tool reads the accessibility tree of whatever app owns the foreground
window and hands that text to the model as an ordinary tool result. That text is authored by *another app*, not by
Flames and not by the user, yet nothing marks it as untrusted, delimit it, or scan it. The repository already
ships `SkillSecurityScanner` for exactly this payload class, but wires it only to skill import — so screen content
reaches the model bare. The model can then call Tier-1 tools that need no approval (`save_memory`,
`clipboard_write`) and read Tier-1/2 sensitive data. Saved memories are re-injected on later turns as a
`role: "system"` message, which converts transient screen text into persistent highest-authority instructions.
Separately, `captureTree()` never checks `AccessibilityNodeInfo.isPassword` — the identifier appears nowhere in
`android/` or `lib/` — so the client does not exclude secure fields even if a given device redacts them.

**PoC (static).** The finding ships `verify_screen_tree_framing.py`, which mirrors
`AccessibilityTreeSerializer.serialize()` verbatim, prints the resulting tool-result string with an injected
directive intact, and then greps the source tree to show no framing or scan control exists on that path. Not
executed against a live model — the attacker side (a co-resident app rendering the payload window and waiting) was
not run.

**Remediation.** Frame the serialized tree at the single point where it becomes text; reuse `SkillSecurityScanner`
over the tree and prepend matched pattern ids as defence in depth (the framing is the primary control, since a
literal pattern list is evadable by paraphrase); skip `isPassword` nodes and their subtrees in `captureTree`; state
the data class in the tool description. The finding also recommends extending the same boundary to notification
text, web-page text and recalled memory, and demoting recalled memory out of the `system` role.

**Owner task:** `t_f18878fa`

### 2. vuln-0012 — Hostile QR pairing payload becomes the active gateway (CVSS 7.1)

**Location:** `lib/domain/tools/pairing/pairing_parser.dart:53-62` (the only destination control),
`lib/presentation/screen/chat/chat_screen.dart:1199-1238` (activation),
`lib/presentation/screen/settings/settings_screen.dart:158-171` (second entry point),
`lib/data/datasources/remote/gateway/gateway_client.dart:211-216` (socket + auth frame)

**Root cause.** Pairing accepts a fully attacker-controlled payload (a QR code anyone can print, or the same JSON
pasted into the manual-entry dialog). The only validation on `gatewayUrl` is a scheme check: `http`/`https` with a
non-empty authority. There is no host allowlist, no same-origin check, and no rejection of URL user-info — so a
payload whose readable prefix names a trusted host can resolve to a different one
(`https://trusted.example@pair.evil.example` passes). The app then persists the destination as the active
profile, overwrites the stored base-URL/API-key pair, connects, and writes its authentication frame in the same
interaction. The only user feedback is a success message echoing the attacker-chosen `profileName`. The paired
origin subsequently receives the full device tool manifest and a working RPC channel.

**PoC (static).** `poc_script_code` mirrors the Dart predicate exactly, showing that both the plain attacker URL
and the user-info-confusion variant are accepted and that the socket contacts `pair.evil.example` in both cases.
The end-to-end steps (scan the QR, observe the success snackbar, receive the tool manifest) were traced in source,
not executed.

**Remediation.** Require explicit user confirmation of the *resolved* origin (scheme, host, port as actually
contacted — not the raw payload string) before persisting or connecting, at both entry points; reject payloads
carrying user-info; require HTTPS/WSS for any destination outside a private address range.

**Owner task:** `t_66b5dd46`

## MEDIUM / LOW findings — accepted / backlog

These are recorded for the record and **not** dispensed as work cards. Several are real defects with low fix
effort; they are listed here so PM can decide whether to schedule them, per the card's instruction not to
dispense cosmetic work without a PM decision. Grouped by theme.

**Unvalidated trust anchors**
- `vuln-0009` (MEDIUM, 5.9) — `acceptedGatewayUrlSchemes` admits `http`/`ws`; the stored API key / gateway token
  is attached to whatever endpoint results. The scanner explicitly disproved the "Android 9+ blocks cleartext"
  assumption for this build: the pinned Flutter engine never consults the Android cleartext policy and permits
  loopback unconditionally. The project's own docs recommend plain-HTTP LAN endpoints.
- `vuln-0017` (MEDIUM, 5.3, **confidence high**) — `WebSocket.connect()` uses a shared `HttpClient` whose requests
  default to `followRedirects = true`, so a `30x` on the handshake forwards the socket — and the bearer token
  written immediately after it — to a different origin. Reproduced against a local redirect server.

**Transport-level authorization**
- `vuln-0015` (MEDIUM, 4.8) — `_handleIncomingData` intercepts only auth frames while `connecting`; every other
  frame type falls through to a dispatcher whose "If connected:" comment is not backed by a state test. A peer
  answering the configured origin can drive tool execution during the 10 s auth timeout, re-opened on each of up
  to 10 reconnect attempts.
- `vuln-0016` (MEDIUM, 4.2) — the inbound chat frame `role` is taken from the wire, persisted, and re-serialized
  unfiltered, so a frame declaring `role: "system"` gains instruction authority.

**Device-tool authorization**
- `vuln-0005` (MEDIUM, 6.5) — six state-modifying tools are Tier 1 and auto-execute. Provably a defect rather
  than policy: `send_local_notification` (Tier 1) and `schedule_reminder` (Tier 3) are registered against the same
  service in the same method. `SecurityPolicy.isAutoExecute` is referenced nowhere in the repository.
- `vuln-0006` (MEDIUM, 4.3) — the Tier-2 gate is `requiresPermission(tier) && checkPermission != null`, so a
  Tier-2 tool with no checker skips permission evaluation and executes like Tier 1. Seven registrations are in
  this state. Note the scanner's own caveat: several omissions are deliberate so a service can return a more
  actionable error, so the fix must be scoped, not blanket.
- `vuln-0008` (MEDIUM, 4.8) — `extract_latest_otp` returns a live one-time code to the configured LLM endpoint
  while the sibling notification tool deliberately filters OTP/banking notifications. Tier 2 = auto-execute after
  a one-time listener grant, with no per-use confirmation.
- `vuln-0007` (MEDIUM, 5.3) — `read_device_file` / `list_device_files` pass a model-supplied absolute path to
  `File(...).readAsBytes()` / `Directory(...).list()` with no containment check. The declared workspace boundary
  exists only in the tools' prose. `list_device_files` is Tier 1 with `recursive: true` and therefore has no gate.
- `vuln-0013` (LOW, 3.7) — `read_web_page` accepts loopback, private, link-local and cloud-metadata addresses,
  reachable from model output and from an inbound gateway RPC frame. The validator behaviour was confirmed by
  executing the exact function in a standalone Dart runtime.

**Exported component surface**
- `vuln-0003` (MEDIUM, 5.1) — exported `MainActivity` reads `extra_flames_action` from any intent and forwards it
  to Dart with no allowlist: `voice_input` starts a 15 s mic capture, `quick_status` sends a canned prompt to the
  agent. Any co-resident app, needing no permissions, can trigger this.
- `vuln-0011` (MEDIUM, 4.0) — the exported `ACTION_SEND` / `ACTION_SEND_MULTIPLE` filters route shared text into
  the chat pipeline, which submits it as a user turn with no confirmation, and prefetches any URL it contains.
- `vuln-0014` (MEDIUM, 6.8) — `receive_sharing_intent` 1.9.0 copies a provider-controlled `_display_name` into a
  path with no sanitisation, so a malicious provider can write outside the cache directory into the app's private
  data directory (all three SQLite DBs, the Hive store, secure-storage prefs). The guard belongs in the app's own
  mapping layer, treating the plugin as untrusted.

**Prompt-injection surface**
- `vuln-0010` (MEDIUM, 4.2) — notification title/body from any app reaches the model as a tool result with no
  delimiting, no length cap and no scan, and can drive auto-executing Tier-1 tools.

**Build / release hygiene**
- `vuln-0001` (MEDIUM, 4.2) — `release` signs with `signingConfigs.getByName("debug")` and no `key.properties`,
  `.jks` or `.keystore` exists anywhere in the repo. The shipped release APK is signed with a key any third party
  can reproduce; the app cannot be published under a trustworthy signing identity.
- `vuln-0002` (LOW, 3.7) — no `android:allowBackup`, `fullBackupContent` or `dataExtractionRules`, so Android's
  default `allowBackup=true` sweeps chat transcripts, the memory vault, imported skills and the Action Center
  inbox into cloud backups and device-to-device transfers.

## Positive results (worth recording, not padding)

The scanner affirmatively disproved several suspected classes with named controls, and in two cases with an
executed harness:

- **Credentials at rest are properly protected** — key-store wrapped, not plaintext. No secret reaches any log.
  `Secrets At Rest And In Logs` ruled out 9 surfaces and filed 1 (the debug-keystore finding).
- **No analytics, crash-reporting or telemetry SDK**, and no hardcoded credentials in the source.
- **The pinned dependency surface is clean against OSV**, checked with positive controls to confirm the negative
  was trustworthy.
- **Memory vault FTS5 is not injectable.** All FTS5/LIKE SQL is parameterized; `_extractWords` strips every
  character outside `[A-Za-z0-9_\s]` before `_sanitizeFtsQuery` runs, and the MATCH value is bound as `?`. Proven
  empirically with a PoC against a real SQLite FTS5 instance: 20 operator payloads, none altered the query, and
  `'; DROP TABLE memories; --` produced 0 rows with the table intact. Residual (over-match, not injection): `_`
  survives as a LIKE wildcard.
- **The Piper TTS download/extract path held** (`TTS Download Extract And Skills Loader`: 4 ruled out, 2 no issue).
  The tar extraction loop was exercised on aarch64 with crafted archives.
- **Several prompt-injection candidates were ruled out with named controls** (`Skill And Tool-Result Injection
  Validator`: 7 ruled out; `Split-Write Credential Exfil Adversary`: 2 ruled out).

## Coverage gaps (explicit)

**These surfaces were NOT covered, or were covered only partially. Do not read this section as "clean".**

`coverage.json` records `completeness.complete = false` with this caveat:

> 14 agent(s) did not finish cleanly (Adversarial Validator: Share Intent Auto-Submit, Gateway Cleartext And
> Redirect Token Exposure Validator, Gateway Frame System-Role Context Injection Validator, Gateway RPC Tier-2
> Gate SSRF Validator, HITL Approval Slot Race Validator, Intent-Action-Trigger Validator, Memory Injection
> Validator, Memory Vault Injection Validator, Notification Injection Independent Validator And Filer, OTP
> Control Bypass Validator And Filer, Pre-Auth Frame Dispatch Validator, Share-Intent SSRF Validator, Skill Import
> Advisory-Scanner Validator, Skill Loader Ingest Validator); any surface they held is under-covered.

### Open proof gaps (4) — a control is missing, but the consequence was not observable here

1. **`FlamesAccessibilityService.captureTree()` password/secure-field handling.** `isPassword` is never called
   and appears nowhere in `android/` or `lib/`. Whether the platform already redacts password text before an
   accessibility service sees it is device/OEM dependent and could not be verified. The missing *client-side*
   control is established; actual secret capture is not. Fix is folded into vuln-0004; device verification of both
   the gap and the fix remains open.
2. **Residual Tier-1 side-effecting tools.** `speak_text` (`tool_registry.dart:1119`, tier at `:1138`),
   `open_map_navigation` (`:1442`, tier at `:1462`) and `list_device_files` (`:793`, tier at `:809`) share the
   vuln-0005 root cause but were deliberately excluded from that fix set as lower impact. Flagged, not dropped.
3. **HITL approval-slot integrity across concurrent turns.** Approval is bound to the shared mutable slot
   `_pendingToolCall` (`agent_cubit.dart:64`) rather than to the request the user is looking at;
   `approveAction` re-reads the slot (`:606-614`) and never compares it with `state.request`. A second turn can
   start while a Tier-3 approval is pending because `sendMessage` has no busy/awaiting-approval guard
   (`:502-536`) — and two unguarded entry points reach it: the exported share intent
   (`chat_screen.dart:386-398 -> :531-565`) and the NFC trigger (`agent_cubit.dart:561-580`). **Cross-turn
   approval confusion was not proven**; the shared-slot design is.
4. **Runtime confirmation of the readable path set** for `read_device_file` against app-private storage
   (`databases/flames_memory.db`, `flames_skills.db`). No Android build was possible, so which absolute paths the
   app process can actually open at runtime was not observed. Reported in vuln-0007 at `confidence: medium`.

### Risk classes assigned to agents but with no coverage entry recorded (4)

Treat these as **unexamined, not clean**:

- `business_logic` — assigned to 8 agents (HITL Approval Slot Race Validator, Intent-Action-Trigger Validator,
  Memory Injection Validator, Tier-1 Misclassification Validator ×2, Validate MainActivity Action Injection,
  Validate Share Intent Auto-Submit And SSRF, Voice Action Center And Local Storage); no coverage entry records
  the class being assessed.
- `header_injection` — assigned to Gateway Transport And Token Attach; no coverage entry.
- `insecure_file_uploads` — assigned to Android IPC And Intent Surface and Validate Share Provider Path
  Traversal Write; no coverage entry.
- `semantic_confusion` — assigned to Adversarial Validator: Share Intent Auto-Submit, Split-Write Credential
  Exfil Adversary, Tar Extraction Bypass Validator; no coverage entry.

### Agents that ran without recording any coverage (13)

`Adversarial Validator: Share Intent Auto-Submit`, `HITL Approval Slot Race Validator`,
`Intent-Action-Trigger Validator`, `Memory Injection Validator`, `Memory Vault Injection Validator`,
`Notification Injection Independent Validator And Filer`, `OTP Control Bypass Validator And Filer`,
`Pre-Auth Frame Dispatch Validator`, `SSRF Refutation Checker`, `Share-Intent SSRF Validator`,
`Skill Import Advisory-Scanner Validator`, `Skill Loader Ingest Validator`, `Tier-2 Gate Independent Validator`.

Ten of these stopped (`status: stopped`) and three completed without recording coverage. **Whatever they examined
is absent from the ledger.** This is the single biggest reason `completeness.complete` is `false`.

### Not covered at all

- **No dynamic validation of anything.** No emulator, no `adb`, no running app, no Android build. Every stochastic
  and platform-dependent step is unobserved: whether a model complies with injected text, whether a speech
  recogniser opens, whether a filesystem write lands outside its intended directory.
- **Non-Android platform folders** (iOS, macOS, Linux, Windows, web) were excluded except where a contradiction
  with an Android conclusion would have been material; none was found.
- **Vendored third-party code** was reviewed only where the application calls into it.

### Retest guidance

Before any remediation is called complete, the specific unobserved steps must be validated on hardware: pair with
a controlled gateway using a crafted payload and confirm the destination is shown and confirmed before any auth
frame; send a tool-call frame before the auth result and confirm nothing executes; confirm a checker-less Tier-2
tool is refused; confirm injected text from a notification / the screen / recalled memory does not cause a tool
invocation and that tool results are visibly framed as data; confirm a crafted `content://` provider cannot write
outside the intended directory and a crafted share intent cannot auto-submit a turn; confirm the handshake's
redirect behaviour against a controlled `30x` responder.

## Artifacts

Committed alongside this document under `strix_runs/flames-audit-t196_d765/`:

| File | Contents |
|---|---|
| `run.json` | Run state, scope, LLM usage, and the scanner's own executive summary / methodology / technical analysis / recommendations |
| `coverage.json` | 174 surface entries with per-surface outcome and evidence, plus the 21 recorded gaps |
| `vulnerabilities.json` | Machine-readable findings — `id, title, severity, cwe, cvss, confidence, code_locations, poc_description, poc_script_code, remediation_steps, fix_pr_body, target` |
| `findings.sarif` | SARIF export |
| `vulnerabilities/vuln-0001.md` … `vuln-0017.md` | Full per-finding reports with evidence, PoC, remediation and fix verification |

Deliberately **not** committed: the Strix sandbox working directory (`.state/agents.db`, `.state/*.json`) and
`strix.log` (the sandbox runtime log). Those are scan internals, not reviewable findings.

Before committing, the artifacts were checked for leaked credentials: **0 occurrences** of the 9router API key
across every committed file, no live-looking credential matching `sk-…` / `nvapi-…` / `ghp_…` / `AKIA…`, and no
internal gateway host or IP present.

## Provenance of this run

- Scanner invoked through the verified wrapper `~/.local/bin/strix-run.sh` (handles the three known VPS traps:
  `STRIX_DOCKER_SANDBOX_NETWORK=shared_9r`, the `~/.strix/cli-config.json` override, and the `openai/` provider
  prefix).
- Sandbox-to-gateway reachability probed before the scan: `shared_9r` -> HTTP 200; default `bridge` -> 000
  (expected). Recorded so the 200 is evidence rather than assumption.
- Telemetry disabled (`STRIX_TELEMETRY=0`). No application data left the host.
- Target mounted from a throwaway copy so the scan could not dirty a checkout other workers hold worktrees on.
