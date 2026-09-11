class ThoughtExtraction {
  final String? thoughtProcess;
  final String cleanContent;

  const ThoughtExtraction({
    required this.thoughtProcess,
    required this.cleanContent,
  });

  bool get hasThought => thoughtProcess != null && thoughtProcess!.isNotEmpty;
}

class ThoughtExtractor {
  static final RegExp _thoughtPattern =
      RegExp(r'<thought>(.*?)</thought>', dotAll: true);
  static final RegExp _collapseNewlines = RegExp(r'\n{3,}');
  static const String _openTag = '<thought>';
  static const String _closeTag = '</thought>';

  static ThoughtExtraction extract(String raw, {bool streaming = false}) {
    if (raw.trim().isEmpty) {
      return const ThoughtExtraction(
        thoughtProcess: null,
        cleanContent: '',
      );
    }

    final thoughts = <String>[];
    for (final match in _thoughtPattern.allMatches(raw)) {
      final block = (match.group(1) ?? '').trim();
      if (block.isNotEmpty) {
        thoughts.add(block);
      }
    }

    String cleanBase = raw;
    if (streaming) {
      final lastOpen = raw.lastIndexOf(_openTag);
      if (lastOpen != -1) {
        final lastClose = raw.lastIndexOf(_closeTag);
        if (lastClose == -1 || lastOpen > lastClose) {
          final partial =
              raw.substring(lastOpen + _openTag.length).trim();
          if (partial.isNotEmpty) {
            thoughts.add(partial);
          }
          cleanBase = raw.substring(0, lastOpen);
        }
      }
    }

    var clean = cleanBase.replaceAll(_thoughtPattern, '');
    if (streaming && clean.contains(_openTag)) {
      clean = clean.substring(0, clean.indexOf(_openTag));
    }
    clean = _collapseNewlines.allMatches(clean).isEmpty
        ? clean.trim()
        : clean.replaceAll(_collapseNewlines, '\n\n').trim();

    final thoughtProcess =
        thoughts.isEmpty ? null : thoughts.join('\n\n');

    return ThoughtExtraction(
      thoughtProcess: thoughtProcess,
      cleanContent: clean,
    );
  }
}
