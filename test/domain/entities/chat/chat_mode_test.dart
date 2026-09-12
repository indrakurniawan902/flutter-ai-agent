import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatMode', () {
    test('has direct and gateway modes', () {
      expect(ChatMode.values, contains(ChatMode.direct));
      expect(ChatMode.values, contains(ChatMode.gateway));
      expect(ChatMode.values.length, 2);
    });

    test('helper getters return correct boolean values', () {
      const direct = ChatMode.direct;
      expect(direct.isDirect, isTrue);
      expect(direct.isGateway, isFalse);

      const gateway = ChatMode.gateway;
      expect(gateway.isDirect, isFalse);
      expect(gateway.isGateway, isTrue);
    });
  });
}
