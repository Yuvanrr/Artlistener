import 'package:cloud_firestore/cloud_firestore.dart';

class ConfigService {
  static const String _configCollection = 'app_config';
  static const String _allowedSsidsDoc = 'allowed_ssids';

  // Default SSIDs as fallback
  static const List<String> _defaultSsids = [
    'PSG',
    'MuseumWiFi',
    'GalleryNet',
    'ExhibitNet',
    'MuseumGuest',
  ];

  /// Initialize the database with default configuration
  static Future<void> initializeDefaultConfig() async {
    try {
      print('Initializing default SSID configuration...');
      await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_allowedSsidsDoc)
          .set({
            'ssids': _defaultSsids,
            'updated_at': FieldValue.serverTimestamp(),
          });
      print('Default configuration initialized successfully');
    } catch (e) {
      print('Error initializing default config: $e');
    }
  }

  /// Fetches allowed SSIDs from database, falls back to defaults if not found
  static Future<List<String>> getAllowedSsids() async {
    try {
      print('Fetching SSIDs from database...');
      final doc = await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_allowedSsidsDoc)
          .get();

      print('Document exists: ${doc.exists}');

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final ssids = data['ssids'] as List<dynamic>?;

        print('Raw SSIDs from DB: $ssids');

        if (ssids != null && ssids.isNotEmpty) {
          final result = ssids.map((ssid) => ssid.toString()).toList();
          print('Parsed SSIDs: $result');
          return result;
        }
      }

      // Return defaults if no config found or empty
      print('Using default SSIDs: $_defaultSsids');
      return _defaultSsids;
    } catch (e) {
      print('Error fetching allowed SSIDs: $e');
      // Return defaults on error
      return _defaultSsids;
    }
  }

  /// Saves allowed SSIDs to database
  static Future<void> setAllowedSsids(List<String> ssids) async {
    try {
      await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_allowedSsidsDoc)
          .set({
            'ssids': ssids,
            'updated_at': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error saving allowed SSIDs: $e');
      throw e;
    }
  }

  /// Adds a new SSID to the allowed list
  static Future<void> addAllowedSsid(String ssid) async {
    try {
      final currentSsids = await getAllowedSsids();

      if (!currentSsids.contains(ssid)) {
        final updatedSsids = [...currentSsids, ssid];
        await setAllowedSsids(updatedSsids);
      }
    } catch (e) {
      print('Error adding allowed SSID: $e');
      throw e;
    }
  }

  /// Removes an SSID from the allowed list
  static Future<void> removeAllowedSsid(String ssid) async {
    try {
      final currentSsids = await getAllowedSsids();
      final updatedSsids = currentSsids.where((s) => s != ssid).toList();
      await setAllowedSsids(updatedSsids);
    } catch (e) {
      print('Error removing allowed SSID: $e');
      throw e;
    }
  }
}
