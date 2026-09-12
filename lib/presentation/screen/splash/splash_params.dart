import 'package:flutter/material.dart';

class SplashParams {
  final Duration? duration;
  final Widget? nextScreen;
  final String? splashAsset;
  final VoidCallback? onComplete;

  const SplashParams({
    this.duration,
    this.nextScreen,
    this.splashAsset,
    this.onComplete,
  });
}
