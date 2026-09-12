import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';

class PairingParams {
  final QrScannerControllerBase? controller;
  final PairingParser? parser;
  final DateTime? currentTime;
  final void Function(PairingPayload payload)? onPayloadScanned;
  final Widget Function(
    BuildContext context,
    void Function(String barcode) onDetect,
  )? scannerWidgetBuilder;

  const PairingParams({
    this.controller,
    this.parser,
    this.currentTime,
    this.onPayloadScanned,
    this.scannerWidgetBuilder,
  });
}
