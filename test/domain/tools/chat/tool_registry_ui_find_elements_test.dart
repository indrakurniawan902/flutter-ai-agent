import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAccessibilityInspectorService extends Mock
    implements AccessibilityInspectorServiceBase {}

void main() {
  late MockAccessibilityInspectorService service;
  late ToolRegistry registry;

  setUp(() {
    service = MockAccessibilityInspectorService();
    registry = ToolRegistry(accessibilityInspectorService: service);
  });

  void stubFindElements(Either<Failure, String> result) {
    when(() => service.findElementsFormatted(
          textFilter: any(named: 'textFilter'),
          packageFilter: any(named: 'packageFilter'),
          clickableOnly: any(named: 'clickableOnly'),
          maxNodes: any(named: 'maxNodes'),
          maxDepth: any(named: 'maxDepth'),
        )).thenAnswer((_) async => result);
  }

  group('ui_find_elements registration', () {
    test('registered as tier2 with exactly the five optional properties', () {
      expect(registry.hasTool('ui_find_elements'), isTrue);

      final tool = registry.getTool('ui_find_elements')!;
      expect(tool.securityTier, SecurityTier.tier2Permission);

      final parameters = tool.parameters;
      expect(parameters['type'], 'object');
      expect(
        (parameters['properties'] as Map).keys.toSet(),
        <String>{
          'text_filter',
          'package_filter',
          'clickable_only',
          'max_nodes',
          'max_depth',
        },
      );
      expect(parameters['required'], isEmpty);
    });

    test('absent when no accessibility service is provided', () {
      expect(ToolRegistry().hasTool('ui_find_elements'), isFalse);
    });

    test('appears in OpenAI tool definitions with description and schema', () {
      final definitions = registry.getOpenAiToolDefinitions();
      final definition = definitions.firstWhere(
        (entry) => (entry['function'] as Map)['name'] == 'ui_find_elements',
      );

      final function = definition['function'] as Map;
      expect(function['description'].toString(), isNotEmpty);
      expect(function['parameters'], isA<Map>());
    });
  });

  group('ui_find_elements execution', () {
    test('service not enabled yields the actionable Left message', () async {
      when(() => service.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.notEnabled);
      final expected =
          AccessibilityMessages.forStatus(AccessibilityStatus.notEnabled);
      stubFindElements(Left(ServerFailure(expected)));

      final result = await registry.executeTool('ui_find_elements', {});

      expect(result, Left<Failure, String>(ServerFailure(expected)));
      expect((result as Left).value.message, expected);
    });

    test('active yields whatever the service returned', () async {
      when(() => service.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.active);
      stubFindElements(
        const Right<Failure, String>('accessibility tree: package=com.x'),
      );

      final result = await registry.executeTool('ui_find_elements', {});

      expect(
        result,
        const Right<Failure, String>('accessibility tree: package=com.x'),
      );
    });

    test('forwards filters and caps to the service', () async {
      stubFindElements(const Right<Failure, String>('tree'));

      await registry.executeTool('ui_find_elements', {
        'text_filter': 'send',
        'package_filter': 'whatsapp',
        'clickable_only': true,
        'max_nodes': 5,
        'max_depth': 3,
      });

      verify(() => service.findElementsFormatted(
            textFilter: 'send',
            packageFilter: 'whatsapp',
            clickableOnly: true,
            maxNodes: 5,
            maxDepth: 3,
          )).called(1);
    });

    test('applies defaults when arguments are omitted', () async {
      stubFindElements(const Right<Failure, String>('tree'));

      await registry.executeTool('ui_find_elements', {});

      verify(() => service.findElementsFormatted(
            textFilter: null,
            packageFilter: null,
            clickableOnly: false,
            maxNodes: AccessibilityTreeSerializer.defaultMaxNodes,
            maxDepth: AccessibilityTreeSerializer.defaultMaxDepth,
          )).called(1);
    });

    test('disabled by skill policy is rejected before execution', () async {
      registry.setToolEnabled('ui_find_elements', false);

      final result = await registry.executeTool('ui_find_elements', {});

      expect(
        result,
        const Left<Failure, String>(
          ServerFailure('Tool ui_find_elements is disabled by skill policy.'),
        ),
      );
      verifyNever(() => service.findElementsFormatted(
            textFilter: any(named: 'textFilter'),
            packageFilter: any(named: 'packageFilter'),
            clickableOnly: any(named: 'clickableOnly'),
            maxNodes: any(named: 'maxNodes'),
            maxDepth: any(named: 'maxDepth'),
          ));
    });

    test('tool_search("screen") surfaces ui_find_elements', () async {
      final result =
          await registry.executeTool('tool_search', {'query': 'screen'});

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), contains('ui_find_elements'));
    });
  });
}
