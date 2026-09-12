# Architecture

> App: **Flames** (`ai.hermes.flames`, package `flutter_ai_agent`) — a Flutter-based
> Autonomous Device Agent and Mobile AI Agent workstation. Core flows: chat with
> streaming SSE markdown & tool cards, native device tool execution (ReAct loop),
> Human-in-the-Loop (HITL) security approval sheet, universal gateway client
> (WebSocket/SSE RPC transport), and multi-server profile manager with QR pairing.
>
> This document is the source of truth for **how the code is organised**. It is
> canonized from `my_quran` (`dev/prayer-timev2`), the reference implementation
> for every personal Flutter project. Read it before adding a feature, touching
> cross-cutting code, or creating new files. For coding conventions see
> [`rules.md`](./rules.md); for visual/UI rules see
> [`design-system.md`](./design-system.md).
>
> The repo still lives at the old **feature-first** layout (`lib/features/...`).
> This document describes the **target layer-first** tree. The file-by-file
> old → new mapping is in [`MIGRATION-PLAN.md`](./MIGRATION-PLAN.md); later cards
> execute it. Where this document and the current tree disagree, this document
> wins.

---

## 1. Stack

| Concern | Choice |
|---|---|
| Framework | Flutter, Dart SDK `>=3.3.0 <4.0.0` |
| State management | `flutter_bloc` — **Cubit only**, no `Bloc`/events anywhere |
| Dependency injection | `get_it` + `injectable` (codegen), entry `lib/common/injection/` |
| Routing | `go_router` (introduced as part of the layer-first migration; today the app uses a `MaterialApp(home:)` splash → navigation-shell chain) |
| Networking | `dio` — injected directly into datasources, no wrapper client class; custom `SseParser` for streaming SSE completions |
| Realtime gateway | `web_socket_channel` for bidirectional RPC transport |
| Local storage | `flutter_secure_storage` (credentials, tokens, profiles) + `hive_ce_flutter` (cache) |
| Device tools | `battery_plus`, `connectivity_plus`, `device_info_plus`, `geolocator`, `image_picker`, `device_calendar`, `flutter_local_notifications` |
| Functional error handling | `dartz` (`Either<Failure, T>`) |
| Equality | `equatable` |
| Design & theme | Dark surface `#0F172A`, surface container `#1E293B`, border `#334155`, accent teal `#008080`; **0 emoji icons** in chrome (`Icons.*` only) |
| Markdown rendering | `flutter_markdown` (assistant chat bubbles) |
| Testing | `flutter_test` + `mocktail` (mocking) + `bloc_test` (Cubit assertions); AAA pattern, shared mocks in `test/helpers/mocks.dart`, no `build_runner` mocks |

Codegen (`json_serializable`, `injectable_generator`, `hive_generator`)
runs via `build_runner`. **Never hand-edit generated files**
(`*.g.dart`, `injection.config.dart`) — change the source, then regenerate.

---

## 2. Top-level layout — layers first, features inside

The `lib/` tree is organised **by architectural layer at the top level**, with
the feature folder *inside* each layer. This is deliberately not the
feature-first `lib/features/<feature>/{data,domain,presentation}` shape: with
layer-first you read all repository contracts in one place, all usecases in one
place, and you never have to open five feature folders to answer "what talks to
the network?".

