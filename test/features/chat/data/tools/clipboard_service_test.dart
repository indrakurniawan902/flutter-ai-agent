import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockClipboardPlatformWrapper extends Mock
    implements ClipboardPlatformWrapper {}

void main() {
  late MockClipboardPlatformWrapper mockClipboard;
  late ClipboardService service;

  setUp(() {
    mockClipboard = MockClipboardPlatformWrapper();
    service = ClipboardService(clipboard: mockClipboard);
  });

  setUpAll(() {
    registerFallbackValue(const ClipboardData(text: 'fallback'));
  });

  group('clipboardRead', () {
    test('returns text when wrapper has data', () async {
      when(() => mockClipboard.getData(any()))
          .thenAnswer((_) async => const ClipboardData(text: 'hello'));

      final result = await service.clipboardRead();

      expect(result, const Right<Failure, String>('hello'));
      verify(() => mockClipboard.getData(Clipboard.kTextPlain)).called(1);
    });

    test('returns empty string when data is null', () async {
      when(() => mockClipboard.getData(any()))
          .thenAnswer((_) async => null);

      final result = await service.clipboardRead();

      expect(result, const Right<Failure, String>(''));
    });

    test('returns ServerFailure on exception', () async {
      when(() => mockClipboard.getData(any()))
          .thenThrow(Exception('boom'));

      final result = await service.clipboardRead();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Clipboard read error'));
        },
        (_) => fail('expected Left'),
      );
    });
  });

  group('clipboardWrite', () {
    test('returns success message on write', () async {
      when(() => mockClipboard.setData(any()))
          .thenAnswer((_) async {});

      final result = await service.clipboardWrite('hello');

      expect(result, const Right<Failure, String>('Text copied to clipboard'));
      verify(
        () => mockClipboard.setData(
          any(that: isA<ClipboardData>()),
        ),
      ).called(1);
    });

    test('returns ServerFailure on exception', () async {
      when(() => mockClipboard.setData(any()))
          .thenThrow(Exception('boom'));

      final result = await service.clipboardWrite('hello');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Clipboard write error'));
        },
        (_) => fail('expected Left'),
      );
    });
  });
}
