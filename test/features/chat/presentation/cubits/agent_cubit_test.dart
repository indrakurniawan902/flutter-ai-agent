import 'dart:async';

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

    test('terminates ReAct loop immediately when tool execution returns PermissionFailure without re-requesting tool', () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'get_location',
          description: 'Get device location',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async =>
              const Left(PermissionFailure('Location permission denied')),
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
                id: 'call_loc',
                name: 'get_location',
                argumentsFragment: '{}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ]));
      });

      await cubit.sendMessage('What is my location?');

      expect(cubit.state, isA<AgentSuccess>());
      final successState = cubit.state as AgentSuccess;
      expect(successState.response, contains('Location permission denied'));

      verify(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).called(1);

      final toolMessages =
          cubit.messages.where((m) => m.role == 'tool').toList();
      expect(toolMessages.length, equals(1));
      expect(toolMessages.first.content, contains('Location permission denied'));

      final assistantMessages =
          cubit.messages.where((m) => m.role == 'assistant').toList();
      expect(assistantMessages.last.content, contains('Location permission denied'));
    });

    test('terminates ReAct loop immediately when approved Tier 3 tool returns PermissionFailure', () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'create_calendar_event',
          description: 'Create calendar event',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier3Hitl,
          execute: (args) async =>
              const Left(PermissionFailure('Calendar permission denied')),
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
                id: 'call_cal',
                name: 'create_calendar_event',
                argumentsFragment: '{}',
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ]));
      });

      await cubit.sendMessage('Create event');
      expect(cubit.state, isA<WaitingApproval>());

      await cubit.approveAction();

      expect(cubit.state, isA<AgentSuccess>());
      final successState = cubit.state as AgentSuccess;
      expect(successState.response, contains('Calendar permission denied'));

      verify(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).called(1);
    });

    test('extracts thought tags into thoughtProcess and clean content',
        () async {
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        return Right(Stream.fromIterable([
          const ChatChunk(
            contentDelta: '<thought>my thoughts</thought>Final answer',
            finishReason: 'stop',
          ),
        ]));
      });

      await cubit.sendMessage('Hello');

      expect(cubit.state, isA<AgentSuccess>());
      final success = cubit.state as AgentSuccess;
      expect(success.response, equals('Final answer'));

      final assistant =
          cubit.messages.lastWhere((m) => m.role == 'assistant');
      expect(assistant.thoughtProcess, equals('my thoughts'));
      expect(assistant.content, equals('Final answer'));
    });

    test('stop() while streaming cancels stream and emits AgentIdle', () async {
      final controller = StreamController<ChatChunk>();
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async => Right(controller.stream));

      final sendFuture = cubit.sendMessage('Hello streaming');

      // Wait until loop starts listening.
      var attempts = 0;
      while (cubit.state is! AgentThinking &&
          cubit.state is! AgentStreaming &&
          attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }

      controller.add(const ChatChunk(contentDelta: 'partial '));
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.stop();
      if (!controller.isClosed) {
        await controller.close();
      }
      await sendFuture;

      expect(cubit.state, isA<AgentIdle>());
      final idle = cubit.state as AgentIdle;
      expect(idle.messages, equals(cubit.messages));
      expect(cubit.messages.length, equals(1));
      expect(cubit.messages.first.role, equals('user'));
      expect(cubit.messages.first.content, equals('Hello streaming'));
    });

    test('cancel() cancels stream and emits AgentIdle', () async {
      final controller = StreamController<ChatChunk>();
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async => Right(controller.stream));

      final sendFuture = cubit.sendMessage('Hello cancel');

      var attempts = 0;
      while (cubit.state is! AgentThinking &&
          cubit.state is! AgentStreaming &&
          attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }

      controller.add(const ChatChunk(contentDelta: 'partial '));
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
      await sendFuture;

      expect(cubit.state, isA<AgentIdle>());
      final idle = cubit.state as AgentIdle;
      expect(idle.messages, equals(cubit.messages));
      expect(cubit.messages.length, equals(1));
      expect(cubit.messages.first.content, equals('Hello cancel'));
    });

    test('stop() while executing tool prevents subsequent tool execution',
        () async {
      var firstExecuted = false;
      var secondExecuted = false;

      toolRegistry.register(
        RegisteredTool(
          name: 'slow_action',
          description: 'Slow tier 1 action',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async {
            firstExecuted = true;
            await Future.delayed(const Duration(milliseconds: 300));
            return const Right('slow done');
          },
        ),
      );

      toolRegistry.register(
        RegisteredTool(
          name: 'fast_action',
          description: 'Fast tier 1 action',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async {
            secondExecuted = true;
            return const Right('fast done');
          },
        ),
      );

      var llmCalls = 0;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        llmCalls++;
        if (llmCalls == 1) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_slow',
                  name: 'slow_action',
                  argumentsFragment: '{}',
                ),
                ToolCallDelta(
                  index: 1,
                  id: 'call_fast',
                  name: 'fast_action',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }
        return Right(Stream.fromIterable([
          const ChatChunk(
            contentDelta: 'Should not reach here.',
            finishReason: 'stop',
          ),
        ]));
      });

      final sendFuture = cubit.sendMessage('Run both');

      // Wait until first tool starts executing.
      var attempts = 0;
      while (cubit.state is! ExecutingTool && attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
      expect(cubit.state, isA<ExecutingTool>());

      await cubit.stop();
      await sendFuture;

      expect(firstExecuted, isTrue);
      expect(secondExecuted, isFalse);
      expect(llmCalls, equals(1));
      expect(cubit.state, isA<AgentIdle>());
      final idle = cubit.state as AgentIdle;
      expect(idle.messages, equals(cubit.messages));
    });

    test(
        'stale abandoned turn cannot emit after a new sendMessage() has started',
        () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'slow_action',
          description: 'Slow tier 1 action',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async {
            await Future.delayed(const Duration(milliseconds: 300));
            return const Right('stale result');
          },
        ),
      );

      var llmCalls = 0;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        llmCalls++;
        if (llmCalls == 1) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_slow',
                  name: 'slow_action',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }
        if (llmCalls == 2) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'second answer',
              finishReason: 'stop',
            ),
          ]));
        }
        return Right(Stream.fromIterable([
          const ChatChunk(
            contentDelta: 'STALE LOOP SHOULD NOT RUN',
            finishReason: 'stop',
          ),
        ]));
      });

      final firstFuture = cubit.sendMessage('first');

      var attempts = 0;
      while (cubit.state is! ExecutingTool && attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
      expect(cubit.state, isA<ExecutingTool>());

      await cubit.stop();
      await cubit.sendMessage('second');
      await firstFuture;
      // Allow the stale in-flight tool await time to resolve if guards fail.
      await Future.delayed(const Duration(milliseconds: 500));

      expect(llmCalls, equals(2));
      expect(cubit.state, isA<AgentSuccess>());
      expect((cubit.state as AgentSuccess).response, equals('second answer'));
      expect(
        cubit.messages.where((m) => m.role == 'tool'),
        isEmpty,
        reason: 'stale tool result must be discarded',
      );
      expect(cubit.messages.last.role, equals('assistant'));
      expect(cubit.messages.last.content, equals('second answer'));
    });

    test(
        'stale run parked at streamCompletion await cannot hang a new run started after stop()',
        () async {
      final parked = Completer<Either<Failure, Stream<ChatChunk>>>();
      final controllerB = StreamController<ChatChunk>();
      var calls = 0;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) {
        calls++;
        if (calls == 1) return parked.future;
        return Future.value(Right<Failure, Stream<ChatChunk>>(
          controllerB.stream,
        ));
      });

      final firstFuture = cubit.sendMessage('first');
      var attempts = 0;
      while (calls == 0 && attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
      expect(calls, equals(1));
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.stop();

      final secondFuture = cubit.sendMessage('second');
      attempts = 0;
      while (calls < 2 && attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
      expect(calls, equals(2));

      // Stale run A resumes now while run B is still awaiting its stream.
      parked.complete(Right<Failure, Stream<ChatChunk>>(
        Stream.fromIterable([
          const ChatChunk(
            contentDelta: 'STALE SHOULD NEVER WIN',
            finishReason: 'stop',
          ),
        ]),
      ));

      controllerB.add(const ChatChunk(contentDelta: 'second answer'));
      await Future.delayed(const Duration(milliseconds: 50));
      await controllerB.close();

      await secondFuture.timeout(const Duration(seconds: 5));
      await firstFuture.timeout(const Duration(seconds: 5));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(cubit.state, isA<AgentSuccess>());
      expect(
        (cubit.state as AgentSuccess).response,
        equals('second answer'),
      );
      expect(calls, equals(2));
      expect(
        cubit.messages.any(
            (m) => (m.content ?? '').contains('STALE SHOULD NEVER WIN')),
        isFalse,
      );
    });

    test('reset() while a run is in flight abandons that run', () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'slow_action',
          description: 'Slow tier 1 action',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async {
            await Future.delayed(const Duration(milliseconds: 300));
            return const Right('stale result');
          },
        ),
      );

      var llmCalls = 0;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async {
        llmCalls++;
        if (llmCalls == 1) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_slow',
                  name: 'slow_action',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }
        return Right(Stream.fromIterable([
          const ChatChunk(
            contentDelta: 'STALE LOOP SHOULD NOT RUN',
            finishReason: 'stop',
          ),
        ]));
      });

      final sendFuture = cubit.sendMessage('hello');

      var attempts = 0;
      while (cubit.state is! ExecutingTool && attempts < 200) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
      expect(cubit.state, isA<ExecutingTool>());

      cubit.reset();
      await sendFuture.timeout(const Duration(seconds: 5));
      // Allow the abandoned tool await time to resolve if guards fail.
      await Future.delayed(const Duration(milliseconds: 500));

      expect(llmCalls, equals(1));
      expect(cubit.state, isA<AgentIdle>());
      expect(cubit.messages, isEmpty);
    });
  });
}
