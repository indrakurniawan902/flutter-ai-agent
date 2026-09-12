import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/domain/models/share/shared_payload.dart';
import 'package:flutter_ai_agent/domain/services/share/share_target_service.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_state.dart';
import 'package:flutter_ai_agent/domain/services/shortcuts/quick_actions_service.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../helpers/mocks.dart';

class MockShareMediaProvider extends Mock implements ShareMediaProvider {}

class MockSharedMediaFile extends Mock implements SharedMediaFile {}

class MockContactsProvider extends Mock implements ContactsProvider {}

class MockUrlLauncherProvider extends Mock implements UrlLauncherProvider {}

class MockQuickActionsProvider extends Mock implements QuickActionsProvider {}

SharedMediaFile mediaFile({
  required String path,
  required SharedMediaType type,
  String? mimeType,
  String? thumbnail,
  String? message,
}) {
  final file = MockSharedMediaFile();
  when(() => file.path).thenReturn(path);
  when(() => file.type).thenReturn(type);
  when(() => file.mimeType).thenReturn(mimeType);
  when(() => file.thumbnail).thenReturn(thumbnail);
  when(() => file.message).thenReturn(message);
  return file;
}

SkillsRegistryService buildWhatsappSkillsRegistry() {
  final registry = SkillsRegistryService(loadDefaults: false);
  registry.registerSkill(
    const Skill(
      id: 'whatsapp_outreach',
      name: 'whatsapp_outreach',
      description: 'WhatsApp outreach and contact messaging skill.',
      category: 'Communication',
      tier: 'Tier 3 HITL',
      version: '1.0.0',
      tools: ['open_whatsapp_chat'],
      prompts: ['Send a WhatsApp message to a contact'],
      instructions: 'Always confirm recipient phone before launching WhatsApp.',
      isEnabled: true,
    ),
  );
  return registry;
}

