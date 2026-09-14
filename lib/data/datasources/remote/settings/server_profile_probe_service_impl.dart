import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/services/settings/server_profile_probe_service.dart';

class ServerProfileProbeServiceImpl implements ServerProfileProbeService {
  final Dio _dio;

  ServerProfileProbeServiceImpl({Dio? dio}) : _dio = dio ?? Dio();

  @override
  Future<ProbeResult> probeHermesNode({
    required String url,
    required String token,
  }) async {
    final targetUrl = _normalizeHermesUrl(url);
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _dio.get<dynamic>(
        targetUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      if (response.statusCode == 200) {
        final models = _extractModels(response.data);
        final modelCount = models.length;
        final message =
            'Connected (${latency}ms)${modelCount > 0 ? ' • $modelCount models' : ''}';
        return ProbeResult(
          isSuccess: true,
          message: message,
          latencyMs: latency,
          models: models,
        );
      }

      return ProbeResult(
        isSuccess: false,
        message: 'Connection failed: HTTP ${response.statusCode}',
      );
    } catch (e) {
      stopwatch.stop();
      return _handleError(e);
    }
  }

  @override
  Future<ProbeResult> probeOpenAi({
    required String url,
    required String apiKey,
    String? model,
  }) async {
    final targetUrl = _normalizeOpenAiUrl(url);
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _dio.get<dynamic>(
        targetUrl,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      if (response.statusCode == 200) {
        final models = _extractModels(response.data);
        final modelCount = models.length;
        final message =
            'Connected (${latency}ms)${modelCount > 0 ? ' • $modelCount models' : ''}';
        return ProbeResult(
          isSuccess: true,
          message: message,
          latencyMs: latency,
          models: models,
        );
      }

      return ProbeResult(
        isSuccess: false,
        message: 'Connection failed: HTTP ${response.statusCode}',
      );
    } catch (e) {
      stopwatch.stop();
      return _handleError(e);
    }
  }

  String _normalizeHermesUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.startsWith('ws://')) {
      normalized = 'http://${normalized.substring(5)}';
    } else if (normalized.startsWith('wss://')) {
      normalized = 'https://${normalized.substring(6)}';
    }
    if (normalized.endsWith('/device/ws')) {
      normalized =
          normalized.substring(0, normalized.length - '/device/ws'.length);
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.endsWith('/models')) {
      normalized = '$normalized/models';
    }
    return normalized;
  }

  String _normalizeOpenAiUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.endsWith('/chat/completions')) {
      normalized =
          normalized.substring(0, normalized.length - '/chat/completions'.length);
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (!normalized.endsWith('/models')) {
      normalized = '$normalized/models';
    }
    return normalized;
  }

  List<String> _extractModels(dynamic data) {
    if (data is! Map) {
      return const [];
    }

    final rawData = data['data'];
    if (rawData is List) {
      final list = <String>[];
      for (final item in rawData) {
        if (item is Map && item['id'] is String) {
          final id = (item['id'] as String).trim();
          if (id.isNotEmpty) {
            list.add(id);
          }
        } else if (item is String) {
          final id = item.trim();
          if (id.isNotEmpty) {
            list.add(id);
          }
        }
      }
      return list;
    }

    final rawModels = data['models'];
    if (rawModels is List) {
      final list = <String>[];
      for (final item in rawModels) {
        if (item is String) {
          final id = item.trim();
          if (id.isNotEmpty) {
            list.add(id);
          }
        } else if (item is Map && item['id'] is String) {
          final id = (item['id'] as String).trim();
          if (id.isNotEmpty) {
            list.add(id);
          }
        }
      }
      return list;
    }

    return const [];
  }

  ProbeResult _handleError(Object error) {
    if (error is DioException) {
      final response = error.response;
      if (response != null) {
        final status = response.statusCode;
        final statusMessage = response.statusMessage ?? '';
        final msg = 'Connection failed: HTTP $status $statusMessage'.trim();
        return ProbeResult(isSuccess: false, message: msg);
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return const ProbeResult(
          isSuccess: false,
          message: 'Connection failed: Connection timed out',
        );
      }

      final detail = FailureMessage.humanize(
        error,
        context: 'Unexpected error',
      );
      return ProbeResult(
        isSuccess: false,
        message: 'Connection failed: $detail',
      );
    }

    return ProbeResult(
      isSuccess: false,
      message:
          'Connection failed: ${FailureMessage.humanize(error, context: 'Unexpected error')}',
    );
  }
}
