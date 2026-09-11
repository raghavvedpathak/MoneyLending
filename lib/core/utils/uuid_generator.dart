import 'dart:math';

/// Secure RFC 4122 compliant UUID v4 generator.
///
/// Ensures 100% offline, cross-platform UUID string generation
/// without requiring external plugins or platform channels.
class AppUuid {
  static final Random _random = Random.secure();

  /// Generates a random UUID v4 string in the standard 8-4-4-4-12 hex format.
  static String generate() {
    final bytes = List<int>.generate(16, (i) => _random.nextInt(256));

    // Set version to 4 (0100 in bits 4-7 of time_hi_and_version)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to IETF variant (10xxxxxx in bits 6-7 of clock_seq_hi_and_reserved)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hex[0]}${hex[1]}${hex[2]}${hex[3]}-'
        '${hex[4]}${hex[5]}-'
        '${hex[6]}${hex[7]}-'
        '${hex[8]}${hex[9]}-'
        '${hex[10]}${hex[11]}${hex[12]}${hex[13]}${hex[14]}${hex[15]}';
  }
}
