import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';

/// Plain-Dart view of a discovered tag. Holding the [transceive] callback here
/// keeps the whole APDU flow fakeable without any MethodChannel.
class RawNfcCard {
  final Uint8List uid;
  final List<String> techList;
  final Future<Uint8List> Function(Uint8List) transceive;

  const RawNfcCard({
    required this.uid,
    required this.techList,
    required this.transceive,
  });
}

class NfcScanResult {
  final RawNfcCard card;

  const NfcScanResult({required this.card});
}

/// Test/DI seam over `nfc_manager`. [DefaultNfcPlatformWrapper] is the only
/// production implementation that touches the plugin.
abstract class NfcPlatformWrapper {
  /// Returns `'enabled'`, `'disabled'` or `'unsupported'`.
  Future<String> availability();

  Future<NfcScanResult> scan({
    required Set<String> pollingOptions,
    Duration timeout,
  });

  Future<T> runWithCard<T>({
    required Set<String> pollingOptions,
    Duration timeout,
    required Future<T> Function(RawNfcCard card) action,
  });

  /// Cancels an in-flight [runWithCard] or [scan] and closes the session.
  /// Never throws.
  Future<void> cancel();
}

class NfcPlatformWrapperRegistry {
  static NfcPlatformWrapper instance = DefaultNfcPlatformWrapper();
}

class DefaultNfcPlatformWrapper implements NfcPlatformWrapper {
  void Function()? _canceller;

  @override
  Future<String> availability() async {
    final availability = await NfcManager.instance.checkAvailability();
    switch (availability) {
      case NfcAvailability.enabled:
        return 'enabled';
      case NfcAvailability.disabled:
        return 'disabled';
      case NfcAvailability.unsupported:
        return 'unsupported';
    }
  }

  @override
  Future<T> runWithCard<T>({
    required Set<String> pollingOptions,
    Duration timeout = kNfcScanTimeout,
    required Future<T> Function(RawNfcCard card) action,
  }) async {
    final completer = Completer<T>();
    final polling = pollingOptions.map(_mapPollingOption).toSet();
    // Install the canceller before awaiting session startup so a cancel that
    // arrives while startSession is still in flight is not a silent no-op.
    _canceller = () {
      if (!completer.isCompleted) {
        completer.completeError(const NfcScanCancelledFailure());
      }
    };
    try {
      await NfcManager.instance.startSession(
        pollingOptions: polling,
        onDiscovered: (tag) async {
          if (completer.isCompleted) return;
          final card = _toRawCard(tag);
          if (card == null) {
            completer.completeError(
              UnsupportedError('Discovered NFC tag has no transceive capability'),
            );
            return;
          }
          try {
            final result = await action(card);
            if (!completer.isCompleted) {
              completer.complete(result);
            }
          } catch (e, st) {
            if (!completer.isCompleted) {
              completer.completeError(e, st);
            }
          }
        },
      );
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('NFC scan timed out', timeout),
      );
    } finally {
      _canceller = null;
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {
        // Session may already be closed; never leave callers hanging.
      }
    }
  }

  @override
  Future<void> cancel() async {
    try {
      _canceller?.call();
    } catch (_) {
      // Cancellation is best-effort; a throwing canceller must not leak.
    }
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // Session may already be closed.
    }
  }

  @override
  Future<NfcScanResult> scan({
    required Set<String> pollingOptions,
    Duration timeout = kNfcScanTimeout,
  }) async {
    return runWithCard<NfcScanResult>(
      pollingOptions: pollingOptions,
      timeout: timeout,
      action: (card) async => NfcScanResult(card: card),
    );
  }

  RawNfcCard? _toRawCard(NfcTag tag) {
    final androidTag = NfcTagAndroid.from(tag);
    if (androidTag == null) return null;
    final transceive = IsoDepAndroid.from(tag)?.transceive ??
        NfcAAndroid.from(tag)?.transceive ??
        NfcBAndroid.from(tag)?.transceive;
    if (transceive == null) return null;
    return RawNfcCard(
      uid: androidTag.id,
      techList: androidTag.techList,
      transceive: transceive,
    );
  }

  NfcPollingOption _mapPollingOption(String option) {
    switch (option) {
      case 'iso14443':
        return NfcPollingOption.iso14443;
      case 'iso15693':
        return NfcPollingOption.iso15693;
      case 'iso18092':
        return NfcPollingOption.iso18092;
      default:
        throw UnsupportedError('Unsupported NFC polling option: $option');
    }
  }
}

/// APDU profile for one e-money brand.
class EmoneyApduProfile {
  final EmoneyCardBrand brand;
  final List<int> selectApdu;
  final List<int> balanceApdu;

  const EmoneyApduProfile({
    required this.brand,
    required this.selectApdu,
    required this.balanceApdu,
  });

  static const mandiriEmoney = EmoneyApduProfile(
    brand: EmoneyCardBrand.mandiriEmoney,
    selectApdu: <int>[
      0x00, 0xA4, 0x04, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x01,
    ],
    balanceApdu: <int>[0x00, 0xB5, 0x00, 0x00, 0x0A],
  );

