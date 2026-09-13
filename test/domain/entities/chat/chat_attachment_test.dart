import 'dart:convert';

import 'package:flutter_ai_agent/domain/entities/chat/chat_attachment.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
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

    test('fromJson tolerates missing fields with safe fallbacks', () {
      final attachment = ChatAttachment.fromJson(const {});
      expect(attachment.filename, equals('attachment'));
      expect(attachment.type, equals(ChatAttachmentType.file));
      expect(attachment.mimeType, equals(''));
      expect(attachment.base64Data, equals(''));
    });

    test('fromJson coerces file type to image when mimeType is image/*', () {
      final attachment = ChatAttachment.fromJson({
        'filename': 'mislabelled.png',
        'type': 'file',
        'mimeType': 'image/png',
        'base64Data': 'AAA',
      });
      expect(attachment.type, equals(ChatAttachmentType.image));
    });

    test('fromJson keeps file type for non-image mimeType', () {
      final attachment = ChatAttachment.fromJson({
        'filename': 'doc.pdf',
        'type': 'file',
        'mimeType': 'application/pdf',
        'base64Data': 'AAA',
      });
      expect(attachment.type, equals(ChatAttachmentType.file));
    });

    test('fromJson falls back to attachment filename when empty', () {
      final attachment = ChatAttachment.fromJson({
        'filename': '',
        'type': 'file',
        'mimeType': 'text/plain',
        'base64Data': 'AAA',
      });
      expect(attachment.filename, equals('attachment'));
    });
  });

  group('ChatMessage attachment persistence (toJson)', () {
    test('content stays plain String with zero [Attached file: baked in', () {
      final message = ChatMessage(
        role: 'user',
        content: 'summarize this',
        attachments: [fileAttachment()],
      );
      final json = message.toJson();

      expect(json['content'], isA<String>());
      expect(json['content'], equals('summarize this'));
      expect(
        jsonEncode(json).contains('[Attached file:'),
        isFalse,
        reason: 'storage JSON must never bake multipart file bodies',
      );
      expect(json['attachments'], isA<List>());
    });

    test('file-attachment round-trip is idempotent (no body compounding)', () {
      final message = ChatMessage(
        role: 'user',
        content: 'summarize this',
        attachments: [fileAttachment()],
      );

      final first = message.toJson();
      final second = ChatMessage.fromJson(first).toJson();
      final third = ChatMessage.fromJson(second).toJson();

      expect(second, equals(first));
      expect(third, equals(first));
    });

    test('image-attachment round-trip keeps base64Data intact', () {
      final message = ChatMessage(
        role: 'user',
        content: 'what is this',
        attachments: [imageAttachment()],
      );

      final first = message.toJson();
      final restored = ChatMessage.fromJson(first);
      final second = restored.toJson();

      expect(
        restored.attachments!.single.base64Data,
        equals(imageAttachment().base64Data),
      );
      expect(second, equals(first));
    });

    test('legacy JSON with plain String content and no attachments is stable',
        () {
      final legacy = <String, dynamic>{
        'role': 'user',
        'content': 'old style message',
      };
      final message = ChatMessage.fromJson(legacy);
      expect(message.content, equals('old style message'));
      expect(message.attachments, isNull);
      expect(message.toJson(), equals(legacy));
    });

    test('legacy record with baked List content still flattens', () {
      final legacy = <String, dynamic>{
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'hi\n\n[Attached file: notes.txt]\nhello file contents',
          },
        ],
      };
      final message = ChatMessage.fromJson(legacy);
      expect(message.content, contains('[Attached file: notes.txt]'));
      expect(message.attachments, isNull);
      // Re-saving must keep it as a plain String, not re-expand.
      expect(message.toJson()['content'], isA<String>());
    });
  });

  group('ChatMessage wire serialization (toWireJson)', () {
    test('file attachment produces multipart text and no attachments key', () {
      final message = ChatMessage(
        role: 'user',
        content: 'summarize this',
        attachments: [fileAttachment()],
      );
      final wire = message.toWireJson();

      expect(wire.containsKey('attachments'), isFalse);
      final parts = wire['content'] as List;
      final text =
          parts.firstWhere((p) => (p as Map)['type'] == 'text')['text']
              as String;
      expect(text, contains('summarize this'));
      expect(text, contains('[Attached file: notes.txt]'));
      expect(text, contains('hello file contents'));
      expect(
        parts.any((p) => (p as Map)['type'] == 'image_url'),
        isFalse,
      );
    });

    test('image attachment emits image_url data URI exactly once', () {
      final message = ChatMessage(
        role: 'user',
        content: 'what is this',
        attachments: [imageAttachment()],
      );
      final wire = message.toWireJson();

      expect(wire.containsKey('attachments'), isFalse);
      final encoded = jsonEncode(wire);
      final dataUriOccurrences =
          RegExp('data:image/jpeg;base64,').allMatches(encoded).length;
      expect(dataUriOccurrences, equals(1));

      final parts = wire['content'] as List;
      final imagePart =
          parts.firstWhere((p) => (p as Map)['type'] == 'image_url');
      expect(
        (imagePart as Map)['image_url']['url'],
        equals(imageAttachment().dataUrl),
      );
    });

    test('undecodable attachment yields placeholder, not raw base64', () {
      final attachment = ChatAttachment(
        filename: 'mystery.bin',
        type: ChatAttachmentType.file,
        mimeType: 'application/octet-stream',
        base64Data: '!!!not-valid-base64!!!',
      );
      final message = ChatMessage(
        role: 'user',
        content: 'read this',
        attachments: [attachment],
      );
      final wire = message.toWireJson();
      final parts = wire['content'] as List;
      final text =
          parts.firstWhere((p) => (p as Map)['type'] == 'text')['text']
              as String;
      expect(text, contains('[undecodable attachment]'));
      expect(text, isNot(contains('!!!not-valid-base64!!!')));
    });
  });
}
