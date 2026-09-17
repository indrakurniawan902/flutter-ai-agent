import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/data/services/geofence/geofence_action_dispatcher.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/services/geofence/geofence_action_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

class MockGeofenceActionDispatcher extends Mock
    implements GeofenceActionDispatcherBase {}

class MockContactLauncherTools extends Mock implements ContactLauncherTools {}

class _FakeDispatcher implements VoicePromptDispatcherBase {
  _FakeDispatcher(this.transportId, {bool ready = true}) : _ready = ready;

  @override
  final String transportId;

  bool _ready;
  final List<String> dispatched = [];

  set ready(bool value) => _ready = value;

  @override
  bool get isReady => _ready;

  @override
  bool get speaksReply => false;

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async {
    dispatched.add(prompt);
    return Right(prompt);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  late MockNotificationService mockNotification;
  late MockContactLauncherTools mockContactLauncher;
  late VoicePromptDispatcherRegistry registry;
  late GeofenceActionDispatcher dispatcher;

  final fixedTime = DateTime(2026, 9, 12, 10, 0, 0);

  AmbientEvent eventOf(AmbientEventType type) => AmbientEvent(
        id: 'e1',
        type: type,
        title: 'Entered home',
        body: 'Entered geofence home.',
        timestamp: fixedTime,
        regionId: 'home',
      );

  GeofenceRegion regionOf({
    GeofenceAction action = GeofenceAction.none,
    String payload = '',
    GeofenceActionTrigger on = GeofenceActionTrigger.both,
  }) =>
      GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
        action: action,
        actionPayload: payload,
        actionOn: on,
      );

  setUpAll(() {
    registerFallbackValue(
      AmbientEvent(
        id: 'fallback',
        type: AmbientEventType.geofenceEnter,
        title: 'fallback',
        body: 'fallback',
        timestamp: fixedTime,
      ),
    );
    registerFallbackValue(
      const GeofenceRegion(
        id: 'fallback',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 100.0,
      ),
    );
  });

