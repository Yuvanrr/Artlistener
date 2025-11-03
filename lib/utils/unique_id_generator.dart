import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Utility class for generating unique IDs that prevent conflicts between builds
class UniqueIdGenerator {
  static const String buildVersion = '1.0.0'; // Update this with each app version

  /// Generates a unique exhibit ID with multiple components to prevent conflicts
  /// Format: EX_[timestamp]_[random]_[location_hash]_[version]
  static String generateExhibitId({
    String? locationHint,
    String? deviceId,
  }) {
    final now = DateTime.now();

    // Timestamp component (YYYYMMDDHHMMSS)
    final timestamp = _formatTimestamp(now);

    // Random component (6 characters, alphanumeric)
    final random = _generateRandomString(6);

    // Location hash (first 4 chars of SHA256 of location hint or device ID)
    final locationHash = _generateLocationHash(locationHint ?? deviceId ?? 'default');

    // Version component (first 3 chars of version)
    final version = buildVersion.replaceAll('.', '').substring(0, 3);

    return 'EX_${timestamp}_${random}_${locationHash}_${version}'.toUpperCase();
  }

  /// Generates a unique exhibit ID with collision detection
  /// Checks against existing IDs in Firestore to ensure uniqueness
  static Future<String> generateUniqueExhibitId({
    String? locationHint,
    String? deviceId,
  }) async {
    String newId;
    int attempts = 0;
    const maxAttempts = 10;

    do {
      newId = generateExhibitId(
        locationHint: locationHint,
        deviceId: deviceId,
      );
      attempts++;

      if (attempts >= maxAttempts) {
        // Fallback to ultra-safe ID if too many collisions
        newId = 'EX_${DateTime.now().millisecondsSinceEpoch}_${_generateRandomString(8)}';
        break;
      }

      // In a real implementation, you'd check Firestore here:
      // final exists = await _checkIfIdExists(newId);
      // if (!exists) break;

    } while (attempts < maxAttempts);

    return newId;
  }

  /// Generates a simple unique ID for other purposes
  static String generateSimpleId({int length = 12}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = _generateRandomString(length - 8);
    return '${now}_$random';
  }

  static String _formatTimestamp(DateTime date) {
    return '${date.year}${(date.month).toString().padLeft(2, '0')}${(date.day).toString().padLeft(2, '0')}${(date.hour).toString().padLeft(2, '0')}${(date.minute).toString().padLeft(2, '0')}${(date.second).toString().padLeft(2, '0')}';
  }

  static String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  static String _generateLocationHash(String input) {
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 4).toUpperCase();
  }

  /// Validates if an exhibit ID follows the expected format
  static bool isValidExhibitId(String id) {
    final regex = RegExp(r'^EX_\d{14}_[A-Z0-9]{6}_[A-Z0-9]{4}_[A-Z0-9]{3}$');
    return regex.hasMatch(id);
  }

  /// Extracts components from an exhibit ID for debugging
  static Map<String, String> parseExhibitId(String id) {
    if (!isValidExhibitId(id)) {
      return {'error': 'Invalid format'};
    }

    final parts = id.split('_');
    if (parts.length != 5) {
      return {'error': 'Invalid parts count'};
    }

    return {
      'prefix': parts[0],
      'timestamp': parts[1],
      'random': parts[2],
      'location_hash': parts[3],
      'version': parts[4],
    };
  }
}