```text
lib/
  main.dart                    # fallback default entry (today)
  main_development.dart        # dev flavor entry → bootstrap(FlavorConfig.development)
  main_production.dart         # prod flavor entry → bootstrap(FlavorConfig.production)
  app.dart                     # bootstrap() + App (root MaterialApp); rename/tidy per §13

  common/                      # cross-cutting infrastructure (see §5)
    injection/
      injection.dart           # getIt + @InjectableInit + @module providers
      injection.config.dart    # GENERATED — never hand-edit
    constant.dart              # AppConstants (defaults, endpoints, storage keys)
    failure.dart               # Failure hierarchy
    exception.dart             # ServerException / DatabaseException / CacheException
    remote_response_mapper.dart# ResponseMapper<T> marker interface
    hive_constant.dart         # Hive box names + type IDs (when Hive is used)

  data/                        # see §4
    datasources/
      remote/<feature>/<feature>_datasource.dart
      local/<feature>/<feature>_local_datasource.dart
    models/
      <feature>/<feature>_remote_response.dart
      <feature>/local/<feature>_local_model.dart
    repositories/<feature>_repository_impl.dart
    tools/<feature>/           # device tool service implementations (chat/data/tools/*)

  domain/                      # see §4
    entities/<feature>/        # plain Dart classes
    models/<feature>/          # domain-level value objects (e.g. ToolCallRequest)
    repositories/<feature>/    # abstract interfaces
    usecase/<feature>/         # thin callable wrappers, one action each
    tools/<feature>/           # domain tool contracts + security policy (ToolRegistry, SecurityPolicy)

  presentation/                # see §4
    navigation/
      app_router.dart          # single GoRouter instance (planned)
      app_routes.dart          # AppRoutes.nr* name constants (planned)
    screen/<feature>/
      <feature>_screen.dart
      cubit/<feature>_cubit.dart   # part '<feature>_state.dart';
      cubit/<feature>_state.dart   # part of '<feature>_cubit.dart';
    widget/                    # shared widgets reused across screens (e.g. FloatingBottomNavBar)

  utils/                       # design tokens + generic helpers
    app_theme.dart             # AppTheme (dark slate & teal)
    hermes_theme.dart          # HermesColors / HermesTypography / HermesTheme
    either_extensions.dart     # EitherX helpers
    dio_err_handler.dart       # DioErrHandler.handleDioError(...)
```

Two corollaries worth stating outright:

- **There is no `lib/features/`.** A "feature" is a *name* that repeats across
  `data/`, `domain/`, and `presentation/screen/` — not a folder that owns its
  own three layers.
- **Folder names are singular** — `usecase/`, not `usecases/`; a file is
  `<feature>_datasource.dart`, not `<feature>_datasources.dart`.

The current feature set: **chat** (ReAct agent loop, SSE chat, tool execution),
**gateway** (WebSocket/SSE RPC transport), **pairing** (QR scanner & pairing
payload), **server_profiles** (multi-server profile CRUD & active switcher),
**settings** (LLM endpoint, API keys, temperature), **navigation**, **skills**
(skills hub), **splash**, **memory_vault**, and **pocket_node**.

### `bootstrap()` init order (target, `lib/app.dart` / `myapp.dart`)

```dart
Future<void> bootstrap(FlavorConfig flavor) async {
  FlavorConfig.current = flavor;
  WidgetsFlutterBinding.ensureInitialized();
  // await Firebase.initializeApp(...);              // if Firebase is added
  configureInjection();                             // get_it/injectable (see §5)
  await _initHiveAdapters();                        // AWAIT this — don't fire-and-forget
  runApp(MyApp(flavor: flavor));
}

Future<void> _initHiveAdapters() async {
  await Hive.initFlutter();
  Hive.registerAdapter(SomeLocalModelAdapter());
  // ...one registerAdapter per @HiveType model
}
```

Order: set `FlavorConfig.current` → bind Flutter → init backend SDKs →
`configureInjection()` → register Hive adapters (awaited) → `runApp`.

---

## 3. Flavors

- Flames ships three entries: `lib/main.dart` (fallback), `lib/main_development.dart`
  (`ai.hermes.flames.dev`), `lib/main_production.dart` (`ai.hermes.flames`).
- Android product flavors mirror the Dart flavors, each with its own app name
  and `applicationIdSuffix`.
- CI builds with `flutter build apk --flavor <name> -t lib/main_<name>.dart`
  and gates on `flutter analyze` / `flutter test`, all serialized with
  `flock /tmp/flutter.lock` on this 2-vCPU VPS.
- Only add flavors the project actually needs.

---

## 4. Feature modules

A feature is a slice spread across the three layer folders:

