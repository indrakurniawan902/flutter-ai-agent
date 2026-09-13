import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:nfc_card_reader/core/errors/nfc_exception.dart';
import 'package:nfc_card_reader/core/utils/hex_utils.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

class NfcScannerService {
  const NfcScannerService();

  Future<NFCAvailability> availability() {
    return FlutterNfcKit.nfcAvailability;
  }

  Future<void> ensureAvailable() async {
    final status = await availability();
    switch (status) {
      case NFCAvailability.available:
        return;
      case NFCAvailability.disabled:
        throw const NfcDisabledException();
      case NFCAvailability.not_supported:
        throw const NfcUnavailableException();
    }
  }

  Future<NfcCard> pollAndNormalize({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await ensureAvailable();

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: timeout,
        iosAlertMessage: 'Tempelkan kartu NFC di dekat iPhone',
        iosMultipleTagMessage:
            'Lebih dari satu kartu terdeteksi. Sisakan satu kartu saja.',
        androidCheckNDEF: true,
        readIso14443A: true,
        readIso14443B: true,
        readIso18092: true,
        readIso15693: true,
      );
      return normalizeTag(tag);
    } on NfcException {
      rethrow;
    } catch (error) {
      throw mapPlatformError(error);
    }
  }

  Future<String> transceiveHex(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final result = await FlutterNfcKit.transceive(command, timeout: timeout);
      return result;
    } catch (error) {
      throw mapPlatformError(error);
    }
  }

  Future<void> finish({
    String? iosAlertMessage,
    String? iosErrorMessage,
  }) async {
    try {
      await FlutterNfcKit.finish(
        iosAlertMessage: iosAlertMessage,
        iosErrorMessage: iosErrorMessage,
      );
    } catch (_) {
      // Session may already be closed; never leave callers hanging.
    }
  }

  NfcCard normalizeTag(NFCTag tag) {
    final typeName = tag.type.name;
    final technology = mapTechnology(tag);
    final raw = <String, String>{
      'id': tag.id,
      'type': typeName,
      'standard': tag.standard,
      if (tag.atqa != null) 'atqa': tag.atqa!,
      if (tag.sak != null) 'sak': tag.sak!,
      if (tag.historicalBytes != null) 'historicalBytes': tag.historicalBytes!,
      if (tag.protocolInfo != null) 'protocolInfo': tag.protocolInfo!,
      if (tag.manufacturer != null) 'manufacturer': tag.manufacturer!,
      if (tag.systemCode != null) 'systemCode': tag.systemCode!,
      if (tag.applicationData != null) 'applicationData': tag.applicationData!,
      if (tag.ndefAvailable != null)
        'ndefAvailable': tag.ndefAvailable!.toString(),
      if (tag.ndefType != null) 'ndefType': tag.ndefType!,
      if (tag.ndefCapacity != null)
        'ndefCapacity': tag.ndefCapacity!.toString(),
      if (tag.mifareInfo != null) 'mifareInfo': tag.mifareInfo.toString(),
    };

    final technologies = <String>[
      typeName,
      tag.standard,
      if (tag.ndefAvailable == true) 'NDEF',
    ].where((value) => value.isNotEmpty).toList();

    return NfcCard(
      id: HexUtils.normalize(tag.id).isEmpty
          ? tag.id
          : HexUtils.normalize(tag.id),
      type: typeName,
      standard: tag.standard,
      technology: technology,
      manufacturer: emptyToNull(tag.manufacturer),
      atqa: emptyToNull(tag.atqa),
      sak: emptyToNull(tag.sak),
      historicalBytes: emptyToNull(tag.historicalBytes),
      systemCode: emptyToNull(tag.systemCode),
      protocolInfo: emptyToNull(tag.protocolInfo),
      applicationData: emptyToNull(tag.applicationData),
      ndefAvailable: tag.ndefAvailable,
      ndefType: emptyToNull(tag.ndefType),
      ndefCapacity: tag.ndefCapacity,
      mifareType: tag.mifareInfo?.type,
      availableTechnologies: technologies,
      rawMetadata: raw,
    );
  }

  NfcTechnology mapTechnology(NFCTag tag) {
    switch (tag.type) {
      case NFCTagType.iso7816:
        return NfcTechnology.iso7816;
      case NFCTagType.iso18092:
        return NfcTechnology.nfcF;
      case NFCTagType.mifare_classic:
        return NfcTechnology.mifareClassic;
      case NFCTagType.mifare_ultralight:
        return NfcTechnology.mifareUltralight;
      case NFCTagType.mifare_plus:
        return NfcTechnology.mifarePlus;
      case NFCTagType.mifare_desfire:
        return NfcTechnology.mifareDesfire;
      case NFCTagType.iso15693:
        return NfcTechnology.nfcV;
      case NFCTagType.webusb:
        return NfcTechnology.webusb;
      case NFCTagType.unknown:
        final standard = tag.standard.toLowerCase();
        if (standard.contains('14443-a') || standard.contains('nfc-a')) {
          return NfcTechnology.nfcA;
        }
        if (standard.contains('14443-b') || standard.contains('nfc-b')) {
          return NfcTechnology.nfcB;
        }
        if (standard.contains('18092') || standard.contains('felica')) {
          return NfcTechnology.nfcF;
        }
        return NfcTechnology.unknown;
    }
  }

  NfcException mapPlatformError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('timeout') || text.contains('408')) {
      return const NfcTimeoutException();
    }
    if (text.contains('tag was lost') ||
        text.contains('tag_lost') ||
        text.contains('tag lost')) {
      return const NfcTagLostException();
    }
    if (text.contains('disabled') || text.contains('not enabled')) {
      return const NfcDisabledException();
    }
    if (text.contains('not supported') || text.contains('unavailable')) {
      return const NfcUnavailableException();
    }
    if (text.contains('permission') || text.contains('denied')) {
      return const NfcPermissionException();
    }
    if (text.contains('unsupported')) {
      return const NfcUnsupportedException();
    }
    return NfcReadException('Gagal membaca kartu NFC: $error');
  }

  String? emptyToNull(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }
}
