import 'package:equatable/equatable.dart';

/// Kind of attachment staged with a chat message.
enum ChatAttachmentType { image, file }

/// A single attachment (image or file) staged for a chat message.
class ChatAttachment extends Equatable {
  /// Display name, e.g. "photo.jpg" or "notes.txt".
  final String filename;
  final ChatAttachmentType type;

  /// MIME type, e.g. "image/jpeg", "text/plain".
  final String mimeType;

  /// Raw base64 payload (no `data:` prefix).
  final String base64Data;

  const ChatAttachment({
    required this.filename,
    required this.type,
    required this.mimeType,
    required this.base64Data,
  });

  /// Data URI helper, primarily for image attachments.
  String get dataUrl => 'data:$mimeType;base64,$base64Data';

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'type': type == ChatAttachmentType.image ? 'image' : 'file',
      'mimeType': mimeType,
      'base64Data': base64Data,
    };
  }

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString().toLowerCase();
    final mimeType = json['mimeType']?.toString() ?? '';
    var type = rawType == 'image'
        ? ChatAttachmentType.image
        : ChatAttachmentType.file;
    if (type == ChatAttachmentType.file && mimeType.startsWith('image/')) {
      type = ChatAttachmentType.image;
    }
    final rawFilename = json['filename']?.toString() ?? '';
    return ChatAttachment(
      filename: rawFilename.isEmpty ? 'attachment' : rawFilename,
      type: type,
      mimeType: mimeType,
      base64Data: json['base64Data']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [filename, type, mimeType, base64Data];
}