```text
data/
  datasources/remote/<feature>/<feature>_datasource.dart  # abstract + Impl, talks to Dio/SDK
  datasources/local/<feature>/<feature>_local_datasource.dart
  models/<feature>/<feature>_remote_response.dart         # json_serializable, implements ResponseMapper<Entity>
  models/<feature>/local/<feature>_local_model.dart       # @HiveType, implements ResponseMapper<Entity>
  repositories/<feature>_repository_impl.dart             # implements the domain interface
  tools/<feature>/                                        # device tool services (ClipboardService, ...)

domain/
  entities/<feature>/<feature>.dart                       # plain Dart class
  models/<feature>/                                       # domain value objects (no JSON)
  repositories/<feature>/<feature>_repository.dart        # abstract class
  usecase/<feature>/<verb>_<feature>_usecase.dart         # one action each
  tools/<feature>/                                        # tool contracts + security policy (ToolRegistry, SecurityPolicy)

presentation/
  screen/<feature>/
    <feature>_screen.dart
    cubit/<feature>_cubit.dart                            # part '<feature>_state.dart';
    cubit/<feature>_state.dart                            # part of '<feature>_cubit.dart';
```

Not every feature needs every layer — a purely local/offline feature can skip
the remote datasource, and a static screen can skip the usecase. Add the pieces
the feature actually needs.

### The dependency rule

```text
presentation  ──▶  domain  ◀──  data
   (screens,       (entities,    (datasources,
    cubits)        usecases,     models,
                    repo iface)  repo impl)
```

- `domain` depends on nothing outside itself — entities are plain Dart classes,
  repository interfaces are abstract, a usecase imports only `dartz` + its own
  repository interface.
- `data` implements the interfaces declared in `domain/repositories/` and maps
  its DTOs to `domain/entities/` via each model's `toDomain()`.
- `presentation` depends on `domain` only — a cubit **never** imports a
  `data/` type. If a cubit needs something a datasource returns, that thing
  belongs in `domain/entities/` or `domain/models/`.

### The standard call chain

```text
Screen (StatefulWidget)
  → _xCubit.someAction()                          # pulled from getIt in State
      → <Feature>Usecase.call(...)                # a plain callable class
          → <Feature>RepositoryImpl                # implements the domain interface
              → <Feature>Datasource / LocalDatasource
                  → Dio / Hive / backend SDK
```

Standard files:

```dart
// domain/repositories/<feature>/<feature>_repository.dart
abstract class LlmRepository {
  Future<Either<Failure, Stream<ChatChunk>>> streamCompletion({
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? apiKey,
  });
}

// domain/usecase/<feature>/send_chat_message_usecase.dart
@lazySingleton
class SendChatMessageUsecase {
  final LlmRepository llmRepository;
  SendChatMessageUsecase({required this.llmRepository});

  Future<Either<Failure, Stream<ChatChunk>>> call(
          {required String baseUrl,
           required String model,
           required List<Map<String, dynamic>> messages,
           List<Map<String, dynamic>>? tools,
           String? apiKey}) =>
      llmRepository.streamCompletion(
          baseUrl: baseUrl,
          model: model,
          messages: messages,
          tools: tools,
          apiKey: apiKey);
}

// data/datasources/remote/<feature>/<feature>_datasource.dart
abstract class LlmDatasource {
  Future<ResponseBody> streamCompletion(...);
}

@LazySingleton(as: LlmDatasource)
class LlmDatasourceImpl implements LlmDatasource { /* injects Dio */ }

// data/repositories/<feature>_repository_impl.dart
@LazySingleton(as: LlmRepository)
class LlmRepositoryImpl implements LlmRepository {
  final LlmDatasource llmDatasource;
  final SseParser sseParser;
  LlmRepositoryImpl({required this.llmDatasource, required this.sseParser});

  @override
  Future<Either<Failure, Stream<ChatChunk>>> streamCompletion(...) async {
    try {
      // parse SSE lines via sseParser, return Right(stream)
    } on SocketException {
      return const Left(ConnectionFailure('Failed to connect to the network'));
    }
  }
}
```

> Migration note: today `LlmRepository` is a single concrete class in
> `features/chat/data/llm_repository.dart` that both defines the contract and
> talks to `Dio` directly. Later migration cards split it into
> `domain/repositories/chat/llm_repository.dart` (abstract) +
> `data/repositories/chat/llm_repository_impl.dart` (impl) and move the SSE
> parsing into the impl / datasource.

