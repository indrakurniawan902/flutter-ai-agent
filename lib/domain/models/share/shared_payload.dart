import 'package:equatable/equatable.dart';

/// Kind of content received through the OS share sheet.
enum SharedPayloadKind {
  text,
  url,
  image,
  video,
  file,
}

/// Single unit of shared content routed into the agent chat.
class SharedPayload extends Equatable {
  final SharedPayloadKind kind;
  final String value;
  final String? mimeType;
  final String? thumbnail;
  final String? message;

  const SharedPayload({
    required this.kind,
    required this.value,
    this.mimeType,
    this.thumbnail,
    this.message,
  });

  bool get isText => kind == SharedPayloadKind.text;
  bool get isUrl => kind == SharedPayloadKind.url;
  bool get isImage => kind == SharedPayloadKind.image;
  bool get isVideo => kind == SharedPayloadKind.video;
  bool get isFile => kind == SharedPayloadKind.file;
  bool get isMedia => isImage || isVideo;

  /// Builds a chat prompt routing this payload to the relevant skill.
  String toChatPrompt() {
    switch (kind) {
      case SharedPayloadKind.url:
        return 'Summarize this shared link: $value';
      case SharedPayloadKind.image:
        return 'Describe this shared image and extract any visible text: $value';
      case SharedPayloadKind.video:
        return 'Summarize this shared video file: $value';
      case SharedPayloadKind.file:
        return 'Analyze this shared file: $value';
      case SharedPayloadKind.text:
        return 'Process this shared text:\n\n$value';
    }
  }

  /// Alias for [toChatPrompt] kept for API ergonomics.
  String toPrompt() => toChatPrompt();

  /// Combines prompts for a batch of payloads into one chat input.
  static String buildSuggestedPrompt(List<SharedPayload> payloads) {
    if (payloads.isEmpty) return '';
    if (payloads.length == 1) return payloads.first.toChatPrompt();
    final buffer = StringBuffer('Process these shared items:\n');
    for (var i = 0; i < payloads.length; i++) {
      buffer.writeln('${i + 1}. ${payloads[i].toChatPrompt()}');
    }
    return buffer.toString().trim();
  }

  @override
  List<Object?> get props => [kind, value, mimeType, thumbnail, message];
}
