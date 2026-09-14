# T18.11 cont'd: Gateway mode busy UX + cancel (remainder)

## Task ID
t_287b562a / sub-task 2 (complete the remaining edits after first worker died mid-way)

## What's already done (verified)
- `lib/domain/entities/gateway/gateway_message.dart`: `GatewayChatCancelMessage` class + `case 'chat_cancel':` in fromJson switch.
- `lib/domain/services/gateway/gateway_client_base.dart`: `void sendChatCancel();` abstract method added.

## Files to modify NOW (surgical continuation)
- lib/data/datasources/remote/gateway/gateway_client.dart
- lib/presentation/screen/chat/chat_screen.dart
- test/data/datasources/remote/gateway/gateway_client_test.dart
- test/presentation/screen/chat/chat_screen_gateway_test.dart

## Files to NOT touch
- Any file already modified by first worker beyond what's listed above.
- lib/presentation/screen/chat/cubit/agent_cubit.dart (no changes needed — stop() exists).
- lib/domain/entities/gateway/gateway_message.dart, lib/domain/services/gateway/gateway_client_base.dart (done).

## Goal / Specification (exact remaining work)

### 1. GatewayClient (data impl) — lib/data/datasources/remote/gateway/gateway_client.dart
Add override near line ~425 (after sendChatMessage):
```dart
@override
void sendChatCancel() {
  send(const GatewayChatCancelMessage());
}
```
Import `GatewayChatCancelMessage` from domain if not already.

### 2. ChatScreen busy state + cancel wiring — lib/presentation/screen/chat/chat_screen.dart
Current state (grep confirms these NOT present): `_gatewayBusy`, `sendChatCancel`, busy clear logic.

**A. Add field** in `_ChatScreenState` (near line ~103 where `_streamingGatewayDelta` declared):
```dart
bool _gatewayBusy = false;
```

**B. Gateway send branch** (~line 1091):
Change from:
```dart
client.sendChatMessage(prompt);
```
To:
```dart
client.sendChatMessage(prompt);
if (mounted) {
  setState(() => _gatewayBusy = true);
  _scrollToBottom();
}
```

**C. Thinking bar render** (~line 1195):
Change from:
```dart
if (state is AgentThinking) _buildThinkingBar(context),
```
To:
```dart
if (state is AgentThinking || _gatewayBusy) _buildThinkingBar(context),
```

**D. AppBar stop button isBusy** (two places, search for `chat_stop_button` / `final isBusy`):
Change from:
```dart
final isBusy = state is AgentThinking || state is AgentStreaming || state is ExecutingTool;
```
To (both locations):
```dart
final isBusy = state is AgentThinking || state is AgentStreaming || state is ExecutingTool || _gatewayBusy;
```

**E. Clear _gatewayBusy in _gatewayTextDeltaSub** (listener starting ~line 232):
Inside the `if (mounted && _mode == ChatMode.gateway)` block, after `_streamingGatewayDelta += delta.delta;`, add:
```dart
if (_gatewayBusy) {
  setState(() => _gatewayBusy = false);
}
```

**F. Clear _gatewayBusy in _gatewayMessageSub** (listener starting ~line 243):
In the `GatewayChatMessage` branch, after `_streamingGatewayDelta = '';`, add:
```dart
if (_gatewayBusy) {
  setState(() => _gatewayBusy = false);
}
```

**G. Handle GatewayErrorMessage in _gatewayMessageSub**:
Add another `else if (message is GatewayErrorMessage)` branch inside the same listener:
```dart
else if (message is GatewayErrorMessage) {
  if (_gatewayBusy) {
    setState(() => _gatewayBusy = false);
  }
  // Skip SnackBar for chat_cancelled (it's our own stop ack)
  if (message.code != 'chat_cancelled') {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
```