---

## 5. Dependency injection (`lib/common/injection/`)

Two files: hand-written `injection.dart` and generated
`injection.config.dart` (via `injectable_generator` + `build_runner`).

```dart
// lib/common/injection/injection.dart
final getIt = GetIt.instance;

@InjectableInit()
void configureInjection() => getIt.init();

@module
abstract class NetworkModule {
  @lazySingleton
  Dio provideDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));
    return dio;
  }
}

@module
abstract class StorageModule {
  @lazySingleton
  FlutterSecureStorage provideSecureStorage() => const FlutterSecureStorage();
}
```

`@module` abstract classes are how third-party types that can't be annotated
directly (`Dio`, secure storage) get registered — the single `Dio` instance
produced here is injected into every remote datasource's constructor. There is
no separate `ApiClient`/`ApiService` wrapper class.

### Annotation map

| Layer | Annotation | Example |
|---|---|---|
| Remote/local datasource impl | `@LazySingleton(as: AbstractType)` | `<Feature>DatasourceImpl` |
| Repository impl | `@LazySingleton(as: AbstractType)` | `<Feature>RepositoryImpl` |
| Usecase | `@lazySingleton` (concrete class, no interface) | `SendChatMessageUsecase` |
| Cubit | `@injectable` (factory — new instance per resolve) | `AgentCubit` |
| Plain utility singleton | `@singleton` | `DioErrHandler` |
| Third-party singleton | `@module` + `@lazySingleton` | `Dio`, `FlutterSecureStorage` |

### How a cubit reaches a widget

Not via an app-wide `BlocProvider(create: ...)` at the root. Instead:

```dart
class _ChatScreenState extends State<ChatScreen> {
  final AgentCubit _cubit = getIt<AgentCubit>();

  @override
  void initState() {
    super.initState();
    _cubit.load();                       // trigger the action right here
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [BlocProvider<AgentCubit>.value(value: _cubit)],
      child: Scaffold(body: BlocBuilder<AgentCubit, AgentState>(...)),
    );
  }
}
```

i.e. pull the cubit from `getIt` as a `State` field → trigger its action in
`initState` → wrap the subtree in `BlocProvider<T>.value(...)` (use
`MultiBlocProvider` when a screen needs more than one). Only create a cubit
inline inside a route `builder` when the route itself passes constructor
arguments the cubit can't get from DI alone.

> Migration note: today DI is hand-written (`lib/core/di/injection_container.dart`,
> ~25 `sl.register*` calls with manual `isRegistered` guards). The migration
> retires it: `initDependencies()` delegates to `configureInjection()` and later
> cards delete it.

---

## 6. State management (Cubit)

Every feature uses a plain `Cubit<State>` (no `Bloc`, no event classes). Each
`<feature>_cubit.dart` / `<feature>_state.dart` pair lives in
`presentation/screen/<feature>/cubit/` and is joined with `part` / `part of`.

```dart
// presentation/screen/<feature>/cubit/<feature>_cubit.dart
part '<feature>_state.dart';

@injectable
class <Feature>Cubit extends Cubit<<Feature>State> {
  final <Feature>Usecase <feature>Usecase;
  <Feature>Cubit({required this.<feature>Usecase}) : super(<Feature>Initial());

  void load() async {
    emit(<Feature>Loading());
    final result = await <feature>Usecase.call();
    result.fold(
      (failure) => emit(<Feature>Error(message: failure.message)),
      (data) => emit(<Feature>Success(data: data)),
    );
  }
}
```

```dart
// presentation/screen/<feature>/cubit/<feature>_state.dart
part of '<feature>_cubit.dart';

sealed class <Feature>State extends Equatable {
  const <Feature>State();
  @override
  List<Object> get props => [];
}

final class <Feature>Initial extends <Feature>State {}
final class <Feature>Loading extends <Feature>State {}

final class <Feature>Success extends <Feature>State {
  final <Entity> data;
  const <Feature>Success({required this.data});
  @override
  List<Object> get props => [data];
}

final class <Feature>Error extends <Feature>State {
  final String message;
  const <Feature>Error({required this.message});
  @override
  List<Object> get props => [message];
}
```

