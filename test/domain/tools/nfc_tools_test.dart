import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class FakeNfcService extends Mock implements NfcServiceBase {}

void main() {
  late ToolRegistry registry;
  late FakeNfcService nfc;

  setUp(() {
    nfc = FakeNfcService();
    registry = ToolRegistry(nfcService: nfc);
  });

  group('registration', () {
    test('registers both nfc tools as tier2 and active', () {
      final readTag = registry.getTool('nfc_read_tag');
      final readEmoney = registry.getTool('nfc_read_emoney_balance');

      expect(readTag, isNotNull);
      expect(readEmoney, isNotNull);
      expect(readTag!.securityTier, SecurityTier.tier2Permission);
      expect(readEmoney!.securityTier, SecurityTier.tier2Permission);

      final activeNames = registry.activeTools.map((tool) => tool.name);
      expect(activeNames, contains('nfc_read_tag'));
      expect(activeNames, contains('nfc_read_emoney_balance'));
    });
  });

  group('nfc_read_tag', () {
    test('returns Left mentioning "not supported" when unavailable', () async {
      when(() => nfc.isAvailable()).thenAnswer((_) async => const Right(false));

      final result = await registry.executeTool('nfc_read_tag');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) => expect(failure.message, contains('not supported')),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => nfc.readCardUid());
    });

    test('returns Left naming launch_system_setting when disabled', () async {
      when(() => nfc.isAvailable()).thenAnswer((_) async => const Right(true));
      when(() => nfc.isEnabled()).thenAnswer((_) async => const Right(false));

      final result = await registry.executeTool('nfc_read_tag');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure.message, contains('launch_system_setting'));
          expect(failure.message, contains('nfc'));
        },
        (_) => fail('Expected Left'),
      );
      verifyNever(() => nfc.readCardUid());
    });

    test('happy path returns the UID from the service', () async {
      when(() => nfc.isAvailable()).thenAnswer((_) async => const Right(true));
      when(() => nfc.isEnabled()).thenAnswer((_) async => const Right(true));
      when(() => nfc.readCardUid())
          .thenAnswer((_) async => const Right('04a1b2c3'));

      final result = await registry.executeTool('nfc_read_tag');

      expect(result, const Right<Failure, String>('04a1b2c3'));
      verify(() => nfc.readCardUid()).called(1);
    });
  });

  group('nfc_read_emoney_balance', () {
    test('happy path returns json-encoded balance', () async {
      when(() => nfc.isAvailable()).thenAnswer((_) async => const Right(true));
      when(() => nfc.isEnabled()).thenAnswer((_) async => const Right(true));
      when(() => nfc.readEmoneyBalance(expectedCardUid: any(named: 'expectedCardUid')))
          .thenAnswer(
        (_) async => const Right(
          EmoneyBalance(
            brand: EmoneyCardBrand.mandiriEmoney,
            cardUid: '04a1b2c3',
            balanceRupiah: 25000,
            recentTransactions: [
              EmoneyTransaction(amountRupiah: -5000, label: 'KRL'),
            ],
          ),
        ),
      );

      final result = await registry.executeTool('nfc_read_emoney_balance');

      expect(result.isRight(), isTrue);
      final payload =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(payload['balanceRupiah'], 25000);
      expect((payload['recentTransactions'] as List<dynamic>).length, 1);
    });

    test('forwards expected_uid to the service', () async {
      when(() => nfc.isAvailable()).thenAnswer((_) async => const Right(true));
      when(() => nfc.isEnabled()).thenAnswer((_) async => const Right(true));
      when(() => nfc.readEmoneyBalance(expectedCardUid: '04a1b2c3')).thenAnswer(
        (_) async => const Right(
          EmoneyBalance(
            brand: EmoneyCardBrand.bcaFlazz,
            cardUid: '04a1b2c3',
            balanceRupiah: 1000,
          ),
        ),
      );

      final result = await registry.executeTool(
        'nfc_read_emoney_balance',
        {'expected_uid': '04a1b2c3'},
      );

      expect(result.isRight(), isTrue);
      verify(() => nfc.readEmoneyBalance(expectedCardUid: '04a1b2c3'))
          .called(1);
    });

    test('returns Left and never reads when disabled', () async {
      when(() => nfc.isAvailable()).thenAnswer((_) async => const Right(true));
      when(() => nfc.isEnabled()).thenAnswer((_) async => const Right(false));

      final result = await registry.executeTool('nfc_read_emoney_balance');

      expect(result, isA<Left<Failure, String>>());
      verifyNever(
        () => nfc.readEmoneyBalance(expectedCardUid: any(named: 'expectedCardUid')),
      );
    });
  });
}
