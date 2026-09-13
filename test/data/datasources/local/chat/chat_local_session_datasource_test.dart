import 'package:flutter_ai_agent/data/datasources/local/chat/chat_local_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockFlutterSecureStorage mockStorage;
  late Database db;
  late ChatLocalDatasourceImpl datasource;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    mockStorage = MockFlutterSecureStorage();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: ChatLocalDatasourceImpl.currentSchemaVersion,
        onCreate: ChatLocalDatasourceImpl.onCreateDatabase,
        onUpgrade: ChatLocalDatasourceImpl.onUpgradeDatabase,
      ),
    );
    datasource = ChatLocalDatasourceImpl(storage: mockStorage, database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('session CRUD', () {
    test('createSession inserts and returns a persisted session', () async {
      final session = await datasource.createSession('p1', 'First chat');

      expect(session.id, greaterThan(0));
      expect(session.profileId, 'p1');
      expect(session.title, 'First chat');
      expect(session.createdAt, session.updatedAt);
    });

    test('getSession returns the session by id, null when missing', () async {
      final created = await datasource.createSession('p1', 'First chat');

      final found = await datasource.getSession(created.id);
      final missing = await datasource.getSession(9999);

      expect(found, created);
      expect(missing, isNull);
    });

    test('getSessions scopes by profile and orders by updated_at DESC',
        () async {
      final a = await datasource.createSession('p1', 'A');
      final b = await datasource.createSession('p1', 'B');
      await datasource.createSession('p2', 'Other');
      await datasource.updateSessionTitle(a.id, 'A renamed');

      final sessions = await datasource.getSessions('p1');

      expect(sessions.map((s) => s.id), [a.id, b.id]);
      expect(sessions.first.title, 'A renamed');
    });

    test('updateSessionTitle updates the stored title', () async {
      final created = await datasource.createSession('p1', 'Old');

      await datasource.updateSessionTitle(created.id, 'New');

      final reloaded = await datasource.getSession(created.id);
      expect(reloaded!.title, 'New');
      expect(reloaded.updatedAt, greaterThanOrEqualTo(created.updatedAt));
    });

    test('deleteSession removes the row and its messages', () async {
      final created = await datasource.createSession('p1', 'Bye');
      when(() => mockStorage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      await datasource.deleteSession(created.id);

      expect(await datasource.getSession(created.id), isNull);
      verify(
        () => mockStorage.delete(
          key: ChatLocalDatasourceImpl.keyFor(created.id.toString()),
        ),
      ).called(1);
    });
  });

  group('session messages', () {
    test('keyFor derives a stable session key', () {
      expect(ChatLocalDatasourceImpl.keyFor('42'), 'chat_history_42');
    });
  });
}