SkillsRegistryService buildBrowserSkillsRegistry() {
  final registry = SkillsRegistryService(loadDefaults: false);
  registry.registerSkill(
    const Skill(
      id: 'browser_opener',
      name: 'browser_opener',
      description: 'External browser link opening skill.',
      category: 'Productivity',
      tier: 'Tier 2 Perm',
      version: '1.0.0',
      tools: ['open_external_url'],
      prompts: ['Open this link in the browser'],
      instructions: 'Open only http and https links in external browser.',
      isEnabled: true,
    ),
  );
  return registry;
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(LaunchMode.platformDefault);
    registerFallbackValue(<SharedPayload>[]);
    registerFallbackValue(<ShortcutItem>[]);
    registerFallbackValue(const ShortcutItem(
      type: 'fallback',
      localizedTitle: 'fallback',
    ));
  });

  group('E2E Fase 6: Skills Hub, Share Target and Intent Launcher', () {
    test(
      'share text pipeline ends in Tier 3 WhatsApp approval and wa.me launch',
      () async {
        final shareProvider = MockShareMediaProvider();
        when(() => shareProvider.getMediaStream())
            .thenAnswer((_) => const Stream.empty());
        when(() => shareProvider.getInitialMedia()).thenAnswer((_) async => [
              mediaFile(
                path: 'Chat Budi about tomorrow meeting',
                type: SharedMediaType.text,
              ),
            ]);
        when(() => shareProvider.reset()).thenAnswer((_) async {});

        final shareService = ShareTargetService(provider: shareProvider);
        final shareCubit = ShareTargetCubit(service: shareService);
        await shareCubit.init();

        expect(shareCubit.state, isA<ShareTargetReceived>());
        final received = shareCubit.state as ShareTargetReceived;
        expect(received.payloads, hasLength(1));
        expect(received.payloads.first.kind, SharedPayloadKind.text);
        expect(
          received.suggestedPrompt,
          contains('Chat Budi about tomorrow meeting'),
        );

        final skillsRegistry = buildWhatsappSkillsRegistry();
        expect(skillsRegistry.getActiveSkills().map((s) => s.id),
            contains('whatsapp_outreach'));

        final urlLauncher = MockUrlLauncherProvider();
        when(() => urlLauncher.canLaunchUrl(any())).thenAnswer((_) async => true);
        when(() => urlLauncher.launchUrl(any(), mode: any(named: 'mode')))
            .thenAnswer((_) async => true);
        final contactsProvider = MockContactsProvider();
        final contactTools = ContactLauncherTools(
          contactsProvider: contactsProvider,
          urlLauncherProvider: urlLauncher,
        );

        final toolRegistry = ToolRegistry();
        toolRegistry.registerContactLauncherTools(contactTools);
        skillsRegistry.syncWithToolRegistry(toolRegistry);
        expect(toolRegistry.isToolEnabled('open_whatsapp_chat'), isTrue);

        final mockLlm = MockLlmRepository();
        List<Map<String, dynamic>>? capturedMessages;
        when(() => mockLlm.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final messages =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          capturedMessages = messages;
          if (messages.length == 2) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_wa_1',
                    name: 'open_whatsapp_chat',
                    argumentsFragment:
                        '{"phone":"+6281234567890","message":"Hello Budi"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'WhatsApp chat opened for Budi.',
              finishReason: 'stop',
            ),
          ]));
        });

        final agentCubit = AgentCubit(
          llmRepository: mockLlm,
          toolRegistry: toolRegistry,
          skillsRegistryService: skillsRegistry,
        );

        await agentCubit.sendMessage(received.suggestedPrompt);

        expect(capturedMessages, isNotNull);
        final systemMessage = capturedMessages!
            .firstWhere((m) => m['role'] == 'system');
        expect(systemMessage['content'], contains('whatsapp_outreach'));
        expect(systemMessage['content'],
            contains('Always confirm recipient phone'));

        expect(agentCubit.state, isA<WaitingApproval>());
        final waiting = agentCubit.state as WaitingApproval;
        expect(waiting.request.name, 'open_whatsapp_chat');
        expect(waiting.request.parameters['phone'], '+6281234567890');
        verifyNever(() => urlLauncher.launchUrl(any(),
            mode: any(named: 'mode')));

        await agentCubit.approveAction();

        final launched = verify(() => urlLauncher.launchUrl(captureAny(),
            mode: LaunchMode.externalApplication)).captured;
        expect(launched, hasLength(1));
        final uri = launched.first as Uri;
        expect(uri.scheme, 'https');
        expect(uri.host, 'wa.me');
        expect(uri.path, contains('6281234567890'));
        expect(uri.queryParameters['text'], 'Hello Budi');

        expect(agentCubit.state, isA<AgentSuccess>());
        final success = agentCubit.state as AgentSuccess;
        expect(success.response, contains('WhatsApp chat opened'));

        await shareCubit.close();
        await agentCubit.close();
        await shareService.dispose();
      },
    );

    test(
      'share URL pipeline auto executes Tier 2 open_external_url intent',
      () async {
        final shareProvider = MockShareMediaProvider();
        when(() => shareProvider.getMediaStream())
            .thenAnswer((_) => const Stream.empty());
        when(() => shareProvider.getInitialMedia()).thenAnswer((_) async => [
              mediaFile(
                path: 'https://flutter.dev/docs',
                type: SharedMediaType.url,
              ),
            ]);
        when(() => shareProvider.reset()).thenAnswer((_) async {});

        final shareService = ShareTargetService(provider: shareProvider);
        final shareCubit = ShareTargetCubit(service: shareService);
        await shareCubit.init();

        expect(shareCubit.state, isA<ShareTargetReceived>());
        final received = shareCubit.state as ShareTargetReceived;
        expect(received.payloads.first.kind, SharedPayloadKind.url);
        expect(received.suggestedPrompt, contains('https://flutter.dev/docs'));

        final skillsRegistry = buildBrowserSkillsRegistry();
        final urlLauncher = MockUrlLauncherProvider();
        when(() => urlLauncher.canLaunchUrl(any())).thenAnswer((_) async => true);
        when(() => urlLauncher.launchUrl(any(), mode: any(named: 'mode')))
            .thenAnswer((_) async => true);
        final contactTools = ContactLauncherTools(
          contactsProvider: MockContactsProvider(),
          urlLauncherProvider: urlLauncher,
        );

        final toolRegistry = ToolRegistry();
        toolRegistry.registerContactLauncherTools(contactTools);

        final mockLlm = MockLlmRepository();
        when(() => mockLlm.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final messages =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          final hasSystem =
              messages.isNotEmpty && messages.first['role'] == 'system';
          final userCount =
              messages.where((m) => m['role'] == 'user').length;
          if ((hasSystem && messages.length == 2) ||
              (!hasSystem && userCount == 1 && messages.length == 1)) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_url_1',
                    name: 'open_external_url',
                    argumentsFragment:
                        '{"url":"https://flutter.dev/docs"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Opened shared link in browser.',
              finishReason: 'stop',
            ),
          ]));
        });

        final agentCubit = AgentCubit(
          llmRepository: mockLlm,
          toolRegistry: toolRegistry,
          skillsRegistryService: skillsRegistry,
        );

        await agentCubit.sendMessage(received.suggestedPrompt);

        expect(agentCubit.state, isA<AgentSuccess>());
        verify(() => urlLauncher.launchUrl(
              Uri.parse('https://flutter.dev/docs'),
              mode: LaunchMode.externalApplication,
            )).called(1);
        final toolMessage =
            agentCubit.messages.firstWhere((m) => m.role == 'tool');
        expect(toolMessage.name, 'open_external_url');
        expect(toolMessage.content, contains('Opened URL'));

        await shareCubit.close();
        await agentCubit.close();
        await shareService.dispose();
      },
    );

    test(
      'disabling skill gates tool and re-enabling restores access',
      () async {
        final skillsRegistry = buildBrowserSkillsRegistry();
        final urlLauncher = MockUrlLauncherProvider();
        when(() => urlLauncher.canLaunchUrl(any())).thenAnswer((_) async => true);
        when(() => urlLauncher.launchUrl(any(), mode: any(named: 'mode')))
            .thenAnswer((_) async => true);
        final contactTools = ContactLauncherTools(
          contactsProvider: MockContactsProvider(),
          urlLauncherProvider: urlLauncher,
        );
        final toolRegistry = ToolRegistry();
        toolRegistry.registerContactLauncherTools(contactTools);

        skillsRegistry.setSkillEnabled('browser_opener', false);
        skillsRegistry.syncWithToolRegistry(toolRegistry);

        expect(skillsRegistry.isSkillEnabled('browser_opener'), isFalse);
        expect(toolRegistry.isToolEnabled('open_external_url'), isFalse);
        expect(
          toolRegistry.getOpenAiToolDefinitions().any(
              (t) => t['function']['name'] == 'open_external_url'),
          isFalse,
        );
        expect(skillsRegistry.buildSystemPrompt(), isEmpty);

        final mockLlm = MockLlmRepository();
        when(() => mockLlm.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final messages =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          final userMessages =
              messages.where((m) => m['role'] == 'user').toList();
          if (userMessages.length == 1 && messages.length <= 2) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_gated_1',
                    name: 'open_external_url',
                    argumentsFragment:
                        '{"url":"https://flutter.dev/docs"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Tool unavailable under current skill policy.',
              finishReason: 'stop',
            ),
          ]));
        });

        final gatedCubit = AgentCubit(
          llmRepository: mockLlm,
          toolRegistry: toolRegistry,
          skillsRegistryService: skillsRegistry,
        );
        await gatedCubit.sendMessage('Open https://flutter.dev/docs');

        expect(gatedCubit.state, isNot(isA<WaitingApproval>()));
        final gatedToolMessage =
            gatedCubit.messages.firstWhere((m) => m.role == 'tool');
        expect(gatedToolMessage.content, contains('disabled by skill policy'));
        verifyNever(() => urlLauncher.launchUrl(any(),
            mode: any(named: 'mode')));
        await gatedCubit.close();

        skillsRegistry.setSkillEnabled('browser_opener', true);
        skillsRegistry.syncWithToolRegistry(toolRegistry);

        expect(skillsRegistry.isSkillEnabled('browser_opener'), isTrue);
        expect(toolRegistry.isToolEnabled('open_external_url'), isTrue);
        expect(
          toolRegistry.getOpenAiToolDefinitions().any(
              (t) => t['function']['name'] == 'open_external_url'),
          isTrue,
        );
        expect(skillsRegistry.buildSystemPrompt(), contains('browser_opener'));

        final restoredCubit = AgentCubit(
          llmRepository: mockLlm,
          toolRegistry: toolRegistry,
          skillsRegistryService: skillsRegistry,
        );
        await restoredCubit.sendMessage('Open https://flutter.dev/docs');

        expect(restoredCubit.state, isA<AgentSuccess>());
        verify(() => urlLauncher.launchUrl(
              Uri.parse('https://flutter.dev/docs'),
              mode: LaunchMode.externalApplication,
            )).called(1);
        await restoredCubit.close();
      },
    );

    test(
      'QuickActions registers default shortcuts and dispatches actionStream',
      () async {
        final provider = MockQuickActionsProvider();
        List<ShortcutItem>? capturedItems;
        void Function(String)? capturedCallback;

        when(() => provider.setShortcutItems(any())).thenAnswer(
            (invocation) async {
          capturedItems =
              invocation.positionalArguments[0] as List<ShortcutItem>;
        });
        when(() => provider.initialize(any())).thenAnswer(
            (invocation) async {
          capturedCallback =
              invocation.positionalArguments[0] as void Function(String);
        });

        final service = QuickActionsService(provider: provider);
        await service.initialize();

        verify(() => provider.setShortcutItems(
            QuickActionsService.defaultShortcuts)).called(1);
        verify(() => provider.initialize(any())).called(1);

        expect(capturedItems, isNotNull);
        expect(capturedItems, hasLength(3));
        expect(
          capturedItems!.map((e) => e.type),
          containsAll([
            'action_voice_chat',
            'action_ask_camera',
            'action_scan_qr',
          ]),
        );
        expect(QuickActionsService.actionVoiceChat, 'action_voice_chat');
        expect(QuickActionsService.actionAskCamera, 'action_ask_camera');
        expect(QuickActionsService.actionScanQr, 'action_scan_qr');

        expect(capturedCallback, isNotNull);
        final expectation = expectLater(
          service.actionStream,
          emitsInOrder([
            'action_voice_chat',
            'action_ask_camera',
            'action_scan_qr',
          ]),
        );
        capturedCallback!('action_voice_chat');
        capturedCallback!('action_ask_camera');
        capturedCallback!('action_scan_qr');
        await expectation;

        final directExpectation = expectLater(
          service.actionStream,
          emits('action_voice_chat'),
        );
        service.handleAction('action_voice_chat');
        await directExpectation;

        await service.dispose();
      },
    );

    test(
      'Tier 3 rejection reports to LLM and blocks external launch',
      () async {
        final skillsRegistry = buildWhatsappSkillsRegistry();
        final urlLauncher = MockUrlLauncherProvider();
        when(() => urlLauncher.canLaunchUrl(any())).thenAnswer((_) async => true);
        when(() => urlLauncher.launchUrl(any(), mode: any(named: 'mode')))
            .thenAnswer((_) async => true);
        final contactTools = ContactLauncherTools(
          contactsProvider: MockContactsProvider(),
          urlLauncherProvider: urlLauncher,
        );
        final toolRegistry = ToolRegistry();
        toolRegistry.registerContactLauncherTools(contactTools);

        final mockLlm = MockLlmRepository();
        var turn = 0;
        when(() => mockLlm.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((_) async {
          turn++;
          if (turn == 1) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_wa_reject',
                    name: 'open_whatsapp_chat',
                    argumentsFragment:
                        '{"phone":"+6281234567890","message":"Hello"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'WhatsApp action cancelled as requested.',
              finishReason: 'stop',
            ),
          ]));
        });

        final agentCubit = AgentCubit(
          llmRepository: mockLlm,
          toolRegistry: toolRegistry,
          skillsRegistryService: skillsRegistry,
        );

        await agentCubit.sendMessage('Send WhatsApp to Budi');
        expect(agentCubit.state, isA<WaitingApproval>());

        await agentCubit.rejectAction();

        verifyNever(() => urlLauncher.launchUrl(any(),
            mode: any(named: 'mode')));
        verifyNever(() => urlLauncher.canLaunchUrl(any()));

        final toolMessage =
            agentCubit.messages.firstWhere((m) => m.role == 'tool');
        expect(toolMessage.name, 'open_whatsapp_chat');
        expect(toolMessage.content, contains('rejected by user'));

        expect(agentCubit.state, isA<AgentSuccess>());
        final success = agentCubit.state as AgentSuccess;
        expect(success.response, contains('cancelled'));

        await agentCubit.close();
      },
    );
  });
}
