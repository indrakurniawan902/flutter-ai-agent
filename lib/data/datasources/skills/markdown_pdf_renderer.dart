import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Minimal Markdown-to-PDF renderer.
///
/// Supports ATX headings, fenced code blocks, bullet and numbered lists,
/// pipe tables, block quotes, horizontal rules, and inline bold/italic/code.
class MarkdownPdfRenderer {
  const MarkdownPdfRenderer();

  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^[-*+]\s+(.*)$');
  static final RegExp _ordered = RegExp(r'^(\d+)[.)]\s+(.*)$');
  static final RegExp _quote = RegExp(r'^>\s?(.*)$');
  static final RegExp _rule = RegExp(r'^(-{3,}|\*{3,}|_{3,})$');
  static final RegExp _tableDelimiter = RegExp(r'^\|?[\s:|-]+\|[\s:|-]*$');
  static final RegExp _inline = RegExp(r'(\*\*[^*]+\*\*|__[^_]+__|\*[^*]+\*|`[^`]+`)');

  pw.MultiPage render({required String markdown, required String title}) {
    final widgets = <pw.Widget>[
      pw.Header(
        level: 0,
        text: title,
        textStyle: pw.TextStyle(
          fontSize: 20,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey900,
        ),
      ),
    ];

    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    var index = 0;

    while (index < lines.length) {
      final before = index;
      final raw = lines[index];
      final line = raw.trimRight();

      if (line.trim().isEmpty) {
        index++;
        continue;
      }

      if (_startsWithFence(line)) {
        final block = <String>[];
        index++;
        while (index < lines.length && !_startsWithFence(lines[index])) {
          block.add(lines[index]);
          index++;
        }
        index++;
        widgets.add(_codeBlock(block.join('\n')));
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        widgets.add(_headingWidget(heading.group(1)!.length, heading.group(2)!));
        index++;
        continue;
      }

      if (_rule.hasMatch(line.trim())) {
        widgets.add(
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey400),
              ),
            ),
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
          ),
        );
        index++;
        continue;
      }

      if (_isTableStart(lines, index)) {
        final rows = <List<String>>[_splitRow(line)];
        index += 2;
        while (index < lines.length && _isTableRow(lines[index])) {
          rows.add(_splitRow(lines[index]));
          index++;
        }
        widgets.add(_table(rows));
        continue;
      }

      if (_bullet.hasMatch(line.trim())) {
        final items = <String>[];
        while (index < lines.length && _bullet.hasMatch(lines[index].trim())) {
          items.add(_bullet.firstMatch(lines[index].trim())!.group(1)!);
          index++;
        }
        widgets.add(_list(items, ordered: false));
        continue;
      }

      if (_ordered.hasMatch(line.trim())) {
        final items = <String>[];
        while (index < lines.length && _ordered.hasMatch(lines[index].trim())) {
          items.add(_ordered.firstMatch(lines[index].trim())!.group(2)!);
          index++;
        }
        widgets.add(_list(items, ordered: true));
        continue;
      }

      if (_quote.hasMatch(line.trim())) {
        final quoted = <String>[];
        while (index < lines.length && _quote.hasMatch(lines[index].trim())) {
          quoted.add(_quote.firstMatch(lines[index].trim())!.group(1)!);
          index++;
        }
        widgets.add(_quoteBlock(quoted.join(' ')));
        continue;
      }

      final paragraph = <String>[];
      while (index < lines.length &&
          lines[index].trim().isNotEmpty &&
          !_startsOtherBlock(lines, index)) {
        paragraph.add(lines[index].trim());
        index++;
      }
      widgets.add(
        pw.Paragraph(
          text: paragraph.join(' '),
          style: pw.TextStyle(fontSize: 11, lineSpacing: 2),
          margin: const pw.EdgeInsets.only(bottom: 8),
        ),
      );

      if (index == before) index++;
    }

    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: null,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (context) => widgets,
    );
  }

  bool _isTableStart(List<String> lines, int index) {
    if (!_isTableRow(lines[index].trimRight())) return false;
    if (index + 1 >= lines.length) return false;
    final delimiter = lines[index + 1].trim();
    return _tableDelimiter.hasMatch(delimiter) && delimiter.contains('-');
  }

  bool _startsOtherBlock(List<String> lines, int index) {
    final line = lines[index].trimRight();
    final trimmed = line.trim();
    return _startsWithFence(line) ||
        _heading.hasMatch(line) ||
        _rule.hasMatch(trimmed) ||
        _isTableStart(lines, index) ||
        _bullet.hasMatch(trimmed) ||
        _ordered.hasMatch(trimmed) ||
        _quote.hasMatch(trimmed);
  }

  bool _startsWithFence(String line) => line.trimLeft().startsWith('```');

  bool _isTableRow(String line) => line.trim().startsWith('|');

  List<String> _splitRow(String line) {
    var body = line.trim();
    if (body.startsWith('|')) body = body.substring(1);
    if (body.endsWith('|')) body = body.substring(0, body.length - 1);
    return body.split('|').map((cell) => _plain(cell.trim())).toList();
  }

  /// Strips inline markup so table cells render as plain text.
  String _plain(String text) =>
      text.replaceAll(RegExp(r'\*\*|__|\*|`'), '').trim();

  pw.Widget _headingWidget(int level, String text) {
    final sizes = {1: 18.0, 2: 15.0, 3: 13.0, 4: 12.0, 5: 11.0, 6: 10.5};
    final fontSize = sizes[level] ?? 11.0;
    return pw.Header(
      level: level,
      text: text,
      margin: pw.EdgeInsets.only(top: level <= 1 ? 12 : 10, bottom: 6),
      textStyle: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey900,
      ),
    );
  }

  pw.Widget _codeBlock(String code) => pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Text(
          code,
          style: pw.TextStyle(
            font: pw.Font.courier(),
            fontSize: 9.5,
            lineSpacing: 1.5,
          ),
        ),
      );

  pw.Widget _list(List<String> items, {required bool ordered}) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 18,
                  child: pw.Text(
                    ordered ? '${i + 1}.' : '\u2022',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
                pw.Expanded(
                  child: _richText(items[i]),
                ),
              ],
            ),
          pw.SizedBox(height: 8),
        ],
      );

  pw.Widget _quoteBlock(String text) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(left: 10, top: 4, bottom: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(left: pw.BorderSide(color: PdfColors.grey400, width: 3)),
        ),
        child: _richText(text, italic: true, color: PdfColors.grey800),
      );

  pw.Widget _table(List<List<String>> rows) {
    final headers = rows.first;
    final body = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
    final columnCount =
        rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
    final normalizedBody = body
        .map((row) => List<String>.generate(
              columnCount,
              (i) => i < row.length ? row[i] : '',
            ))
        .toList();

    final grid = pw.TableHelper.fromTextArray(
      headers: List<String>.generate(
        columnCount,
        (i) => i < headers.length ? headers[i] : '',
      ),
      data: normalizedBody,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 10),
      cellPadding: const pw.EdgeInsets.all(4),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.topLeft,
    );

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: grid,
    );
  }

  /// Renders inline bold/italic/code spans as a rich paragraph.
  pw.Widget _richText(
    String text, {
    bool italic = false,
    PdfColor? color,
  }) {
    final children = <pw.InlineSpan>[];
    var cursor = 0;

    for (final match in _inline.allMatches(text)) {
      if (match.start > cursor) {
        children.add(
          _span(text.substring(cursor, match.start), italic: italic, color: color),
        );
      }
      final token = match.group(0)!;
      if (token.startsWith('**') || token.startsWith('__')) {
        children.add(_span(
          token.substring(2, token.length - 2),
          bold: true,
          italic: italic,
          color: color,
        ));
      } else if (token.startsWith('`')) {
        children.add(_span(
          token.substring(1, token.length - 1),
          mono: true,
          italic: italic,
          color: color,
        ));
      } else {
        children.add(_span(
          token.substring(1, token.length - 1),
          italic: true,
          color: color,
        ));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      children.add(_span(text.substring(cursor), italic: italic, color: color));
    }
    if (children.isEmpty) {
      children.add(_span('', italic: italic, color: color));
    }

    return pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: 11, color: color ?? PdfColors.black),
        children: children,
      ),
    );
  }

  pw.InlineSpan _span(
    String text, {
    bool bold = false,
    bool italic = false,
    bool mono = false,
    PdfColor? color,
  }) =>
      pw.TextSpan(
        text: text,
        style: pw.TextStyle(
          fontSize: mono ? 10 : 11,
          font: mono ? pw.Font.courier() : null,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          color: color ?? PdfColors.black,
        ),
      );
}
