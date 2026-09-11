# Architecture

> App: **Flames** (`ai.hermes.flames`, package `flutter_ai_agent`) — a Flutter-based
> Autonomous Device Agent and Mobile AI Agent workstation. Core flows: chat with streaming
> SSE markdown & tool cards, native device tool execution (ReAct loop), Human-in-the-Loop (HITL)
> security approval sheet, universal gateway client (WebSocket/SSE RPC transport), and multi-server
> profile manager with QR pairing.
>
> This document is the source of truth for *how the code is organised*. Read it
> before adding a feature, touching cross-cutting code, or creating new files.
> For visual/UI rules see [`design-system.md`](./design-system.md); for coding conventions
> see [`rules.md`](./rules.md).

---

## 1. Stack

| Concern | Choice |
|---|---|
| Framework | Flutter, Dart SDK `>=3.3.0 <4.0.0` |
| State management | `flutter_bloc` (Cubit-only, NO Bloc/events) |
| Dependency injection | `get_it` service locator (`lib/core/di/injection_container.dart`) |
| Error handling | `dartz` (`Either<Failure, T>`), custom `Failure` hierarchy |
| Networking | `dio` with custom `SseParser` for streaming SSE completions |
| Realtime gateway | `web_socket_channel` for bidirectional RPC transport |
| Local storage | `flutter_secure_storage` (credentials, tokens, profiles) + `hive_ce_flutter` (cache) |
| Device tools | `battery_plus`, `connectivity_plus`, `device_info_plus`, `geolocator`, `image_picker`, `device_calendar`, `flutter_local_notifications` |
| Design & theme | Dark surface `#0F172A`, Teal accent `#008080`, 0 emoji icons in chrome (`Icons.*` only) |
| Testing | `mocktail` (AAA pattern, shared mocks in `test/helpers/mocks.dart`, no build_runner mocks) |

---

## 2. Top-Level Layout

```text
lib/
  main_development.dart      # Dev flavor entry (com.sosfomt.guide / ai.hermes.flames.dev)
  main_production.dart       # Prod flavor entry (ai.hermes.flames)
  main.dart                  # Fallback default entry
  app.dart                   # MaterialApp root & theme config

  core/                      # Cross-cutting infrastructure
    constants/               # Default endpoints, models, timeouts, storage keys
    di/                      # GetIt dependency injection container
    errors/                  # Failure hierarchy (failures.dart)
    extensions/              # Either extensions and Dart helpers
    theme/                   # AppTheme and HermesTheme design tokens

  features/                  # Feature modules, one folder each (see §3)
    chat/                    # ReAct agent loop, SSE chat, tool execution
    gateway/                 # WebSocket RPC transport & bidirectional device tools
    pairing/                 # QR code scanner & pairing payload parser
    server_profiles/         # Multi-server profile CRUD & active switcher
    settings/                # LLM endpoint, API keys, temperature configuration
```

---

## 3. Feature Structure (Clean Architecture)

Each feature in `lib/features/<feature>/` strictly follows Clean Architecture:

```text
features/<feature>/
  data/
    datasources/             # Remote API clients, secure storage wrappers, WebSockets
    models/                  # DTOs with fromJson / toJson, serialization
    repositories/            # Implementations of domain repository interfaces
    tools/                   # Device tool service implementations (e.g. chat/data/tools)
  domain/
    entities/                # Plain Dart business objects (framework-agnostic)
    models/                  # Domain-level request/value models (e.g. ToolCallRequest)
    repositories/            # Abstract repository interfaces (contracts)
    usecases/                # Single-responsibility interactors (optional if Cubit is lean)
    tools/                   # Domain tool registries and security policies
  presentation/
    cubits/                  # Cubit & State classes (STATE MANAGEMENT LIVES HERE)
    screens/                 # Full-page screens/views
    widgets/                 # Feature-specific UI widgets & modals (e.g. ActionApprovalSheet)
```

