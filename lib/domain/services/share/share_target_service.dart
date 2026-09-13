import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:flutter_ai_agent/domain/entities/share/shared_payload.dart';

/// Abstraction over the platform share-intent plugin for testability.
abstract class ShareMediaProvider {
  Future<List<SharedMediaFile>> getInitialMedia();
  Stream<List<SharedMediaFile>> getMediaStream();
  Future<void> reset();
}

/// Default provider delegating to `receive_sharing_intent`.
@LazySingleton(as: ShareMediaProvider)
class ReceiveSharingIntentProvider implements ShareMediaProvider {
  @override
  Future<List<SharedMediaFile>> getInitialMedia() =>
      ReceiveSharingIntent.instance.getInitialMedia();

  @override
  Stream<List<SharedMediaFile>> getMediaStream() =>
      ReceiveSharingIntent.instance.getMediaStream();

  @override
  Future<void> reset() => ReceiveSharingIntent.instance.reset();
}

/// Listens to OS-level shared text, URLs, images, and files and maps them
/// to [SharedPayload] batches routed to chat prompts.
@lazySingleton
class ShareTargetService {
  final ShareMediaProvider _provider;
  final StreamController<List<SharedPayload>> _controller =
      StreamController<List<SharedPayload>>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _subscription;
  bool _listening = false;

  ShareTargetService({ShareMediaProvider? provider})
      : _provider = provider ?? ReceiveSharingIntentProvider();

  /// Broadcast stream of incoming payload batches.
  Stream<List<SharedPayload>> get payloadStream => _controller.stream;

  bool get isListening => _listening;

  /// Starts listening to the live media stream. Idempotent.
  Future<void> startListening() async {
    if (_listening) return;
    _listening = true;
    _subscription = _provider.getMediaStream().listen(
      (media) {
        final payloads = mapMediaFiles(media);
        if (payloads.isNotEmpty && !_controller.isClosed) {
          _controller.add(payloads);
        }
      },
      onError: (Object e) {
        if (!_controller.isClosed) {
          _controller.addError(e);
        }
      },
    );
  }

  /// Returns payloads delivered while the app was cold-started via share.
  Future<List<SharedPayload>> getInitialPayloads() async {
    final media = await _provider.getInitialMedia();
    final payloads = mapMediaFiles(media);
    if (payloads.isNotEmpty && !_controller.isClosed) {
      _controller.add(payloads);
    }
    await _provider.reset();
    return payloads;
  }

  /// Clears the platform share cache without emitting.
  Future<void> reset() => _provider.reset();

  /// Stops the live subscription but keeps the broadcast stream open.
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
    _listening = false;
  }

  /// Releases all resources.
  Future<void> dispose() async {
    await stopListening();
    await _controller.close();
  }

  /// Maps raw plugin files to domain payloads, dropping empty entries.
  List<SharedPayload> mapMediaFiles(List<SharedMediaFile> media) {
    final payloads = <SharedPayload>[];
    for (final file in media) {
      final payload = mapFile(file);
      if (payload != null) payloads.add(payload);
    }
    return payloads;
  }

  /// Maps one plugin file to a payload. Returns null when path is empty.
  SharedPayload? mapFile(SharedMediaFile file) {
    if (file.path.trim().isEmpty) return null;
    return SharedPayload(
      kind: _mapKind(file.type),
      value: file.path,
      mimeType: file.mimeType,
      thumbnail: file.thumbnail,
      message: file.message,
    );
  }

  /// Builds the suggested chat prompt for a batch of payloads.
  String buildSuggestedPrompt(List<SharedPayload> payloads) =>
      SharedPayload.buildSuggestedPrompt(payloads);

  SharedPayloadKind _mapKind(SharedMediaType type) {
    switch (type) {
      case SharedMediaType.url:
        return SharedPayloadKind.url;
      case SharedMediaType.image:
        return SharedPayloadKind.image;
      case SharedMediaType.video:
        return SharedPayloadKind.video;
      case SharedMediaType.file:
        return SharedPayloadKind.file;
      case SharedMediaType.text:
        return SharedPayloadKind.text;
    }
  }
}