The standard shape: `emit(XLoading())` → call the usecase → `result.fold` into
`XError(failure.message)` or `XSuccess(data)`. Screens render with
`BlocBuilder`, branching on `state is XLoading / XSuccess / XError` — **always
handle all three**, plus an `else` returning `SizedBox.shrink()` for
`Initial`.

The chat/ReAct cubit is the reference for a **stream-driven exception**: it
models the live SSE stream directly, tracks cancellable subscriptions
(`_isCancelled`, `StreamSubscription`) and exposes a `stop()`, because a
streaming loop must be interruptible. Stream-driven state is the exception,
not the template — don't use it for ordinary data-fetching features.

---

## 7. Networking

`Dio` is provided once via DI (see §5) and injected directly into each remote
datasource's constructor — there is no `ApiClient`/`ApiService` wrapper.

### Error handling — two layers

1. A shared `lib/utils/dio_err_handler.dart` — `class DioErrHandler` with
   `String handleDioError(DioException error)`, switching on
   `DioExceptionType` (connection timeout, receive timeout, `badResponse` with
   status-code-specific messages) to produce a human-readable string.

   ```dart
   class DioErrHandler {
     const DioErrHandler();
     String handleDioError(DioException error) {
       switch (error.type) {
         case DioExceptionType.connectionTimeout:
           return 'Network error occurred. Please check your internet connection.';
         case DioExceptionType.receiveTimeout:
           return 'Request timeout occurred';
         case DioExceptionType.badResponse:
           if (error.response?.statusCode == 401) {
             return 'Authentication failed. Please login again.';
           }
           return 'An unexpected error occurred. Please try again later.';
         default:
           return 'An unexpected error occurred. Please try again later.';
       }
     }
   }
   ```

2. Repository impls catch `DioException` / `SocketException` — call the shared
   handler, wrap the string in a `ConnectionFailure` inside `dartz`'s `Left`.
   Use the shared handler for every repository; don't write bespoke
   per-repository try/catch for the same errors.

Datasources throw plain exceptions from `lib/common/exception.dart`
(`ServerException`, `DatabaseException`, `CacheException`) on failure.

Streaming chat uses `dio` with `ResponseType.stream` + the custom `SseParser`
(`data/datasources/remote/chat/sse_parser.dart`) to turn SSE lines into
`ChatChunk` / tool-call deltas.

---

## 8. Error model

- `lib/common/failure.dart` — abstract `Failure extends Equatable` (holds a
  `message`) with concrete subclasses `ServerFailure`, `ConnectionFailure`,
  `DatabaseFailure`, `CacheFailure`, plus Flames-specific storage/permission
  failures (`StorageFailure`, `PermissionFailure`) as needed.
- `lib/common/exception.dart` — plain exceptions `ServerException`,
  `DatabaseException(message)`, `CacheException(message)`, thrown by
  datasources, caught by repository impls.
- `Either<Failure, T>` (from `dartz`) is the return type for every repository
  method and usecase `call()`. Cubits consume it via
  `result.fold((failure) => emit(XError(...)), (data) => emit(XSuccess(...)))`.

---

## 9. Local storage (Hive + secure storage)

- `flutter_secure_storage` holds credentials, API keys/tokens, and server
  profiles; `hive_ce_flutter` is the offline cache layer.
- `Hive.initFlutter()` runs once in `bootstrap()`'s `_initHiveAdapters()`,
  followed by `Hive.registerAdapter(...)` for each `@HiveType` model — awaited.
- Hive type IDs and box names are centralized in
  `lib/common/hive_constant.dart`.
- Only cache a feature's data if it actually benefits from an offline/fast read
  path — not every feature needs a Hive box.
- Repository impls that cache follow a **cache-first** pattern: check the local
  Hive datasource first; if present, map to domain and return; otherwise hit
  the remote datasource, map remote → domain, persist remote → local for next
  time, then return.
