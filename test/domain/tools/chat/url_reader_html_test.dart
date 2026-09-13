import 'package:flutter_ai_agent/data/datasources/tools/chat/url_reader_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractUrl', () {
    test('finds bare domain and prefixes https', () {
      expect(UrlReaderService.extractUrl('read example.com/x now'),
          'https://example.com/x');
    });

    test('finds https url inside prose', () {
      expect(
        UrlReaderService.extractUrl('see https://a.test/p?q=1 for details'),
        'https://a.test/p?q=1',
      );
    });

    test('strips trailing punctuation', () {
      expect(
        UrlReaderService.extractUrl('visit https://a.test/page.'),
        'https://a.test/page',
      );
    });

    test('returns null for blank text', () {
      expect(UrlReaderService.extractUrl('   '), isNull);
      expect(UrlReaderService.extractUrl(''), isNull);
    });
  });

  group('isUrl', () {
    test('accepts http and https', () {
      expect(UrlReaderService.isUrl('http://a.test'), isTrue);
      expect(UrlReaderService.isUrl('https://a.test/x'), isTrue);
    });

    test('rejects non-http scheme, no-scheme and empty', () {
      expect(UrlReaderService.isUrl('ftp://a.test'), isFalse);
      expect(UrlReaderService.isUrl('example.com'), isFalse);
      expect(UrlReaderService.isUrl(''), isFalse);
    });
  });

  group('validateUrl', () {
    test('null for acceptable urls', () {
      expect(UrlReaderService.validateUrl('http://a.test'), isNull);
      expect(UrlReaderService.validateUrl('https://a.test/x'), isNull);
    });

    test('rejects ftp scheme', () {
      expect(UrlReaderService.validateUrl('ftp://a.test'),
          contains('Unsupported URL scheme'));
    });

    test('rejects empty', () {
      expect(UrlReaderService.validateUrl('  '), 'URL is empty');
    });
  });

  group('extractTitle', () {
    test('reads present title', () {
      expect(UrlReaderService.extractTitle('<html><head><title>Hello</title>'),
          'Hello');
    });

    test('empty when absent', () {
      expect(UrlReaderService.extractTitle('<html><body>x</body></html>'), '');
    });

    test('decodes entities and collapses whitespace', () {
      expect(
        UrlReaderService.extractTitle('<title>A &amp;   B&nbsp;C</title>'),
        'A & B C',
      );
    });

    test('case-insensitive tag', () {
      expect(UrlReaderService.extractTitle('<TITLE>Up</TITLE>'), 'Up');
    });
  });

  group('htmlToPlainText', () {
    test('drops script/style/noscript content', () {
      const html =
          '<p>Keep</p><script>var gone=1;</script><style>.a{}</style>'
          '<noscript>ns</noscript>';
      final text = UrlReaderService.htmlToPlainText(html);
      expect(text, contains('Keep'));
      expect(text, isNot(contains('gone')));
      expect(text, isNot(contains('.a')));
      expect(text, isNot(contains('ns')));
    });

    test('block tags become newlines', () {
      final text = UrlReaderService.htmlToPlainText('<p>one</p><p>two</p>');
      expect(text, 'one\ntwo');
    });

    test('decodes entities', () {
      final text = UrlReaderService.htmlToPlainText('a&nbsp;b&amp;c&#39;d');
      expect(text, "a b&c'd");
    });

    test('removes comments', () {
      final text = UrlReaderService.htmlToPlainText('keep<!-- drop -->more');
      expect(text, isNot(contains('drop')));
    });

    test('collapses whitespace', () {
      final text = UrlReaderService.htmlToPlainText('a    b c');
      expect(text, 'a b c');
    });
  });

  group('capText', () {
    test('no-op under the limit', () {
      expect(UrlReaderService.capText('short', 100), 'short');
    });

    test('over-limit respects length bound', () {
      final long = 'word ' * 100;
      final capped = UrlReaderService.capText(long, 50);
      expect(capped.length, lessThanOrEqualTo(50 + '\n\n…[truncated]'.length));
      expect(capped, endsWith('…[truncated]'));
    });

    test('zero max returns marker and does not throw', () {
      expect(UrlReaderService.capText('anything', 0), '…[truncated]');
    });

    test('negative max returns marker', () {
      expect(UrlReaderService.capText('anything', -5), '…[truncated]');
    });
  });
}
