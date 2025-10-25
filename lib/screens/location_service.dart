import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;

// Data model for the matched exhibit result (Unchanged)
class ExhibitMatchResult {
  final String id;
  final String name;
  final String description;
  final String? audioUrl;
  final double confidenceDistance; // The calculated WkNN confidence

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
    Map<String, Map<String, dynamic>> liveFingerprint, 
    Map<String, Map<String, dynamic>> storedFingerprint) {
  
  double squaredDifferenceSum = 0.0;
  final allBssids = {...liveFingerprint.keys, ...storedFingerprint.keys};
  
  const int defaultRssi = -100;

  for (final bssid in allBssids) {
    final liveData = liveFingerprint[bssid];
    final storedData = storedFingerprint[bssid];

    final liveRssi = liveData?['rssi']?.toInt() ?? defaultRssi;
    final storedRssi = storedData?['rssi']?.toInt() ?? defaultRssi;

    final rssiDiff = (liveRssi - storedRssi);
    
    squaredDifferenceSum += rssiDiff * rssiDiff; 
  }
  
  return squaredDifferenceSum; 
}


class LocationService {
  static const List<String> _targetSsids = ['MCA', 'PSG'];
  static const int K_NEIGHBORS = 3; // Setting K for WkNN

  // --- ACCURACY ENHANCEMENT: TEMPORAL AVERAGING (5 Scans) with FILTERING ---
  Future<Map<String, Map<String, dynamic>>> getAveragedFingerprint(int scanCount) async {
    final Map<String, List<Map<String, dynamic>>> rssiHistory = {};

    for (int i = 0; i < scanCount; i++) {
      final bool scanStarted = await wifi_scan.WiFiScan.instance.startScan();
      
      if (scanStarted) {
          // Increased delay for cache-busting
          await Future.delayed(const Duration(milliseconds: 1500)); 
      }
      final currentScan = await wifi_scan.WiFiScan.instance.getScannedResults();
      
      for (var ap in currentScan) {
          // Filter to only record target SSIDs (MCA, PSG)
          if (ap.bssid.isNotEmpty && _targetSsids.contains(ap.ssid)) {
              final apData = {
                  'rssi': ap.level, 
                  'frequency': ap.frequency
              };
              rssiHistory.putIfAbsent(ap.bssid, () => []).add(apData);
          }
      }
      
      // Wait between averaging cycles
      if (i < scanCount - 1) await Future.delayed(const Duration(milliseconds: 700)); 
    }

    final Map<String, Map<String, dynamic>> averagedFingerprint = {};
    rssiHistory.forEach((bssid, dataList) {
      final int totalRssi = dataList.map((d) => d['rssi'] as int).reduce((a, b) => a + b);
      final int averageRssi = (totalRssi / dataList.length).round();
      
      final int frequency = dataList.first['frequency'] as int; 

      averagedFingerprint[bssid] = {
        'rssi': averageRssi,
        'frequency': frequency,
      };
    });

    return averagedFingerprint;
  }
  
  // --- CORE WKNN MATCHING LOGIC ---
  Future<ExhibitMatchResult?> findClosestExhibit() async {
    final liveFingerprint = await getAveragedFingerprint(5);

    if (liveFingerprint.isEmpty) return null;

    final qs = await FirebaseFirestore.instance.collection('c_guru').get();
    if (qs.docs.isEmpty) return null;

    final List<Map<String, dynamic>> matchResults = [];
    
    // 1. Calculate Distance for ALL stored exhibits
    for (final doc in qs.docs) {
      final data = doc.data();
      final List<dynamic>? wifiFingerprintList = data['wifi_fingerprint'] as List<dynamic>?;
      
      if (wifiFingerprintList == null || wifiFingerprintList.isEmpty) continue;

      final Map<String, Map<String, dynamic>> storedFingerprint = {
        for (var item in wifiFingerprintList)
          if (item is Map<String, dynamic> && item['bssid'] is String && item['rssi'] is num)
            item['bssid'] as String: {
                'rssi': (item['rssi'] as num).toInt(),
                'frequency': (item['frequency'] as num).toInt(),
            }
      };

      if (storedFingerprint.isEmpty) continue;

      final distanceSquared = calculateEuclideanDistance(liveFingerprint, storedFingerprint);

      matchResults.add({
        'docId': doc.id,
        'distance': distanceSquared,
        'data': data,
      });
    }

    if (matchResults.isEmpty) return null;

    // 2. Sort results and select top K neighbors
    matchResults.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));
    final nearestNeighbors = matchResults.take(K_NEIGHBORS).toList();
    
    // 3. WkNN: Determine final exhibit by finding the one with the highest collective weight
    
    // Total weight for the winning exhibit (used for confidence scoring)
    double totalInverseDistance = 0.0; 
    
    // Determine the winning Exhibit ID based on highest cumulative weight
    Map<String, double> exhibitWeightMap = {};

    for (final match in nearestNeighbors) {
      final double distance = match['distance'];
      final String exhibitId = match['docId'];
      
      // Calculate weight: Use inverse of distance (or inverse squared distance)
      // We use (1.0 / (distance + small_epsilon)) to prevent division by zero if distance is 0.
      final double weight = 1.0 / (distance + 1.0); 

      // Accumulate total weight for this exhibit ID
      exhibitWeightMap.update(exhibitId, (value) => value + weight, ifAbsent: () => weight);
      totalInverseDistance += weight;
    }
    
    // Find the Exhibit ID with the maximum accumulated weight
    String? winningExhibitId;
    double maxWeight = 0.0;

    exhibitWeightMap.forEach((id, weight) {
      if (weight > maxWeight) {
        maxWeight = weight;
        winningExhibitId = id;
      }
    });

    if (winningExhibitId == null) return null;
    
    // 4. Retrieve and return the data for the winning exhibit
    final winningMatch = nearestNeighbors.firstWhere((m) => m['docId'] == winningExhibitId);
    final winningData = winningMatch['data'] as Map<String, dynamic>;
    
    // Use the max weight (or related inverse distance) as the final confidence score
    final finalConfidenceScore = totalInverseDistance; 

    // Final threshold check remains high for safety
    if (finalConfidenceScore < 0.0001) { // If total inverse distance is near zero, reject
      return null;
    }
    
    return ExhibitMatchResult(
      id: winningExhibitId!,
      name: (winningData['name'] ?? '').toString(),
      description: (winningData['description'] ?? '').toString(),
      audioUrl: (winningData['audioUrl'] as String?),
      confidenceDistance: finalConfidenceScore, // Using total inverse weight as the final "score"
    );
  }
}