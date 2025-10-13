import 'package:wifi_scan/wifi_scan.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WifiService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Check if WiFi scanning is supported on the device
  Future<({bool canScan, String? reason})> get canScanWifi async {
    try {
      final can = await WiFiScan.instance.canStartScan(askPermissions: true);
      
      // If we can scan, return early with success
      if (can == CanStartScan.yes) {
        return (canScan: true, reason: null);
      }
      
      // For all other cases, return a generic message and log the actual error
      print('WiFi scan not available: $can');
      return (
        canScan: false, 
        reason: 'WiFi scanning is not available. Please ensure location services are enabled and the app has location permission.'
      );
    } catch (e) {
      print('Error checking WiFi scan availability: $e');
      return (
        canScan: false, 
        reason: 'Error checking WiFi scan availability. Please try again.'
      );
    }
  }

  // Scan for nearby WiFi networks
  Future<List<WiFiAccessPoint>> scanNetworks() async {
    try {
      // Check if WiFi scanning is available
      final scanCheck = await canScanWifi;
      if (!scanCheck.canScan) {
        throw Exception(scanCheck.reason ?? 'WiFi scanning is not available');
      }

      print('Starting WiFi scan...');
      final result = await WiFiScan.instance.startScan();
      
      if (result != true) {
        throw Exception('Failed to start WiFi scan');
      }
      
      print('Waiting for scan results...');
      // Wait a moment for scan results (increased from 2 to 3 seconds)
      await Future.delayed(const Duration(seconds: 3));
      
      // Get the results
      final results = await WiFiScan.instance.getScannedResults();
      print('Found ${results.length} WiFi networks');
      
      // Log first few networks for debugging
      final networksToLog = results.take(3).toList();
      for (var i = 0; i < networksToLog.length; i++) {
        final network = networksToLog[i];
        print('Network ${i + 1}: ${network.ssid} (${network.bssid}), Strength: ${network.level}dBm');
      }
      
      return results;
    } catch (e) {
      print('Error scanning WiFi: $e');
      rethrow; // Re-throw to allow callers to handle the error
    }
  }

  // Find matching exhibit based on WiFi fingerprint
  Future<({Map<String, dynamic>? exhibit, String? error})> findMatchingExhibit() async {
    try {
      print('Starting exhibit matching process...');
      
      // Check if WiFi scanning is available first
      final scanCheck = await canScanWifi;
      if (!scanCheck.canScan) {
        final error = 'Cannot scan for exhibits: ${scanCheck.reason}';
        print(error);
        return (exhibit: null, error: error);
      }

      print('Scanning for nearby WiFi networks...');
      // Get current WiFi scan results
      List<WiFiAccessPoint> accessPoints;
      try {
        accessPoints = await scanNetworks();
      } catch (e) {
        final error = 'Failed to scan WiFi networks: $e';
        print(error);
        return (exhibit: null, error: error);
      }

      if (accessPoints.isEmpty) {
        final error = 'No WiFi networks found. Please ensure WiFi is enabled and you are in range of networks.';
        print(error);
        return (exhibit: null, error: error);
      }

      print('Fetching exhibits from database...');
      // Get all exhibits from Firestore
      final snapshot = await _firestore.collection('exhibits').get();
      
      if (snapshot.docs.isEmpty) {
        final error = 'No exhibits found in the database. Please add exhibits first.';
        print(error);
        return (exhibit: null, error: error);
      }

      // Convert current scan to a map of BSSID to RSSI
      final currentFingerprint = {
        for (var ap in accessPoints) ap.bssid: ap.level
      };

      print('Found ${accessPoints.length} WiFi networks and ${snapshot.docs.length} exhibits to compare');
      
      Map<String, dynamic>? bestMatch;
      double bestScore = 0.0;
      int exhibitsWithFingerprints = 0;

      // Compare with each exhibit's WiFi fingerprint zones
      for (var doc in snapshot.docs) {
        final exhibitData = doc.data();
        if (exhibitData['fingerprintZones'] == null || exhibitData['fingerprintZones'].isEmpty) {
          // Fallback to old single fingerprint method if zones not available
          if (exhibitData['wifiFingerprint'] != null) {
            final exhibitFingerprint = Map<String, dynamic>.from(exhibitData['wifiFingerprint']);
            final score = _calculateMatchScore(currentFingerprint, exhibitFingerprint);
            
            if (score > bestScore) {
              bestScore = score;
              bestMatch = {
                'id': doc.id,
                ...exhibitData,
                'matchScore': score,
              };
            }
          }
          continue; // Skip exhibits without zones or fingerprints
        }
        
        try {
          final fingerprintZones = List<Map<String, dynamic>>.from(exhibitData['fingerprintZones']);
          double zoneBestScore = 0.0;
          
          // Check each zone for the best match
          for (var zone in fingerprintZones) {
            final zoneFingerprint = Map<String, dynamic>.from(zone['fingerprint']);
            final score = _calculateMatchScore(currentFingerprint, zoneFingerprint);
            
            if (score > zoneBestScore) {
              zoneBestScore = score;
            }
          }
          
          print('Exhibit "${exhibitData['name'] ?? doc.id}" best zone match score: ${(zoneBestScore * 100).toStringAsFixed(1)}%');
          
          if (zoneBestScore > bestScore) {
            bestScore = zoneBestScore;
            bestMatch = {
              'id': doc.id,
              ...exhibitData,
              'matchScore': zoneBestScore,
            };
          }
        } catch (e) {
          print('Error processing exhibit ${exhibitData['name'] ?? doc.id}: $e');
          continue;
        }
      }

      if (exhibitsWithFingerprints == 0) {
        final error = 'No exhibits with WiFi fingerprints or zones found in the database.';
        print(error);
        return (exhibit: null, error: error);
      }

      // Only return a match if the score is above a certain threshold
      if (bestScore > 0.5) {
        final matchMessage = '✅ Found matching exhibit: ${bestMatch?['name'] ?? 'Unknown'} (${(bestScore * 100).toStringAsFixed(1)}% match)';
        print(matchMessage);
        return (exhibit: bestMatch, error: null);
      }
      
      final message = 'No matching exhibit found nearby. Best match score was ${(bestScore * 100).toStringAsFixed(1)}%';
      print('❌ $message');
      return (exhibit: null, error: message);

    } catch (e, stackTrace) {
      final error = 'Unexpected error finding matching exhibit: $e\n$stackTrace';
      print(error);
      return (exhibit: null, error: 'An unexpected error occurred. Please try again.');
    }
  }

  // Calculate a match score between two WiFi fingerprints
  // Returns a value between 0.0 (no match) and 1.0 (perfect match)
  double _calculateMatchScore(
    Map<String, int> currentFingerprint,
    Map<String, dynamic> exhibitFingerprint,
  ) {
    // If either fingerprint is empty, return 0
    if (currentFingerprint.isEmpty || exhibitFingerprint.isEmpty) {
      return 0.0;
    }

    int matchingNetworks = 0;
    double signalStrengthScore = 0.0;
    
    // Maximum possible signal strength difference (dBm)
    const maxSignalDiff = 100.0;
    
    // Convert exhibitFingerprint values to int if they're not already
    final exhibitFingerprintInt = exhibitFingerprint.map<String, int>(
      (key, value) => MapEntry(key, value is int ? value : int.tryParse(value.toString()) ?? -100)
    );
    
    // Find matching networks and calculate signal strength differences
    for (final entry in currentFingerprint.entries) {
      final bssid = entry.key;
      final currentRssi = entry.value;
      
      if (exhibitFingerprintInt.containsKey(bssid)) {
        matchingNetworks++;
        final exhibitRssi = exhibitFingerprintInt[bssid]!;
        
        // Calculate signal strength similarity (0.0 to 1.0)
        final signalDiff = (currentRssi - exhibitRssi).abs();
        final signalSimilarity = 1.0 - (signalDiff / maxSignalDiff).clamp(0.0, 1.0);
        
        // Weight by signal strength (stronger signals have more weight)
        final weight = (currentRssi + 100) / 100.0; // Convert from -100..0 to 0..1
        signalStrengthScore += signalSimilarity * weight;
      }
    }
    
    // If no matching networks, return 0
    if (matchingNetworks == 0) {
      return 0.0;
    }
    
    // Calculate network presence score (0.0 to 1.0)
    final presenceScore = matchingNetworks / exhibitFingerprintInt.length;
    
    // Calculate average signal strength score
    final avgSignalScore = signalStrengthScore / matchingNetworks;
    
    // Combine scores with weights (adjust these based on testing)
    const presenceWeight = 0.4;
    const signalWeight = 0.6;
    
    final totalScore = (presenceScore * presenceWeight) + (avgSignalScore * signalWeight);
    
    // Ensure the score is between 0.0 and 1.0
    return totalScore.clamp(0.0, 1.0);
  }
}
