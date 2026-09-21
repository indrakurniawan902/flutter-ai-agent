# Flames (`flutter_ai_agent`) — Architecture & DoD Guardrails

Single source of truth for all agents (@dev, @ops, orchestrator). No PR/card marked done without all gates.

## 0. Stack & Clean Architecture Map
- Framework: Flutter (Dart 3.x), Dark theme only (`#0F172A`, surface `#1E293B`, accent Teal `#008080`).
- Layers (`data → domain ← presentation`):
  - `lib/presentation/`: Screens, Widgets, Cubits (`screens/<feature>/cubit/`). Cubit-only (NO Bloc/events).
  - `lib/domain/`: Pure Dart entities, models, repository contracts, `ToolRegistry`.
  - `lib/data/`: Models/DTOs, repository implementations, device services.
- DI & Testing: `get_it` service locator, `mocktail` (AAA pattern, NO build_runner mocks).

## 1. Hard Verification Gates (Definition of Done)
Compile serialization is automatically handled by wrapper `compile-lock` in `~/.local/bin/flutter`. Do NOT use raw `flock`.
- `flutter analyze` (0 issues)
- `flutter test` (100% green)
- `sh tool/check_layout.sh` (must print LAYOUT OK)

## 2. UI/UX & Hardware Gates
- Zero emoji in chrome: `Icons.*` only for all navbars, appbars, buttons, and cards.
- Single active state: Exactly one state rendered (`LoadingState`, `EmptyState`, `ErrorState`, `DataView`).
- Bulletproof 3-State Permission: Granted -> execute; Denied -> rationale modal; Permanently Denied -> `openAppSettings()` button. Must be covered in tests.

## 3. Learned Pitfalls (DO NOT REPEAT)
- Cubit Placement: MUST be in `lib/presentation/screens/<feature>/cubit/`, NEVER in `domain/` or `lib/features/`.
- No Re-export Shims: Never create barrel export files (`export 'screens/...'`). Place files directly in target paths.
- Exit 75 in Compile: Transient lock contention — do NOT `kanban_block`, just exit cleanly.
