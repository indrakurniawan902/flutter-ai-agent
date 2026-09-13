import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Hard caps for FlateDecode inflation: PDFs are untrusted input, so a
/// zip-bomb stream must never be fully materialized.
const int kMaxInflatedStreamBytes = 32 * 1024;
const int kMaxInflatedTotalBytes = 256 * 1024;

/// Result of parsing one PDF: extracted page texts, in page order.
class PdfParseResult {
  final List<String> pages;
  final int pageCount;
  final bool isEncrypted;

  const PdfParseResult({
    required this.pages,
    required this.pageCount,
    this.isEncrypted = false,
  });

  /// Text of all pages joined.
  String get text => pages.join('\n\n').trim();

  bool get hasText => text.trim().isNotEmpty;
}

/// Pure-Dart fallback PDF text extractor. Uncompressed and FlateDecode
/// content streams only; decompression is capped (zip-bomb guard).
class PdfTextParser {
  const PdfTextParser();

  static const List<int> _magic = [0x25, 0x50, 0x44, 0x46, 0x2d]; // %PDF-
  static const int _magicWindow = 1024;
  static const int _maxDocumentBytes = 20 * 1024 * 1024;
  static const int _maxStreamBodies = 64;
  static const int _maxCompressedStreamBytes = 4096;
  static const int _inflateInputChunkBytes = 1024;

  static const List<String> _imageFilters = [
    '/DCTDecode',
    '/JPXDecode',
    '/CCITTFaxDecode',
    '/JBIG2Decode',
    '/DCT',
  ];

  /// Returns null when [bytes] is not a parseable PDF at all.
  PdfParseResult? parse(Uint8List bytes) {
    try {
      return _parse(bytes);
    } catch (_) {
      return null;
    }
  }

  PdfParseResult? _parse(Uint8List bytes) {
    // Documented guard: oversized inputs are rejected outright.
    if (bytes.length > _maxDocumentBytes) return null;
    if (!_hasMagic(bytes)) return null;

    final latin = latin1.decode(bytes, allowInvalid: true);
    final isEncrypted = latin.contains('/Encrypt');
    final pageTokens = RegExp(r'/Type\s*/Page(?![s/])').allMatches(latin).length;
    final hasObjects = RegExp(r'\d+\s+0\s+obj').hasMatch(latin);

    final pages = <String>[];
    var streamsSeen = 0;
    var inflatedTotal = 0;
    for (final body in _streamBodies(latin)) {
      if (streamsSeen >= _maxStreamBodies) break;
      streamsSeen++;
      final filter = _filterOf(latin, body.dictEnd);
      if (filter == null) continue;

      String? content;
      if (filter == 'flate') {
        content = _inflate(body.bytes, kMaxInflatedTotalBytes - inflatedTotal);
        if (content != null) inflatedTotal += content.length;
      } else if (filter == 'plain') {
        content = latin1.decode(body.bytes, allowInvalid: true);
      }
      if (content == null) continue;

      final text = _clean(_extractText(content));
      if (text.isNotEmpty) pages.add(text);
    }

    if (pages.isEmpty && !isEncrypted && !hasObjects) return null;
    return PdfParseResult(
      pages: pages,
      pageCount: pages.isEmpty ? pageTokens : pages.length,
      isEncrypted: isEncrypted,
    );
  }

