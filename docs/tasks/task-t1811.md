# T18.11: Gateway mode thinking/busy feedback + stop (chat_cancel)

## Task ID
t_287b562a / sub-task 1 (single atomic unit: gateway send path busy UX + cancel sender + widget tests)

## Context
- Repo: Flutter Clean Arch. Cubits live in `lib/presentation/screen/chat/cubit/`.
- In Direct mode the ReAct loop emits `AgentThinking` (agent_cubit.dart:800) so the thinking bar
  and AppBar stop button appear. In Gateway mode the send path
  (`chat_screen.dart` ~line 1091, `client.sendChatMessage(prompt)`) emits nothing busy, so
  between tapping send and the first `text_delta` there is NO thinking bar and NO stop button.
- Cancellation exists server-side: the flames-device-bridge relay supports an inbound
  `{"type": "chat_cancel"}` frame that aborts in-flight generation (answered by an
  `error` frame with code `chat_cancelled`). The app currently has NO sender for it.

## Current facts you must build on (verified by lead)
- `lib/domain/entities/gateway/gateway_message.dart` has no `chat_cancel` type. There are
  existing outbound frame classes like `GatewayChatMessage` (type 'chat_message',
  constructor `GatewayChatMessage({required content, role = 'user', metadata}) : super('chat_message')`,
  with `toJson`). `GatewayErrorMessage` exists (type 'error', fields likely `code`/`message`) —
  check its shape before reusing it for the `chat_cancelled` inbound error handling.
- `lib/domain/services/gateway/gateway_client_base.dart` (abstract transport): has
  `sendChatMessage`, `send`, `sendJson`, etc. Add an abstract `void sendChatCancel()`.
- `lib/data/datasources/remote/gateway/gateway_client.dart` implements the base; add the
  override there, mirroring `sendChatMessage` (line ~425).
- `lib/presentation/screen/chat/chat_screen.dart`:
  - line ~1091: gateway send branch (`client.sendChatMessage(prompt);` inside
    `_mode == ChatMode.gateway` else-branch of the send handler).
  - line ~1195: `if (state is AgentThinking) _buildThinkingBar(context),` — busy bar render.
  - line ~1350-1487 (AppBar actions BlocBuilder): `final isBusy = state is AgentThinking ||
    state is AgentStreaming || state is ExecutingTool;` renders stop button
    (`chat_stop_button`, calls `_confirmStop`).
  - line ~1035 `_confirmStop` → confirm button calls `context.read<AgentCubit>().stop()`.
  - line ~229-253: `_gatewayTextDeltaSub` / `_gatewayMessageSub` listeners on client streams.
  - `_isAgentBusy(AgentState)` helper at ~line 604: `state is AgentThinking || AgentStreaming
    || ExecutingTool || WaitingApproval`.
- `lib/presentation/screen/chat/cubit/agent_state.dart`: `AgentThinking` is a stateless
  sealed-variant (`class AgentThinking extends AgentState` with no props of its own beyond base).
  `AgentCubit.stop()` exists and emits `AgentIdle(messages: messages)`.
- Existing gateway widget test harness: `test/presentation/screen/chat/chat_screen_gateway_test.dart`
  (MockGatewayClient from `test/helpers/mocks.dart`, `createWidgetUnderTest(initialMode: ChatMode.gateway)`,
  stream controllers wired in setUp). Existing test at line ~504 "submitting message in Gateway
  mode when connected sends chat frame" is the pattern to extend.

## Files to modify
- lib/domain/entities/gateway/gateway_message.dart
- lib/domain/services/gateway/gateway_client_base.dart
- lib/data/datasources/remote/gateway/gateway_client.dart
- lib/presentation/screen/chat/chat_screen.dart
- lib/presentation/screen/chat/cubit/agent_cubit.dart
- test/data/datasources/remote/gateway/gateway_client_test.dart (add sendChatCancel serialization test)
- test/presentation/screen/chat/chat_screen_gateway_test.dart (new busy-UX widget tests)

## Files to NOT touch
- lib/presentation/screen/chat/chat_screen.dart direct-mode branch (`_mode == ChatMode.direct` path
  and AgentCubit sendMessage/_runLoop internals) — direct mode already works.
