# [TASK ASSIGNMENT]
Task ID: T18.3-memory-fts5-fallback

## Goal
Make the Memory Vault resilient on Android devices whose platform SQLite lacks the FTS5
module (verified crash: `DatabaseException(no such module: fts5)` on Xiaomi/Android 14).
Ship a bundled SQLite with FTS5 AND degrade gracefully with a LIKE fallback when FTS5 is
genuinely unavailable. Failures must surface as a structured, self-describing
`memory_unavailable` result — never a raw SQLite error string.

## Target Files
- `pubspec.yaml` (add ONE dependency: `sqlite3_flutter_libs` under `dependencies:` — pick the latest stable from what `flutter pub get` resolves; do NOT touch other deps or versions)
- `lib/data/datasources/tools/chat/local_memory_service.dart`
- `test/data/datasources/tools/chat/local_memory_service_test.dart`

## Files to NOT Touch
- `lib/domain/tools/chat/local_memory_service.dart` (domain contract stays as-is)
- `lib/common/failure.dart`
- `lib/common/injection/injection.config.dart`
- Anything else.

## Context & Architectural Rules
- Clean Architecture: this is a data-layer datasource. Keep the injectable `DatabaseFactory?` /
  `String?` constructor seam EXACTLY as it is — tests pass their own factory.
- Failure type is `StorageFailure` (only has `message`). No new failure classes.
- `sqflite_common_ffi` is already a dependency (exports `databaseFactoryFfi`).
- Current known facts about the file:
  - `LocalMemoryService.database` getter (~line 31) resolves
    `final factory = _databaseFactory ?? databaseFactory;` then `await getDatabasesPath()` (global sqflite fn, line 42).
  - `onCreateDatabase` (~line 58) creates `memories` plain table, then `memories_fts USING fts5(...)`
    + 3 triggers — this is what throws on the device.
  - `searchMemories` (~line 211) uses `bm25(memories_fts)` MATCH query; `_sanitizeFtsQuery` builds
    `word* OR word*`.
  - Existing test file (577 lines) already injects `databaseFactoryFfi` and has ~12 tests —
    EXTEND it, do not rewrite it; keep all existing tests passing.

## Specification Constraints (Non-negotiable)
1. **Bundled SQLite on Android**: add `sqlite3_flutter_libs` to pubspec `dependencies`. In the
   `database` getter, BEFORE the first `openDatabase`: if `_databaseFactory == null` AND
   `Platform.isAndroid`, set the GLOBAL `databaseFactory = databaseFactoryFfi` (import from
   `package:sqflite_common_ffi/sqflite_ffi.dart`; also import `dart:io` for `Platform`).
   When a factory/path IS injected (tests), never touch the global. Resolve the path via
   `factory.getDatabasesPath()` instead of the global `getDatabasesPath()` so the injected-factory
   path stays coherent.
2. **Graceful schema creation**: split `onCreateDatabase` into base-table creation (always runs) and
   FTS setup (FTS virtual table + the 3 triggers) wrapped so that a `no such module: fts5` /
   FTS-unsupported error is caught and swallowed (skip FTS objects). Track support on the instance:
   add a private nullable bool `_ftsSupported` set at open time by probing FTS (e.g. attempt the
   CREATE VIRTUAL TABLE on a temporary probe like `CREATE VIRTUAL TABLE IF NOT EXISTS
   temp.fts5_probe USING fts5(x)` inside try/catch, then DROP it). Keep `onCreateDatabase`'s static
   signature (tests call it directly) — make the FTS section inside it individually guarded so it
   never aborts the base schema.
3. **LIKE fallback search**: in `searchMemories`, if `_ftsSupported == false`, query the plain
   `memories` table with LIKE over `key`, `content`, `tags` (each LIKE term as
   `%<word>%` for every sanitized word, OR-joined via a WHERE of ORs), same `ORDER BY updated_at DESC`,
   same `limit` semantics. Keep the existing FTS path when supported.
4. **Search mode surfaced**: `searchMemoriesFormattedJson` must include `"search_mode": "fts5"`
   or `"search_mode": "like_fallback"` in the JSON result. (Decide mode from `_ftsSupported`; when
   the DB isn't open yet, report the mode of the connection used by the search call — make
   `searchMemories` expose the used mode, e.g. via an internal out-param method the formatted
   wrapper calls, NOT by changing the public `LocalMemoryServiceBase` contract.)
5. **Structured unavailability, no raw SQLite leaks**: in the `catch` blocks of
   `saveMemory`, `searchMemories`, `getAllMemories`, and the formatted JSON wrappers:
   - Either-level: `Left(StorageFailure('memory_unavailable: <short reason>'))`.
   - Formatted-JSON level: return `Right(jsonEncode({'status': 'memory_unavailable', 'reason': '<short reason>'}))`
     so the agent gets a parseable structured result instead of a crash-looking string.
   Strip raw `DatabaseException(...)` dumps from messages — extract the concise cause.
6. **Tests** (add to the existing test file, mocktail-free, AAA style):
   a. Schema creation with an FTS5-capable factory (`databaseFactoryFfi`) succeeds and FTS search
      works end-to-end (likely already covered — keep/extend).
   b. LIKE fallback: inject a factory whose `openDatabase`/execute raises
      `DatabaseException('no such module: fts5 ...')` when the FTS virtual table is created, but
      supports plain SQL. Simplest approach: wrap `databaseFactoryFfi` in a delegating
      `DatabaseFactory`/`Database` stub class whose `execute` throws that exception when the SQL
      contains `USING fts5`, and forwards everything else to the real ffi db. Then: insert 2 rows
      via `saveMemory`, `searchMemories('needle')` returns the row containing 'needle',
      and `searchMemoriesFormattedJson` reports `"search_mode": "like_fallback"`.
   c. Unavailable path: a call on a service whose factory throws a non-FTS open error returns
      `Left` with a message starting `memory_unavailable:`, and the formatted JSON returns
      `status == 'memory_unavailable'`.

## Definition of Done (DoD)
- Run: `flutter analyze`  → No issues found!
- Run: `flutter test test/data/datasources/tools/chat/local_memory_service_test.dart` → 100% pass
  (all pre-existing tests still green + new ones).
- Do NOT run any git command. Do NOT run `flutter test` full suite (lead runs it).
- Do NOT read files under ~/.pub-cache.
- Report what you actually changed (file:line) and paste real DoD command output.

Model note: work step by step; if `flutter pub get` fails on `sqlite3_flutter_libs` resolution,
try `flutter pub add sqlite3_flutter_libs` instead of hand-editing the version.
