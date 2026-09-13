import 'package:equatable/equatable.dart';

class ProbeResult extends Equatable {
  final bool isSuccess;
  final String message;
  final int? latencyMs;
  final List<String> models;

  const ProbeResult({
    required this.isSuccess,
    required this.message,
    this.latencyMs,
    this.models = const [],
  });

  @override
  List<Object?> get props => [isSuccess, message, latencyMs, models];
}

abstract class ServerProfileProbeService {
  Future<ProbeResult> probeHermesNode({
    required String url,
    required String token,
  });

  Future<ProbeResult> probeOpenAi({
    required String url,
    required String apiKey,
    String? model,
  });
}
