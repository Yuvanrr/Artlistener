import 'package:wifi_scan/wifi_scan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WifiService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Check if WiFi scanning is supported on the device
  Future<bool> get canScanWifi async {
    final can = await WiFiScan.instance.canStartScan();
    return can == CanStartScan.yes;
  }

  // Scan for nearby WiFi networks
  Future<List<WiFiAccessPoint>> scanNetworks() async {
    try {
      // Check if WiFi scanning is available
      final can = await canScanWifi;
      if (!can) {
        throw Exception('WiFi scanning is not available on this device');
      }

      // Start a new scan
      final result = await WiFiScan.instance.startScan();
      if (result == true) {
        // Wait a moment for scan results
        await Future.delayed(const Duration(seconds: 2));
        // Get the results
        final results = await WiFiScan.instance.getScannedResults();
        return results;
      }
      return [];
    } catch (e) {
      print('Error scanning WiFi: $e');
      return [];
    }
  }

  // Find matching exhibit based on WiFi fingerprint
  Future<Map<String, dynamic>?> findMatchingExhibit() async {
    try {
      // Get current WiFi scan results
      final accessPoints = await scanNetworks();
      if (accessPoints.isEmpty) {
        return null;
      }

      // Get all exhibits from Firestore
      final snapshot = await _firestore.collection('exhibits').get();
      
      // Convert access points to a map for easier comparison
      final currentFingerprint = {
        for (var ap in accessPoints) 
          ap.bssid: {
            'ssid': ap.ssid,
            'level': ap.level,
            'frequency': ap.frequency,
            'capabilities': ap.capabilities,
          }
      };

      // Find matching exhibit
      for (var doc in snapshot.docs) {
        final exhibitData = doc.data();
        if (exhibitData.containsKey('wifiFingerprint')) {
          final storedFingerprint = Map<String, dynamic>.from(exhibitData['wifiFingerprint']);
          
          // Check if any BSSID in the stored fingerprint matches current scan
          for (var bssid in storedFingerprint.keys) {
            if (currentFingerprint.containsKey(bssid)) {
              // Found a matching BSSID, return this exhibit
              return {
                'id': doc.id,
                ...exhibitData,
              };
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Error finding matching exhibit: $e');
      return null;
    }
  }
}
