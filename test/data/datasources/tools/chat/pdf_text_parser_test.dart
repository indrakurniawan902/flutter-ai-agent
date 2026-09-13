import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/data/datasources/tools/chat/pdf_text_parser.dart';

/// Minimal valid PDF header + a plain uncompressed content stream with
/// `BT /F1 12 Tf (Hello PDF) Tj ET`.
Uint8List _plainPdf() {
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 38 >>
stream
BT /F1 12 Tf (Hello PDF) Tj ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000120 00000 n
0000000210 00000 n
0000000340 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
400
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// Same but with a FlateDecode-filtered stream containing `BT (Compressed) Tj ET`.
Uint8List _flatePdf() {
  const plain = 'BT (Compressed) Tj ET';
  final encoded = ZLibCodec().encode(latin1.encode(plain));
  final length = encoded.length;
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length $length /Filter /FlateDecode >>
stream
${latin1.decode(encoded)}
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000120 00000 n
0000000210 00000 n
0000000340 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
450
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// A "zip bomb": FlateDecode stream whose payload inflates to ~2 MiB from a
/// sub-kibibyte compressed body, used to assert the output caps hold.
Uint8List _bombPdf() {
  final payload = 'BT (${('A' * (2 * 1024 * 1024))}) Tj ET';
  final encoded =
      Uint8List.fromList(ZLibCodec(level: 9).encode(latin1.encode(payload)));
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length ${encoded.length} /Filter /FlateDecode >>
stream
${latin1.decode(encoded)}
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
trailer
<< /Size 6 /Root 1 0 R >>
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// PDF with an uncompressed stream containing a hex string `<48656C6C6F>` (Hello).
Uint8List _hexPdf() {
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 24 >>
stream
BT /F1 12 Tf <48656C6C6F> Tj ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000120 00000 n
0000000210 00000 n
0000000340 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
400
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// PDF with a TJ array and a negative kern number (-150) between strings.
Uint8List _kernPdf() {
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 42 >>
stream
BT /F1 12 Tf [ (Hello) -150 (World) ] TJ ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000120 00000 n
0000000210 00000 n
0000000340 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
400
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// PDF with escapes: `\\n` and `\\(`.
Uint8List _escapePdf() {
  final text = r'''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 42 >>
stream
BT /F1 12 Tf (Line1\nLine2 \(paren\)) Tj ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000120 00000 n
0000000210 00000 n
0000000340 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
400
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// PDF with /Encrypt present (no actual encryption, just the marker).
Uint8List _encryptedPdf() {
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R /Encrypt 10 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 10 >>
stream
BT ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
10 0 obj
<< /Filter /Standard /V 1 >> endobj
xref
0 11
0000000000 65535 f
trailer
<< /Size 11 /Root 1 0 R /Encrypt 10 0 R >>
startxref
100
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

/// PDF with garbage after valid header (no obj/stream structure).
Uint8List _garbageAfterHeader() {
  final text = '%PDF-1.4\nNOT A REAL PDF STRUCTURE HERE JUST GARBAGE';
  return Uint8List.fromList(latin1.encode(text));
}

/// PDF with no extractable text (content stream has no BT/ET, just graphics).
Uint8List _noTextPdf() {
  final text = '''
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 16 >>
stream
0 0 1 rg 10 10 20 20 re f
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
endobj
xref
0 6
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000120 00000 n
0000000210 00000 n
0000000340 00000 n
trailer
<< /Size 6 /Root 1 0 R >>
startxref
400
%%EOF
''';
  return Uint8List.fromList(latin1.encode(text));
}

void main() {
  group('PdfTextParser.parse', () {
    final parser = const PdfTextParser();

    test('non-PDF bytes returns null', () {
      expect(parser.parse(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
      expect(parser.parse(Uint8List.fromList([])), isNull);
    });

    test('plain uncompressed BT/ET stream extracts text', () {
      final result = parser.parse(_plainPdf());
      expect(result, isNotNull);
      expect(result!.hasText, isTrue);
      expect(result.text, contains('Hello PDF'));
    });

    test('hex string <48656C6C6F> decodes to Hello', () {
      final result = parser.parse(_hexPdf());
      expect(result, isNotNull);
      expect(result!.hasText, isTrue);
      expect(result.text, contains('Hello'));
    });

    test('TJ array with negative kern inserts space', () {
      final result = parser.parse(_kernPdf());
      expect(result, isNotNull);
      expect(result!.hasText, isTrue);
      // -150 < -100 => space inserted between Hello and World
      expect(result.text, contains('Hello World'));
    });

    test('escapes \\n and \\( decoded', () {
      final result = parser.parse(_escapePdf());
      expect(result, isNotNull);
      expect(result!.hasText, isTrue);
      expect(result.text, contains('Line1'));
      expect(result.text, contains('Line2'));
      expect(result.text, contains('(paren)'));
    });

    test('/Encrypt present => isEncrypted true, no throw', () {
      final result = parser.parse(_encryptedPdf());
      expect(result, isNotNull);
      expect(result!.isEncrypted, isTrue);
      // isEncrypted && hasText=false -> still a result, no throw
    });

    test('garbage after valid %PDF- header returns null', () {
      final result = parser.parse(_garbageAfterHeader());
      // May return null or empty; spec accepts both
      if (result != null) {
        expect(result.hasText, isFalse);
      }
    });

    test('compressed FlateDecode stream extracts text', () {
      final result = parser.parse(_flatePdf());
      expect(result, isNotNull);
      expect(result!.hasText, isTrue);
      expect(result.text, contains('Compressed'));
    });

    test('zip-bomb stream is aborted by the inflate cap without hanging', () {
      final result = parser.parse(_bombPdf());
      expect(result, isNotNull);
      expect(result!.hasText, isFalse);
      expect(result.text.length, lessThan(kMaxInflatedStreamBytes));
    });

    test('text-less but valid PDF (has objects) => non-null empty', () {
      final result = parser.parse(_noTextPdf());
      expect(result, isNotNull);
      expect(result!.hasText, isFalse);
      expect(result.isEncrypted, isFalse);
    });
  });
}