- `get*` local-datasource methods soft-fail (return `null`) on a cache miss;
  `set*` methods throw `CacheException` on write failure.

---

## 10. Models & serialization

Remote DTOs use `json_annotation` + `json_serializable`. Local cache DTOs use
`hive` (`@HiveType`/`@HiveField`). **Both** implement a shared marker interface:

```dart
// lib/common/remote_response_mapper.dart
abstract class ResponseMapper<T> {
  T toDomain();
}
```

```dart
// data/models/<feature>/<feature>_remote_response.dart
part '<feature>_remote_response.g.dart';

@JsonSerializable()
class <Feature>RemoteResponse implements ResponseMapper<<Feature>Data> {
  @JsonKey(name: 'Some_PascalCase_Field')
  final String someField;

  <Feature>RemoteResponse({required this.someField});

  factory <Feature>RemoteResponse.fromJson(Map<String, dynamic> json) =>
      _$<Feature>RemoteResponseFromJson(json);
  Map<String, dynamic> toJson() => _$<Feature>RemoteResponseToJson(this);

  @override
  <Feature>Data toDomain() => <Feature>Data(someField: someField);
}
```

- Use `@JsonKey(name: '...')` to map upstream field naming (e.g. PascalCase) to
  camelCase Dart fields.
- Local Hive models additionally expose static `fromDomain(...)` and
  `fromRemote(...)` factory helpers to bridge domain entities / remote DTOs
  into the cached shape.
- Naming: `<Feature>RemoteResponse` for API DTOs (`data/models/<feature>/`),
  `<Feature>LocalModel` for Hive cache DTOs (`data/models/<feature>/local/`).
- Domain entities (`domain/entities/<feature>/`) are plain Dart classes with
  only the fields the app needs — repository impls translate DTO → entity via
  `toDomain()` so the UI never sees a raw response shape.

---

## 11. Routing

Target: one `go_router` instance in `lib/presentation/navigation/app_router.dart`
with route name constants in `app_routes.dart` (`AppRoutes.nr*`), wired into the
root `MaterialApp.router` via `routeInformationProvider`,
`routeInformationParser`, and `routerDelegate`.

```dart
final GoRouter appRouter = GoRouter(
  navigatorKey: AppGlobals.navigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: AppRoutes.nrSplash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/chat',
      name: AppRoutes.nrChat,
      builder: (context, state) => const ChatScreen(),
    ),
  ],
);
```

- Pass arguments via `state.extra`, cast with `as`. Guard the cast (or use
  typed query/path params) where a wrong-typed `extra` is reachable from user
  input rather than internal navigation only.
- New route paths derive from the name constant and use kebab-case.

> Current state: the app uses `MaterialApp(home:)` in `lib/app.dart`:
> `SplashScreen → MainNavigationShell`. Introducing `go_router` is part of the
> layer-first migration; until then keep the home chain working.

---

## 12. UI & design tokens

- `lib/utils/app_theme.dart` — `AppTheme`, dark slate & teal palette (`#0F172A` /
  `#008080`). Use it everywhere instead of raw `Colors.*` or literal hex.
- `lib/utils/hermes_theme.dart` — `HermesColors` / `HermesTypography` /
  `HermesTheme`, the technical terminal theme (deep obsidian `#0A0D14`, card
  surface `#131926`, electric teal `#00F2FE`, code bg `#060612`).
- **Zero emoji in chrome**: `Icons.*` only across app bars, navigation, cards,
  buttons, and modals.
- Shared widgets go in `lib/presentation/widget/`; screen-local widgets stay
  inline in the feature's `presentation/screen/<feature>/` until a second
  feature needs them, then they are promoted to `lib/presentation/widget/`.

---

## 13. Feature assembly flow

When assembling a new feature module, build components in dependency order:

1. **Domain first** — entity (`domain/entities/<feature>/`), repository
   interface (`domain/repositories/<feature>/`), one usecase per action
   (`domain/usecase/<feature>/`).
2. **Data** — remote/local models implementing `ResponseMapper<T>`
   (`data/models/`), datasources (`data/datasources/`), repository impl
   (`data/repositories/`), device tool services (`data/tools/<feature>/`).
   Annotate each (`@LazySingleton(as: ...)` etc., see §5) and run
   `build_runner`.