  static const bcaFlazz = EmoneyApduProfile(
    brand: EmoneyCardBrand.bcaFlazz,
    selectApdu: <int>[
      0x00, 0xA4, 0x04, 0x00, 0x0B, 0xA0, 0x00, 0x00, 0x00, 0x18, 0x0F, 0x00,
      0x00, 0x01, 0x80, 0x01,
    ],
    balanceApdu: <int>[0x00, 0xB5, 0x00, 0x00, 0x0A],
  );

  static const briBrizzi = EmoneyApduProfile(
    brand: EmoneyCardBrand.briBrizzi,
    selectApdu: <int>[0x90, 0x5A, 0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00],
    balanceApdu: <int>[0x90, 0x6C, 0x00, 0x00, 0x01, 0x00, 0x00],
  );

  static const bniTapCash = EmoneyApduProfile(
    brand: EmoneyCardBrand.bniTapCash,
    selectApdu: <int>[
      0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x42, 0x4E, 0x49, 0x10,
      0x00, 0x01,
    ],
    balanceApdu: <int>[0x00, 0xB5, 0x00, 0x00, 0x0A],
  );

  static const List<EmoneyApduProfile> values = <EmoneyApduProfile>[
    mandiriEmoney,
    bcaFlazz,
    briBrizzi,
    bniTapCash,
  ];
}

@LazySingleton(as: NfcServiceBase)
class NfcService implements NfcServiceBase {
  /// INS values that mutate/load a card. This service is read-only, so any
  /// attempt to send one is a programming error and must be loud.
  static const Set<int> _forbiddenIns = <int>{
    0xD0,
    0xD1,
    0xD6,
    0xD7,
    0xD8,
    0xDC,
    0xE2,
    0xE0,
    0xD2,
    0xD3,
  };

  final NfcPlatformWrapper _platform;

  NfcService({NfcPlatformWrapper? platformWrapper})
      : _platform = platformWrapper ?? NfcPlatformWrapperRegistry.instance;

  @factoryMethod
  factory NfcService.create() => NfcService();

  @override
  Future<Either<Failure, bool>> isAvailable() async {
    try {
      final availability = await _platform.availability();
      return Right(availability != 'unsupported');
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Failed to check NFC availability'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> isEnabled() async {
    try {
      final availability = await _platform.availability();
      return Right(availability == 'enabled');
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Failed to check NFC state'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, String>> readCardUid() async {
    try {
      final result = await _platform.scan(
        pollingOptions: const <String>{'iso14443', 'iso15693'},
      );
      return Right(bytesToHex(result.card.uid));
    } on NfcScanCancelledFailure {
      return const Left(NfcScanCancelledFailure());
    } on TimeoutException {
      return const Left(
        ServerFailure('NFC scan timed out. Please tap the card again.'),
      );
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Failed to read NFC card UID'),
        ),
      );
    }
  }

  @override
  Future<void> cancelCardRead() async {
    try {
      await _platform.cancel();
    } catch (_) {
      // Cancellation is best-effort; never surface to the caller.
    }
  }

