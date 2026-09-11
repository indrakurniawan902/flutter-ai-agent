# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes for **Flames** (`ai.hermes.flames`, package `flutter_ai_agent`). Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed.

---

## 0. Read Docs First

**Before touching any code or making architectural decisions, read the project docs in this order:**

1. [`docs/architecture.md`](./docs/architecture.md) — folder layout, Clean Architecture layers (`data → domain ← presentation`), Cubits in `presentation/screen/<feature>/cubit/`, domain repository contracts, GetIt DI registration, and testing structure.
2. [`docs/rules.md`](./docs/rules.md) — coding conventions, strict layer rules, state management rules (Cubit only, NO Bloc/events), functional error handling with `Either<Failure, T>`, testing with `mocktail`, and the Definition of Done checklist.
3. [`docs/design-system.md`](./docs/design-system.md) — dark theme colors, typography, surface cards, HITL modals, and the **zero emoji in chrome** rule.
4. [`docs/MIGRATION-PLAN.md`](./docs/MIGRATION-PLAN.md) — file-by-file old (feature-first) to new (layer-first) migration mapping.

> **CRITICAL RULE FOR AI AGENTS (OpenCode, Claude Code, Antigravity):**
> Do **NOT** make assumptions about folder structure, layer boundaries, or naming conventions from memory or context alone — the docs in `docs/` are the **Single Source of Truth** and must be consulted first.
> - Cubits and States **MUST** be placed in `lib/presentation/screen/<feature>/cubit/`, **NEVER** in `domain/`. Note: there is no `lib/features/`.
> - Do **NOT** create re-export shim files (e.g. `export 'screens/...'`). Place files directly in their target directories.

---

## 1. Stack & Purpose

Mobile AI Agent workstation — action-oriented execution node with native device tool calling (ReAct loop), streaming SSE, HITL safety gate, universal gateway client (WebSocket/SSE RPC), and multi-server profile manager with QR pairing.

- **Framework**: Flutter (Dart)
- **State Management**: `flutter_bloc` (**Cubit-only**, NO Bloc/events)
- **Dependency Injection**: `get_it` service locator (`lib/core/di/injection_container.dart`)
- **Error Handling**: `dartz` (`Either<Failure, T>`), `Failure` hierarchy in `core/errors/failures.dart`
- **Storage**: `flutter_secure_storage` + `hive_ce_flutter`
- **Networking**: `dio` with custom `SseParser`
- **Testing**: `mocktail` (AAA pattern, shared mocks in `test/helpers/mocks.dart`, no build_runner mocks)

---

## 2. Architecture Overview

Strict Clean Architecture with three layers (`presentation → domain ← data`):

- **Presentation**:
  - `screens/`: `ChatScreen`, `SettingsScreen`, `QrScannerScreen`
  - `widgets/`: `ActionApprovalSheet` (HITL modal), `ToolCallCard`
  - `cubits/`: `AgentCubit`, `SettingsCubit`, `ServerProfileCubit` (State management belongs here!)
- **Domain**:
  - `entities/`: Plain Dart business objects (`ServerProfile`, `ChatMode`)
  - `models/`: Domain models (`ToolCallRequest`)
  - `repositories/`: Abstract repository interfaces (`LlmRepository`)
  - `tools/`: `ToolRegistry`, `SecurityPolicy` (Tier 1 auto / Tier 2 permission / Tier 3 HITL)
- **Data**:
  - `models/`: DTOs (`ChatMessage`, `ChatChunk`, `ServerProfileModel`, `PairingPayload`)
  - `repositories/`: Repository implementations (`LlmRepositoryImpl`)
  - `tools/`: Device services (`ClipboardService`, `LocationService`, `DeviceContextService`, `CameraVisionService`, `CalendarService`, `NotificationService`)

---

## 3. Design Tokens (Zero Emoji Rule)

- Dark surface `#0F172A`, surface container `#1E293B`, border `#334155`, accent Teal `#008080`.
- **0 emoji icons in chrome**: `Icons.*` only across all app bars, navigation, cards, and buttons.

---

## 4. Workflow — Run This First (Any Task)

Follow the standard engineering workflow:
1. Read docs: `docs/architecture.md`, `docs/rules.md`, `docs/design-system.md`.
2. Plan changes surgically: touch only what is required.
3. Build with TDD or verify with tests: write unit/widget tests using `mocktail`.
4. Run verification before claiming done:
   - `flock /tmp/flutter.lock flutter analyze` (must be 0 issues)
   - `flock /tmp/flutter.lock flutter test` (must be 100% green)

---

## 5. Testing & Verification Commands

```bash
# Linting (must be clean)
flutter analyze

# Testing (must be 100% pass)
flutter test

# VPS-safe execution (respect 2 vCPU limit)
flock /tmp/flutter.lock flutter analyze
flock /tmp/flutter.lock flutter test
flock /tmp/flutter.lock dart run build_runner build --delete-conflicting-outputs

# Run flavors
flutter run --flavor development -t lib/main_development.dart
flutter run --flavor production -t lib/main_production.dart
```

---

## 6. Multi-Agent Orchestration Protocol (Hermes & OpenCode)

To prevent context window overflow and enforce Clean Architecture, work is strictly divided:

### Roles & Boundaries
- **Hermes Dev (`@dev`) = Tech Lead / Architect**:
  - Analyzes requirements, plans feature breakdown, and spawns OpenCode workers.
  - **DILARANG KERAS** menulis atau mengedit file kode aplikasi secara langsung di context Hermes via `write_file` atau `patch`.
  - Runs independent verification commands (`flock /tmp/flutter.lock flutter analyze` & `flock /tmp/flutter.lock flutter test`).
  - Manages git commits per verified sub-task and advances Kanban cards.
- **OpenCode CLI (`opencode run`) = Worker / Code Monkey**:
  - Receives granular sub-tasks wrapped in `[TASK ASSIGNMENT]` schema.
  - Executes surgical code modifications strictly within specified `Target Files`.
  - Strictly follows `docs/architecture.md` (Clean Architecture: Cubits in presentation, services in domain).
  - Never touches files outside scope or substitutes requested packages.

### Sub-task Definition (Atomic Unit of Work)
Every sub-task delegated to OpenCode MUST satisfy:
1. **Single Concern**: Focuses on one layer or component (Data Service, Cubit, UI Screen, or Tests). Never dump an entire full-stack feature in one prompt.
2. **Explicit Target Files**: Lists exact target files to create/modify and files off-limits.
3. **Specification Adherence**: Strict negative constraints (e.g. "Do NOT use Bloc", "Do NOT use build_runner for mocks").
4. **Verifiable Definition of Done (DoD)**: Clear CLI test/lint command that must exit 0.

