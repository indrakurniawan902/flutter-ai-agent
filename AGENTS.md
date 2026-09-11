# AGENTS.md

Flutter app: **Flutter AI Agent** (personal project). Clean Architecture (`data → domain ← presentation`) with **Cubit-only** state management (`flutter_bloc`, no Bloc/events), `get_it` DI, `dartz` `Either<Failure, T>` error handling, `hive` local cache, `flutter_secure_storage` for credentials.

## Stack & Purpose
Mobile AI Agent workstation — action-oriented execution node with native device tool calling (ReAct loop), streaming SSE, HITL safety gate, OpenAI-compatible provider router. See PRD at `~/Documents/Obsidian Vault/notes/prd-flutter-ai-agent-device-control.md`.

## Architecture
- **Presentation**: ChatScreen (streaming Markdown bubbles, tool call cards), SettingsScreen (endpoint/model/API key), ActionApprovalSheet (HITL modal).
- **Domain**: AgentCubit (ReAct loop orchestrator), ToolRegistry (tier-based dispatch), SecurityPolicy (Tier 1 auto / Tier 2 permission / Tier 3 HITL).
- **Data**: LLMRepository (Dio SSE), DeviceContextService, ClipboardService, LocationService, CameraVisionService, CalendarService, NotificationService.

## Design Tokens (flutter-mobile-design)
- Dark surface `#0F172A`, accent Teal `#008080`, neutral borders, 0 emoji icons in chrome, `Icons.*` only.

## Workflow — run this FIRST (any project/task)
Before writing any code, follow the **superpowers** workflow: **brainstorming** → **writing-plans** → build with **test-driven-development** → **requesting-code-review** → **verification-before-completion**. Do NOT jump straight into code.

## Testing
- **Mocktail** (no build_runner mocks). AAA pattern. Shared mocks in `test/helpers/mocks.dart`.
- 100% coverage on core: AgentCubit, ToolRegistry, LLMRepository, all Service classes.

## Commands
```bash
flutter analyze                                          # must be clean
flutter test                                             # all green
flock /tmp/flutter.lock flutter test                     # serialized on VPS
flutter run --flavor dev -t lib/main_dev.dart
```
