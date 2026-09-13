import 'package:flutter_ai_agent/domain/services/tools/tool_search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolSearchIndex.tokenize', () {
    test('expands Indonesian synonyms and drops stopwords', () {
      final tokens = ToolSearchIndex.tokenize('cek baterai hp saya');

      expect(tokens, contains('baterai'));
      expect(tokens, contains('battery'));
      expect(tokens, contains('hp'));
      expect(tokens, contains('device'));
      expect(tokens, isNot(contains('saya')));
    });

    test('returns empty for empty string', () {
      expect(ToolSearchIndex.tokenize(''), isEmpty);
    });

    test('returns empty for blank string', () {
      expect(ToolSearchIndex.tokenize('   '), isEmpty);
    });

    test('lowercases and splits on punctuation with alphanumeric tokens', () {
      final tokens = ToolSearchIndex.tokenize('Battery, STATUS!');

      expect(tokens, contains('battery'));
      expect(tokens, contains('status'));
      for (final token in tokens) {
        expect(token, matches(RegExp(r'^[a-z0-9]+$')));
      }
    });

    test('dedupes repeated tokens', () {
      final tokens = ToolSearchIndex.tokenize('battery battery battery');

      expect(tokens, equals(<String>['battery']));
    });
  });

  group('ToolSearchIndex.toolNamesForPrompt', () {
    test('does not match wa inside want', () {
      expect(
        ToolSearchIndex.toolNamesForPrompt('i want to write a paper'),
        isEmpty,
      );
    });

    test('matches contact tools for wa chat prompt', () {
      expect(
        ToolSearchIndex.toolNamesForPrompt('open wa chat with budi'),
        contains('search_contacts'),
      );
    });

    test('matches device tools for battery prompt', () {
      final names =
          ToolSearchIndex.toolNamesForPrompt('what is my battery level');

      expect(names, contains('device_status'));
      expect(names, contains('system_info'));
    });

    test('matches clipboard and calendar tools', () {
      final names = ToolSearchIndex.toolNamesForPrompt(
        'copy this calendar event to my clipboard',
      );

      expect(names, contains('clipboard_read'));
      expect(names, contains('clipboard_write'));
      expect(names, contains('calendar_list_events'));
      expect(names, contains('calendar_create_event'));
      expect(names, contains('schedule_reminder'));
    });

    test('matches device tools via Indonesian synonyms', () {
      expect(
        ToolSearchIndex.toolNamesForPrompt('cek baterai hp saya'),
        contains('device_status'),
      );
    });

    test('matches notification tools for Indonesian prompt', () {
      expect(
        ToolSearchIndex.toolNamesForPrompt('ada notifikasi baru?'),
        contains('read_recent_notifications'),
      );
    });

    test('returns empty for greeting with no keywords', () {
      expect(
        ToolSearchIndex.toolNamesForPrompt('hello, how are you?'),
        isEmpty,
      );
    });
  });

  group('ToolSearchIndex.rank', () {
    final docs = <ToolSearchDoc>[
      const ToolSearchDoc(
        name: 'device_status',
        description:
            'Returns device status including battery level, charging state, and network connectivity (WiFi/Cellular).',
      ),
      const ToolSearchDoc(
        name: 'system_info',
        description:
            'Returns device system info including model, OS version, app version, and screen specs.',
      ),
      const ToolSearchDoc(
        name: 'get_location',
        description: 'Get the current device location',
      ),
      const ToolSearchDoc(
        name: 'read_recent_notifications',
        description: 'Reads recent device notifications.',
      ),
      const ToolSearchDoc(
        name: 'camera_take_photo',
        description:
            'Captures a photo via camera or gallery and returns base64 image data.',
      ),
      const ToolSearchDoc(
        name: 'search_contacts',
        description: 'Search device contacts by name or phone number.',
      ),
      const ToolSearchDoc(
        name: 'save_memory',
        description: 'Saves a key-value memory entry.',
      ),
      const ToolSearchDoc(
        name: 'tool_search',
        description:
            'Searches the available tools by keyword and returns matching tool names, best match first. Accepts multi-word queries; prefer single keywords like battery, location, notification.',
      ),
    ];

    test('ranks device_status first for multi-word query', () {
      final result = ToolSearchIndex.rank(
        query: 'device status battery',
        docs: docs,
      );

      expect(result, isNotEmpty);
      expect(result, contains('device_status'));
      expect(result.first, equals('device_status'));
    });

    test('finds device_status for battery status query', () {
      final result = ToolSearchIndex.rank(
        query: 'battery status',
        docs: docs,
      );

      expect(result, contains('device_status'));
    });

    test('finds system_info for Indonesian device info query', () {
      final result = ToolSearchIndex.rank(
        query: 'perangkat model informasi',
        docs: docs,
      );

      expect(result, contains('system_info'));
    });

    test('ranks exact full-name match first', () {
      final result = ToolSearchIndex.rank(
        query: 'device_status',
        docs: docs,
      );

      expect(result.first, equals('device_status'));
    });

    test('returns empty for unknown gibberish', () {
      expect(
        ToolSearchIndex.rank(query: 'zzzqqq nonsense', docs: docs),
        isEmpty,
      );
    });

    test('returns empty for empty query', () {
      expect(ToolSearchIndex.rank(query: '', docs: docs), isEmpty);
    });

    test('returns empty for blank query', () {
      expect(ToolSearchIndex.rank(query: '   ', docs: docs), isEmpty);
    });

    test('returns empty for all-stopword query', () {
      expect(ToolSearchIndex.rank(query: 'what is my', docs: docs), isEmpty);
    });

    test('respects limit', () {
      final result = ToolSearchIndex.rank(
        query: 'device status battery',
        docs: docs,
        limit: 1,
      );

      expect(result, hasLength(1));
    });

    test('preserves input order on ties', () {
      const tied = <ToolSearchDoc>[
        ToolSearchDoc(name: 'alpha_tool', description: 'common description xyz'),
        ToolSearchDoc(name: 'beta_tool', description: 'common description xyz'),
      ];

      final result = ToolSearchIndex.rank(query: 'common', docs: tied);

      expect(result, equals(<String>['alpha_tool', 'beta_tool']));
    });
  });
}
