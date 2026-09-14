import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  late MockSecureStorageService mockStorageService;

  final profile1 = ServerProfile(
    id: 'profile-1',
    name: 'VPS Oracle',
    gatewayUrl: 'https://example.com/v1',
    token: 'sk-token-1',
    isActive: true,
    lastConnected: DateTime.utc(2026, 9, 11, 10, 0),
  );

  final profile2 = ServerProfile(
    id: 'profile-2',
    name: 'Dev Server',
    gatewayUrl: 'http://localhost:8080',
    token: 'sk-token-2',
    isActive: false,
  );

  setUpAll(() {
    registerFallbackValue(
      const ServerProfile(
        id: 'fallback-id',
        name: 'Fallback',
        gatewayUrl: 'https://fallback.com',
        token: 'fallback-token',
      ),
    );
  });

  setUp(() {
    mockStorageService = MockSecureStorageService();
  });

  group('ServerProfileCubit - loadProfiles', () {
    test('initial state is ServerProfileInitial', () {
      final cubit = ServerProfileCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      );

      expect(cubit.state, equals(const ServerProfileInitial()));
      cubit.close();
    });

    test('constructor triggers loadProfiles when autoLoad is true (default)', () async {
      when(() => mockStorageService.getServerProfiles())
          .thenAnswer((_) async => [profile1, profile2]);

      final cubit = ServerProfileCubit(
        secureStorageService: mockStorageService,
        autoLoad: true,
      );

      await pumpEventQueue();

      expect(
        cubit.state,
        ServerProfileLoaded(
          profiles: [profile1, profile2],
          activeProfile: profile1,
        ),
      );
      cubit.close();
    });

    blocTest<ServerProfileCubit, ServerProfileState>(
      'loadProfiles emits [ServerProfileLoading, ServerProfileLoaded] with empty list when no profiles',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => []);
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.loadProfiles(),
      expect: () => [
        const ServerProfileLoading(),
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'loadProfiles emits [ServerProfileLoading, ServerProfileError] when storage throws',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenThrow(Exception('Storage disk read error'));
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.loadProfiles(),
      expect: () => [
        const ServerProfileLoading(),
        const ServerProfileError(message: 'Failed to load server profiles'),
      ],
    );
  });

  group('ServerProfileCubit - addProfile & addFromPairingPayload', () {
    blocTest<ServerProfileCubit, ServerProfileState>(
      'addProfile emits ServerProfileError when name is empty',
      build: () => ServerProfileCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.addProfile(
        name: '   ',
        gatewayUrl: 'https://gateway.example.com',
        token: 'token-123',
      ),
      expect: () => [
        const ServerProfileError(message: 'Profile name cannot be empty'),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'addProfile emits ServerProfileError when gatewayUrl is invalid',
      build: () => ServerProfileCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.addProfile(
        name: 'My Server',
        gatewayUrl: 'invalid-url',
        token: 'token-123',
      ),
      expect: () => [
        const ServerProfileError(message: 'Please enter a valid HTTP/HTTPS URL'),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'addProfile emits ServerProfileError when token is empty',
      build: () => ServerProfileCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.addProfile(
        name: 'My Server',
        gatewayUrl: 'https://gateway.example.com',
        token: '',
      ),
      expect: () => [
        const ServerProfileError(message: 'Authentication token cannot be empty'),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'addProfile saves profile and makes it active if first profile',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => []);
        when(() => mockStorageService.saveServerProfile(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveBaseUrl(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveApiKey(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveModel(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveTemperature(any()))
            .thenAnswer((_) async {});
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) async {
        await cubit.addProfile(
          name: 'VPS Oracle',
          gatewayUrl: 'https://example.com/v1',
          token: 'sk-token-1',
        );
      },
      verify: (_) {
        verify(() => mockStorageService.saveServerProfile(any(
              that: isA<ServerProfile>().having((p) => p.isActive, 'isActive', isTrue),
            ))).called(1);
        verify(() => mockStorageService.saveBaseUrl('https://example.com/v1')).called(1);
        verify(() => mockStorageService.saveApiKey('sk-token-1')).called(1);
      },
      expect: () => [
        const ServerProfileLoading(),
        isA<ServerProfileOperationSuccess>().having(
          (s) => s.message,
          'message',
          contains('added successfully'),
        ),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'addFromPairingPayload extracts data and adds profile',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => [profile1]);
        when(() => mockStorageService.saveServerProfile(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveBaseUrl(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveApiKey(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveModel(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveTemperature(any()))
            .thenAnswer((_) async {});
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) async {
        final payload = PairingPayload(
          gatewayUrl: 'https://mbp.local:8080',
          token: 'token-mbp',
          profileName: 'MacBook Pro',
          timestamp: DateTime.now().toUtc(),
        );
        await cubit.addFromPairingPayload(payload, makeActive: true);
      },
      verify: (_) {
        verify(() => mockStorageService.saveServerProfile(any(
              that: isA<ServerProfile>()
                  .having((p) => p.name, 'name', 'MacBook Pro')
                  .having((p) => p.gatewayUrl, 'gatewayUrl', 'https://mbp.local:8080')
                  .having((p) => p.isActive, 'isActive', isTrue),
            ))).called(1);
        verify(() => mockStorageService.saveBaseUrl('https://mbp.local:8080')).called(1);
        verify(() => mockStorageService.saveApiKey('token-mbp')).called(1);
      },
      expect: () => [
        const ServerProfileLoading(),
        isA<ServerProfileOperationSuccess>(),
      ],
    );
    blocTest<ServerProfileCubit, ServerProfileState>(
      'addProfile stores custom model and temperature',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => []);
        when(() => mockStorageService.saveServerProfile(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveBaseUrl(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveApiKey(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveModel(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveTemperature(any()))
            .thenAnswer((_) async {});
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.addProfile(
        name: 'Custom Server',
        gatewayUrl: 'https://gateway.example.com',
        token: 'token-123',
        model: 'gpt-4o-mini',
        temperature: 0.3,
      ),
      verify: (_) {
        verify(() => mockStorageService.saveServerProfile(any(
              that: isA<ServerProfile>()
                  .having((p) => p.model, 'model', 'gpt-4o-mini')
                  .having((p) => p.temperature, 'temperature', 0.3),
            ))).called(1);
        verify(() => mockStorageService.saveModel('gpt-4o-mini')).called(1);
        verify(() => mockStorageService.saveTemperature(0.3)).called(1);
      },
      expect: () => [
        const ServerProfileLoading(),
        isA<ServerProfileOperationSuccess>(),
      ],
    );
  });

  group('ServerProfileCubit - updateActiveProfile', () {
    blocTest<ServerProfileCubit, ServerProfileState>(
      'updateActiveProfile updates active profile fields and settings',
      build: () {
        when(() => mockStorageService.getActiveServerProfile())
            .thenAnswer((_) async => profile1);
        when(() => mockStorageService.saveServerProfile(any()))
            .thenAnswer((_) async {});
        when(() => mockStorageService.saveSettings(
              baseUrl: any(named: 'baseUrl'),
              apiKey: any(named: 'apiKey'),
              model: any(named: 'model'),
              temperature: any(named: 'temperature'),
            )).thenAnswer((_) async {});
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => [
                  profile1.copyWith(model: 'm-new', temperature: 1.2),
                  profile2,
                ]);
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.updateActiveProfile(model: 'm-new', temperature: 1.2),
      verify: (_) {
        verify(() => mockStorageService.saveServerProfile(any(
              that: isA<ServerProfile>()
                  .having((p) => p.model, 'model', 'm-new')
                  .having((p) => p.temperature, 'temperature', 1.2),
            ))).called(1);
        verify(() => mockStorageService.saveSettings(
              baseUrl: 'https://example.com/v1',
              apiKey: 'sk-token-1',
              model: 'm-new',
              temperature: 1.2,
            )).called(1);
      },
      expect: () => [
        isA<ServerProfileOperationSuccess>()
            .having((s) => s.activeProfile?.model, 'activeProfile.model', 'm-new'),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'updateActiveProfile emits ServerProfileError when there is no active profile',
      build: () {
        when(() => mockStorageService.getActiveServerProfile())
            .thenAnswer((_) async => null);
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.updateActiveProfile(model: 'm-new'),
      expect: () => [
        const ServerProfileError(message: 'No active server profile to update'),
      ],
    );
  });

  group('ServerProfileCubit - switchActiveProfile', () {
    blocTest<ServerProfileCubit, ServerProfileState>(
      'switchActiveProfile sets active in storage and reloads profiles',
      build: () {
        when(() => mockStorageService.setActiveServerProfile('profile-2', syncSettings: true))
            .thenAnswer((_) async {});
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => [
                  profile1.copyWith(isActive: false),
                  profile2.copyWith(isActive: true),
                ]);
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.switchActiveProfile('profile-2'),
      verify: (_) {
        verify(() => mockStorageService.setActiveServerProfile('profile-2', syncSettings: true)).called(1);
      },
      expect: () => [
        const ServerProfileLoading(),
        isA<ServerProfileOperationSuccess>().having(
          (s) => s.activeProfile?.id,
          'activeProfile.id',
          'profile-2',
        ),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'switchActiveProfile emits ServerProfileError when setActiveServerProfile throws',
      build: () {
        when(() => mockStorageService.setActiveServerProfile(any(), syncSettings: any(named: 'syncSettings')))
            .thenThrow(Exception('Profile not found'));
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.switchActiveProfile('non-existent'),
      expect: () => [
        const ServerProfileLoading(),
        const ServerProfileError(message: 'Failed to switch server profile'),
      ],
    );
  });

  group('ServerProfileCubit - deleteProfile', () {
    blocTest<ServerProfileCubit, ServerProfileState>(
      'deleteProfile deletes from storage, auto-switches active if needed, and emits success',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => [profile1, profile2]);
        when(() => mockStorageService.deleteServerProfile('profile-1'))
            .thenAnswer((_) async {});
        when(() => mockStorageService.setActiveServerProfile('profile-2', syncSettings: true))
            .thenAnswer((_) async {});
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      seed: () => ServerProfileLoaded(
        profiles: [profile1, profile2],
        activeProfile: profile1,
      ),
      act: (cubit) async {
        // Return remaining profile when re-fetching
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => [profile2.copyWith(isActive: true)]);
        await cubit.deleteProfile('profile-1');
      },
      verify: (_) {
        verify(() => mockStorageService.deleteServerProfile('profile-1')).called(1);
        verify(() => mockStorageService.setActiveServerProfile('profile-2', syncSettings: true)).called(1);
      },
      expect: () => [
        isA<ServerProfileLoading>(),
        isA<ServerProfileOperationSuccess>().having(
          (s) => s.profiles.length,
          'profiles.length',
          1,
        ),
      ],
    );

    blocTest<ServerProfileCubit, ServerProfileState>(
      'deleteProfile emits ServerProfileError when storage throws',
      build: () {
        when(() => mockStorageService.deleteServerProfile(any()))
            .thenThrow(Exception('Disk write failed'));
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) => cubit.deleteProfile('profile-1'),
      expect: () => [
        const ServerProfileLoading(),
        const ServerProfileError(message: 'Failed to delete server profile'),
      ],
    );
  });

  group('ServerProfileCubit - updateLastConnected', () {
    blocTest<ServerProfileCubit, ServerProfileState>(
      'updateLastConnected updates profile timestamp and saves to storage',
      build: () {
        when(() => mockStorageService.getServerProfiles())
            .thenAnswer((_) async => [profile1]);
        when(() => mockStorageService.saveServerProfile(any()))
            .thenAnswer((_) async {});
        return ServerProfileCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
      },
      act: (cubit) async {
        final now = DateTime.utc(2026, 9, 11, 12, 0);
        await cubit.updateLastConnected('profile-1', now);
      },
      verify: (_) {
        verify(() => mockStorageService.saveServerProfile(any(
              that: isA<ServerProfile>().having(
                (p) => p.lastConnected,
                'lastConnected',
                DateTime.utc(2026, 9, 11, 12, 0),
              ),
            ))).called(1);
      },
      expect: () => [
        isA<ServerProfileLoaded>(),
      ],
    );
  });
}
