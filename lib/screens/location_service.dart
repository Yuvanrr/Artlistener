import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'dart:math';

// Data model for the matched exhibit result
class ExhibitMatchResult {
  final String id;
  final String name;
  final String description;
  final String? audioUrl;
  final double confidenceDistance;

  ExhibitMatchResult({
    required this.id,
    required this.name,
    required this.description,
    this.audioUrl,
    required this.confidenceDistance,
  });
}

// --- KNN HELPER FUNCTION ---
double calculateEuclideanDistance(
    Map<String, int> liveRssiMap, Map<String, int> storedRssiMap) {
  double squaredDifferenceSum = 0.0;
  // Use the union of BSSIDs found in both fingerprints for comparison
  final allBssids = {...liveRssiMap.keys, ...storedRssiMap.keys};
  const int defaultRssi = -100;

  for (final bssid in allBssids) {
    final liveRssi = liveRssiMap[bssid] ?? defaultRssi;
    final storedRssi = storedRssiMap[bssid] ?? defaultRssi;
    final diff = (liveRssi - storedRssi);
    squaredDifferenceSum += diff * diff;
  }
  return squaredDifferenceSum; 
}
// --- END KNN HELPER FUNCTION ---


class LocationService {
  // Define the critical SSIDs for both saving and retrieving
  static const List<String> _targetSsids = ['MCA', 'PSG'];

  // --- ACCURACY ENHANCEMENT: TEMPORAL AVERAGING (5 Scans) with FILTERING ---
  Future<Map<String, int>> getAveragedFingerprint(int scanCount) async {
    final Map<String, List<int>> rssiHistory = {};

    for (int i = 0; i < scanCount; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 300)); 
      
      await wifi_scan.WiFiScan.instance.startScan();
      final currentScan = await wifi_scan.WiFiScan.instance.getScannedResults();
      
      for (var ap in currentScan) {
          // KEY CHANGE: ONLY record the target SSIDs for the live fingerprint
          if (ap.bssid.isNotEmpty && _targetSsids.contains(ap.ssid)) {
              rssiHistory.putIfAbsent(ap.bssid, () => []).add(ap.level);
          }
      }
    }

    final Map<String, int> averagedRssiMap = {};
    rssiHistory.forEach((bssid, rssiList) {
      // Calculate the average RSSI for each BSSID
      final averageRssi = (rssiList.reduce((a, b) => a + b) / rssiList.length).round();
      averagedRssiMap[bssid] = averageRssi;
    });

    return averagedRssiMap;
  }
  
  // --- CORE KNN MATCHING LOGIC ---
  Future<ExhibitMatchResult?> findClosestExhibit() async {
    // 1. Capture Live Fingerprint Vector: Now FILTERS for 'MCA'/'PSG'
    final liveRssiMap = await getAveragedFingerprint(5);

    if (liveRssiMap.isEmpty) return null;

    // 2. Query Firestore for all exhibits
    final qs = await FirebaseFirestore.instance.collection('c_guru').get();
    if (qs.docs.isEmpty) return null;

    final List<Map<String, dynamic>> matchResults = [];
    
    // 3. Calculate Distance (KNN step)
    for (final doc in qs.docs) {
      final data = doc.data();
      final List<dynamic>? wifiFingerprintList = data['wifi_fingerprint'] as List<dynamic>?;
      
      if (wifiFingerprintList == null || wifiFingerprintList.isEmpty) continue;

      final Map<String, int> storedRssiMap = {
        for (var item in wifiFingerprintList)
          if (item is Map<String, dynamic> && item['bssid'] is String && item['rssi'] is num)
            item['bssid'] as String: (item['rssi'] as num).toInt()
      };

      if (storedRssiMap.isEmpty) continue;

      // The similarity calculation now works correctly because both inputs (live and stored)
      // contain ONLY the BSSIDs of MCA and PSG.
      final distanceSquared = calculateEuclideanDistance(liveRssiMap, storedRssiMap);

      matchResults.add({
        'docId': doc.id,
        'distance': distanceSquared,
        'data': data,
      });
    }

    if (matchResults.isEmpty) return null;

    // 4. Find Best Match (Nearest Neighbor)
    matchResults.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    final bestMatch = matchResults.first;
    final bestData = bestMatch['data'] as Map<String, dynamic>;
    final confidenceDistance = bestMatch['distance'] as double;
    
    // Threshold set higher as a safety measure. You can adjust this after testing.
    const double distanceThreshold = 5000.0; 
    if (confidenceDistance > distanceThreshold) {
      // If the best match is still too far, return null (no confident match)
      return null;
    }
    
    return ExhibitMatchResult(
      id: bestMatch['docId'],
      name: (bestData['name'] ?? '').toString(),
      description: (bestData['description'] ?? '').toString(),
      audioUrl: (bestData['audioUrl'] as String?),
      confidenceDistance: confidenceDistance,
    );
  }
}