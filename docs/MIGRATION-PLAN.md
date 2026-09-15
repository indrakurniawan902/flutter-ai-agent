# Migration Plan — Feature-First → Layer-First

> Target standard: [`architecture.md`](./architecture.md) §2 (layer-first).
> Rules to obey while migrating: [`rules.md`](./rules.md) §2, §7, §8 (layout traps).
>
> This plan is the **file-by-file contract** the migration cards (T13.x) execute.
> It is generated mechanically from `git ls-files lib test` on the current
> feature-first tree and must be regenerated if the file list changes.
>
> **Golden rule: one card moves one logical slice; every move updates imports and
> deletes shims; `flutter analyze` + `flutter test` stay green after each card.**

---

## 1. Target tree (summary)

```text
lib/
  main.dart                     # single entrypoint → bootstrap()
  common/          # injection/, constant.dart, failure.dart, exception.dart,
                   # remote_response_mapper.dart, hive_constant.dart
  data/            # datasources/{remote,local}/<feature>/, models/<feature>/,
                   # repositories/<feature>_repository_impl.dart, tools/<feature>/
  domain/          # entities/<feature>/, models/<feature>/, repositories/<feature>/,
                   # usecase/<feature>/, tools/<feature>/
  presentation/    # navigation/, screen/<feature>/ (cubit/ + screens + local widgets), widget/
  utils/           # app_theme.dart, hermes_theme.dart, either_extensions.dart, dio_err_handler.dart
```

## 2. Mapping rules (generic)

| Old (feature-first) | New (layer-first) |
|---|---|
| `lib/features/<feature>/data/**` | `lib/data/**` (per-feature subfolder inside the layer, e.g. `lib/data/models/<feature>/`) |
| `lib/features/<feature>/domain/**` | `lib/domain/**` (`entities/<feature>/`, `models/<feature>/`, `repositories/<feature>/`, `usecase/<feature>/`, `tools/<feature>/`) |
| `lib/features/<feature>/presentation/cubits/**` | `lib/presentation/screen/<feature>/cubit/**` |
| `lib/features/<feature>/presentation/screens/**` | `lib/presentation/screen/<feature>/` |
| `lib/features/<feature>/presentation/widgets/**` | stay screen-local in `lib/presentation/screen/<feature>/` unless a second feature uses them → then `lib/presentation/widget/` |
| `lib/features/navigation/**` | `lib/presentation/{navigation,screen/navigation}/` |
| `lib/core/theme/*` | `lib/utils/*` (design tokens) |
| `lib/core/errors/failures.dart`, `lib/core/constants/constants.dart` | `lib/common/{failure,constant}.dart` |
| `lib/core/extensions/either_extensions.dart` | `lib/utils/either_extensions.dart` |
| `lib/core/di/injection_container.dart` | superseded by `lib/common/injection/` (injectable codegen) |
| `test/features/<feature>/**` | `test/<mirrored layer path>/**` |
| re-export shims (`domain/*_cubit.dart`, `domain/*_state.dart`, `common/{constants,failures,either_extensions}.dart`) | **DELETE** — update imports, no replacement path |

## 3. Special cases

- **`lib/features/chat/data/llm_repository.dart`** — today one concrete class that
  defines the contract AND talks to `Dio`. Split into
  `lib/domain/repositories/chat/llm_repository.dart` (abstract) +
  `lib/data/repositories/chat/llm_repository_impl.dart` (impl, owns SSE parsing).
- **`lib/features/chat/data/sse_parser.dart`** → `lib/data/datasources/remote/chat/sse_parser.dart`
  (SSE parsing belongs to the chat datasource).
- **`lib/features/pairing/domain/qr_scanner_controller.dart`** — abstract contract
  `QrScannerControllerBase` → `lib/domain/repositories/pairing/qr_scanner_controller.dart`.
- **`lib/features/pairing/data/scanner_controller_wrapper.dart`** — implements that
  contract; device-tool implementation → `lib/data/tools/pairing/scanner_controller_wrapper.dart`.
- **`lib/features/pairing/domain/pairing_parser.dart`** — domain business logic →
  `lib/domain/tools/pairing/pairing_parser.dart`. It imports `PairingPayload`
  (a DTO); migrate that dependency to a domain entity if `domain/` must consume it.
- **`lib/features/settings/data/secure_storage_service.dart`** →
  `lib/data/tools/settings/secure_storage_service.dart` (cross-cutting storage
  service; promote to a shared data service if reused beyond settings).
