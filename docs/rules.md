# Rules

> Coding conventions and working agreements for **Flames** (`ai.hermes.flames`, package `flutter_ai_agent`).
> Read this together with [`architecture.md`](./architecture.md) (structure) and
> [`design-system.md`](./design-system.md) (visuals). For the file-by-file
> current → target moves, see [`MIGRATION-PLAN.md`](./MIGRATION-PLAN.md).
>
> These rules describe the **target** layer-first conventions for this
> codebase. The repo still physically lives at the old feature-first layout
> (`lib/features/...`); follow this document (and the migration plan) when
> writing or moving code so the tree converges on the target.

---

## 1. Golden Rules

1. **Match the surrounding code.** Copy the nearest existing feature's structure, naming, and idioms rather than inventing a new style.
2. **Respect the layers.** `presentation → domain ← data`. UI never imports `data/` types; `domain` imports nothing framework-specific or data-specific.
3. **Cubit is Presentation.** Cubits and their States **MUST** reside in `presentation/screen/<feature>/cubit/`. **NEVER** put a Cubit, State, or `flutter_bloc` import in `domain/`.
4. **No Shim / Re-export files.** Never leave backward-compatibility shims like `export 'screens/foo_screen.dart';` in feature roots or in `domain/`. Place files directly in their target subfolder and import the real path.
5. **Contract-First Repositories.** Define abstract interfaces in `domain/repositories/` and implement them in `data/repositories/`.
6. **Functional Error Handling.** Use `Either<Failure, T>` from `dartz`. Catch all HTTP, socket, and storage exceptions at the data layer boundary and translate them to typed `Failure` subclasses from `common/failure.dart`.
7. **Zero Emoji in Chrome.** Never use emojis in UI icons, buttons, navigation headers, or cards. Use `Icons.*` only.
8. **Test with Mocktail.** Shared mocks live in `test/helpers/mocks.dart`. Use the AAA pattern. Test tree **must mirror** `lib/` (Cubit tests in `test/presentation/screen/<feature>/cubit/`).
9. **VPS CPU Discipline.** When compiling or testing on the VPS (2 vCPU), always serialize heavy commands with `flock /tmp/flutter.lock`. Never run parallel flutter compiles.
10. **Definition of Done (DoD).** `flutter analyze` clean (0 issues) and `flutter test` 100% green before committing or declaring work complete.

---

## 2. Project Structure Rules

