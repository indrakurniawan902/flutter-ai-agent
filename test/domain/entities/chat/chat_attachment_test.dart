import 'dart:convert';

import 'package:flutter_ai_agent/domain/entities/chat/chat_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatAttachment imageAttachment() => ChatAttachment(
        filename: 'photo.jpg',
        type: ChatAttachmentType.image,
        mimeType: 'image/jpeg',
        base64Data: base64Encode(utf8.encode('binary-image-bytes')),
      );

  ChatAttachment fileAttachment() => ChatAttachment(
        filename: 'notes.txt',
        type: ChatAttachmentType.file,
        mimeType: 'text/plain',
        base64Data: base64Encode(utf8.encode('hello file contents')),
      );

  group('ChatAttachment', () {
    test('dataUrl builds data: URI with mime and base64', () {
      final attachment = imageAttachment();
      expect(
        attachment.dataUrl,
        equals('data:image/jpeg;base64,${attachment.base64Data}'),
      );
    });

    test('toJson serializes type as string and round-trips via fromJson', () {
      final attachment = fileAttachment();
      final json = attachment.toJson();

      expect(json['filename'], equals('notes.txt'));
      expect(json['type'], equals('file'));
      expect(json['mimeType'], equals('text/plain'));
      expect(json['base64Data'], equals(attachment.base64Data));

      final restored = ChatAttachment.fromJson(json);
      expect(restored, equals(attachment));
    });

    test('image type round-trips', () {
      final attachment = imageAttachment();
      final restored = ChatAttachment.fromJson(attachment.toJson());
      expect(restored.type, equals(ChatAttachmentType.image));
      expect(restored, equals(attachment));
    });

    test('fromJson parses type string', () {
      final fromImage = ChatAttachment.fromJson({
        'filename': 'a.png',
        'type': 'image',
        'mimeType': 'image/png',
        'base64Data': 'AAA',
      });
      expect(fromImage.type, equals(ChatAttachmentType.image));

      final fromFile = ChatAttachment.fromJson({
        'filename': 'a.txt',
        'type': 'file',
        'mimeType': 'text/plain',
        'base64Data': 'AAA',
      });
      expect(fromFile.type, equals(ChatAttachmentType.file));
    });

    test('fromJson tolerates unknown type with safe fallback', () {
      final attachment = ChatAttachment.fromJson({
        'filename': 'weird.bin',
        'type': 'spaceship',
        'mimeType': 'application/octet-stream',
        'base64Data': 'AAA',
      });
      expect(attachment.type, equals(ChatAttachmentType.file));
    });

    test('fromJson tolerates missing fields without throwing', () {
      final attachment = ChatAttachment.fromJson(const {});
      expect(attachment.filename, equals(''));
      expect(attachment.mimeType, equals(''));
      expect(attachment.base64Data, equals(''));
    });
  });
}