- test/helpers/mocks.dart (MockGatewayClient already implements the interface; adding an abstract
  method needs no mock change since it's a Mock).
- Any file under lib/data/datasources/tools/, lib/domain/tools/, injection config.

## Goal / Specification

### 1. Protocol: chat_cancel outbound frame
In `gateway_message.dart` add:
```dart
/// Requests cancellation of the in-flight generation on the remote agent.
class GatewayChatCancelMessage extends GatewayMessage {
  const GatewayChatCancelMessage() : super('chat_cancel');

  factory GatewayChatCancelMessage.fromJson(Map<String, dynamic> json) =>
      const GatewayChatCancelMessage();

  @override
  Map<String, dynamic> toJson() => {'type': 'chat_cancel'};
  // match the props/== style of GatewayChatMessage (props likely [type])
}
```
Add `case 'chat_cancel': return GatewayChatCancelMessage.fromJson(json);` to
`GatewayMessage.fromJson` switch.

### 2. Transport
- `GatewayClientBase`: add `void sendChatCancel();` with doc comment
  "Sends a chat_cancel frame to abort the in-flight gateway generation."
- `GatewayClient` (data impl): override `void sendChatCancel() { send(const GatewayChatCancelMessage()); }`.

### 3. Busy state on gateway send path (chat_screen.dart)
Design decision (locked by lead — implement exactly this):
- Add `bool _gatewayBusy = false;` state field on the ChatScreen State.
- In the gateway send branch, immediately after `client.sendChatMessage(prompt);`:
  `setState(() => _gatewayBusy = true); _scrollToBottom();`
- Render: change line ~1195 condition to
  `if (state is AgentThinking || _gatewayBusy) _buildThinkingBar(context),`
- AppBar stop button (line ~1350): `final isBusy = state is AgentThinking ||
  state is AgentStreaming || state is ExecutingTool || _gatewayBusy;` (add `|| _gatewayBusy`
  in BOTH AppBar actions BlocBuilders if there are two — grep for `chat_stop_button` to find all).
- Clear `_gatewayBusy = false` via `setState` on:
  a) first `text_delta` — in `_gatewayTextDeltaSub` listener, if `_gatewayBusy` clear it
     (bubble takes over; guard so we only setState once per turn),
  b) final `chat_message` — in `_gatewayMessageSub` GatewayChatMessage branch,
  c) `error` frame — extend the `_gatewayMessageSub` listener to also handle
     `GatewayErrorMessage` (clear busy and show a SnackBar with the error message, pattern-match
     the existing SnackBar style; if the error `code == 'chat_cancelled'` skip the SnackBar —
     it's the ack for our own stop tap),
  d) socket disconnect — in the client `stateStream` subscription (find it; it drives the
     connection indicator), when state is disconnected and `_gatewayBusy`, clear it.
  Also clear it in `dispose()` cleanup of the subscriptions if present, and when switching
  mode to direct (`_toggleMode`) if set.

### 4. Stop button → chat_cancel
In `_confirmStop`'s confirm button: keep `context.read<AgentCubit>().stop();` (harmless in
gateway mode; direct mode needs it) and add gateway-path cancel:
```dart
if (_mode == ChatMode.gateway) {
  try {
    _resolveGatewayClient()?.sendChatCancel();
  } catch (_) {}
}
setState(() => _gatewayBusy = false);
```
Order: send the cancel frame FIRST, then clear busy + pop dialog (existing pop stays).

### 5. Tests (chat_screen_gateway_test.dart) — TDD, add these testWidgets:
1. "gateway send shows thinking bar and stop button immediately":
   connected client, stub sendChatMessage, pump, submit 'Hello', pump;
   expect thinking bar visible (find the same widget/direct-mode thinking indicator the
   `_buildThinkingBar` renders — inspect `_buildThinkingBar` body to pick a stable finder,
   e.g. its Key or text) and `find.byKey(const Key('chat_stop_button'))` findsOneWidget.
2. "first text_delta clears gateway busy state": after (1), add
   `gatewayTextDeltaController.add(GatewayTextDeltaMessage(delta: 'Hi'))`, pump;
   thinking bar gone, stop button gone.
3. "final chat_message clears gateway busy state": after (1) add a
   `GatewayChatMessage(content: 'Done', role: 'assistant')` on gatewayMessageController, pump;
   busy cleared.
4. "stop button in gateway mode sends chat_cancel frame": after (1), tap
   `chat_stop_button`, handle the confirm dialog (`confirm_stop_button`), pump;
   `verify(() => mockGatewayClient.sendChatCancel()).called(1);` and busy cleared.
   Stub `when(() => mockGatewayClient.sendChatCancel()).thenReturn(null);` in setUp.
5. "error frame clears gateway busy state": after (1), add a GatewayErrorMessage on
   messageStream; busy cleared and error SnackBar shown.
Also in `gateway_client_test.dart`: one test that `sendChatCancel()` emits a frame whose
`toJson()` / captured WebSocket payload is `{'type': 'chat_cancel'}` — follow however
existing sendChatMessage frames are asserted in that file.

### 6. Rules
- Cubit-only state management; do NOT add Bloc/events.
- No new packages. No new UI components — reuse `_buildThinkingBar`, existing stop button.
- Zero emoji in chrome; Icons.* only; HermesColors for styling additions.
- Do NOT read files under ~/.pub-cache.
- Keep edits surgical; no reformatting of untouched code.

## Definition of Done (worker must run these and report REAL output)
- `flutter analyze` → 0 issues (use plain `flutter`, NOT flock prefix).
- `flutter test test/data/datasources/remote/gateway/gateway_client_test.dart
  test/presentation/screen/chat/chat_screen_gateway_test.dart` → 100% pass.
- `flutter test test/presentation/screen/chat/chat_screen_test.dart` → still 100% pass
  (must not regress direct-mode tests).
- Report git `diff --stat` of files you changed.
