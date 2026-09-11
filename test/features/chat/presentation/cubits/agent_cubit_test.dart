import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockLlmRepository mockLlmRepository;
  late ToolRegistry toolRegistry;
  late AgentCubit cubit;

  const baseUrl = 'https://api.openai.com/v1';
  const model = 'gpt-4o';
  const apiKey = 'test-key';

  setUp(() {
    mockLlmRepository = MockLlmRepository();
    toolRegistry = ToolRegistry();
    cubit = AgentCubit(
      llmRepository: mockLlmRepository,
      toolRegistry: toolRegistry,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('AgentCubit ReAct Loop', () {
    test('initial state is AgentIdle and messages are empty', () {
      expect(cubit.state, equals(const AgentIdle()));
      expect(cubit.messages, isEmpty);
    });

    test('simulates 2-turn tool calling loop: user -> LLM tool_call -> tool execute -> LLM final text', () async {
      // 1. Register Tier 1 tool
      var toolExecuted = false;
      toolRegistry.register(
        RegisteredTool(
          name: 'get_battery',
          description: 'Get device battery',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async {
            toolExecuted = true;
            return const Right('{"battery": 85}');
          },
        ),
      );

      // 2. Mock Turn 1 LLM response (tool call)
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((invocation) async {
        final messages = invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
        // If this is Turn 1 (only user message)
        if (messages.length == 1) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_1',
                  name: 'get_battery',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        } else {
          // Turn 2: messages has user, assistant (tool_calls), and tool result
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Your battery is at 85%.',
              finishReason: 'stop',
            ),
          ]));
        }
      });

      // 3. User sends message
      await cubit.sendMessage('How is my battery?');

      // 4. Verification
      expect(toolExecuted, isTrue);
      expect(cubit.state, isA<AgentSuccess>());
      final successState = cubit.state as AgentSuccess;
      expect(successState.response, equals('Your battery is at 85%.'));

      // Check conversation history
      expect(cubit.messages.length, equals(4));
      expect(cubit.messages[0].role, equals('user'));
      expect(cubit.messages[0].content, equals('How is my battery?'));

      expect(cubit.messages[1].role, equals('assistant'));
      expect(cubit.messages[1].toolCalls, isNotNull);
      expect(cubit.messages[1].toolCalls!.first.name, equals('get_battery'));

      expect(cubit.messages[2].role, equals('tool'));
      expect(cubit.messages[2].toolCallId, equals('call_1'));
      expect(cubit.messages[2].content, equals('{"battery": 85}'));

      expect(cubit.messages[3].role, equals('assistant'));
      expect(cubit.messages[3].content, equals('Your battery is at 85%.'));
    });

    test('Tier 3 tool pauses the loop with WaitingApproval state', () async {
      var tier3Executed = false;
      toolRegistry.register(
        RegisteredTool(
          name: 'delete_event',
          description: 'Delete calendar event',
          parameters: const {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
            },
            'required': ['id'],
          },
          securityTier: SecurityTier.tier3Hitl,
          execute: (args) async {
            tier3Executed = true;
            return const Right('{"success": true}');
          },
        ),
      );

      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        return Right(Stream.fromIterable([
          const ChatChunk(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call_delete_1',
                name: 'delete_event',
                argumentsFragment: '{"id":"evt_999"}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ]));
      });

      await cubit.sendMessage('Delete event evt_999');

      // The loop must pause at WaitingApproval
      expect(cubit.state, isA<WaitingApproval>());
      final waiting = cubit.state as WaitingApproval;
      expect(waiting.request.id, equals('call_delete_1'));
      expect(waiting.request.name, equals('delete_event'));
      expect(waiting.request.parameters, equals({'id': 'evt_999'}));

      // Tool must NOT have been executed yet
      expect(tier3Executed, isFalse);
    });

    test('approving Tier 3 action resumes execution and completes ReAct loop', () async {
      var tier3Executed = false;
      toolRegistry.register(
        RegisteredTool(
          name: 'delete_event',
          description: 'Delete calendar event',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier3Hitl,
          execute: (args) async {
            tier3Executed = true;
            return const Right('{"deleted": true}');
          },
        ),
      );

      var turnCount = 0;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        turnCount++;
        if (turnCount == 1) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_del',
                  name: 'delete_event',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        } else {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Event has been deleted successfully.',
              finishReason: 'stop',
            ),
          ]));
        }
      });

      await cubit.sendMessage('Delete the event');
      expect(cubit.state, isA<WaitingApproval>());
      expect(tier3Executed, isFalse);

      // Now approve
      await cubit.approveAction();

      expect(tier3Executed, isTrue);
      expect(cubit.state, isA<AgentSuccess>());
      final success = cubit.state as AgentSuccess;
      expect(success.response, equals('Event has been deleted successfully.'));
    });

    test('rejecting Tier 3 action emits RejectedAction and resumes loop with rejection notice', () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'delete_event',
          description: 'Delete calendar event',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier3Hitl,
          execute: (args) async => const Right('{"deleted": true}'),
        ),
      );

      var turnCount = 0;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        turnCount++;
        if (turnCount == 1) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_del',
                  name: 'delete_event',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        } else {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Action was cancelled.',
              finishReason: 'stop',
            ),
          ]));
        }
      });

      await cubit.sendMessage('Delete the event');
      expect(cubit.state, isA<WaitingApproval>());

      await cubit.rejectAction();

      expect(cubit.state, isA<AgentSuccess>());
      final success = cubit.state as AgentSuccess;
      expect(success.response, equals('Action was cancelled.'));
      // The tool message should indicate user rejection
      final toolMsg = cubit.messages.firstWhere((m) => m.role == 'tool');
      expect(toolMsg.content, contains('rejected'));
    });

    test('handles LLM connection failure gracefully', () async {
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async => const Left(ConnectionFailure('Network error')));

      await cubit.sendMessage('Hello');

      expect(cubit.state, isA<AgentError>());
      final errorState = cubit.state as AgentError;
      expect(errorState.message, contains('Network error'));
    });

    test('handles mid-stream exception gracefully', () async {
      final errorStream = Stream<ChatChunk>.error(Exception('Stream disconnected'));
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async => Right(errorStream));

      await cubit.sendMessage('Hello');

      expect(cubit.state, isA<AgentError>());
      final errorState = cubit.state as AgentError;
      expect(errorState.message, contains('Stream interrupted'));
    });

    test('processes multiple tool calls in a turn even when early tool requires Tier 3 HITL', () async {
      var tier3Executed = false;
      var tier1Executed = false;

      toolRegistry.register(
        RegisteredTool(
          name: 'critical_action',
          description: 'Tier 3 action',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier3Hitl,
          execute: (args) async {
            tier3Executed = true;
            return const Right('Critical action executed');
          },
        ),
      );

      toolRegistry.register(
        RegisteredTool(
          name: 'info_action',
          description: 'Tier 1 action',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async {
            tier1Executed = true;
            return const Right('Info action executed');
          },
        ),
      );

      var turn = 0;
      when(() => mockLlmRepository.streamCompletion(
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
                  id: 'call_crit',
                  name: 'critical_action',
                  argumentsFragment: '{}',
                ),
                ToolCallDelta(
                  index: 1,
                  id: 'call_info',
                  name: 'info_action',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        } else {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Both actions processed successfully.',
              finishReason: 'stop',
            ),
          ]));
        }
      });

      await cubit.sendMessage('Run both actions');
      expect(cubit.state, isA<WaitingApproval>());
      expect(tier3Executed, isFalse);
      expect(tier1Executed, isFalse);

      await cubit.approveAction();

      expect(tier3Executed, isTrue);
      expect(tier1Executed, isTrue);
      expect(cubit.state, isA<AgentSuccess>());
      expect((cubit.state as AgentSuccess).response,
          equals('Both actions processed successfully.'));

      final toolMessages =
          cubit.messages.where((m) => m.role == 'tool').toList();
      expect(toolMessages.length, equals(2));
      expect(toolMessages[0].content, equals('Critical action executed'));
      expect(toolMessages[1].content, equals('Info action executed'));
    });
  });
}