  bool _hasMagic(Uint8List bytes) {
    final limit = bytes.length < _magicWindow ? bytes.length : _magicWindow;
    for (var i = 0; i + _magic.length <= limit; i++) {
      var ok = true;
      for (var j = 0; j < _magic.length; j++) {
        if (bytes[i + j] != _magic[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  Iterable<_StreamBody> _streamBodies(String latin) sync* {
    var from = 0;
    while (from < latin.length) {
      final start = latin.indexOf('stream', from);
      if (start < 0) return;
      final isEndStream = start >= 3 && latin.substring(start - 3, start) == 'end';
      if (isEndStream) {
        from = start + 6;
        continue;
      }

      var bodyStart = start + 6;
      if (bodyStart < latin.length && latin[bodyStart] == '\r') bodyStart++;
      if (bodyStart < latin.length && latin[bodyStart] == '\n') bodyStart++;

      final end = latin.indexOf('endstream', bodyStart);
      if (end < 0) return;

      var bodyEnd = end;
      if (bodyEnd > bodyStart && latin[bodyEnd - 1] == '\n') bodyEnd--;
      if (bodyEnd > bodyStart && latin[bodyEnd - 1] == '\r') bodyEnd--;

      final raw = Uint8List.fromList(latin.substring(bodyStart, bodyEnd).codeUnits);
      yield _StreamBody(dictEnd: start, bytes: raw);
      from = end + 9;
    }
  }

  /// Filter of the object dictionary that owns the stream starting at
  /// [streamKeyword]. Returns null when the filter is unsupported.
  String? _filterOf(String latin, int streamKeyword) {
    final dictStart = latin.lastIndexOf('obj', streamKeyword);
    final from = dictStart < 0
        ? (streamKeyword - 2000 < 0 ? 0 : streamKeyword - 2000)
        : dictStart;
    final header = latin.substring(from, streamKeyword);

    if (header.contains('/FlateDecode') || header.contains('/Fl')) return 'flate';
    for (final unsupported in _imageFilters) {
      if (header.contains(unsupported)) return null;
    }
    if (header.contains('/Filter')) return null;
    return 'plain';
  }

  /// Chunked inflate with output bounded by [kMaxInflatedStreamBytes] and the
  /// remaining document [budget]; returns null (stream skipped) on caps or
  /// decode errors so parsing of other streams continues.
  String? _inflate(Uint8List bytes, int budget) {
    if (bytes.isEmpty ||
        bytes.length > _maxCompressedStreamBytes ||
        budget <= 0) {
      return null;
    }
    final maxOutput =
        budget < kMaxInflatedStreamBytes ? budget : kMaxInflatedStreamBytes;
    try {
      return _inflateBounded(bytes, maxOutput, raw: false) ??
          _inflateBounded(bytes, maxOutput, raw: true);
    } on _InflateLimitExceeded {
      return null;
    }
  }

  String? _inflateBounded(Uint8List bytes, int maxOutput, {required bool raw}) {
    final output = BytesBuilder(copy: false);
    final sink = _CapSink(output, maxOutput);
    final input = ZLibCodec(raw: raw).decoder.startChunkedConversion(sink);
    var decodeFailed = false;
    try {
      for (var i = 0; i < bytes.length; i += _inflateInputChunkBytes) {
        final end = i + _inflateInputChunkBytes < bytes.length
            ? i + _inflateInputChunkBytes
            : bytes.length;
        input.add(bytes.sublist(i, end));
      }
      if (!sink.exceeded) input.close();
    } catch (_) {
      decodeFailed = true;
    }
    if (sink.exceeded) throw const _InflateLimitExceeded();
    if (decodeFailed && output.length == 0) return null;
    return latin1.decode(output.toBytes(), allowInvalid: true);
  }

  /// Extracts show-text operands from a decoded content stream.
  String _extractText(String content) {
    final blocks = RegExp(r'BT\b([\s\S]*?)ET\b').allMatches(content);
    if (blocks.isEmpty) return _allStrings(content);

    final buffer = StringBuffer();
    for (final block in blocks) {
      buffer.writeln(_textBlock(block.group(1)!));
    }
    return buffer.toString();
  }

  String _textBlock(String block) {
    final buffer = StringBuffer();
    final operands = <double>[];
    var i = 0;

    while (i < block.length) {
      final char = block[i];
      if (char == '(') {
        final read = _readLiteral(block, i);
        buffer.write(read.value);
        operands.clear();
        i = read.end;
        continue;
      }
      if (char == '<' && !_startsWith(block, i, '<<')) {
        final read = _readHex(block, i);
        buffer.write(read.value);
        operands.clear();
        i = read.end;
        continue;
      }
      if (char == '[') {
        final read = _readArray(block, i);
        buffer.write(read.value);
        operands.clear();
        i = read.end;
        continue;
      }
      if (char == "'" || char == '"') {
        buffer.write('\n');
        operands.clear();
        i++;
        continue;
      }
      if (char == '-' || char == '+' || char == '.' || _isDigit(char)) {
        final read = _readNumber(block, i);
        operands.add(read.number);
        i = read.end;
        continue;
      }
      if (_isLetter(char)) {
        final start = i;
        while (i < block.length && _isLetter(block[i])) {
          i++;
        }
        final operator = block.substring(start, i);
        if (operator == 'Td' || operator == 'TD') {
          if (operands.isNotEmpty && operands.last != 0) buffer.write('\n');
        } else if (operator == 'T*') {
          buffer.write('\n');
        }
        operands.clear();
        continue;
      }
      operands.clear();
      i++;
    }
    return buffer.toString();
  }

  /// Reads a `TJ` array: concatenates string operands and inserts a space
  /// when a kerning number below -100 separates two strings.
  _TextRead _readArray(String src, int start) {
    final buffer = StringBuffer();
    var i = start + 1;
    var wroteString = false;
    var pendingSpace = false;

    while (i < src.length) {
      final char = src[i];
      if (char == ']') {
        i++;
        break;
      }
      if (char == '(') {
        final read = _readLiteral(src, i);
        if (pendingSpace && wroteString) buffer.write(' ');
        buffer.write(read.value);
        wroteString = true;
        pendingSpace = false;
        i = read.end;
        continue;
      }
      if (char == '<' && !_startsWith(src, i, '<<')) {
        final read = _readHex(src, i);
        if (pendingSpace && wroteString) buffer.write(' ');
        buffer.write(read.value);
        wroteString = true;
        pendingSpace = false;
        i = read.end;
        continue;
      }
      if (char == '-' || char == '+' || char == '.' || _isDigit(char)) {
        final read = _readNumber(src, i);
        if (read.number < -100) pendingSpace = true;
        i = read.end;
        continue;
      }
      i++;
    }
    return _TextRead(buffer.toString(), i);
  }

  _TextRead _readLiteral(String src, int start) {
    final buffer = StringBuffer();
    var i = start + 1;
    var depth = 1;

    while (i < src.length) {
      final char = src[i];
      if (char == r'\') {
        i++;
        if (i >= src.length) break;
        final esc = src[i];
        switch (esc) {
          case 'n':
            buffer.write('\n');
            i++;
          case 'r':
            buffer.write('\r');
            i++;
          case 't':
            buffer.write('\t');
            i++;
          case 'b':
            buffer.write('\b');
            i++;
          case 'f':
            buffer.write('\f');
            i++;
          case '(':
            buffer.write('(');
            i++;
          case ')':
            buffer.write(')');
            i++;
          case r'\':
            buffer.write(r'\');
            i++;
          case '\n':
            i++;
          case '\r':
            i++;
          default:
            if (_isOctal(esc)) {
              final code = <String>[esc];
              i++;
              while (code.length < 3 && i < src.length && _isOctal(src[i])) {
                code.add(src[i]);
                i++;
              }
              buffer.writeCharCode(int.parse(code.join(), radix: 8));
            } else {
              buffer.write(esc);
              i++;
            }
        }
        continue;
      }
      if (char == '(') {
        depth++;
        buffer.write(char);
        i++;
        continue;
      }
      if (char == ')') {
        depth--;
        i++;
        if (depth == 0) break;
        buffer.write(char);
        continue;
      }
      buffer.write(char);
      i++;
    }
    return _TextRead(buffer.toString(), i);
  }

  /// Hex string `<...>`; UTF-16BE (BOM `FE FF`) decoded as UTF-16, else Latin-1.
  _TextRead _readHex(String src, int start) {
    final end = src.indexOf('>', start);
    if (end < 0) return _TextRead('', src.length);

    final digits = StringBuffer();
    for (var i = start + 1; i < end; i++) {
      final char = src[i];
      if (_isHexDigit(char)) digits.write(char);
    }

    var body = digits.toString();
    if (body.length.isOdd) body = '${body}0';
    final bytes = Uint8List(body.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(body.substring(i * 2, i * 2 + 2), radix: 16);
    }

    final text = _decodeBytes(bytes);
    return _TextRead(text, end + 1);
  }

  String _decodeBytes(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final buffer = StringBuffer();
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        final codeUnit = (bytes[i] << 8) | bytes[i + 1];
        buffer.writeCharCode(codeUnit);
      }
      return buffer.toString();
    }
    return latin1.decode(bytes, allowInvalid: true);
  }

  String _allStrings(String content) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < content.length) {
      final char = content[i];
      if (char == '(') {
        final read = _readLiteral(content, i);
        buffer.writeln(read.value);
        i = read.end;
        continue;
      }
      if (char == '<' && !_startsWith(content, i, '<<')) {
        final read = _readHex(content, i);
        if (read.value.isNotEmpty) buffer.writeln(read.value);
        i = read.end;
        continue;
      }
      i++;
    }
    return buffer.toString();
  }

  _NumRead _readNumber(String src, int start) {
    var i = start;
    while (i < src.length) {
      final char = src[i];
      if (char == '-' || char == '+' || char == '.' || _isDigit(char)) {
        i++;
        continue;
      }
      break;
    }
    return _NumRead(double.tryParse(src.substring(start, i)) ?? 0, i);
  }

  String _clean(String input) {
    var out = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    out = out.replaceAll(RegExp(r'[ \t]{3,}'), ' ');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  bool _startsWith(String src, int at, String token) =>
      at + token.length <= src.length &&
      src.substring(at, at + token.length) == token;

  bool _isLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }

  bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  bool _isOctal(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x37;
  }

  bool _isHexDigit(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x46) ||
        (code >= 0x61 && code <= 0x66);
  }
}

class _StreamBody {
  final int dictEnd;
  final Uint8List bytes;

  const _StreamBody({required this.dictEnd, required this.bytes});
}

class _InflateLimitExceeded implements Exception {
  const _InflateLimitExceeded();
}

class _CapSink implements Sink<Uint8List> {
  _CapSink(this._output, this._max);

  final BytesBuilder _output;
  final int _max;
  bool exceeded = false;

  @override
  void add(Uint8List data) {
    if (exceeded) return;
    if (_output.length + data.length > _max) {
      exceeded = true;
      throw const _InflateLimitExceeded();
    }
    _output.add(data);
  }

  @override
  void close() {}
}

class _TextRead {
  final String value;
  final int end;

  const _TextRead(this.value, this.end);
}

class _NumRead {
  final double number;
  final int end;

  const _NumRead(this.number, this.end);
}
