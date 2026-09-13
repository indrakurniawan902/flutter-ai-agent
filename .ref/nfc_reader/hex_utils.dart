class HexUtils {
  const HexUtils._();

  static String normalize(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }
    return value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
  }

  static String bytesToHex(List<int> bytes, {bool spaced = false}) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      final hex = bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase();
      buffer.write(hex);
      if (spaced && i < bytes.length - 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  static List<int> hexToBytes(String hex) {
    final normalized = normalize(hex);
    if (normalized.isEmpty || normalized.length.isOdd) {
      throw FormatException('Invalid hex string: $hex');
    }
    final result = <int>[];
    for (var i = 0; i < normalized.length; i += 2) {
      result.add(int.parse(normalized.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static String formatUid(String? uid, {bool mask = false}) {
    final normalized = normalize(uid);
    if (normalized.isEmpty) {
      return '—';
    }
    if (mask && normalized.length >= 8) {
      final prefix = normalized.substring(0, 4);
      final suffix = normalized.substring(normalized.length - 4);
      return '$prefix **** **** $suffix';
    }
    final groups = <String>[];
    for (var i = 0; i < normalized.length; i += 4) {
      final end = (i + 4 < normalized.length) ? i + 4 : normalized.length;
      groups.add(normalized.substring(i, end));
    }
    return groups.join(' ');
  }

  static String formatCardNumber(String? number, {bool mask = true}) {
    final digits = (number ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return '—';
    }
    if (mask && digits.length >= 8) {
      final prefix = digits.substring(0, 4);
      final suffix = digits.substring(digits.length - 4);
      return '$prefix **** **** $suffix';
    }
    final groups = <String>[];
    for (var i = 0; i < digits.length; i += 4) {
      final end = (i + 4 < digits.length) ? i + 4 : digits.length;
      groups.add(digits.substring(i, end));
    }
    return groups.join(' ');
  }
}
