import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:nfc_manager/src/nfc_manager_android/pigeon.g.dart';

const String _host = 'dev.flutter.pigeon.nfc_manager.HostApiPigeon.';
const String _flutter = 'dev.flutter.pigeon.nfc_manager.FlutterApiPigeon.';

/// Records every APDU sent through [transceive] so tests can assert the
/// service never emitted a mutating command or a balance read it shouldn't.
class FakeNfcPlatformWrapper implements NfcPlatformWrapper {
  FakeNfcPlatformWrapper({
    required this.uid,
    required this.responder,
    this.availabilityValue = 'enabled',
    this.scanError,
    this.techList = const <String>['android.nfc.tech.IsoDep'],
    this.pendingScan = false,
  });

  final List<int> uid;
  final Future<List<int>> Function(FakeNfcPlatformWrapper self, List<int> apdu)
      responder;
  final String availabilityValue;
  final Object? scanError;
  final List<String> techList;
  final bool pendingScan;

  final List<List<int>> sentApdus = <List<int>>[];
  final List<Set<String>> scanPollingOptions = <Set<String>>[];
  int scanCount = 0;
  int cancelCount = 0;

  Completer<NfcScanResult>? _pendingScanCompleter;

  @override
  Future<String> availability() async => availabilityValue;

  @override
  Future<void> cancel() async {
    cancelCount++;
    final completer = _pendingScanCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const NfcScanCancelledFailure());
    }
  }

  @override
  Future<T> runWithCard<T>({
    required Set<String> pollingOptions,
    Duration timeout = const Duration(seconds: 20),
    required Future<T> Function(RawNfcCard card) action,
  }) async {
    final result = await scan(
      pollingOptions: pollingOptions,
      timeout: timeout,
    );
    return action(result.card);
  }

  @override
  Future<NfcScanResult> scan({
    required Set<String> pollingOptions,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    scanCount++;
    scanPollingOptions.add(pollingOptions);
    if (scanError != null) throw scanError!;
    if (pendingScan) {
      final completer = Completer<NfcScanResult>();
      _pendingScanCompleter = completer;
      return completer.future;
    }
    return NfcScanResult(
      card: RawNfcCard(
        uid: Uint8List.fromList(uid),
        techList: techList,
        transceive: (apdu) async {
          sentApdus.add(apdu.toList());
          return Uint8List.fromList(await responder(this, apdu.toList()));
        },
      ),
    );
  }
}

const List<int> _mandiriSelect = <int>[
  0x00, 0xA4, 0x04, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
];
const List<int> _flazzSelect = <int>[
  0x00, 0xA4, 0x04, 0x00, 0x0B, 0xA0, 0x00, 0x00, 0x00, 0x18, 0x0F, 0x00, 0x00,
  0x01, 0x80, 0x01,
];
const List<int> _brizziSelect = <int>[
  0x90, 0x5A, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00,
];
const List<int> _tapCashSelect = <int>[
  0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x42, 0x4E, 0x49, 0x10, 0x00,
  0x01,
];
const List<int> _readBinaryBalance = <int>[0x00, 0xB5, 0x00, 0x00, 0x0A];
const List<int> _brizziBalance = <int>[
  0x90, 0x6C, 0x00, 0x00, 0x01, 0x00, 0x00,
];

List<int> _failureSw() => <int>[0x6A, 0x82];

/// Only [wanted]'s SELECT answers 9000; the others fail. Balance reads answer
/// with [balancePayload] (data only, SW 9000 appended automatically).
FakeNfcPlatformWrapper fakeCardFor({
  List<int> wanted = _mandiriSelect,
  List<int> balancePayload = const <int>[0x00, 0x00, 0x30, 0x39],
  String availability = 'enabled',
  List<int> uid = const <int>[0x04, 0xAB, 0xCD, 0xEF],
  Object? scanError,
  List<String> techList = const <String>['android.nfc.tech.IsoDep'],
}) {
  return FakeNfcPlatformWrapper(
    uid: uid,
    availabilityValue: availability,
    scanError: scanError,
    techList: techList,
    responder: (self, apdu) async {
      if (_sameApdu(apdu, wanted)) return <int>[0x90, 0x00];
      if (_sameApdu(apdu, _readBinaryBalance) ||
          _sameApdu(apdu, _brizziBalance)) {
        return <int>[...balancePayload, 0x90, 0x00];
      }
      return _failureSw();
    },
  );
}