3. **State** — the cubit + state pair
   (`presentation/screen/<feature>/cubit/`), annotated `@injectable`.
4. **UI** — the screen widget, pulling the cubit from `getIt` in `State`,
   triggering its action in `initState` (see §5).
5. **Routing** — add a name constant to `AppRoutes` and a `GoRoute` (see §11).

---

## 14. Testing

Test folder structure **strictly mirrors** `lib/`'s layer-first layout — one
`<file>_test.dart` per source file:

```text
test/
  helpers/
    mocks.dart               # shared mocktail mocks + fallback registration
  common/                    # injection, constant, failure, exception
  utils/                     # app_theme, hermes_theme, dio_err_handler
  data/
    datasources/<feature>/
    models/<feature>/
    repositories/<feature>/
    tools/<feature>/
  domain/
    entities/<feature>/
    models/<feature>/
    repositories/<feature>/
    usecase/<feature>/
    tools/<feature>/
  presentation/
    navigation/
    screen/<feature>/
      cubit/<feature>_cubit_test.dart     # Cubit unit tests belong here
      <feature>_screen_test.dart          # widget tests
    widget/
  integration/               # end-to-end integration tests
```

| Layer | Tool | What it covers |
|---|---|---|
| Usecase / repository | `flutter_test` + `mocktail` | mock one layer below (a repository mocks its datasource; a usecase mocks its repository interface), assert the `Either<Failure, T>` |
| Cubit | `bloc_test` + `mocktail` | mock the usecase, assert the emitted state sequence (`Initial → Loading → Success`/`Error`) |
| Widget/screen | `flutter_test` (`testWidgets`) | pump the screen with a mocked cubit via `BlocProvider.value`, assert each render branch |

Prefer `mocktail` over `mockito` — no code generation, works directly with
`get_it`/`injectable`'s constructor-injected classes. Register `mocktail`
fallback values once in `test/helpers/mocks.dart`, not per-test.

**Mock one layer down, never further** — a cubit test mocks its usecase, not the
repository underneath it; a usecase test mocks its repository interface, not the
datasource. Not every class needs a test: prioritize usecases (business logic)
and cubits (state transitions) first — widget tests earn their cost on a
screen's branching logic, not on pure layout.

> For coding standards, naming conventions, and the verification checklist
> before marking work complete, see [`rules.md`](./rules.md). For the exact
> current-file → target-file moves, see
> [`MIGRATION-PLAN.md`](./MIGRATION-PLAN.md).

---

## 15. Flames exceptions to the template

Canonical base is `flutter-cubit-template` (layer-first `lib/{common,data,
domain,presentation,utils}/`, Cubit-only, `get_it` + `injectable`, `dartz`
`Either<Failure, T>`). Flames keeps that core and deliberately deviates in
the 7 ways below. Nothing here is accidental drift — each exception exists
for a Flames-specific requirement.

### 1. Entrypoints & Flavors (dev + prod only, lib/main.dart fallback, no staging)

- Entries: `lib/main_development.dart` → `bootstrap(FlavorConfig.development)`,
  `lib/main_production.dart` → `bootstrap(FlavorConfig.production)`, plus
  `lib/main.dart` as fallback default entry.
- No `staging` flavor. Android product flavors mirror dev/prod only, each
  with its own app name and `applicationIdSuffix`.
- CI builds with `flutter build apk --flavor <name> -t lib/main_<name>.dart`.
- Rationale: Flames needs exactly two deploy targets today; a third flavor
  adds signing/CI cost with no consumer.

### 2. Local Storage & Module DI (flutter_secure_storage + hive_ce_flutter, StorageModule)

- `flutter_secure_storage` holds credentials, API keys/tokens, and server
  profiles; `hive_ce_flutter` is the offline cache layer (see §9).
- Registered via an injectable `@module` `StorageModule` in
  `lib/common/injection/injection.dart`:
  `provideSecureStorage() => const FlutterSecureStorage()`.