  @override
  Future<Either<Failure, EmoneyBalance>> readEmoneyBalance({
    String? expectedCardUid,
  }) async {
    try {
      return await _platform.runWithCard<Either<Failure, EmoneyBalance>>(
        pollingOptions: const <String>{'iso14443'},
        action: (card) async {
          final uid = bytesToHex(card.uid);

          if (expectedCardUid != null &&
              expectedCardUid.toLowerCase() != uid.toLowerCase()) {
            return const Left(ServerFailure('Card UID mismatch'));
          }

          final profile = await _detectBrand(card);
          if (profile == null) {
            return const Left(NfcCardUnsupportedFailure());
          }

          final balanceResponse = await _transceive(card, profile.balanceApdu);
          return Right(
            EmoneyBalance(
              brand: profile.brand,
              cardUid: uid,
              balanceRupiah: parseBalanceBytes(balanceResponse, profile.brand),
              recentTransactions: parseTransactions(balanceResponse),
            ),
          );
        },
      );
    } on NfcScanCancelledFailure {
      return const Left(NfcScanCancelledFailure());
    } on TimeoutException {
      return const Left(NfcScanTimeoutFailure());
    } on UnsupportedError catch (e) {
      // Only the wrapper's deliberate no-transceive error means "unsupported
      // card". Anything else (notably the read-only guard in assertInsAllowed)
      // must stay loud: fall through to the generic branch, which logs via
      // FailureMessage.humanize.
      if (e.message == 'Discovered NFC tag has no transceive capability') {
        return const Left(NfcCardUnsupportedFailure());
      }
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Failed to read e-money balance'),
        ),
      );
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Failed to read e-money balance'),
        ),
      );
    }
  }

  Future<EmoneyApduProfile?> _detectBrand(RawNfcCard card) async {
    for (final profile in EmoneyApduProfile.values) {
      final response = await _transceive(card, profile.selectApdu);
      if (isSuccessStatus(response)) {
        return profile;
      }
    }
    return null;
  }

  /// Sends [apdu] and transparently resolves ISO 7816 continuations:
  /// `6C xx` (wrong Le) re-issues with the corrected Le, `61 xx` (more data)
  /// issues a GET RESPONSE.
  Future<Uint8List> _transceive(RawNfcCard card, List<int> apdu) async {
    assertInsAllowed(apdu);
    var currentApdu = apdu;
    var response = await card.transceive(Uint8List.fromList(currentApdu));
    var attempts = 0;
    while (response.length >= 2 && attempts < 3) {
      final sw1 = response[response.length - 2];
      final sw2 = response[response.length - 1];
      if (sw1 == 0x6C && currentApdu.isNotEmpty) {
        final isCase1 = currentApdu.length == 4;
        final isCase3 =
            currentApdu.length > 4 && currentApdu.length == 5 + currentApdu[4];
        final List<int> corrected;
        if (isCase1 || isCase3) {
          corrected = List<int>.from(currentApdu)..add(sw2);
        } else {
          corrected = List<int>.from(currentApdu);
          corrected[corrected.length - 1] = sw2;
        }
        assertInsAllowed(corrected);
        currentApdu = corrected;
        response = await card.transceive(Uint8List.fromList(currentApdu));
      } else if (sw1 == 0x61) {
        final getResponse = <int>[0x00, 0xC0, 0x00, 0x00, sw2];
        assertInsAllowed(getResponse);
        currentApdu = getResponse;
        response = await card.transceive(Uint8List.fromList(currentApdu));
      } else {
        break;
      }
      attempts++;
    }
    return response;
  }

  /// Guards against ever emitting a WRITE/DEBIT/UPDATE/LOAD APDU.
  @visibleForTesting
  static void assertInsAllowed(List<int> apdu) {
    final ins = apdu.length > 1 ? apdu[1] : -1;
    if (_forbiddenIns.contains(ins)) {
      throw UnsupportedError(
        'Refusing to send mutating NFC APDU with INS 0x${ins.toRadixString(16)}',
      );
    }
  }

  /// True for `90 00`, or a `61 xx` / `6C xx` continuation.
  @visibleForTesting
  static bool isSuccessStatus(Uint8List response) {
    if (response.length < 2) return false;
    final sw1 = response[response.length - 2];
    final sw2 = response[response.length - 1];
    if (sw1 == 0x90 && sw2 == 0x00) return true;
    return sw1 == 0x61 || sw1 == 0x6C;
  }

  /// Balance = first 4 data bytes. The trailing SW1/SW2 are stripped first,
  /// so the offset is 0 into the data area.
  /// BRI Brizzi / DESFire stores balance in Little-Endian order.
  /// Other cards store balance in Big-Endian order.
  @visibleForTesting
  static int parseBalanceBytes(
    Uint8List apduResponse, [
    EmoneyCardBrand? brand,
  ]) {
    final data = _dataArea(apduResponse);
    if (data.length < 4) return 0;
    if (brand == EmoneyCardBrand.briBrizzi) {
      return data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
    }
    return (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
  }

  /// Best-effort transaction parsing. Records are 16 bytes each (4-byte signed
  /// big-endian amount + 12-byte label) and live after the 4-byte balance.
  /// Only full records are read (max 3); anything ambiguous yields an empty
  /// list instead of guessing.
  @visibleForTesting
  static List<EmoneyTransaction> parseTransactions(Uint8List apduResponse) {
    try {
      final data = _dataArea(apduResponse);
      if (data.length < 20) return const <EmoneyTransaction>[];
      final transactions = <EmoneyTransaction>[];
      var offset = 4;
      while (transactions.length < 3 && offset + 16 <= data.length) {
        final record = data.sublist(offset, offset + 16);
        transactions.add(
          EmoneyTransaction(
            amountRupiah: _readSignedInt32(record, 0),
            label: _readAsciiLabel(record, 4, 12),
          ),
        );
        offset += 16;
      }
      return transactions;
    } catch (_) {
      return const <EmoneyTransaction>[];
    }
  }

  @visibleForTesting
  static String bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List _dataArea(Uint8List apduResponse) {
    if (apduResponse.length < 2) return Uint8List(0);
    return Uint8List.sublistView(apduResponse, 0, apduResponse.length - 2);
  }

  static int _readSignedInt32(Uint8List bytes, int offset) {
    final value = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    return value.toSigned(32);
  }

  static String? _readAsciiLabel(Uint8List bytes, int offset, int length) {
    final chars = <int>[];
    for (var i = offset; i < offset + length && i < bytes.length; i++) {
      final byte = bytes[i];
      if (byte == 0x00 || byte == 0xFF) break;
      if (byte >= 0x20 && byte <= 0x7E) chars.add(byte);
    }
    if (chars.isEmpty) return null;
    return String.fromCharCodes(chars).trim();
  }
}
