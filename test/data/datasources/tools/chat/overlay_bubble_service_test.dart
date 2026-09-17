import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockOverlayBubblePlatformWrapper extends Mock
    implements OverlayBubblePlatformWrapper {}

class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockOverlayBubblePlatformWrapper mockPlatform;
  late MockSecureStorageService mockStorage;
  late OverlayBubbleService service;

  setUp(() {
    mockPlatform = MockOverlayBubblePlatformWrapper();
    mockStorage = MockSecureStorageService();
    service = OverlayBubbleService(
      storage: mockStorage,
      platformWrapper: mockPlatform,
    );
    when(() => mockPlatform.isPermissionGranted())
        .thenAnswer((_) async => false);
    when(() => mockPlatform.requestPermission()).thenAnswer((_) async => false);
    when(() => mockPlatform.isBubbleVisible()).thenAnswer((_) async => false);
    when(() => mockPlatform.showBubble()).thenAnswer((_) async => false);
    when(() => mockPlatform.hideBubble()).thenAnswer((_) async => true);
    when(() => mockPlatform.setRecording(any())).thenAnswer((_) async => true);
    when(() => mockPlatform.openApp()).thenAnswer((_) async => false);
    when(() => mockStorage.saveOverlayBubbleEnabled(any()))
        .thenAnswer((_) async {});
    when(() => mockStorage.getOverlayBubbleEnabled())
        .thenAnswer((_) async => false);
  });

  group('checkPermission', () {
    test('granted when the platform reports granted', () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenAnswer((_) async => true);

      // Act
      final state = await service.checkPermission();

      // Assert
      expect(state, OverlayPermissionState.granted);
    });

    test('denied on the first call when the platform reports not granted',
        () async {
      // Act
      final state = await service.checkPermission();

      // Assert
      expect(state, OverlayPermissionState.denied);
    });

    test('permanentlyDenied after requestPermission while still not granted',
        () async {
      // Arrange
      await service.requestPermission();

      // Act
      final state = await service.checkPermission();

      // Assert
      expect(state, OverlayPermissionState.permanentlyDenied);
    });

    test('a throwing platform still yields an enum and never throws',
        () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenThrow(Exception('boom'));

      // Act
      final state = await service.checkPermission();

      // Assert
      expect(state, OverlayPermissionState.denied);
    });
  });

  group('setBubbleEnabled(true)', () {
    test('returns false and never creates the bubble without permission',
        () async {
      // Act
      final enabled = await service.setBubbleEnabled(true);

      // Assert
      expect(enabled, isFalse);
      verifyNever(() => mockPlatform.showBubble());
      verifyNever(() => mockStorage.saveOverlayBubbleEnabled(true));
    });

    test('shows the bubble and persists true when granted', () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenAnswer((_) async => true);
      when(() => mockPlatform.showBubble()).thenAnswer((_) async => true);

      // Act
      final enabled = await service.setBubbleEnabled(true);

      // Assert
      expect(enabled, isTrue);
      verify(() => mockPlatform.showBubble()).called(1);
      verify(() => mockStorage.saveOverlayBubbleEnabled(true)).called(1);
    });

    test('does not persist true when showBubble fails', () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenAnswer((_) async => true);

      // Act
      final enabled = await service.setBubbleEnabled(true);

      // Assert
      expect(enabled, isFalse);
      verify(() => mockPlatform.showBubble()).called(1);
      verifyNever(() => mockStorage.saveOverlayBubbleEnabled(true));
    });
  });

  group('setBubbleEnabled(false)', () {
    test('hides the bubble and persists false', () async {
      // Act
      final hidden = await service.setBubbleEnabled(false);

      // Assert
      expect(hidden, isTrue);
      verify(() => mockPlatform.hideBubble()).called(1);
      verify(() => mockStorage.saveOverlayBubbleEnabled(false)).called(1);
    });
  });

  group('setRecording', () {
    test('forwards true to the platform', () async {
      // Act
      final result = await service.setRecording(true);

      // Assert
      expect(result, isTrue);
      final captured =
          verify(() => mockPlatform.setRecording(captureAny())).captured;
      expect(captured.single, isTrue);
    });

    test('forwards false to the platform', () async {
      // Act
      await service.setRecording(false);

      // Assert
      final captured =
          verify(() => mockPlatform.setRecording(captureAny())).captured;
      expect(captured.single, isFalse);
    });
  });

  group('openApp', () {
    test('returns true and forwards to the platform once', () async {
      // Arrange
      when(() => mockPlatform.openApp()).thenAnswer((_) async => true);

      // Act
      final result = await service.openApp();

      // Assert
      expect(result, isTrue);
      verify(() => mockPlatform.openApp()).called(1);
    });

    test('returns false and does not rethrow when the platform throws',
        () async {
      // Arrange
      when(() => mockPlatform.openApp()).thenThrow(Exception('boom'));

      // Act
      final result = await service.openApp();

      // Assert
      expect(result, isFalse);
    });
  });

  group('platform failures degrade instead of throwing', () {
    test('setBubbleEnabled(true) returns false when the grant check throws',
        () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenThrow(Exception('boom'));

      // Act
      final enabled = await service.setBubbleEnabled(true);

      // Assert
      expect(enabled, isFalse);
      verifyNever(() => mockPlatform.showBubble());
    });

    test('setBubbleEnabled(false) returns false when hideBubble throws',
        () async {
      // Arrange
      when(() => mockPlatform.hideBubble()).thenThrow(Exception('boom'));

      // Act
      final hidden = await service.setBubbleEnabled(false);

      // Assert
      expect(hidden, isFalse);
      verify(() => mockStorage.saveOverlayBubbleEnabled(false)).called(1);
    });

    test('isBubbleVisible returns false when the platform throws', () async {
      // Arrange
      when(() => mockPlatform.isBubbleVisible()).thenThrow(Exception('boom'));

      // Act
      final visible = await service.isBubbleVisible();

      // Assert
      expect(visible, isFalse);
    });
  });

  group('persisted preference', () {
    test('isBubbleEnabled reads through secure storage', () async {
      // Arrange
      when(() => mockStorage.getOverlayBubbleEnabled())
          .thenAnswer((_) async => true);

      // Act
      final enabled = await service.isBubbleEnabled();

      // Assert
      expect(enabled, isTrue);
      verify(() => mockStorage.getOverlayBubbleEnabled()).called(1);
    });

    test('isBubbleEnabled returns false when storage throws', () async {
      // Arrange
      when(() => mockStorage.getOverlayBubbleEnabled())
          .thenThrow(Exception('boom'));

      // Act
      final enabled = await service.isBubbleEnabled();

      // Assert
      expect(enabled, isFalse);
    });

    test('persistBubbleEnabled writes through secure storage', () async {
      // Act
      await service.persistBubbleEnabled(true);

      // Assert
      verify(() => mockStorage.saveOverlayBubbleEnabled(true)).called(1);
    });
  });

  group('DefaultOverlayBubblePlatformWrapper wire format', () {
    const channel = MethodChannel('ai.hermes.flames/overlay_bubble');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late DefaultOverlayBubblePlatformWrapper wrapper;
    late List<MethodCall> captured;

    setUp(() {
      wrapper = DefaultOverlayBubblePlatformWrapper();
      captured = <MethodCall>[];
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('boolean methods return the reply and false for null/throw',
        () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async => true);

      // Act + Assert
      expect(await wrapper.isPermissionGranted(), isTrue);
      expect(await wrapper.requestPermission(), isTrue);
      expect(await wrapper.isBubbleVisible(), isTrue);
      expect(await wrapper.showBubble(), isTrue);
      expect(await wrapper.hideBubble(), isTrue);
      expect(await wrapper.openApp(), isTrue);

      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await wrapper.isPermissionGranted(), isFalse);
      expect(await wrapper.requestPermission(), isFalse);
      expect(await wrapper.isBubbleVisible(), isFalse);
      expect(await wrapper.showBubble(), isFalse);
      expect(await wrapper.hideBubble(), isFalse);
      expect(await wrapper.openApp(), isFalse);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'kaboom');
      });
      expect(await wrapper.isPermissionGranted(), isFalse);
      expect(await wrapper.requestPermission(), isFalse);
      expect(await wrapper.isBubbleVisible(), isFalse);
      expect(await wrapper.showBubble(), isFalse);
      expect(await wrapper.hideBubble(), isFalse);
      expect(await wrapper.openApp(), isFalse);
    });

    test('openApp invokes the openApp channel method', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return true;
      });

      // Act
      final result = await wrapper.openApp();

      // Assert
      expect(result, isTrue);
      expect(captured.single.method, 'openApp');
    });

    test('setRecording sends the recording flag and returns the reply',
        () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return true;
      });

      // Act
      final result = await wrapper.setRecording(true);

      // Assert
      expect(result, isTrue);
      expect(captured.single.method, 'setRecording');
      final args = captured.single.arguments as Map;
      expect(args['recording'], isTrue);
    });

    test('setRecording degrades to false on a null reply or a throw', () async {
      // Arrange
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      // Act + Assert
      expect(await wrapper.setRecording(false), isFalse);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'kaboom');
      });
      expect(await wrapper.setRecording(false), isFalse);
    });
  });
}