**H. Clear _gatewayBusy on socket disconnect**:
Find the `stateStream` subscription (search for `stateStream.listen` or `GatewayConnectionState.disconnected` in initState). When state is disconnected and `_gatewayBusy`, clear it. Pattern:
```dart
_gatewayStateSub = client?.stateStream.listen((state) {
  if (mounted) {
    if (state == GatewayConnectionState.disconnected && _gatewayBusy) {
      setState(() => _gatewayBusy = false);
    }
    // ... existing connection indicator logic
  }
});
```

**I. Clear _gatewayBusy in dispose() and _toggleMode()**:
- In `dispose()`: if subscriptions are cancelled there, add `if (_gatewayBusy) _gatewayBusy = false;` (no setState needed since dispose).
- In `_toggleMode()`: if switching away from gateway mode and `_gatewayBusy`, `setState(() => _gatewayBusy = false);`.

**J. _confirmStop confirm button** (~line 1052-1054):
Change from:
```dart
onPressed: () {
  context.read<AgentCubit>().stop();
  Navigator.of(dialogContext).pop();
},
```
To:
```dart
onPressed: () {
  context.read<AgentCubit>().stop();
  if (_mode == ChatMode.gateway) {
    try {
      _resolveGatewayClient()?.sendChatCancel();
    } catch (_) {}
    if (mounted) setState(() => _gatewayBusy = false);
  }
  Navigator.of(dialogContext).pop();
},
```

### 3. Tests
**A. test/data/datasources/remote/gateway/gateway_client_test.dart**
Add test (follow existing pattern for sendChatMessage):
```dart
test('sendChatCancel emits chat_cancel frame', () {
  // however frames are captured in existing tests — follow that pattern
});
```

**B. test/presentation/screen/chat/chat_screen_gateway_test.dart**
Add these testWidgets (setUp already has mockGatewayClient, stream controllers):
1. "gateway send shows thinking bar and stop button immediately":
   - `when(mockGatewayClient.state).thenReturn(GatewayConnectionState.connected);`
   - `when(mockGatewayClient.sendChatMessage(any())).thenReturn(null);`
   - `when(mockGatewayClient.sendChatCancel()).thenReturn(null);`
   - pump widget gateway mode, submit 'Hello', pump;
   - `expect(find.byKey(const Key('chat_stop_button')), findsOneWidget);`
   - `expect(find.byWidgetPredicate(...thinking bar finder...), findsOneWidget);` — inspect `_buildThinkingBar` for a stable Key or text to find. It likely renders a `LinearProgressIndicator` or similar — use `find.byType(LinearProgressIndicator)` or similar.
2. "first text_delta clears gateway busy state": after (1), `gatewayTextDeltaController.add(GatewayTextDeltaMessage(delta: 'Hi'))`, pump; expect stop button gone.
3. "final chat_message clears gateway busy state": after (1), `gatewayMessageController.add(GatewayChatMessage(content: 'Done', role: 'assistant'))`, pump; expect stop button gone.
4. "stop button in gateway mode sends chat_cancel frame": after (1), tap `chat_stop_button`, tap `confirm_stop_button`, pump; `verify(() => mockGatewayClient.sendChatCancel()).called(1);` and stop button gone.
5. "error frame clears gateway busy state": after (1), `gatewayMessageController.add(GatewayErrorMessage(message: 'Server error', code: 'server_error'))`, pump; expect stop button gone and SnackBar shown.

### 4. Rules
- No new packages. No new UI components.
- Zero emoji. Icons.* only. HermesColors.
- Do NOT read ~/.pub-cache.
- Keep edits surgical.

## Definition of Done (worker must run these and report REAL output)
- `flutter analyze` → 0 issues (plain flutter, no flock).
- `flutter test test/data/datasources/remote/gateway/gateway_client_test.dart test/presentation/screen/chat/chat_screen_gateway_test.dart` → 100% pass.
- `flutter test test/presentation/screen/chat/chat_screen_test.dart` → 100% pass (no regressions).
- Report `git diff --stat` of files you changed.