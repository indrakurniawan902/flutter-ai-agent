# Rules

> Coding conventions and working agreements for **Flames** (`ai.hermes.flames`, package `flutter_ai_agent`).
> Read this together with [`architecture.md`](./architecture.md) (structure) and
> [`design-system.md`](./design-system.md) (visuals).
>
> These rules describe how this codebase is actually written. Follow them so new
> code is indistinguishable from existing code.

---

## 1. Golden Rules

1. **Match the surrounding code.** Copy the nearest existing feature's structure, naming, and idioms rather than inventing a new style.
2. **Respect the layers.** `presentation → domain ← data`. UI never imports `data/` types; `domain` imports nothing framework-specific or data-specific.
3. **Cubit is Presentation.** Cubits and their States **MUST** reside in `presentation/cubits/`. **NEVER** put a Cubit, State, or `flutter_bloc` import in `domain/`.
4. **No Shim / Re-export files.** Never leave backward-compatibility shims like `export 'screens/foo_screen.dart';` in feature roots. Place files directly in their target subfolder (`screens/`, `cubits/`, `widgets/`) and import the real path.
5. **Contract-First Repositories.** Define abstract interfaces in `domain/repositories/` and implement them in `data/repositories/`.
6. **Functional Error Handling.** Use `Either<Failure, T>` from `dartz`. Catch all HTTP, socket, and storage exceptions at the data layer boundary and translate them to typed `Failure` subclasses from `core/errors/failures.dart`.
7. **Zero Emoji in Chrome.** Never use emojis in UI icons, buttons, navigation headers, or cards. Use `Icons.*` only.
8. **Test with Mocktail.** Shared mocks live in `test/helpers/mocks.dart`. Use the AAA pattern. Test tree **must mirror** `lib/` (Cubit tests in `test/.../presentation/cubits/`).
9. **VPS CPU Discipline.** When compiling or testing on the VPS (2 vCPU), always serialize heavy commands with `flock /tmp/flutter.lock`. Never run parallel flutter compiles.
10. **Definition of Done (DoD).** `flutter analyze` clean (0 issues) and `flutter test` 100% green before committing or declaring work complete.

---

## 2. Project Structure Rules

- Features live in `lib/features/<feature>/` following Clean Architecture:
  - `data/`: `datasources/`, `models/`, `repositories/`, `tools/`
  - `domain/`: `entities/`, `models/`, `repositories/`, `usecases/`, `tools/`
  - `presentation/`: `cubits/`, `screens/`, `widgets/`
- Shared/cross-cutting infrastructure belongs in `lib/core/`:
  - `core/di/`: Dependency injection (`injection_container.dart`)
  - `core/errors/`: Failures and exception definitions (`failures.dart`)
  - `core/constants/`: App constants, defaults, storage keys (`constants.dart`)
  - `core/theme/`: Theme data and colors (`app_theme.dart`, `hermes_theme.dart`)
  - `core/extensions/`: Shared extensions (`either_extensions.dart`)
- Test mirrors `lib/`:
  - Cubit tests go to `test/features/<feature>/presentation/cubits/<feature>_cubit_test.dart` (NOT in domain!).
  - Screen tests go to `test/features/<feature>/presentation/screens/<feature>_screen_test.dart`.
  - Repository/Datasource tests go to `test/features/<feature>/data/...`.

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
| Remote DataSource | `<Feature>RemoteDataSource` | `LlmRemoteDataSource` |
| Local DataSource | `<Feature>LocalDataSource` / Service | `SecureStorageService` |
| Model (DTO) | `<Thing>Model` / `<Thing>Payload` | `ServerProfileModel`, `PairingPayload` |
| Entity | `<Thing>` / `<Thing>Entity` | `ServerProfile`, `ChatMode` |
| Screen | `<Thing>Screen` | `ChatScreen`, `SettingsScreen` |
| Widget | `<Thing>` / `<Thing>Sheet` / `<Thing>Card` | `ActionApprovalSheet`, `ToolCallCard` |

---

## 4. Layer Rules & Dependency Constraints

### Domain Layer
- **Pure Dart**: Only depends on Dart standard library, `equatable`, and `dartz`.
- **NO UI dependencies**: Never import `flutter/material.dart`, `flutter_bloc`, `flutter/widgets.dart`.
- **NO Data dependencies**: Never import anything from `lib/features/<feature>/data/`.

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
5. Provide a factory constructor or register in GetIt container (`injection_container.dart`).

---

## 6. Testing Rules

1. Use `mocktail` for mocking classes. Register fallbacks in `setUpAll()` when using `any()`.
2. Shared mocks are kept central in `test/helpers/mocks.dart`.
3. Test files follow the AAA (Arrange, Act, Assert) structure.
4. For Cubit testing, use `blocTest` from `bloc_test` package for state transition assertions.
5. All tests must be 100% passing before any commit.

---

## 7. Definition of Done (DoD) Checklist

Before committing or declaring a task complete:

- [ ] Folder structure matches Clean Architecture (§2).
- [ ] No misplaced Cubits in `domain/`.
- [ ] No re-export shim files left behind.
- [ ] Code follows naming conventions (§3).
- [ ] Zero emoji icons in chrome/UI (§1).
- [ ] `flutter analyze` runs with **zero issues**.
- [ ] `flutter test` runs with **100% passing tests**.
- [ ] All new dependencies registered in `injection_container.dart`.