- **`lib/features/navigation/presentation/widgets/floating_bottom_nav_bar.dart`** →
  `lib/presentation/widget/floating_bottom_nav_bar.dart` (shared across shells).
- **Root entries** (`lib/app.dart`, `lib/main*.dart`) stay at repo root; `test/helpers/`,
  `test/integration/`, `test/app_test.dart` stay put.
- **`lib/features/gateway/**`** — listed in architecture/features but has no files
  tracked today; when gateway code lands, follow the same rules (implementation
  under `data/tools/gateway/` or `data/datasources/`, contract under
  `domain/repositories/gateway/`).

## 4. Full file-by-file mapping (105 files = 63 lib + 42 test)

<!-- TABLE GENERATED FROM git ls-files lib test (105 rows) -->
| Old path (today) | New path (layer-first target) | Note |
|---|---|---|
| `lib/app.dart` | `lib/myapp.dart` | [DONE] deleted and consolidated into lib/myapp.dart + the single lib/main.dart per T13.7 (GoRouter + myapp bootstrap) |
| `lib/common/constants.dart` | `—` | re-export shim -> DELETE (update imports, no replacement path) |
| `lib/common/either_extensions.dart` | `—` | re-export shim -> DELETE (update imports, no replacement path) |
| `lib/common/failures.dart` | `—` | re-export shim -> DELETE (update imports, no replacement path) |
| `lib/core/constants/constants.dart` | `lib/common/constant.dart` |  |
| `lib/core/di/injection_container.dart` | `lib/common/injection/injection.dart` | [DONE] superseded by injectable codegen; deleted |
| `lib/core/errors/failures.dart` | `lib/common/failure.dart` |  |
| `lib/core/extensions/either_extensions.dart` | `lib/utils/either_extensions.dart` | move only used symbols; drop dead EitherX.getOrThrow() |
| `lib/core/theme/app_theme.dart` | `lib/utils/app_theme.dart` |  |
| `lib/core/theme/hermes_theme.dart` | `lib/utils/hermes_theme.dart` |  |
| `lib/features/chat/data/llm_repository.dart` | `lib/domain/repositories/chat/llm_repository.dart (abstract) + lib/data/repositories/chat/llm_repository_impl.dart (impl)` | [DONE] split concrete class into contract + impl |
| `lib/features/chat/data/models/chat_models.dart` | `lib/data/models/chat/chat_models.dart` | [DONE] |
| `lib/features/chat/data/sse_parser.dart` | `lib/data/datasources/remote/chat/sse_parser.dart` | [DONE] SSE parsing belongs to the chat datasource |
| `lib/features/chat/data/tools/calendar_service.dart` | `lib/data/tools/chat/calendar_service.dart` | [DONE] |
| `lib/features/chat/data/tools/camera_vision_service.dart` | `lib/data/tools/chat/camera_vision_service.dart` | [DONE] |
| `lib/features/chat/data/tools/clipboard_service.dart` | `lib/data/tools/chat/clipboard_service.dart` | [DONE] |
| `lib/features/chat/data/tools/device_context_service.dart` | `lib/data/tools/chat/device_context_service.dart` | [DONE] |
| `lib/features/chat/data/tools/location_service.dart` | `lib/data/tools/chat/location_service.dart` | [DONE] |
| `lib/features/chat/data/tools/notification_service.dart` | `lib/data/tools/chat/notification_service.dart` | [DONE] |
| `lib/features/chat/domain/agent_cubit.dart` | `—` | [DONE] re-export shim -> DELETE (update imports, no replacement path) |
| `lib/features/chat/domain/agent_state.dart` | `—` | [DONE] re-export shim -> DELETE (update imports, no replacement path) |
| `lib/features/chat/domain/models/action_step.dart` | `lib/domain/entities/chat/action_step.dart` | [DONE] |
| `lib/features/chat/domain/models/generative_card_data.dart` | `lib/domain/entities/chat/generative_card_data.dart` | [DONE] |
| `lib/features/chat/domain/models/tool_call_request.dart` | `lib/domain/entities/chat/tool_call_request.dart` | [DONE] |
| `lib/features/chat/domain/tools/security_policy.dart` | `lib/domain/tools/chat/security_policy.dart` | [DONE] |
| `lib/features/chat/domain/tools/tool_registry.dart` | `lib/domain/tools/chat/tool_registry.dart` | [DONE] |
| `lib/features/chat/presentation/cubits/agent_cubit.dart` | `lib/presentation/screen/chat/cubit/agent_cubit.dart` | [DONE] |
| `lib/features/chat/presentation/cubits/agent_state.dart` | `lib/presentation/screen/chat/cubit/agent_state.dart` | [DONE] |
| `lib/features/chat/presentation/screens/chat_screen.dart` | `lib/presentation/screen/chat/chat_screen.dart` | [DONE] |
| `lib/features/chat/presentation/widgets/action_approval_sheet.dart` | `lib/presentation/screen/chat/action_approval_sheet.dart` | [DONE] screen-local |
| `lib/features/chat/presentation/widgets/action_confirmation_card.dart` | `lib/presentation/screen/chat/action_confirmation_card.dart` | [DONE] screen-local |
| `lib/features/chat/presentation/widgets/header_console_bar.dart` | `lib/presentation/screen/chat/header_console_bar.dart` | [DONE] screen-local |
| `lib/features/chat/presentation/widgets/live_action_stepper_card.dart` | `lib/presentation/screen/chat/live_action_stepper_card.dart` | [DONE] screen-local |
| `lib/features/chat/presentation/widgets/permission_rationale_modal.dart` | `lib/presentation/screen/chat/permission_rationale_modal.dart` | [DONE] screen-local |
| `lib/features/chat/presentation/widgets/summary_card.dart` | `lib/presentation/screen/chat/summary_card.dart` | [DONE] screen-local |
| `lib/features/memory_vault/presentation/screens/memory_vault_screen.dart` | `lib/presentation/screen/memory_vault/memory_vault_screen.dart` | [DONE] |
| `lib/features/navigation/presentation/cubits/navigation_cubit.dart` | `lib/presentation/screen/navigation/cubit/navigation_cubit.dart` | [DONE] |
| `lib/features/navigation/presentation/cubits/navigation_state.dart` | `lib/presentation/screen/navigation/cubit/navigation_state.dart` | [DONE] |
| `lib/features/navigation/presentation/screens/main_navigation_shell.dart` | `lib/presentation/screen/navigation/main_navigation_shell.dart` | [DONE] |
| `lib/features/navigation/presentation/widgets/floating_bottom_nav_bar.dart` | `lib/presentation/widget/floating_bottom_nav_bar.dart` | [DONE] shared nav widget -> presentation/widget/ |
| `lib/features/pairing/data/models/pairing_payload.dart` | `lib/data/models/pairing/pairing_payload.dart` | [DONE] |
| `lib/features/pairing/data/scanner_controller_wrapper.dart` | `lib/data/tools/pairing/scanner_controller_wrapper.dart` | [DONE] implements QrScannerControllerBase; device-tool implementation -> data/tools/<feature>/ |
| `lib/features/pairing/domain/pairing_parser.dart` | `lib/domain/tools/pairing/pairing_parser.dart` | [DONE] domain business logic; migrate PairingPayload dependency to a domain entity if domain must consume it |
| `lib/features/pairing/domain/qr_scanner_controller.dart` | `lib/domain/repositories/pairing/qr_scanner_controller.dart` | [DONE] abstract contract QrScannerControllerBase -> domain/repositories/<feature>/ |
| `lib/features/pairing/presentation/screens/qr_scanner_screen.dart` | `lib/presentation/screen/pairing/qr_scanner_screen.dart` | [DONE] |
| `lib/features/pocket_node/presentation/screens/pocket_node_screen.dart` | `lib/presentation/screen/pocket_node/pocket_node_screen.dart` | [DONE] |
| `lib/features/server_profiles/data/models/server_profile_model.dart` | `lib/data/models/server_profiles/server_profile_model.dart` | [DONE] |
| `lib/features/server_profiles/domain/entities/server_profile.dart` | `lib/domain/entities/server_profiles/server_profile.dart` | [DONE] |
| `lib/features/server_profiles/domain/server_profile_cubit.dart` | `—` | [DONE] re-export shim -> DELETE (update imports, no replacement path) |
| `lib/features/server_profiles/domain/server_profile_state.dart` | `—` | [DONE] re-export shim -> DELETE (update imports, no replacement path) |
| `lib/features/server_profiles/presentation/cubits/server_profile_cubit.dart` | `lib/presentation/screen/server_profiles/cubit/server_profile_cubit.dart` | [DONE] |
| `lib/features/server_profiles/presentation/cubits/server_profile_state.dart` | `lib/presentation/screen/server_profiles/cubit/server_profile_state.dart` | [DONE] |
| `lib/features/settings/data/secure_storage_service.dart` | `lib/data/tools/settings/secure_storage_service.dart` | [DONE] cross-cutting storage service; promote to a shared data service if reused beyond settings |
| `lib/features/settings/domain/settings_cubit.dart` | `—` | [DONE] re-export shim -> DELETE (update imports, no replacement path) |
| `lib/features/settings/domain/settings_state.dart` | `—` | [DONE] re-export shim -> DELETE (update imports, no replacement path) |
| `lib/features/settings/presentation/cubits/settings_cubit.dart` | `lib/presentation/screen/settings/cubit/settings_cubit.dart` | [DONE] |
| `lib/features/settings/presentation/cubits/settings_state.dart` | `lib/presentation/screen/settings/cubit/settings_state.dart` | [DONE] |
| `lib/features/settings/presentation/screens/settings_screen.dart` | `lib/presentation/screen/settings/settings_screen.dart` | [DONE] |
| `lib/features/skills/presentation/screens/skills_hub_screen.dart` | `lib/presentation/screen/skills/skills_hub_screen.dart` | [DONE] |
| `lib/features/splash/presentation/screens/splash_screen.dart` | `lib/presentation/screen/splash/splash_screen.dart` | [DONE] |
| `lib/main.dart` | `lib/main.dart` | [DONE] single entrypoint; the dev/prod split introduced by T13.7 was reverted (this card removed it) |
| `test/app_test.dart` | `test/app_test.dart` | stays (mirrors repo-root file / shared helpers / e2e) |
| `test/core/di/injection_container_test.dart` | `test/common/injection/injection_container_test.dart` | [DONE] mirrors new injection home |
| `test/core/theme/hermes_theme_test.dart` | `test/utils/hermes_theme_test.dart` | mirrors token move to utils/ |
| `test/features/chat/data/llm_repository_test.dart` | `test/data/repositories/chat/llm_repository_test.dart` | [DONE] tests the impl |
| `test/features/chat/data/models/chat_models_test.dart` | `test/data/models/chat/chat_models_test.dart` | [DONE] |
| `test/features/chat/data/sse_parser_test.dart` | `test/data/datasources/remote/chat/sse_parser_test.dart` | [DONE] |
| `test/features/chat/data/tools/calendar_service_test.dart` | `test/data/tools/chat/calendar_service_test.dart` | [DONE] |
| `test/features/chat/data/tools/camera_vision_service_test.dart` | `test/data/tools/chat/camera_vision_service_test.dart` | [DONE] |
| `test/features/chat/data/tools/clipboard_service_test.dart` | `test/data/tools/chat/clipboard_service_test.dart` | [DONE] |
| `test/features/chat/data/tools/device_context_service_test.dart` | `test/data/tools/chat/device_context_service_test.dart` | [DONE] |
| `test/features/chat/data/tools/location_service_test.dart` | `test/data/tools/chat/location_service_test.dart` | [DONE] |
| `test/features/chat/data/tools/notification_service_test.dart` | `test/data/tools/chat/notification_service_test.dart` | [DONE] |
| `test/features/chat/domain/models/action_step_test.dart` | `test/domain/entities/chat/action_step_test.dart` | [DONE] |
| `test/features/chat/domain/models/generative_card_data_test.dart` | `test/domain/entities/chat/generative_card_data_test.dart` | [DONE] |
| `test/features/chat/domain/tools/tool_registry_test.dart` | `test/domain/tools/chat/tool_registry_test.dart` | [DONE] |
| `test/features/chat/presentation/cubits/agent_cubit_test.dart` | `test/presentation/screen/chat/cubit/agent_cubit_test.dart` | [DONE] |
| `test/features/chat/presentation/screens/chat_screen_test.dart` | `test/presentation/screen/chat/chat_screen_test.dart` | [DONE] |
| `test/features/chat/presentation/widgets/action_approval_sheet_test.dart` | `test/presentation/screen/chat/action_approval_sheet_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/chat/presentation/widgets/action_confirmation_card_test.dart` | `test/presentation/screen/chat/action_confirmation_card_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/chat/presentation/widgets/header_console_bar_test.dart` | `test/presentation/screen/chat/header_console_bar_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/chat/presentation/widgets/live_action_stepper_card_test.dart` | `test/presentation/screen/chat/live_action_stepper_card_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/chat/presentation/widgets/permission_rationale_modal_test.dart` | `test/presentation/screen/chat/permission_rationale_modal_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/chat/presentation/widgets/summary_card_test.dart` | `test/presentation/screen/chat/summary_card_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/memory_vault/presentation/screens/memory_vault_screen_test.dart` | `test/presentation/screen/memory_vault/memory_vault_screen_test.dart` | [DONE] |
| `test/features/navigation/presentation/cubits/navigation_cubit_test.dart` | `test/presentation/screen/navigation/cubit/navigation_cubit_test.dart` | [DONE] |
| `test/features/navigation/presentation/screens/main_navigation_shell_test.dart` | `test/presentation/screen/navigation/main_navigation_shell_test.dart` | [DONE] |
| `test/features/navigation/presentation/widgets/floating_bottom_nav_bar_test.dart` | `test/presentation/screen/navigation/floating_bottom_nav_bar_test.dart` | [DONE] mirrors screen-local widget |
| `test/features/pairing/data/models/pairing_payload_test.dart` | `test/data/models/pairing/pairing_payload_test.dart` | [DONE] |
| `test/features/pairing/data/scanner_controller_wrapper_test.dart` | `test/data/tools/pairing/scanner_controller_wrapper_test.dart` | [DONE] |
| `test/features/pairing/domain/pairing_parser_test.dart` | `test/domain/tools/pairing/pairing_parser_test.dart` | [DONE] |
| `test/features/pairing/presentation/screens/qr_scanner_screen_test.dart` | `test/presentation/screen/pairing/qr_scanner_screen_test.dart` | [DONE] |
| `test/features/pocket_node/presentation/screens/pocket_node_screen_test.dart` | `test/presentation/screen/pocket_node/pocket_node_screen_test.dart` | [DONE] |
| `test/features/server_profiles/data/models/server_profile_model_test.dart` | `test/data/models/server_profiles/server_profile_model_test.dart` | [DONE] |
| `test/features/server_profiles/presentation/cubits/server_profile_cubit_test.dart` | `test/presentation/screen/server_profiles/cubit/server_profile_cubit_test.dart` | [DONE] |
| `test/features/settings/data/secure_storage_service_test.dart` | `test/data/tools/settings/secure_storage_service_test.dart` | [DONE] |
| `test/features/settings/presentation/cubits/settings_cubit_test.dart` | `test/presentation/screen/settings/cubit/settings_cubit_test.dart` | [DONE] |
| `test/features/settings/presentation/screens/settings_screen_test.dart` | `test/presentation/screen/settings/settings_screen_test.dart` | [DONE] |
| `test/features/skills/presentation/screens/skills_hub_screen_test.dart` | `test/presentation/screen/skills/skills_hub_screen_test.dart` | [DONE] |
| `test/features/splash/presentation/screens/splash_screen_test.dart` | `test/presentation/screen/splash/splash_screen_test.dart` | [DONE] |
| `test/helpers/mocks.dart` | `test/helpers/mocks.dart` | stays (mirrors repo-root file / shared helpers / e2e) |
| `test/integration/e2e_agent_integration_test.dart` | `test/integration/e2e_agent_integration_test.dart` | stays (mirrors repo-root file / shared helpers / e2e) |
| `test/integration/e2e_nous_ui_navigation_integration_test.dart` | `test/integration/e2e_nous_ui_navigation_integration_test.dart` | stays (mirrors repo-root file / shared helpers / e2e) |

