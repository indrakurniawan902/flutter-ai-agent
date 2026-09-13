import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_attachment.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockCameraVisionService mockCameraService;
  late MockFileWorkspaceService mockFileService;

  final galleryBase64 = base64Encode(utf8.encode('gallery-image-bytes'));

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockCameraService = MockCameraVisionService();
    mockFileService = MockFileWorkspaceService();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockAgentCubit.stop()).thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerFactory<CameraVisionServiceBase>(() => mockCameraService);
    sl.registerFactory<FileWorkspaceServiceBase>(() => mockFileService);
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: const ChatScreen(),
    );
  }

  group('ChatScreen - Attachment UX', () {
    testWidgets('attach button exists and opens sheet with all tiles', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_attach_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_attach_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_attachment_sheet')), findsOneWidget);
      expect(find.byKey(const Key('chat_attach_camera')), findsOneWidget);
      expect(find.byKey(const Key('chat_attach_gallery')), findsOneWidget);
      expect(find.byKey(const Key('chat_attach_file')), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Browse Documents'), findsOneWidget);
    });

    testWidgets(
      'gallery success stages chip and sends attachment on submit',
      (tester) async {
        when(
          () => mockCameraService.takePhoto(source: CameraSource.gallery),
        ).thenAnswer((_) async => Right(galleryBase64));

        final expectedAttachment = ChatAttachment(
          filename: 'gallery.jpg',
          type: ChatAttachmentType.image,
          mimeType: 'image/jpeg',
          base64Data: galleryBase64,
        );
        when(
          () => mockAgentCubit.sendMessage(
            'Check this',
            attachments: [expectedAttachment],
          ),
        ).thenAnswer((_) async {});

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('chat_attach_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat_attach_gallery')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('chat_attachment_chip')), findsOneWidget);
        expect(find.text('gallery.jpg'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Check this',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('chat_send_button')));
        await tester.pump();

        verify(
          () => mockAgentCubit.sendMessage(
            'Check this',
            attachments: [expectedAttachment],
          ),
        ).called(1);
        expect(find.byKey(const Key('chat_attachment_chip')), findsNothing);
      },
    );

    testWidgets('remove button clears the staged chip', (tester) async {
      when(
        () => mockCameraService.takePhoto(source: CameraSource.gallery),
      ).thenAnswer((_) async => Right(galleryBase64));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_attach_gallery')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_attachment_chip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_attach_remove')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_attachment_chip')), findsNothing);
    });

    testWidgets('camera failure shows SnackBar and stages no chip', (
      tester,
    ) async {
      when(
        () => mockCameraService.takePhoto(source: CameraSource.camera),
      ).thenAnswer(
        (_) async => const Left(NetworkFailure('Camera unavailable')),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_attach_camera')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('chat_attachment_chip')), findsNothing);
      expect(find.text('Camera unavailable'), findsOneWidget);
    });

    testWidgets('attach button disabled when no attachment services', (
      tester,
    ) async {
      await sl.reset();
      sl.registerFactory<AgentCubit>(() => mockAgentCubit);
      sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final attachButton = tester.widget<IconButton>(
        find.byKey(const Key('chat_attach_button')),
      );
      expect(attachButton.onPressed, isNull);
    });
  });
}
