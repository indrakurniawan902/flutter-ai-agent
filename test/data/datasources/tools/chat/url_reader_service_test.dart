import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/url_reader_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart'
    show ValidationFailure;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockDio mockDio;
  late UrlReaderService service;

  setUpAll(() {
    registerFallbackValue(Options());
  });

  setUp(() {
    mockDio = MockDio();
    service = UrlReaderService.create(mockDio);
  });

  void stubBody(String? body) {
    when(
      () => mockDio.get<String>(any(), options: any(named: 'options')),
    ).thenAnswer(
      (_) async => Response<String>(
          data: body, statusCode: 200, requestOptions: RequestOptions()),
    );
  }

  group('fetchUrl', () {
    test('returns Right raw body on success', () async {
      stubBody('<html>hi</html>');

      final result = await service.fetchUrl('https://a.test');

      expect(result, const Right<Failure, String>('<html>hi</html>'));
    });

    test('Left ParseFailure when body empty', () async {
      stubBody('   ');

      final result = await service.fetchUrl('https://a.test');

      expect(result, isA<Left>());
      expect((result as Left).value, isA<ParseFailure>());
    });

    test('Left NetworkFailure on DioException', () async {
      when(
        () => mockDio.get<String>(any(), options: any(named: 'options')),
      ).thenThrow(
        DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(),
          response: Response<dynamic>(
              statusCode: 500, requestOptions: RequestOptions()),
        ),
      );

      final result = await service.fetchUrl('https://a.test');

      expect(result, isA<Left>());
      expect((result as Left).value, isA<NetworkFailure>());
    });

    test('passes an 18s receive timeout and a 10s connect timeout', () async {
      stubBody('<html>hi</html>');

      await service.fetchUrl('https://a.test');

      final captured = verify(
        () => mockDio.get<String>(any(), options: captureAny(named: 'options')),
      ).captured;
      final options = captured.single as Options;
      expect(options.receiveTimeout, const Duration(seconds: 18));
      expect(options.connectTimeout, const Duration(seconds: 10));
    });

    test('Left NetworkFailure with timeout wording on TimeoutException',
        () async {
      when(
        () => mockDio.get<String>(any(), options: any(named: 'options')),
      ).thenAnswer((_) => Future<Response<String>>.error(TimeoutException('slow')));

      final result = await service.fetchUrl('https://a.test');

      expect(
        result,
        const Left<Failure, String>(
          NetworkFailure(
            'Failed to fetch https://a.test: Request timeout occurred',
          ),
        ),
      );
    });
  });

  group('fetchReadableText', () {
    test('Left ValidationFailure for bad scheme', () async {
      final result = await service.fetchReadableText('ftp://a.test');

      expect(result, isA<Left>());
      expect((result as Left).value, isA<ValidationFailure>());
      verifyNever(
        () => mockDio.get<String>(any(), options: any(named: 'options')),
      );
    });

    test('Right capped text on readable html', () async {
      stubBody('<html><head><title>T</title></head>'
          '<body><p>Readable body text.</p></body></html>');

      final result = await service.fetchReadableText('https://a.test');

      expect(result, isA<Right>());
      final text = (result as Right<Failure, String>).value;
      expect(text, contains('Readable body text.'));
      expect(text, contains('T'));
    });

    test('Left ParseFailure when no readable text', () async {
      stubBody('<html><body><script>a</script></body></html>');

      final result = await service.fetchReadableText('https://a.test');

      expect(result, isA<Left>());
      expect((result as Left).value, isA<ParseFailure>());
    });

    test('caps to defaultMaxChars end-to-end', () async {
      final big = ('lorem ipsum dolor ' * 4000);
      stubBody('<html><body><p>$big</p></body></html>');

      final result = await service.fetchReadableText('https://a.test');

      final text = (result as Right<Failure, String>).value;
      expect(
        text.length,
        lessThanOrEqualTo(
            UrlReaderService.defaultMaxChars + '\n\n…[truncated]'.length),
      );
    });
  });
}
