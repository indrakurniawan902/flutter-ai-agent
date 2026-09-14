import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccessibilityBounds.tryParse', () {
    test('parses the native comma string', () {
      final bounds = AccessibilityBounds.tryParse('10,20,110,220');

      expect(
        bounds,
        const AccessibilityBounds(left: 10, top: 20, right: 110, bottom: 220),
      );
      expect(bounds!.short, '10,20,110,220');
      expect(bounds.width, 100);
      expect(bounds.height, 200);
      expect(bounds.centerX, 60);
      expect(bounds.centerY, 120);
    });

    test('parses a four-element list', () {
      final bounds = AccessibilityBounds.tryParse([10, 20, 110, 220]);

      expect(
        bounds,
        const AccessibilityBounds(left: 10, top: 20, right: 110, bottom: 220),
      );
    });

    test('returns null for null, empty and garbage input', () {
      expect(AccessibilityBounds.tryParse(null), isNull);
      expect(AccessibilityBounds.tryParse(''), isNull);
      expect(AccessibilityBounds.tryParse('garbage'), isNull);
      expect(AccessibilityBounds.tryParse('1,2,3'), isNull);
      expect(AccessibilityBounds.tryParse('a,b,c,d'), isNull);
      expect(AccessibilityBounds.tryParse([1, 2, 3]), isNull);
      expect(AccessibilityBounds.tryParse(<Object?>[1, 2, 'x', 4]), isNull);
    });
  });

  group('AccessibilityBounds.fromJson', () {
    test('is tolerant of missing and invalid values', () {
      final bounds = AccessibilityBounds.fromJson(<String, dynamic>{
        'left': 'nope',
        'right': 50,
      });

      expect(bounds.left, 0);
      expect(bounds.top, 0);
      expect(bounds.right, 50);
      expect(bounds.bottom, 0);
    });

    test('round-trips through toJson', () {
      const bounds = AccessibilityBounds(
        left: 1,
        top: 2,
        right: 3,
        bottom: 4,
      );

      expect(bounds.toJson(), {
        'left': 1,
        'top': 2,
        'right': 3,
        'bottom': 4,
      });
    });
  });

  group('AccessibilityElement.fromJson', () {
    test('an empty map yields empty defaults', () {
      final element = AccessibilityElement.fromJson(<String, dynamic>{});

      expect(element.role, '');
      expect(element.text, '');
      expect(element.contentDescription, '');
      expect(element.packageName, '');
      expect(element.clickable, isFalse);
      expect(element.focusable, isFalse);
      expect(element.editable, isFalse);
      expect(element.scrollable, isFalse);
      expect(element.depth, 0);
      expect(element.bounds, isNull);
    });

    test('ignores unknown keys and parses a bounds string', () {
      final element = AccessibilityElement.fromJson(<String, dynamic>{
        'role': 'Button',
        'text': 'Submit',
        'clickable': true,
        'depth': 2,
        'bounds': '10,20,110,220',
        'unknownKey': 'ignored',
      });

      expect(element.role, 'Button');
      expect(element.text, 'Submit');
      expect(element.clickable, isTrue);
      expect(element.depth, 2);
      expect(
        element.bounds,
        const AccessibilityBounds(left: 10, top: 20, right: 110, bottom: 220),
      );
    });
  });

  group('AccessibilityElement.label', () {
    test('prefers text, then contentDescription, then empty', () {
      const withText = AccessibilityElement(
        role: 'Button',
        text: 'Submit',
        contentDescription: 'Submit button',
        packageName: 'com.x',
      );
      const descriptionOnly = AccessibilityElement(
        role: 'Button',
        text: '',
        contentDescription: 'Submit button',
        packageName: 'com.x',
      );
      const blank = AccessibilityElement(
        role: 'View',
        text: '',
        contentDescription: '',
        packageName: 'com.x',
      );

      expect(withText.label, 'Submit');
      expect(descriptionOnly.label, 'Submit button');
      expect(blank.label, '');
    });
  });

  group('AccessibilityTreeSerializer.parse', () {
    test('returns empty for non-list input', () {
      expect(AccessibilityTreeSerializer.parse(null), isEmpty);
      expect(AccessibilityTreeSerializer.parse('not a list'), isEmpty);
      expect(AccessibilityTreeSerializer.parse(<int>[1, 2]), isEmpty);
    });

    test('skips unparsable entries and keeps the good ones', () {
      final parsed = AccessibilityTreeSerializer.parse(<Object?>[
        <String, dynamic>{'role': 'Button', 'text': 'OK'},
        'garbage',
        42,
        null,
        <String, dynamic>{'role': 'TextView', 'text': 'Body'},
      ]);

      expect(parsed.length, 2);
      expect(parsed.first.role, 'Button');
      expect(parsed.last.text, 'Body');
    });
  });

  group('AccessibilityTreeSerializer.serialize', () {
    test('empty input returns the canonical empty message', () {
      expect(
        AccessibilityTreeSerializer.serialize(const []),
        AccessibilityMessages.emptyTree,
      );
    });

    test('prints header, role, quoted label, true flags, bounds and depth', () {
      final element = AccessibilityElement(
        role: 'Button',
        text: 'OK',
        contentDescription: '',
        packageName: 'com.x',
        clickable: true,
        bounds: const AccessibilityBounds(
          left: 10,
          top: 20,
          right: 110,
          bottom: 220,
        ),
      );

      final output = AccessibilityTreeSerializer.serialize(
        [element],
        packageName: 'com.x',
      );

      expect(
        output,
        'accessibility tree: package=com.x total=1 shown=1\n'
        '- [Button] "OK" clickable bounds=10,20,110,220 depth=0',
      );
    });

    test('omits the quoted label when text and description are empty', () {
      const element = AccessibilityElement(
        role: 'TextView',
        text: '',
        contentDescription: '',
        packageName: 'com.x',
      );

      final output = AccessibilityTreeSerializer.serialize([element]);

      expect(output, contains('- [TextView] depth=0'));
      expect(output, isNot(contains('""')));
      expect(output, contains('package=unknown'));
    });

    test('caps at maxNodes and appends a truncation marker', () {
      final elements = List<AccessibilityElement>.generate(
        100,
        (index) => AccessibilityElement(
          role: 'TextView',
          text: 'item$index',
          contentDescription: '',
          packageName: 'com.x',
        ),
      );

      final output = AccessibilityTreeSerializer.serialize(
        elements,
        maxNodes: 10,
      );
      final lines = output.split('\n');
      final elementLines =
          lines.where((line) => line.startsWith('- ')).toList();

      expect(elementLines.length, 10);
      expect(lines.last, contains('90'));
      expect(lines.last, contains('max_nodes'));
      expect(lines.last, contains('max_depth'));
    });

    test('drops nodes deeper than maxDepth and reports them', () {
      final elements = List<AccessibilityElement>.generate(
        13,
        (index) => AccessibilityElement(
          role: 'TextView',
          text: 'depth$index',
          contentDescription: '',
          packageName: 'com.x',
          depth: index,
        ),
      );

      final output = AccessibilityTreeSerializer.serialize(
        elements,
        maxDepth: 3,
      );
      final lines = output.split('\n');
      final elementLines =
          lines.where((line) => line.startsWith('- ')).toList();

      expect(elementLines.length, 4);
      expect(elementLines.last, endsWith('depth=3'));
      expect(lines.last, contains('9'));
    });

    test('sanitizes newlines, tabs and quotes onto one line', () {
      const element = AccessibilityElement(
        role: 'TextView',
        text: 'Line1\nLine2\tTabbed "quote"',
        contentDescription: '',
        packageName: 'com.x',
      );

      final output = AccessibilityTreeSerializer.serialize([element]);
      final elementLine =
          output.split('\n').firstWhere((line) => line.startsWith('- '));

      expect(elementLine, contains('"Line1 Line2 Tabbed \'quote\'"'));
      expect(elementLine, isNot(contains('"quote"')));
    });

    test('cuts a label longer than 80 characters with a trailing ellipsis', () {
      final longLabel = 'a' * 120;
      final element = AccessibilityElement(
        role: 'TextView',
        text: longLabel,
        contentDescription: '',
        packageName: 'com.x',
      );

      final output = AccessibilityTreeSerializer.serialize([element]);

      expect(output, contains('${'a' * 80}...'));
      expect(output, isNot(contains('a' * 81)));
    });
  });

  group('AccessibilityTreeSerializer.filter', () {
    final elements = <AccessibilityElement>[
      const AccessibilityElement(
        role: 'Button',
        text: 'Submit',
        contentDescription: '',
        packageName: 'com.shop.app',
        clickable: true,
      ),
      const AccessibilityElement(
        role: 'TextView',
        text: '',
        contentDescription: 'Submit order',
        packageName: 'com.shop.app',
      ),
      const AccessibilityElement(
        role: 'TextView',
        text: 'Cancel',
        contentDescription: '',
        packageName: 'com.other.app',
      ),
    ];

    test('matches text case-insensitively against label and description', () {
      expect(
        AccessibilityTreeSerializer.filter(elements, textFilter: 'SUBMIT')
            .length,
        2,
      );

      final descriptionMatch =
          AccessibilityTreeSerializer.filter(elements, textFilter: 'order');
      expect(descriptionMatch.length, 1);
      expect(descriptionMatch.first.label, 'Submit order');
    });

    test('matches package substrings case-insensitively', () {
      expect(
        AccessibilityTreeSerializer.filter(elements, packageFilter: 'SHOP')
            .length,
        2,
      );
    });

    test('drops non-clickable elements when clickableOnly is set', () {
      final result =
          AccessibilityTreeSerializer.filter(elements, clickableOnly: true);

      expect(result.length, 1);
      expect(result.first.clickable, isTrue);
    });

    test('null and blank filters match everything', () {
      expect(AccessibilityTreeSerializer.filter(elements).length, 3);
      expect(
        AccessibilityTreeSerializer.filter(
          elements,
          textFilter: '',
          packageFilter: '   ',
        ).length,
        3,
      );
    });

    test('combines text and clickable filters', () {
      final result = AccessibilityTreeSerializer.filter(
        elements,
        textFilter: 'submit',
        clickableOnly: true,
      );

      expect(result.length, 1);
      expect(result.first.text, 'Submit');
    });
  });

  group('AccessibilityMessages.forStatus', () {
    test('active needs no message', () {
      expect(AccessibilityMessages.forStatus(AccessibilityStatus.active), '');
    });

    test('each non-active state names its fix and service', () {
      final cases = <AccessibilityStatus, String>{
        AccessibilityStatus.notEnabled: '[accessibility_not_enabled]',
        AccessibilityStatus.denied: '[accessibility_denied]',
        AccessibilityStatus.grantedNotConnected:
            '[accessibility_not_connected]',
      };

      for (final entry in cases.entries) {
        final message = AccessibilityMessages.forStatus(entry.key);

        expect(message, contains(entry.value));
        expect(
          message,
          contains('launch_system_setting(setting_type="accessibility")'),
        );
        expect(message, contains('Flames Screen Reader'));
        expect(message, contains('cannot be read'));
      }
    });

    test('the three non-active messages are distinct', () {
      final messages = {
        AccessibilityMessages.forStatus(AccessibilityStatus.notEnabled),
        AccessibilityMessages.forStatus(AccessibilityStatus.denied),
        AccessibilityMessages.forStatus(
          AccessibilityStatus.grantedNotConnected,
        ),
      };

      expect(messages.length, 3);
    });
  });
}
