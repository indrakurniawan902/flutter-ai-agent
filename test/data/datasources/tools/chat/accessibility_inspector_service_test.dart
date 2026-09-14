import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai.hermes.flames/accessibility_inspector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MockAccessibilityInspectorPlatformWrapper mockPlatform;
  late AccessibilityInspectorService service;

  Map<String, dynamic> node({
    String role = 'Button',
    String text = 'Send',
    String contentDescription = '',
    String packageName = 'com.whatsapp',
    bool clickable = true,
    int depth = 1,
  }) {
    return {
      'role': role,
      'text': text,
      'contentDescription': contentDescription,
      'packageName': packageName,
      'clickable': clickable,
      'focusable': false,
      'editable': false,
      'scrollable': false,
      'depth': depth,
      'bounds': '0,0,100,50',
    };
  }

  Map<String, dynamic> tree({List<Map<String, dynamic>>? nodes}) {
    return {
      'packageName': 'com.whatsapp',
      'nodes': nodes ?? [node()],
      'truncated': false,
    };
  }

  setUpAll(() {
    registerFallbackValue(0);
  });

  setUp(() {
    mockPlatform = MockAccessibilityInspectorPlatformWrapper();
    service = AccessibilityInspectorService(platformWrapper: mockPlatform);
    when(() => mockPlatform.isServiceConnected()).thenAnswer((_) async => false);
    when(() => mockPlatform.isPermissionGranted())
        .thenAnswer((_) async => false);
    when(() => mockPlatform.requestPermission()).thenAnswer((_) async => false);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('checkStatus', () {
    test('connected maps to active', () async {
      // Arrange
      when(() => mockPlatform.isServiceConnected())
          .thenAnswer((_) async => true);

      // Act
      final status = await service.checkStatus();

      // Assert
      expect(status, AccessibilityStatus.active);
    });

    test('not connected but granted maps to grantedNotConnected', () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenAnswer((_) async => true);

      // Act
      final status = await service.checkStatus();

      // Assert
      expect(status, AccessibilityStatus.grantedNotConnected);
    });

    test('never requested and not granted maps to notEnabled', () async {
      // Act
      final status = await service.checkStatus();

      // Assert
      expect(status, AccessibilityStatus.notEnabled);
    });

    test('after requestPermission while still not granted maps to denied',
        () async {
      // Arrange
      await service.requestPermission();

      // Act
      final status = await service.checkStatus();

      // Assert
      expect(status, AccessibilityStatus.denied);
    });

    test('a throwing platform is treated as not granted and never throws',
        () async {
      // Arrange
      when(() => mockPlatform.isServiceConnected())
          .thenThrow(Exception('boom'));

      // Act
      final status = await service.checkStatus();

      // Assert
      expect(status, AccessibilityStatus.notEnabled);
    });
  });

  group('requestPermission', () {
    test('returns the platform result and flips status to denied', () async {
      // Arrange
      when(() => mockPlatform.requestPermission()).thenAnswer((_) async => true);

      // Act
      final granted = await service.requestPermission();

      // Assert
      expect(granted, isTrue);
      expect(await service.checkStatus(), AccessibilityStatus.denied);
    });

    test('a throwing platform returns false and does not throw', () async {
      // Arrange
      when(() => mockPlatform.requestPermission())
          .thenThrow(Exception('boom'));

      // Act
      final granted = await service.requestPermission();

      // Assert
      expect(granted, isFalse);
      expect(await service.checkStatus(), AccessibilityStatus.denied);
    });
  });

  group('findElementsFormatted never reads the tree while inactive', () {
    Future<void> expectInactive(AccessibilityStatus status) async {
      // Arrange
      final result = await service.findElementsFormatted();

      // Act
      final message = result.fold((failure) => failure.message, (_) => '');

      // Assert
      expect(result, Left(ServerFailure(AccessibilityMessages.forStatus(status))));
      expect(message, AccessibilityMessages.forStatus(status));
      verifyNever(
        () => mockPlatform.getScreenTree(
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        ),
      );
    }

    test('notEnabled returns the not-enabled message without tree access',
        () async {
      await expectInactive(AccessibilityStatus.notEnabled);
    });

    test('denied returns the denied message without tree access', () async {
      // Arrange
      await service.requestPermission();

      // Act + Assert
      await expectInactive(AccessibilityStatus.denied);
    });

    test('grantedNotConnected returns the not-connected message without tree access',
        () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenAnswer((_) async => true);

      // Act + Assert
      await expectInactive(AccessibilityStatus.grantedNotConnected);
    });
  });

  group('findElementsFormatted active path', () {
    setUp(() {
      when(() => mockPlatform.isServiceConnected())
          .thenAnswer((_) async => true);
    });

    test('serializes the tree with package name, role and label', () async {
      // Arrange
      when(
        () => mockPlatform.getScreenTree(
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        ),
      ).thenAnswer((_) async => tree());

      // Act
      final result = await service.findElementsFormatted();

      // Assert
      final text = result.getOrElse(() => '');
      expect(result.isRight(), isTrue);
      expect(text, contains('com.whatsapp'));
      expect(text, contains('[Button]'));
      expect(text, contains('Send'));
    });

    test('forwards textFilter and clickableOnly', () async {
      // Arrange
      when(
        () => mockPlatform.getScreenTree(
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        ),
      ).thenAnswer(
        (_) async => tree(
          nodes: [
            node(text: 'Send message', clickable: true),
            node(role: 'Text', text: 'Send draft', clickable: false),
            node(role: 'Text', text: 'Cancel', clickable: false),
          ],
        ),
      );

      // Act
      final result = await service.findElementsFormatted(
        textFilter: 'send',
        clickableOnly: true,
      );

      // Assert
      final text = result.getOrElse(() => '');
      expect(text, contains('Send message'));
      expect(text, isNot(contains('Send draft')));
      expect(text, isNot(contains('Cancel')));
    });

    test('clamps maxNodes to 200 and maxDepth to 1', () async {
      // Arrange
      when(
        () => mockPlatform.getScreenTree(
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        ),
      ).thenAnswer((_) async => tree());

      // Act
      await service.findElementsFormatted(maxNodes: 9999, maxDepth: 0);

      // Assert
      final captured = verify(
        () => mockPlatform.getScreenTree(
          maxNodes: captureAny(named: 'maxNodes'),
          maxDepth: captureAny(named: 'maxDepth'),
        ),
      ).captured;
      expect(captured[0], 200);
      expect(captured[1], 1);
    });

    test('a null tree returns the grantedNotConnected message', () async {
      // Arrange
      when(
        () => mockPlatform.getScreenTree(
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        ),
      ).thenAnswer((_) async => null);

      // Act
      final result = await service.findElementsFormatted();

      // Assert
      expect(
        result,
        Left(
          ServerFailure(
            AccessibilityMessages.forStatus(
              AccessibilityStatus.grantedNotConnected,
            ),
          ),
        ),
      );
    });

    test('a throwing tree read becomes an accessibility_read_failed Left',
        () async {
      // Arrange
      when(
        () => mockPlatform.getScreenTree(
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        ),
      ).thenThrow(Exception('boom'));

      // Act
      final result = await service.findElementsFormatted();

      // Assert
      final message = result.fold((failure) => failure.message, (_) => '');
      expect(result.isLeft(), isTrue);
      expect(message, startsWith('[accessibility_read_failed]'));
    });
  });

  group('DefaultAccessibilityInspectorPlatformWrapper wire format', () {
    late DefaultAccessibilityInspectorPlatformWrapper wrapper;
    late List<MethodCall> captured;

    setUp(() {
      wrapper = DefaultAccessibilityInspectorPlatformWrapper();
      captured = <MethodCall>[];
    });

    test('getScreenTree sends maxNodes/maxDepth and returns a Map', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return {'packageName': 'com.whatsapp', 'nodes': [], 'truncated': false};
      });

      // Act
      final result = await wrapper.getScreenTree(maxNodes: 5, maxDepth: 3);

      // Assert
      expect(result, isA<Map<String, dynamic>>());
      expect(captured.single.method, 'getScreenTree');
      final args = captured.single.arguments as Map;
      expect(args['maxNodes'], 5);
      expect(args['maxDepth'], 3);
    });

    test('getScreenTree returns null on a null reply', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      // Act
      final result = await wrapper.getScreenTree(maxNodes: 5, maxDepth: 3);

      // Assert
      expect(result, isNull);
    });

    test('getScreenTree returns null on a non-Map reply', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async => 'nope');

      // Act
      final result = await wrapper.getScreenTree(maxNodes: 5, maxDepth: 3);

      // Assert
      expect(result, isNull);
    });

    test('getScreenTree returns null when the handler throws', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'kaboom');
      });

      // Act
      final result = await wrapper.getScreenTree(maxNodes: 5, maxDepth: 3);

      // Assert
      expect(result, isNull);
    });

    test('boolean methods return the reply and false for null/throw', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async => true);

      // Act + Assert
      expect(await wrapper.isPermissionGranted(), isTrue);
      expect(await wrapper.isServiceConnected(), isTrue);
      expect(await wrapper.requestPermission(), isTrue);

      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await wrapper.isPermissionGranted(), isFalse);
      expect(await wrapper.isServiceConnected(), isFalse);
      expect(await wrapper.requestPermission(), isFalse);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'kaboom');
      });
      expect(await wrapper.isPermissionGranted(), isFalse);
      expect(await wrapper.isServiceConnected(), isFalse);
      expect(await wrapper.requestPermission(), isFalse);
    });
  });
}