- Layout is **layer-first**: `lib/{common,data,domain,presentation,utils}/`
  per [`architecture.md §2`](./architecture.md#2-top-level-layout--layers-first-features-inside).
  There is **no** `lib/features/<feature>/` folder and no
  `lib/features/<feature>/{data,domain,presentation}` nesting.
- A "feature" is a *name* repeated across the layers:
  `data/datasources/remote/<feature>/`, `data/models/<feature>/`,
  `data/repositories/<feature>_repository_impl.dart`,
  `domain/entities/<feature>/`, `domain/repositories/<feature>/`,
  `domain/usecase/<feature>/`, `presentation/screen/<feature>/`.
- Cross-cutting infrastructure goes in `lib/common/`:
  - `common/injection/`: DI container and `injection.config.dart` (generated)
  - `common/constant.dart`: App constants, defaults, storage keys
  - `common/failure.dart`: `Failure` hierarchy and exceptions
  - `common/exception.dart`: `ServerException` / `DatabaseException` / `CacheException`
  - `common/remote_response_mapper.dart`: `ResponseMapper<T>` marker interface
  - `common/hive_constant.dart`: Hive box names + type IDs
- Generic helpers and design tokens go in `lib/utils/`:
  - `utils/app_theme.dart`, `utils/hermes_theme.dart` (tokens)
  - `utils/either_extensions.dart`, `utils/dio_err_handler.dart` (helpers)
- Shared widgets go in `lib/presentation/widget/`; screen-local widgets stay
  inline in the feature's `presentation/screen/<feature>/`.
- Folder names stay **singular** — `usecase/` (not `usecases/`),
  `<feature>_datasource.dart` (not `<feature>_datasources.dart`).
- Local datasources go under `data/datasources/local/<feature>/`, remote ones
  under `data/datasources/remote/<feature>/` — don't nest one under the other.
- Tests mirror the same tree under `test/` (`test/domain/usecase/<feature>/`,
  `test/presentation/screen/<feature>/cubit/`, ...).

---

## 3. Naming Conventions

| Kind | Convention | Example |
|---|---|---|
| Files | `snake_case.dart` | `chat_screen.dart`, `agent_cubit.dart` |
| Classes / Enums | `UpperCamelCase` | `AgentCubit`, `ServerProfile` |
| Members / Variables | `lowerCamelCase` | `sendMessage`, `baseUrl` |
| Constants | `lowerCamelCase` (`static const`) | `AppConstants.defaultTimeout` |
| Cubit | `<Feature>Cubit` | `AgentCubit`, `SettingsCubit` |
| State | `<Feature>State` | `AgentState`, `AgentStreaming` |
| Repo interface | `<Feature>Repository` | `LlmRepository`, `ServerProfileRepository` |
| Repo impl | `<Feature>RepositoryImpl` | `LlmRepositoryImpl` |
| Usecase | `<Verb><Noun>Usecase` (lowercase `c`) | `SendChatMessageUsecase` |
| Remote DataSource | `<Feature>Datasource` (abstract) / `...Impl` | `LlmDatasource` / `LlmDatasourceImpl` |
| Remote model (DTO) | `<Feature>RemoteResponse` | `ChatMessageRemoteResponse` |
| Local model (Hive) | `<Feature>LocalModel` | `ChatMessageLocalModel` |
| Entity | `<Thing>` (plain class, no suffix) | `ServerProfile`, `ChatMode` |
| Screen | `<Thing>Screen` | `ChatScreen`, `SettingsScreen` |
| Widget | `<Thing>` / `<Thing>Sheet` / `<Thing>Card` | `ActionApprovalSheet`, `ToolCallCard` |

Keep usecase classes suffixed `Usecase` (lowercase `c`), state variants
suffixed `Error` (not `Failed`), and DTOs suffixed `RemoteResponse` / `LocalModel` —
pick one and use it consistently across every feature.

JSON keys from an API are sometimes PascalCase or another casing — map them
with `@JsonKey(name: '...')` to camelCase Dart fields.

---

## 4. Layer Rules & Dependency Constraints

### Domain Layer
- **Pure Dart**: Only depends on Dart standard library, `equatable`, and `dartz`.
- **NO UI dependencies**: Never import `flutter/material.dart`, `flutter_bloc`, `flutter/widgets.dart`.
- **NO Data dependencies**: Never import anything from `data/` (no DTOs, no `data/datasources/`, no `data/repositories/`, no `data/tools/`).

### Presentation Layer
- Contains all UI and state management components.
- Cubits manage state and interact with domain repositories or use cases.
- Screens and widgets observe states using `BlocBuilder`, `BlocConsumer`, or `BlocListener`.
- Presentation layer only consumes entities and models from Domain or local presentation models. It must **never** instantiate or directly call Data layer classes.

### Data Layer
- Implements the contracts defined in Domain.
- Manages serialization (`fromJson`, `toJson`).
- Wraps raw API/Dio errors into domain `Failure` instances.

---

## 5. State Management Rules (Cubit)

1. Extend `Cubit<FeatureState>` from `flutter_bloc`.
2. Do not use events or `Bloc<Event, State>`. Cubit methods are invoked directly by the UI or callers.
3. Every state must be immutable and extend `Equatable`.
4. Cubit constructor should accept dependencies via constructor injection (e.g. Repositories or Services) so it can be cleanly mocked with `mocktail` in unit tests.
5. Annotate the cubit `@injectable`; resolve it via `getIt<XCubit>()` as a `State` field on the screen, trigger the initial action in `initState`, and wrap the subtree in `BlocProvider<X>.value(...)`.
6. `presentation/screen/<feature>/cubit/<feature>_state.dart` is a `part of` the cubit — the pair lives together, never in `domain/`.

---

## 6. Testing Rules

1. Use `mocktail` for mocking classes. Register fallbacks in `setUpAll()` when using `any()`.
2. Shared mocks are kept central in `test/helpers/mocks.dart`.
3. Test files follow the AAA (Arrange, Act, Assert) structure.
4. For Cubit testing, use `blocTest` from `bloc_test` package for state transition assertions.
5. **Mock one layer down, never further.** A cubit test mocks its usecase; a usecase test mocks its repository interface; a repository test mocks its datasource.
6. Test files **strictly mirror** `lib/` under `test/` — `test/<same path>/<file>_test.dart`. Cubit tests go to `test/presentation/screen/<feature>/cubit/<feature>_cubit_test.dart`, NOT in a `test/.../domain/` path.
7. All tests must be 100% passing before any commit.

---

## 7. Definition of Done (DoD) Checklist

Before committing or declaring a task complete:

- [ ] Folder structure matches the layer-first tree (§2) — **no `lib/features/`**.
- [ ] No misplaced Cubits in `domain/` (no `flutter_bloc` import under `domain/`).
- [ ] No re-export shim files left behind (delete the shim, update imports).
- [ ] No DTOs (`*RemoteResponse` / `*LocalModel`) in `domain/`.
- [ ] No parallel `lib/core/` next to `lib/common/`.
- [ ] Usecase folders are singular (`domain/usecase/`, not `use cases`/`usecases/`).
- [ ] Tests mirror the layer tree (`test/presentation/screen/<feature>/cubit/`, ...), not `test/features/`.
- [ ] Code follows naming conventions (§3).
- [ ] Zero emoji icons in chrome/UI (§1).
- [ ] `flutter analyze` runs with **zero issues**.
- [ ] `flutter test` runs with **100% passing tests**.
- [ ] All new dependencies registered via `@injectable` / `configureInjection()`.
- [ ] `tool/check_layout.sh` exits 0 (enforces layer-first layout and catches layout traps per §8 / §15).

---

## 8. Layout Traps (read this before "fixing" the structure)

These are the specific ways this layout has been broken before. All of them
make the tree harder to read, none of them are improvements:

- **Do not reintroduce `lib/features/`.** A layer-first tree is the point: all
  repository contracts are in `domain/repositories/`, all usecases in
  `domain/usecase/`, all screens in `presentation/screen/`. Folding a feature's
  three layers into one folder means answering "what calls the network?" now
  requires opening every feature folder.
- **Do not leave re-export shim files.** A one-line
  `export '../presentation/cubits/x_cubit.dart';` sitting in `domain/` is not
  "backwards compatibility" — it is a cubit in the wrong layer with a decoy
  path. If something moved, update the imports and delete the shim. (Flames has
  exactly these today: `lib/features/chat/domain/agent_cubit.dart` and friends —
  the migration deletes them, see `MIGRATION-PLAN.md`.)
- **Do not put a Cubit or `flutter_bloc` import in `domain/`.** Not in
  `domain/`, not in `domain/usecase/`, not anywhere under `domain/`. State
  management is presentation-only
  ([`architecture.md §6`](./architecture.md#6-state-management-cubit)).
- **Do not put DTOs in `domain/`.** `*RemoteResponse` / `*LocalModel` live in
  `data/models/`; `domain/entities/` holds the plain class the UI consumes,
  produced by `toDomain()`.
- **Do not create a parallel `lib/core/` next to `lib/common/`.** Cross-cutting
  infra has one home (`lib/common/`) plus `lib/utils/` for design tokens and
  helpers. Two folders holding the same four files is exactly the "berantakan"
  this convention exists to prevent. (Flames has this today: `lib/core/*` vs
  `lib/common/*` — the migration collapses them.)
- **Do not hand-roll DI registration** where an `@injectable` annotation would
  do — hand-written `sl.register*` lines drift out of sync with the generated
  `injection.config.dart`.
- **Automated Layout Guard**: Run `tool/check_layout.sh` to verify zero layout traps exist.

---

## 9. Networking & Data

- **No raw `Dio` outside datasources.** Datasources receive the injected
  `Dio` instance via constructor; nothing else should call `Dio` directly.
- **Error mapping:** catch `DioException` in the repository impl and route
  it through the shared `DioErrHandler.handleDioError(...)` into a
  `Failure` — prefer this over a bespoke try/catch per repository.
- **DTO to Entity boundary:** datasources return `<Feature>RemoteResponse` /
  `<Feature>LocalModel`, both implementing `ResponseMapper<T>`. Repository
  impls call `.toDomain()` and return `Either<Failure, Entity>`. The UI layer
  must never consume a `*RemoteResponse`/`*LocalModel` directly.
- **Cache-first for cacheable features:** check the local Hive datasource
  first, fall back to remote, persist remote → local on success. Not every
  feature needs a cache — only add one where it actually helps.
- **Model rules:** `json_serializable` DTOs with `@JsonKey(name: '...')`
  mapping; Hive local models with `@HiveType`/`@HiveField` and a
  `fromRemote(...)`/`fromDomain(...)` bridge factory.

---

## 10. UI & Widgets

- Colors via `AppTheme` / `HermesColors.*`; text via the theme's typography /
  shared text widget's named constructors. No bare `TextStyle(...)` or literal
  hex in new widgets.
- Reuse `lib/presentation/widget/` components before building new UI;
  promote a screen-local widget there only when a second feature needs it.
- Handle all three `BlocBuilder` branches: Loading (`CircularProgressIndicator`)
  → Error (human-readable message) → Success (content).
- **Zero emoji in chrome.** `Icons.*` only (`Icons.settings`, `Icons.terminal`,
  `Icons.security`, ...).

---

## 11. Error Handling & Logging

- Convert exceptions to `Failure` subclasses at the repository boundary
  (`lib/common/failure.dart`); cubits and UI only ever see `Either<Failure, T>`
  / a `Failure.message` string, never a raw exception.
- Datasources throw plain exceptions from `lib/common/exception.dart`
  (`ServerException`, `DatabaseException`, `CacheException`).
- **No `print()` in committed code.** Use proper logging if you need
  runtime visibility.

---

## 12. Code Generation & Tooling

Run codegen after touching `json_serializable` models, `@HiveType` models,
or `@injectable`/`@LazySingleton`/`@module`-annotated classes:

```bash
flock /tmp/flutter.lock dart run build_runner build --delete-conflicting-outputs
```

Lint/analyze before finishing:

```bash
flock /tmp/flutter.lock flutter analyze
```

Lints come from the stock `flutter_lints` set via `analysis_options.yaml`
(no project-specific overrides today). Keep `flutter analyze` output clean —
fix warnings introduced by your change.

---

## 13. Git & PRs

- Keep changes scoped to the task; avoid drive-by refactors.
- Don't commit unless asked; stage specific files rather than `git add .`.
- PR description: what changed, why, what was verified (analyze/build/manual).
- Intermediate/routine commits on feature branches use `[skip ci]` to save
  CI quota.

---

## 15. Layout Traps (Automated Layout Guard)

All layout constraints and layer-first architecture rules are mechanically enforced by `tool/check_layout.sh`.
Run `sh tool/check_layout.sh` (must exit 0 and output `LAYOUT OK`).

---

## 16. Flames Exceptions to the Template

Canonical base is `flutter-cubit-template`. Flames keeps its layer-first,
Cubit-only, `Either<Failure, T>` core and deliberately deviates as follows.
Details per item live in [`architecture.md §15`](./architecture.md#15-flames-exceptions-to-the-template).

1. **Zero emoji in chrome.** `Icons.*` only across app bars, navigation,
   cards, buttons, and modals. No emojis in UI icons, headers, or HITL
   sheets (§1.7, §10).
2. **Dev/prod flavors only.** `lib/main_development.dart` + 
   `lib/main_production.dart` with `lib/main.dart` fallback; no `staging`
   flavor. Android flavors mirror dev/prod with per-flavor app name and
   `applicationIdSuffix`.
3. **VPS lock discipline.** On the 2-vCPU VPS, serialize heavy commands
   with `flock /tmp/flutter.lock` — never run parallel flutter compiles
   (`flutter analyze`, `flutter test`, `build_runner build`).
4. **`tool/check_layout.sh` is DoD.** Must exit 0 with `LAYOUT OK` before
   committing or declaring work complete, alongside `flutter analyze`
   (0 issues) and `flutter test` (100% green). It guards: no
   `lib/features/`, no parallel `lib/core/`, no `flutter_bloc` in
   `domain/`, no re-export shims, no `presentation → data` imports, no
   DTOs in `domain/`.
5. **Secure storage.** `flutter_secure_storage` (credentials, tokens,
   profiles) + `hive_ce_flutter` (cache), registered via `@module`
   `StorageModule`; Hive adapters awaited in `bootstrap()`, IDs/boxes in
   `common/hive_constant.dart`.
6. **Native device tools.** `lib/data/datasources/tools/chat/` (service
   impls: clipboard, location, device context, camera vision, calendar,
   notifications) + `lib/domain/tools/chat/` (`ToolRegistry`,
   `SecurityPolicy` Tier 1 auto / Tier 2 permission / Tier 3 HITL).
7. **Streaming-first networking + AgentCubit.** `web_socket_channel`
   gateway transport; `Dio` + `ResponseType.stream` + `SseParser` for SSE
   `ChatChunk` / tool-call deltas; `AgentCubit` models the live stream
   with cancel/`stop()` instead of one-shot `Loading → Success/Error`.