  setUp(() {
    mockNotification = MockNotificationService();
    mockContactLauncher = MockContactLauncherTools();
    registry = VoicePromptDispatcherRegistry();
    dispatcher = GeofenceActionDispatcher(
      notificationService: mockNotification,
      promptRegistry: registry,
      contactLauncherTools: mockContactLauncher,
    );
    when(
      () => mockNotification.sendLocalNotification(
        title: any(named: 'title'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => const Right(null));
    when(() => mockContactLauncher.openExternalUrl(any()))
        .thenAnswer((_) async => const Right('Opened'));
  });

  group('GeofenceActionDispatcher', () {
    test('none action does nothing and reports none', () async {
      // Arrange
      final region = regionOf();

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      verifyNever(
        () => mockNotification.sendLocalNotification(
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      );
      verifyNever(() => mockContactLauncher.openExternalUrl(any()));
      expect(result.action, GeofenceAction.none);
      expect(result.executed, isFalse);
      expect(result.detail, 'none');
      expect(result.payload, isEmpty);
      expect(result.transportId, isNull);
    });

    test('notify sends the event title and body as a local notification',
        () async {
      // Arrange
      final region = regionOf(action: GeofenceAction.notify);
      final event = eventOf(AmbientEventType.geofenceEnter);

      // Act
      final result = await dispatcher.dispatch(region, event);

      // Assert
      verify(
        () => mockNotification.sendLocalNotification(
          title: 'Entered home',
          body: 'Entered geofence home.',
        ),
      ).called(1);
      verifyNever(() => mockContactLauncher.openExternalUrl(any()));
      expect(result.action, GeofenceAction.notify);
      expect(result.executed, isTrue);
      expect(result.detail, 'notification');
      expect(result.payload, isEmpty);
    });

    test('notify without a notification service reports unavailable', () async {
      // Arrange
      final bare = GeofenceActionDispatcher(
        promptRegistry: registry,
        contactLauncherTools: mockContactLauncher,
      );
      final region = regionOf(action: GeofenceAction.notify);

      // Act
      final result =
          await bare.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      expect(result.executed, isFalse);
      expect(result.detail, 'unavailable');
    });

    test('runPrompt dispatches the payload through the active transport',
        () async {
      // Arrange
      final fake = _FakeDispatcher('chat');
      registry.register(fake);
      final region = regionOf(
        action: GeofenceAction.runPrompt,
        payload: 'Turn on the lights',
      );

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      expect(fake.dispatched, ['Turn on the lights']);
      verifyNever(
        () => mockNotification.sendLocalNotification(
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      );
      expect(result.action, GeofenceAction.runPrompt);
      expect(result.executed, isTrue);
      expect(result.payload, 'Turn on the lights');
      expect(result.transportId, 'chat');
      expect(result.detail, 'prompt_dispatched');
    });

    test('runPrompt with an empty payload dispatches nothing', () async {
      // Arrange
      final fake = _FakeDispatcher('chat');
      registry.register(fake);
      final region = regionOf(
        action: GeofenceAction.runPrompt,
        payload: '   ',
      );

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      expect(fake.dispatched, isEmpty);
      expect(result.executed, isFalse);
      expect(result.detail, 'empty_payload');
      expect(result.payload, isEmpty);
    });

    test('runPrompt without a ready transport is a silent no-op', () async {
      // Arrange
      final notReady = _FakeDispatcher('chat', ready: false);
      registry.register(notReady);
      final region = regionOf(
        action: GeofenceAction.runPrompt,
        payload: 'Turn on the lights',
      );

      // Act + Assert: must not throw
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      expect(notReady.dispatched, isEmpty);
      expect(result.executed, isFalse);
      expect(result.detail, 'no_ready_transport');
      expect(result.transportId, isNull);
    });

    test('openUrl launches the payload URL', () async {
      // Arrange
      final region = regionOf(
        action: GeofenceAction.openUrl,
        payload: 'https://example.com',
      );

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      verify(() => mockContactLauncher.openExternalUrl('https://example.com'))
          .called(1);
      expect(result.action, GeofenceAction.openUrl);
      expect(result.executed, isTrue);
      expect(result.payload, 'https://example.com');
      expect(result.detail, 'url_opened');
    });

    test('openUrl with an empty payload does not launch', () async {
      // Arrange
      final region = regionOf(action: GeofenceAction.openUrl, payload: '');

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      verifyNever(() => mockContactLauncher.openExternalUrl(any()));
      expect(result.executed, isFalse);
      expect(result.detail, 'empty_payload');
    });

    test('openUrl failure reports the failure message as detail', () async {
      // Arrange
      when(() => mockContactLauncher.openExternalUrl(any())).thenAnswer(
        (_) async => const Left(ServerFailure('Cannot launch URL: nope')),
      );
      final region = regionOf(
        action: GeofenceAction.openUrl,
        payload: 'https://example.com',
      );

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      expect(result.executed, isFalse);
      expect(result.detail, 'Cannot launch URL: nope');
    });

    test('a throwing collaborator never escapes dispatch', () async {
      // Arrange
      when(
        () => mockNotification.sendLocalNotification(
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('notification plugin down'));
      final region = regionOf(action: GeofenceAction.notify);

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceEnter));

      // Assert
      expect(result.executed, isFalse);
      expect(result.detail, 'error');
    });

    test('trigger mismatch is ignored and reported', () async {
      // Arrange: enter-only region, exit event
      final fake = _FakeDispatcher('chat');
      registry.register(fake);
      final region = regionOf(
        action: GeofenceAction.runPrompt,
        payload: 'Welcome home',
        on: GeofenceActionTrigger.enter,
      );

      // Act
      final result =
          await dispatcher.dispatch(region, eventOf(AmbientEventType.geofenceExit));

      // Assert
      expect(fake.dispatched, isEmpty);
      verifyNever(
        () => mockNotification.sendLocalNotification(
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      );
      expect(result.executed, isFalse);
      expect(result.detail, 'trigger_mismatch');
    });
  });

  group('AmbientTriggerService bound action', () {
    late MockGeofenceActionDispatcher mockDispatcher;
    late AmbientTriggerService service;

    const boundRegion = GeofenceRegion(
      id: 'home',
      latitude: 1.0,
      longitude: 2.0,
      radiusMeters: 200.0,
      action: GeofenceAction.notify,
      actionPayload: 'Hello',
    );

    setUp(() {
      mockDispatcher = MockGeofenceActionDispatcher();
      when(() => mockDispatcher.dispatch(any(), any())).thenAnswer(
        (invocation) async => GeofenceDispatchResult(
          action: GeofenceAction.notify,
          executed: true,
          detail: 'notification',
        ),
      );
      service = AmbientTriggerService(
        battery: MockBatteryPlatformWrapper(),
        workmanager: MockWorkmanagerPlatformWrapper(),
        actionDispatcher: mockDispatcher,
        cooldown: const Duration(hours: 1),
      );
    });

    test('fires the bound action once and honours the crossing cooldown',
        () async {
      // Arrange
      service.addGeofence(boundRegion);

      // Act: first crossing into the region
      final first = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      // Assert: exactly one enter dispatch
      final firstEvents =
          first.getOrElse(() => AmbientCheckResult.empty()).events;
      expect(firstEvents, hasLength(1));

      // Act: still inside -> no crossing, nothing fires
      await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime.add(const Duration(minutes: 1)),
      );

      // Act: leave (exit fires), then re-enter inside the cooldown window
      final exitResult = await service.checkGeofence(
        latitude: 50.0,
        longitude: 50.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );
      final reenter = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime.add(const Duration(minutes: 10)),
      );

      // Assert: cooldown suppresses the second enter crossing
      expect(
        reenter.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isFalse,
      );
      // Exactly two dispatches: the first enter and the exit. A spurious
      // dispatch while still inside, or a cooldown-bypassing re-enter,
      // would make this three.
      final dispatchedEvents = verify(
        () => mockDispatcher.dispatch(captureAny(), captureAny()),
      ).captured.whereType<AmbientEvent>().toList();
      expect(
        dispatchedEvents.map((e) => e.type),
        [AmbientEventType.geofenceEnter, AmbientEventType.geofenceExit],
      );
      // The check results carry exactly the two executed crossings: one on
      // enter, one on exit.
      final enterActions = first
          .getOrElse(() => AmbientCheckResult.empty())
          .dispatchedActions;
      expect(enterActions, hasLength(1));
      expect(enterActions.first.action, GeofenceAction.notify);
      expect(enterActions.first.executed, isTrue);

      final exitActions = exitResult
          .getOrElse(() => AmbientCheckResult.empty())
          .dispatchedActions;
      expect(exitActions, hasLength(1));
      expect(exitActions.first.action, GeofenceAction.notify);
      expect(exitActions.first.executed, isTrue);
    });
  });
}
