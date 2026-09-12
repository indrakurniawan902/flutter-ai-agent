import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAppSettingsOpener extends Mock implements AppSettingsOpener {}

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  String allText(WidgetTester tester) {
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
  }

  bool containsEmoji(String input) {
    return RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]',
      unicode: true,
    ).hasMatch(input);
  }

  group('PermissionRationaleModal defaults', () {
    final cases = <PermissionRationaleType, Map<String, dynamic>>{
      PermissionRationaleType.location: {
        'icon': Icons.location_on_rounded,
        'title': 'Akses Lokasi',
        'description':
            'Agen membutuhkan akses lokasi untuk memberikan konteks perangkat dan rekomendasi berbasis lokasi.',
      },
      PermissionRationaleType.notifications: {
        'icon': Icons.notifications_active_rounded,
        'title': 'Akses Notifikasi',
        'description':
            'Agen membutuhkan izin notifikasi untuk mengirim pengingat dan pembaruan penting.',
      },
      PermissionRationaleType.camera: {
        'icon': Icons.camera_alt_rounded,
        'title': 'Akses Kamera',
        'description':
            'Agen membutuhkan akses kamera untuk memindai QR pairing dan analisis visual.',
      },
      PermissionRationaleType.calendar: {
        'icon': Icons.calendar_month_rounded,
        'title': 'Akses Kalender',
        'description':
            'Agen membutuhkan akses kalender untuk membaca dan membuat jadwal acara.',
      },
      PermissionRationaleType.microphone: {
        'icon': Icons.mic_rounded,
        'title': 'Akses Mikrofon',
        'description':
            'Agen membutuhkan akses mikrofon untuk perintah suara dan input audio.',
      },
      PermissionRationaleType.contacts: {
        'icon': Icons.contacts_rounded,
        'title': 'Akses Kontak',
        'description':
            'Agen membutuhkan akses kontak untuk mencari nomor telepon dan nama kontak perangkat.',
      },
    };

    for (final entry in cases.entries) {
      testWidgets('renders defaults for ${entry.key.name}', (tester) async {
        await tester.pumpWidget(
          buildTestableWidget(
            PermissionRationaleModal(permissionType: entry.key),
          ),
        );
        await tester.pumpAndSettle();

        final icon =
            tester.widget<Icon>(find.byKey(const Key('permission_rationale_icon')));
        expect(icon.icon, entry.value['icon']);

        expect(
          find.byKey(const Key('permission_rationale_title')),
          findsOneWidget,
        );
        expect(find.text(entry.value['title'] as String), findsOneWidget);
        expect(
          find.byKey(const Key('permission_rationale_description')),
          findsOneWidget,
        );
        expect(
          find.text(entry.value['description'] as String),
          findsOneWidget,
        );
        expect(find.text('Izinkan'), findsOneWidget);
        expect(find.text('Nanti'), findsOneWidget);
        expect(
          find.byKey(const Key('permission_rationale_allow_btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('permission_rationale_not_now_btn')),
          findsOneWidget,
        );
      });
    }
  });

  group('PermissionRationaleModal custom content', () {
    testWidgets('supports custom title, description, icon and labels',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const PermissionRationaleModal(
            permissionType: PermissionRationaleType.camera,
            customTitle: 'Custom Camera Title',
            customDescription: 'Custom description for camera access.',
            customIcon: Icons.fingerprint,
            allowLabel: 'Allow',
            notNowLabel: 'Not Now',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom Camera Title'), findsOneWidget);
      expect(
        find.text('Custom description for camera access.'),
        findsOneWidget,
      );
      final icon =
          tester.widget<Icon>(find.byKey(const Key('permission_rationale_icon')));
      expect(icon.icon, Icons.fingerprint);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Not Now'), findsOneWidget);
    });
  });

  group('PermissionRationaleModal callbacks', () {
    testWidgets('tapping Allow triggers onAllow', (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildTestableWidget(
          PermissionRationaleModal(
            permissionType: PermissionRationaleType.location,
            onAllow: () => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('tapping Not Now triggers onNotNow', (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildTestableWidget(
          PermissionRationaleModal(
            permissionType: PermissionRationaleType.location,
            onNotNow: () => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('permission_rationale_not_now_btn')));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('tapping Allow with null callback pops true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showPermissionRationale(
                    context,
                    PermissionRationaleType.microphone,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );

      await tester
          .tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('tapping Not Now with null callback pops false',
        (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showPermissionRationale(
                    context,
                    PermissionRationaleType.calendar,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('permission_rationale_not_now_btn')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('showPermissionRationale helper', () {
    testWidgets('displays bottom sheet with dark background and rounded top',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPermissionRationale(
                  context,
                  PermissionRationaleType.notifications,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionRationaleModal), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('static show delegates and returns verdict', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await PermissionRationaleModal.show(
                    context,
                    PermissionRationaleType.camera,
                    allowLabel: 'Allow',
                    notNowLabel: 'Not Now',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Allow'), findsOneWidget);

      await tester
          .tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });

  group('zero emoji + touch targets + responsiveness', () {
    testWidgets('all text elements contain zero emoji', (tester) async {
      for (final type in PermissionRationaleType.values) {
        await tester.pumpWidget(
          buildTestableWidget(PermissionRationaleModal(permissionType: type)),
        );
        await tester.pumpAndSettle();
        expect(containsEmoji(allText(tester)), isFalse,
            reason: 'emoji found for ${type.name}');
      }

      await tester.pumpWidget(
        buildTestableWidget(
          const PermissionRationaleModal(
            permissionType: PermissionRationaleType.camera,
            customTitle: 'Custom Title',
            customDescription: 'Custom description.',
            allowLabel: 'Allow',
            notNowLabel: 'Not Now',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(containsEmoji(allText(tester)), isFalse);
    });

    testWidgets('buttons meet 44px minimum touch target', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const PermissionRationaleModal(
            permissionType: PermissionRationaleType.location,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final allowSize = tester.getSize(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      final notNowSize = tester.getSize(
        find.byKey(const Key('permission_rationale_not_now_btn')),
      );
      expect(allowSize.height, greaterThanOrEqualTo(44));
      expect(notNowSize.height, greaterThanOrEqualTo(44));
    });

    testWidgets('renders on 320px narrow screen with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: const PermissionRationaleModal(
                permissionType: PermissionRationaleType.notifications,
                customTitle:
                    'A very long custom title that should wrap gracefully on narrow screens without overflowing',
                customDescription:
                    'A very long custom description that must wrap across multiple lines on a 320 pixel wide viewport without causing any RenderFlex overflow errors in the bottom sheet layout.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('permission_rationale_title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );
    });
  });

  group('PermissionRationaleModal isPermanentlyDenied', () {
    testWidgets('displays notice and Buka Pengaturan label', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const PermissionRationaleModal(
            permissionType: PermissionRationaleType.microphone,
            isPermanentlyDenied: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('permission_rationale_permanently_denied_notice'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Izin ini ditolak permanen. Aktifkan manual dari pengaturan aplikasi di sistem.',
        ),
        findsOneWidget,
      );
      expect(find.text('Buka Pengaturan'), findsOneWidget);
      expect(find.text('Izinkan'), findsNothing);
      expect(containsEmoji(allText(tester)), isFalse);
    });

    testWidgets('tapping Buka Pengaturan triggers onOpenSettings',
        (tester) async {
      var called = false;
      await tester.pumpWidget(
        buildTestableWidget(
          PermissionRationaleModal(
            permissionType: PermissionRationaleType.microphone,
            isPermanentlyDenied: true,
            onOpenSettings: () => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets(
        'tapping Buka Pengaturan without callback opens app settings and pops true',
        (tester) async {
      final original = AppSettingsOpenerRegistry.instance;
      final mockOpener = _MockAppSettingsOpener();
      when(() => mockOpener.openAppSettings()).thenAnswer((_) async => true);
      AppSettingsOpenerRegistry.instance = mockOpener;
      addTearDown(() => AppSettingsOpenerRegistry.instance = original);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showPermissionRationale(
                    context,
                    PermissionRationaleType.microphone,
                    isPermanentlyDenied: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Buka Pengaturan'), findsOneWidget);

      await tester
          .tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pumpAndSettle();

      verify(() => mockOpener.openAppSettings()).called(1);
      expect(result, isTrue);
    });

    testWidgets(
        'pops true even when app settings opener throws',
        (tester) async {
      final original = AppSettingsOpenerRegistry.instance;
      final mockOpener = _MockAppSettingsOpener();
      when(() => mockOpener.openAppSettings())
          .thenThrow(Exception('no settings activity'));
      AppSettingsOpenerRegistry.instance = mockOpener;
      addTearDown(() => AppSettingsOpenerRegistry.instance = original);

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showPermissionRationale(
                    context,
                    PermissionRationaleType.camera,
                    isPermanentlyDenied: true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pumpAndSettle();

      verify(() => mockOpener.openAppSettings()).called(1);
      expect(result, isTrue);
    });
  });
}