bool _sameApdu(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('NfcService availability', () {
    test("availability 'unsupported' -> isAvailable false, isEnabled false",
        () async {
      final platform = fakeCardFor(availability: 'unsupported');
      final service = NfcService(platformWrapper: platform);

      expect(await service.isAvailable(), const Right<Failure, bool>(false));
      expect(await service.isEnabled(), const Right<Failure, bool>(false));
    });

    test("availability 'disabled' -> isAvailable true, isEnabled false",
        () async {
      final platform = fakeCardFor(availability: 'disabled');
      final service = NfcService(platformWrapper: platform);

      expect(await service.isAvailable(), const Right<Failure, bool>(true));
      expect(await service.isEnabled(), const Right<Failure, bool>(false));
    });
  });

  group('NfcService.readCardUid', () {
    test('returns lowercase hex with no separators', () async {
      final platform = fakeCardFor(uid: const <int>[0x04, 0xAB, 0x0F, 0xFF]);
      final service = NfcService(platformWrapper: platform);

      final result = await service.readCardUid();

      expect(result, const Right<Failure, String>('04ab0fff'));
      expect(platform.scanPollingOptions.single, <String>{'iso14443', 'iso15693'});
      expect(platform.sentApdus, isEmpty);
    });

    test('returns Left and does not rethrow when the platform throws',
        () async {
      final platform = fakeCardFor(scanError: Exception('adapter off'));
      final service = NfcService(platformWrapper: platform);

      final result = await service.readCardUid();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Failed to read NFC card UID'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left(ServerFailure) on scan timeout', () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x01],
        responder: (self, apdu) async => <int>[0x90, 0x00],
        scanError: TimeoutException('NFC scan timed out'),
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readCardUid();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, contains('timed out')),
        (_) => fail('Expected Left'),
      );
    });
  });

  group('NfcService.cancelCardRead', () {
    test('mid-scan cancel -> Left(NfcScanCancelledFailure), not ServerFailure',
        () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        responder: (self, apdu) async => <int>[0x90, 0x00],
        pendingScan: true,
      );
      final service = NfcService(platformWrapper: platform);

      final pending = service.readCardUid();
      await service.cancelCardRead();
      final result = await pending;

      expect(platform.cancelCount, 1);
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<NfcScanCancelledFailure>());
          expect(failure, isNot(isA<ServerFailure>()));
          expect(failure.message, 'NFC scan cancelled');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('mid-scan cancel of readEmoneyBalance -> NfcScanCancelledFailure',
        () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        responder: (self, apdu) async => <int>[0x90, 0x00],
        pendingScan: true,
      );
      final service = NfcService(platformWrapper: platform);

      final pending = service.readEmoneyBalance();
      await service.cancelCardRead();
      final result = await pending;

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<NfcScanCancelledFailure>());
          expect(failure, isNot(isA<ServerFailure>()));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('DefaultNfcPlatformWrapper session teardown', () {
    test('runWithCard closes the NFC session on the timeout path', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var disableReaderModeCalls = 0;

      ByteData? encode(Object? value) =>
          HostApiPigeon.pigeonChannelCodec.encodeMessage(<Object?>[value]);
      ByteData? encodeEmpty() =>
          HostApiPigeon.pigeonChannelCodec.encodeMessage(<Object?>[]);

      messenger.setMockMessageHandler(
        '${_host}nfcAdapterIsEnabled',
        (message) async => encode(true),
      );
      messenger.setMockMessageHandler(
        '${_host}nfcAdapterEnableReaderMode',
        (message) async => encodeEmpty(),
      );
      messenger.setMockMessageHandler(
        '${_host}nfcAdapterDisableReaderMode',
        (message) async {
          disableReaderModeCalls++;
          return encodeEmpty();
        },
      );

      final wrapper = DefaultNfcPlatformWrapper();

      await expectLater(
        wrapper.runWithCard<void>(
          pollingOptions: const <String>{'iso14443'},
          timeout: const Duration(milliseconds: 50),
          action: (card) async {},
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(disableReaderModeCalls, greaterThanOrEqualTo(1));
    });
  });

  group('NfcService.readEmoneyBalance', () {
    test('detects mandiri e-money and parses balance 12345', () async {
      final platform = fakeCardFor(
        wanted: _mandiriSelect,
        balancePayload: const <int>[0x00, 0x00, 0x30, 0x39],
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (balance) {
          expect(balance.brand, EmoneyCardBrand.mandiriEmoney);
          expect(balance.balanceRupiah, 12345);
          expect(balance.cardUid, '04abcdef');
          expect(balance.recentTransactions, isEmpty);
        },
      );
      expect(platform.scanPollingOptions.single, <String>{'iso14443'});
      // Only mandiri is probed because it succeeds first.
      expect(platform.sentApdus.first, _mandiriSelect);
      expect(platform.sentApdus.last, _readBinaryBalance);
    });

    test('returns Left when no brand SELECT succeeds', () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        responder: (self, apdu) async => _failureSw(),
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(
          failure.message,
          contains('Unrecognized or unsupported e-money card'),
        ),
        (_) => fail('Expected Left'),
      );
    });

    test('expectedCardUid mismatch -> Left and no balance APDU is sent',
        () async {
      final platform = fakeCardFor(uid: const <int>[0x04, 0xAB, 0xCD, 0xEF]);
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance(
        expectedCardUid: '0011223344',
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure.message, 'Card UID mismatch'),
        (_) => fail('Expected Left'),
      );
      expect(platform.sentApdus, isEmpty);
    });

    test('expectedCardUid match (case-insensitive) proceeds to read', () async {
      final platform = fakeCardFor(uid: const <int>[0x04, 0xAB, 0xCD, 0xEF]);
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance(
        expectedCardUid: '04ABCDEF',
      );

      expect(result.isRight(), isTrue);
      expect(platform.sentApdus, isNotEmpty);
    });

    test('accepts a Type B-only card (no IsoDep/NfcA tech)', () async {
      final platform = fakeCardFor(
        wanted: _mandiriSelect,
        techList: const <String>['android.nfc.tech.NfcB'],
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (balance) {
          expect(balance.brand, EmoneyCardBrand.mandiriEmoney);
          expect(balance.balanceRupiah, 12345);
          expect(balance.cardUid, '04abcdef');
        },
      );
    });

    test('real wrapper accepts a Type B-only card and transceives over nfcB',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final typeBTransceiveArgs = <List<Object?>>[];
      final typeATransceiveArgs = <List<Object?>>[];

      ByteData? encode(Object? value) =>
          HostApiPigeon.pigeonChannelCodec.encodeMessage(<Object?>[value]);
      ByteData? encodeEmpty() =>
          HostApiPigeon.pigeonChannelCodec.encodeMessage(<Object?>[]);

      messenger.setMockMessageHandler(
        '${_host}nfcAdapterIsEnabled',
        (message) async => encode(true),
      );
      messenger.setMockMessageHandler(
        '${_host}nfcAdapterEnableReaderMode',
        (message) async => encodeEmpty(),
      );
      messenger.setMockMessageHandler(
        '${_host}nfcAdapterDisableReaderMode',
        (message) async => encodeEmpty(),
      );
      messenger.setMockMessageHandler(
        '${_host}nfcATransceive',
        (message) async {
          typeATransceiveArgs.add(
            HostApiPigeon.pigeonChannelCodec.decodeMessage(message)
                as List<Object?>,
          );
          return encode(Uint8List.fromList(<int>[0x6A, 0x82]));
        },
      );
      messenger.setMockMessageHandler(
        '${_host}nfcBTransceive',
        (message) async {
          final args = HostApiPigeon.pigeonChannelCodec.decodeMessage(message)
              as List<Object?>;
          typeBTransceiveArgs.add(args);
          final apdu = (args[1]! as Uint8List).toList();
          if (_sameApdu(apdu, _mandiriSelect)) {
            return encode(Uint8List.fromList(<int>[0x90, 0x00]));
          }
          if (_sameApdu(apdu, _readBinaryBalance)) {
            return encode(
              Uint8List.fromList(<int>[0x00, 0x00, 0x30, 0x39, 0x90, 0x00]),
            );
          }
          return encode(Uint8List.fromList(_failureSw()));
        },
      );

      final tag = TagPigeon(
        handle: 'typeb',
        id: Uint8List.fromList(const <int>[0x04, 0xAB, 0xCD, 0xEF]),
        techList: <String>['android.nfc.tech.NfcB'],
        nfcB: NfcBPigeon(
          applicationData: Uint8List(0),
          protocolInfo: Uint8List(0),
        ),
      );

      final service = NfcService(platformWrapper: DefaultNfcPlatformWrapper());
      final pending = service.readEmoneyBalance();
      // The plugin registers its inbound tag handler while starting the
      // reader mode, so the tag may only be delivered after that.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await messenger.handlePlatformMessage(
        '${_flutter}onTagDiscovered',
        HostApiPigeon.pigeonChannelCodec.encodeMessage(<Object?>[tag]),
        (_) {},
      );
      final result = await pending;

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (balance) {
          expect(balance.brand, EmoneyCardBrand.mandiriEmoney);
          expect(balance.balanceRupiah, 12345);
          expect(balance.cardUid, '04abcdef');
        },
      );
      expect(typeBTransceiveArgs, isNotEmpty);
      expect(typeBTransceiveArgs[0][0], 'typeb');
      expect(
        (typeBTransceiveArgs[0][1]! as Uint8List).toList(),
        _mandiriSelect,
      );
      expect(typeATransceiveArgs, isEmpty);
    });

    test('unreadable card -> NfcCardUnsupportedFailure, not a scan timeout',
        () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        techList: const <String>['android.nfc.tech.NfcB'],
        responder: (self, apdu) async => _failureSw(),
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<NfcCardUnsupportedFailure>());
          expect(failure, isNot(isA<NfcScanTimeoutFailure>()));
          expect(failure.message, 'Unrecognized or unsupported e-money card');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('card without transceive capability -> NfcCardUnsupportedFailure',
        () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        responder: (self, apdu) async => _failureSw(),
        scanError: UnsupportedError(
          'Discovered NFC tag has no transceive capability',
        ),
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<NfcCardUnsupportedFailure>());
          expect(failure.message, 'Unrecognized or unsupported e-money card');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('a read-only guard violation stays loud, not cardUnsupported', () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        responder: (self, apdu) async => _failureSw(),
        scanError: UnsupportedError(
          'Refusing to send mutating NFC APDU with INS 0xd6',
        ),
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isNot(isA<NfcCardUnsupportedFailure>()));
          expect(failure.message, contains('Failed to read e-money balance'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('EmoneyApduParser (fixture driven)', () {
    test('all four brands expose the documented SELECT/BALANCE bytes', () {
      expect(EmoneyApduProfile.values.map((p) => p.brand), <EmoneyCardBrand>[
        EmoneyCardBrand.mandiriEmoney,
        EmoneyCardBrand.bcaFlazz,
        EmoneyCardBrand.briBrizzi,
        EmoneyCardBrand.bniTapCash,
      ]);
      expect(EmoneyApduProfile.mandiriEmoney.selectApdu, _mandiriSelect);
      expect(EmoneyApduProfile.mandiriEmoney.balanceApdu, _readBinaryBalance);
      expect(EmoneyApduProfile.bcaFlazz.selectApdu, _flazzSelect);
      expect(EmoneyApduProfile.bcaFlazz.balanceApdu, _readBinaryBalance);
      expect(EmoneyApduProfile.briBrizzi.selectApdu, _brizziSelect);
      expect(EmoneyApduProfile.briBrizzi.balanceApdu, _brizziBalance);
      expect(EmoneyApduProfile.bniTapCash.selectApdu, _tapCashSelect);
      expect(EmoneyApduProfile.bniTapCash.balanceApdu, _readBinaryBalance);
    });

    test('isSuccessStatus accepts 9000, 61xx and 6Cxx only', () {
      expect(NfcService.isSuccessStatus(_bytes([0x90, 0x00])), isTrue);
      expect(NfcService.isSuccessStatus(_bytes([0x61, 0x1E])), isTrue);
      expect(NfcService.isSuccessStatus(_bytes([0x6C, 0x20])), isTrue);
      expect(NfcService.isSuccessStatus(_bytes([0x6A, 0x82])), isFalse);
      expect(NfcService.isSuccessStatus(_bytes([0x90])), isFalse);
    });

    test('parseBalanceBytes reads 4 data bytes big-endian, SW stripped', () {
      expect(
        NfcService.parseBalanceBytes(_bytes([0x00, 0x00, 0x30, 0x39, 0x90, 0x00])),
        12345,
      );
      expect(
        NfcService.parseBalanceBytes(_bytes([0x00, 0x01, 0x00, 0x00, 0x90, 0x00])),
        65536,
      );
      // Short data area must not throw.
      expect(NfcService.parseBalanceBytes(_bytes([0x90, 0x00])), 0);
    });

    test('parseBalanceBytes reads 4 data bytes little-endian for briBrizzi', () {
      expect(
        NfcService.parseBalanceBytes(
          _bytes([0x39, 0x30, 0x00, 0x00, 0x90, 0x00]),
          EmoneyCardBrand.briBrizzi,
        ),
        12345,
      );
      expect(
        NfcService.parseBalanceBytes(
          _bytes([0x00, 0x00, 0x01, 0x00, 0x90, 0x00]),
          EmoneyCardBrand.briBrizzi,
        ),
        65536,
      );
    });

    test('readEmoneyBalance decodes Brizzi balance in little-endian', () async {
      final platform = fakeCardFor(
        wanted: _brizziSelect,
        balancePayload: const <int>[0x39, 0x30, 0x00, 0x00],
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (balance) {
          expect(balance.brand, EmoneyCardBrand.briBrizzi);
          expect(balance.balanceRupiah, 12345);
        },
      );
    });

    test('per-brand SELECT fixtures resolve to the expected profile', () async {
      final fixtures = <List<int>, EmoneyCardBrand>{
        _mandiriSelect: EmoneyCardBrand.mandiriEmoney,
        _flazzSelect: EmoneyCardBrand.bcaFlazz,
        _brizziSelect: EmoneyCardBrand.briBrizzi,
        _tapCashSelect: EmoneyCardBrand.bniTapCash,
      };

      for (final entry in fixtures.entries) {
        final platform = fakeCardFor(
          wanted: entry.key,
          balancePayload: const <int>[0x00, 0x00, 0x10, 0x00],
        );
        final service = NfcService(platformWrapper: platform);

        final result = await service.readEmoneyBalance();

        expect(result.isRight(), isTrue, reason: 'fixture ${entry.key}');
        result.fold(
          (_) => fail('Expected Right'),
          (balance) => expect(balance.brand, entry.value),
        );
      }
    });

    test('parseTransactions reads full 16-byte records, max 3', () {
      final payload = <int>[
        // balance 10000
        0x00, 0x00, 0x27, 0x10,
        // record 1: -5000 "KRL"
        ..._signed32(-5000), ..._label('KRL'),
        // record 2: +20000 "TOPUP"
        ..._signed32(20000), ..._label('TOPUP'),
        // record 3: -1250
        ..._signed32(-1250), ..._label('BUS'),
        // record 4: must be dropped (max 3)
        ..._signed32(-1), ..._label('EXTRA'),
      ];
      final response = _bytes([...payload, 0x90, 0x00]);

      final transactions = NfcService.parseTransactions(response);

      expect(transactions.length, 3);
      expect(transactions[0].amountRupiah, -5000);
      expect(transactions[0].label, 'KRL');
      expect(transactions[1].amountRupiah, 20000);
      expect(transactions[1].label, 'TOPUP');
      expect(transactions[2].amountRupiah, -1250);
    });

    test('parseTransactions returns empty list on ambiguous/short payloads',
        () {
      expect(NfcService.parseTransactions(_bytes([0x90, 0x00])), isEmpty);
      expect(
        NfcService.parseTransactions(
          _bytes([0x00, 0x00, 0x27, 0x10, 0x01, 0x02, 0x03, 0x90, 0x00]),
        ),
        isEmpty,
      );
    });
  });

  group('read-only safety guard', () {
    test('forbidden INS list contains every mutating code', () {
      for (final ins in <int>[
        0xD0, 0xD1, 0xD6, 0xD7, 0xD8, 0xDC, 0xE2, 0xE0, 0xD2, 0xD3,
      ]) {
        expect(
          () => NfcService.assertInsAllowed(<int>[0x00, ins, 0x00, 0x00, 0x00]),
          throwsA(isA<UnsupportedError>()),
          reason: 'INS 0x${ins.toRadixString(16)} must be rejected',
        );
      }
    });

    test('read-only APDUs pass the guard', () {
      expect(
        () => NfcService.assertInsAllowed(_readBinaryBalance),
        returnsNormally,
      );
      expect(() => NfcService.assertInsAllowed(_mandiriSelect), returnsNormally);
      expect(() => NfcService.assertInsAllowed(_brizziSelect), returnsNormally);
      expect(() => NfcService.assertInsAllowed(_brizziBalance), returnsNormally);
    });

    test('guard fires from the live transceive path', () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB],
        responder: (self, apdu) async => <int>[0x90, 0x00],
      );
      final service = NfcService(platformWrapper: platform);

      await service.readEmoneyBalance();

      expect(platform.sentApdus, isNotEmpty);
      for (final apdu in platform.sentApdus) {
        expect(
          () => NfcService.assertInsAllowed(apdu),
          returnsNormally,
          reason: 'service must never emit a mutating APDU',
        );
      }
    });
  });

  group('EmoneyBalance serialization', () {
    test('toJson/fromJson round-trips a balance with 2 transactions', () {
      const original = EmoneyBalance(
        brand: EmoneyCardBrand.bcaFlazz,
        cardUid: '04abcdef',
        balanceRupiah: 12345,
        recentTransactions: <EmoneyTransaction>[
          EmoneyTransaction(amountRupiah: -5000, label: 'KRL'),
          EmoneyTransaction(amountRupiah: 20000),
        ],
      );

      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored = EmoneyBalance.fromJson(decoded as Map<String, dynamic>);

      expect(restored.brand, original.brand);
      expect(restored.cardUid, original.cardUid);
      expect(restored.balanceRupiah, original.balanceRupiah);
      expect(restored.recentTransactions.length, 2);
      expect(restored.recentTransactions[0].amountRupiah, -5000);
      expect(restored.recentTransactions[0].label, 'KRL');
      expect(restored.recentTransactions[1].amountRupiah, 20000);
      expect(restored.recentTransactions[1].label, isNull);
    });
  });

  group('6Cxx APDU continuation handling', () {
    test('Case 3 APDU appends sw2, Case 2 APDU replaces last byte with sw2', () async {
      final platform = FakeNfcPlatformWrapper(
        uid: const <int>[0x04, 0xAB, 0xCD, 0xEF],
        responder: (self, apdu) async {
          if (_sameApdu(apdu, _mandiriSelect)) {
            return <int>[0x6C, 0x08];
          }
          if (apdu.length == 14 &&
              _sameApdu(apdu.sublist(0, 13), _mandiriSelect) &&
              apdu[13] == 0x08) {
            return <int>[0x90, 0x00];
          }
          if (_sameApdu(apdu, _readBinaryBalance)) {
            return <int>[0x6C, 0x04];
          }
          if (apdu.length == 5 &&
              _sameApdu(apdu.sublist(0, 4), <int>[0x00, 0xB5, 0x00, 0x00]) &&
              apdu[4] == 0x04) {
            return <int>[0x00, 0x00, 0x30, 0x39, 0x90, 0x00];
          }
          return _failureSw();
        },
      );
      final service = NfcService(platformWrapper: platform);

      final result = await service.readEmoneyBalance();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (balance) {
          expect(balance.brand, EmoneyCardBrand.mandiriEmoney);
          expect(balance.balanceRupiah, 12345);
        },
      );
      expect(platform.sentApdus.length, 4);
      expect(platform.sentApdus[0], _mandiriSelect);
      expect(platform.sentApdus[1], [..._mandiriSelect, 0x08]);
      expect(platform.sentApdus[2], _readBinaryBalance);
      expect(platform.sentApdus[3], <int>[0x00, 0xB5, 0x00, 0x00, 0x04]);
    });
  });
}

Uint8List _bytes(List<int> data) => Uint8List.fromList(data);List<int> _signed32(int value) {
  final unsigned = value & 0xFFFFFFFF;
  return <int>[
    (unsigned >> 24) & 0xFF,
    (unsigned >> 16) & 0xFF,
    (unsigned >> 8) & 0xFF,
    unsigned & 0xFF,
  ];
}

List<int> _label(String text) {
  final bytes = text.codeUnits.take(12).toList();
  while (bytes.length < 12) {
    bytes.add(0x00);
  }
  return bytes;
}