---

## 5. Migration Execution Status

- **T13.4 — Chat Feature Migration (DONE)**
  - Chat data models, datasources, repositories migrated to layer-first (`lib/data/models/chat/`, `lib/data/datasources/remote/chat/`, `lib/data/repositories/chat/`).
  - Chat domain tools (contracts and ToolRegistry) migrated to `lib/domain/tools/chat/`.
  - Chat data tools migrated to `lib/data/datasources/tools/chat/`.
  - Chat presentation (cubit, screen, widgets) migrated to `lib/presentation/screen/chat/`.
  - Chat utils migrated to `lib/utils/thought_extractor.dart`.
  - `lib/features/chat/` and `test/features/chat/` fully deleted.

- **T13.5 — Dependency Injection & Core Cleanup (DONE)**
  - Hand-wired `lib/core/di/injection_container.dart` deleted and replaced with `lib/common/injection/` (Injectable codegen).
  - All unit/widget/integration tests (394 tests) green.

- **T13.6 — Remaining Features Migration Out of lib/features/ (DONE)**
  - All remaining features (splash, skills, memory_vault, pocket_node, navigation, pairing, server_profiles, settings) migrated out of `lib/features/` into layer-first Clean Architecture.
  - `lib/features/` and `test/features/` completely deleted.
  - Presentation is clean of data layer imports.
  - `PairingPayload` domain entity and `QrScannerController` established.
  - All 400 tests green and 0 analyze issues.