### Dependency Rule: `presentation → domain ← data`

1. **Domain is the center**:
   - Pure Dart code. **NEVER** import `flutter_bloc`, Flutter UI widgets, or `data/` classes in `domain/`.
   - Domain contains business models, entities, security policies, and abstract repository contracts.
2. **Presentation depends only on Domain**:
   - Cubits, screens, and widgets live in `presentation/`.
   - Cubits consume domain repositories or usecases via dependency injection (`get_it`).
   - Presentation **NEVER** imports `data/` implementations directly.
3. **Data implements Domain**:
   - Repositories in `data/repositories/` implement interfaces defined in `domain/repositories/`.
   - Data sources and external services (Dio, Storage, Device plugins) are encapsulated inside `data/`.

---

## 4. State Management (Cubit Only)

- **Cubit-only rule**: Use `Cubit<State>` from `flutter_bloc`. Do **NOT** use `Bloc` with events.
- **Location**: All Cubits and their States **MUST** live in `lib/features/<feature>/presentation/cubits/`.
- **States**: Immutable state classes extending `Equatable`.
- **Registration**: Register Cubits as factory or lazy singleton in `lib/core/di/injection_container.dart`.

```dart
// Example: presentation/cubits/settings_cubit.dart
class SettingsCubit extends Cubit<SettingsState> {
  final SettingsRepository _repository;
  
  SettingsCubit({required SettingsRepository repository})
      : _repository = repository,
        super(const SettingsInitial());
  
  Future<void> loadSettings() async {
    emit(const SettingsLoading());
    final result = await _repository.getSettings();
    result.fold(
      (failure) => emit(SettingsError(failure.message)),
      (settings) => emit(SettingsLoaded(settings)),
    );
  }
}
```

---

## 5. Repository Pattern & Error Handling

- Repository interfaces live in `domain/repositories/`:
  ```dart
  abstract class LlmRepository {
    Future<Either<Failure, Stream<ChatChunk>>> streamCompletion({
      required String baseUrl,
      required String model,
      required List<Map<String, dynamic>> messages,
      List<Map<String, dynamic>>? tools,
      String? apiKey,
    });
  }
  ```
- Repository implementations live in `data/repositories/`:
  ```dart
  class LlmRepositoryImpl implements LlmRepository {
    final Dio dio;
    final SseParser sseParser;
    LlmRepositoryImpl({required this.dio, required this.sseParser});
    ...
  }
  ```
- Methods that can fail return `Either<Failure, T>` from `dartz`.
- Catch all exceptions at the data layer boundary and map them to domain `Failure`s (`ServerFailure`, `ConnectionFailure`, `StorageFailure`, `PermissionFailure`, etc.).

---

## 6. Dependency Injection (`core/di/`)

- All dependencies are registered in `lib/core/di/injection_container.dart` via `GetIt.instance` (`sl`).
- Singletons: External clients (`Dio`, `FlutterSecureStorage`), DataSources, Repositories, ToolRegistries.
- Factories: Cubits (recreated or injected per screen scope when needed).
- Always register against abstract interfaces when available:
  ```dart
  sl.registerLazySingleton<LlmRepository>(() => LlmRepositoryImpl(dio: sl<Dio>()));
  ```

---

## 7. Testing Structure

Test folder structure **strictly mirrors** `lib/`:

```text
test/
  helpers/
    mocks.dart               # Shared mocktail mocks
  core/
    di/
  features/
    <feature>/
      data/
        datasources/
        models/
        repositories/
        tools/
      domain/
        entities/
        repositories/
        tools/
      presentation/
        cubits/              # Cubit unit tests belong here!
        screens/             # Widget tests for screens
        widgets/             # Widget tests for components
  integration/               # End-to-end integration tests
```

- Framework: `mocktail` + `bloc_test`.
- No code generation for tests (no `build_runner` or `mockito`).
- AAA pattern (Arrange, Act, Assert).