- `Hive.initFlutter()` + `registerAdapter(...)` run awaited in `bootstrap()`;
  box names / type IDs centralized in `lib/common/hive_constant.dart`.
- Rationale: template has no secure-credential story; Flames stores secrets
  that must never sit in plain Hive boxes.

### 3. Native Device Tools layer (lib/data/datasources/tools/chat/ and lib/domain/tools/chat/)

- Data side: `lib/data/datasources/tools/chat/` — device service
  implementations (`ClipboardService`, `LocationService`,
  `DeviceContextService`, `CameraVisionService`, `CalendarService`,
  `NotificationService`).
- Domain side: `lib/domain/tools/chat/` — tool contracts + `ToolRegistry` and
  `SecurityPolicy` (Tier 1 auto / Tier 2 permission / Tier 3 HITL).
- Backed by plugins: `battery_plus`, `connectivity_plus`, `device_info_plus`,
  `geolocator`, `image_picker`, `device_calendar`,
  `flutter_local_notifications`.
- Rationale: template has no device-tool concept; the ReAct agent loop needs
  a dedicated execution surface with a security gate.

### 4. Realtime Gateway & SSE Streaming (web_socket_channel + Dio SseParser)

- `web_socket_channel` provides the bidirectional universal-gateway RPC
  transport (gateway feature).
- Streaming chat uses `dio` with `ResponseType.stream` + custom `SseParser`
  (`data/datasources/remote/chat/sse_parser.dart`) turning SSE lines into
  `ChatChunk` / tool-call deltas; `LlmRepository.streamCompletion` returns
  `Either<Failure, Stream<ChatChunk>>`.
- `Dio` is injected directly into datasources (no `ApiClient` wrapper);
  errors flow through shared `DioErrHandler` → `ConnectionFailure`.
- Rationale: template assumes request/response REST; Flames is
  streaming-first (tokens + tool-call deltas over SSE/WebSocket).

### 5. Stream-driven Agent Cubit (AgentCubit models SSE tokens with cancel/stop)

- `AgentCubit` (in `presentation/screen/<feature>/cubit/`, `@injectable`)
  models the live SSE stream directly instead of the standard
  `Loading → Success/Error` one-shot shape (see §6).
- Tracks cancellable subscriptions (`_isCancelled`, `StreamSubscription`)
  and exposes `stop()` so a streaming ReAct loop is interruptible.
- Rationale: a token stream must be cancellable mid-flight; ordinary
  data-fetching features keep the standard one-shot shape.

### 6. Design System & Tokens (AppTheme, HermesColors/HermesTypography/HermesTheme, Zero Emoji in Chrome)

- `lib/utils/app_theme.dart` — `AppTheme` dark slate & teal (`#0F172A` /
  `#1E293B` / `#334155` / accent `#008080`).
- `lib/utils/hermes_theme.dart` — `HermesColors` / `HermesTypography` /
  `HermesTheme` terminal theme (obsidian `#0A0D14`, card `#131926`,
  electric teal `#00F2FE`, code bg `#060612`).
- Assistant bubbles render via `flutter_markdown`; HITL approvals via
  `ActionApprovalSheet`, tool runs via `ToolCallCard`.
- **Zero emoji in chrome**: `Icons.*` only across app bars, navigation,
  cards, buttons, modals (see `design-system.md`, `rules.md` §1.7).
- Rationale: template ships no opinionated theme; Flames is a dark
  terminal-style workstation with a hard no-emoji chrome rule.

### 7. Automated Layout Guard (tool/check_layout.sh wired into DoD)

- `tool/check_layout.sh` mechanically enforces layer-first invariants:
  no `lib/features/`, no parallel `lib/core/`, no `flutter_bloc` /
  `package:flutter/` under `lib/domain/`, no re-export shims, required
  paths present, no `presentation → data` imports, no DTOs in `domain/`.
- Must print `LAYOUT OK` (exit 0); wired into Definition of Done alongside
  `flutter analyze` (0 issues) and `flutter test` (100% green).
- Rationale: template relies on review discipline; Flames codifies the
  layout traps (§8) as a script so regressions fail fast on VPS/CI.