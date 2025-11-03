import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'dart:math';
import '../services/sensor_fusion_service.dart';

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

class LocationService {
  // Enhanced parameters for high-interference environments
  static const double MAX_DISTANCE_THRESHOLD = 12.0; // Tighter threshold for better accuracy
  static const int MIN_MATCHING_APS = 4; // Increased minimum APs for more reliable detection
  static const double AMBIGUITY_THRESHOLD = 0.85; // Slightly stricter for better precision
  static const double FREQUENCY_BONUS_MULTIPLIER = 12.0; // Increased to favor 5GHz networks
  static const double MIN_FREQUENCY_DIVERSITY = 0.4; // Increased for better reliability
  static const int FREQUENCY_TOLERANCE_MHZ = 20; // Slightly tighter tolerance
  static const int MIN_5GHZ_APS = 1; // Require at least one 5GHz AP

  // Enhanced scanning parameters
  static const int MULTI_SCAN_COUNT = 5; // Increased for better stability
  static const double RSSI_VARIANCE_THRESHOLD = 4.5; // Tighter variance for stability
  static const double ULTRA_PRECISE_RADIUS_METERS = 4.0; // Slightly tighter radius
  static const int MAX_SCAN_ATTEMPTS = 3; // Max attempts for scan validation
  static const double MIN_SIGNAL_QUALITY = 0.7; // Minimum signal quality score

  // Sensor fusion integration
  final SensorFusionService _sensorFusion = SensorFusionService();
  bool _isInitialized = false;

  // Check if LocationService is properly initialized
  bool get isInitialized => _isInitialized;

  // Helper method to determine if two frequencies are in the same band
  bool _isSameFrequencyBand(int freq1, int freq2) {
    // 2.4GHz band: typically 2400-2500 MHz
    // 5GHz band: typically 5000-6000 MHz
    const int band2_4GHzStart = 2400;
    const int band2_4GHzEnd = 2500;
    const int band5GHzStart = 5000;
    const int band5GHzEnd = 6000;

    bool freq1Is2_4GHz = freq1 >= band2_4GHzStart && freq1 <= band2_4GHzEnd;
    bool freq2Is2_4GHz = freq2 >= band2_4GHzStart && freq2 <= band2_4GHzEnd;

    bool freq1Is5GHz = freq1 >= band5GHzStart && freq1 <= band5GHzEnd;
    bool freq2Is5GHz = freq2 >= band5GHzStart && freq2 <= band5GHzEnd;

    // Same band if both are 2.4GHz or both are 5GHz
    return (freq1Is2_4GHz && freq2Is2_4GHz) || (freq1Is5GHz && freq2Is5GHz);
  }

  // Helper method to check if frequency is in 2.4GHz band
  bool _is2_4GHzBand(int frequency) {
    return frequency >= 2400 && frequency <= 2500;
  }

  // Helper method to check if frequency is in 5GHz band
  bool _is5GHzBand(int frequency) {
    return frequency >= 5000 && frequency <= 6000;
  }

  // Helper method to convert frequency to channel number
  int _frequencyToChannel(int frequency) {
    // 2.4GHz channels
    if (frequency >= 2400 && frequency <= 2500) {
      // Channel 1: 2401-2423, Channel 2: 2404-2426, etc.
      return ((frequency - 2401) ~/ 5) + 1;
    }
    // 5GHz channels
    else if (frequency >= 5000 && frequency <= 6000) {
      // Common 5GHz channels: 36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165
      if (frequency >= 5150 && frequency <= 5250) return 36 + ((frequency - 5150) ~/ 10) * 2;
      if (frequency >= 5250 && frequency <= 5350) return 52 + ((frequency - 5250) ~/ 10) * 2;
      if (frequency >= 5470 && frequency <= 5725) return 100 + ((frequency - 5470) ~/ 10) * 2;
      if (frequency >= 5725 && frequency <= 5875) return 116 + ((frequency - 5725) ~/ 10) * 2;
    }
    return 0; // Unknown channel
  }

  // Initialize sensor fusion for enhanced detection
  Future<bool> initialize() async {
    print('🔄 Initializing sensor fusion for enhanced exhibit detection...');
    try {
      final success = await _sensorFusion.initialize();
      if (success) {
        print('✅ Sensor fusion initialized successfully');
        _isInitialized = true;
      } else {
        print('⚠️ Sensor fusion initialization failed - falling back to WiFi-only mode');
        _isInitialized = false;
      }
      return success;
    } catch (e) {
      print('❌ LocationService initialization error: $e');
      _isInitialized = false;
      return false;
    }
  }

  // Check if user is stationary for stable WiFi fingerprinting
  bool isUserStationary({double threshold = 0.5}) {
    return _sensorFusion.isStationary(threshold: threshold);
  }

  // Get sensor quality metrics for detection confidence
  Map<String, double> getSensorQuality() {
    return _sensorFusion.getSensorQuality();
  }

  // Get movement confidence for detection validation
  double getMovementConfidence() {
    return _sensorFusion.getMovementConfidence();
  }

  // Dispose of sensor fusion resources
  void dispose() {
    _sensorFusion.dispose();
    _isInitialized = false;
  }

  // Multi-scan averaging for stable detection with timeouts
  Future<List<wifi_scan.WiFiAccessPoint>> _performMultiScan() async {
    final List<List<wifi_scan.WiFiAccessPoint>> allScans = [];
    const scanTimeout = Duration(seconds: 10); // Timeout for each scan

    print('📡 Performing $MULTI_SCAN_COUNT averaged scans for stable detection...');

    for (int i = 0; i < MULTI_SCAN_COUNT; i++) {
      try {
        final can = await wifi_scan.WiFiScan.instance.canStartScan();
        if (can == wifi_scan.CanStartScan.yes) {
          // Timeout the scan start
          await wifi_scan.WiFiScan.instance.startScan().timeout(scanTimeout, onTimeout: () {
            print('  ⏱️ Scan start timed out');
            throw TimeoutException('Scan start timed out');
          });

          // Adaptive delay based on previous scan size
          final delay = allScans.isNotEmpty && allScans.last.length > 20 ? 1000 : 500;
          await Future.delayed(Duration(milliseconds: delay));

          // Timeout getting results
          final scanResults = await wifi_scan.WiFiScan.instance.getScannedResults().timeout(scanTimeout, onTimeout: () {
            print('  ⏱️ Get results timed out');
            throw TimeoutException('Get scanned results timed out');
          });

          if (scanResults.isNotEmpty) {
            allScans.add(scanResults);
            print('  📱 Scan ${i + 1}/$MULTI_SCAN_COUNT: ${scanResults.length} networks');
          }
        }
      } catch (e) {
        print('  ❌ Scan $i failed: $e');
        // Continue to next scan instead of failing completely
      }

      if (i < MULTI_SCAN_COUNT - 1) {
        // Adaptive delay between scans
        final interDelay = allScans.isNotEmpty && allScans.last.length > 20 ? 500 : 200;
        await Future.delayed(Duration(milliseconds: interDelay));
      }
    }

    return _averageScans(allScans);
  }

  // Average multiple scans to reduce noise and improve stability
  List<wifi_scan.WiFiAccessPoint> _averageScans(List<List<wifi_scan.WiFiAccessPoint>> allScans) {
    if (allScans.isEmpty) return [];

    const maxAps = 15; // Limit to top 15 APs to reduce computation

    final Map<String, List<wifi_scan.WiFiAccessPoint>> apGroups = {};

    // Group APs by BSSID across all scans
    for (final scan in allScans) {
      for (final ap in scan) {
        if (ap.bssid.isNotEmpty) {
          apGroups.putIfAbsent(ap.bssid, () => []).add(ap);
        }
      }
    }

    final averagedAps = <wifi_scan.WiFiAccessPoint>[];

    // Average RSSI values and filter stable APs
    for (final bssid in apGroups.keys) {
      final apList = apGroups[bssid]!;

      if (apList.length >= 2) { // Require at least 2 scans for stability
        // Calculate average RSSI
        final avgRssi = apList.map((ap) => ap.level).reduce((a, b) => a + b) / apList.length;

        // Check RSSI variance (stability)
        final variance = _calculateRssiVariance(apList.map((ap) => ap.level.toDouble()).toList());

        if (variance <= RSSI_VARIANCE_THRESHOLD) {
          // Use the AP with RSSI closest to average (most representative)
          final representativeAp = apList.reduce((a, b) =>
            (a.level - avgRssi).abs() < (b.level - avgRssi).abs() ? a : b);

          // For now, use the most stable AP (we'll enhance this later with proper averaging)
          averagedAps.add(representativeAp);
          print('  📶 Stable AP: ${apList.first.ssid} (${bssid}) | Avg RSSI: ${avgRssi.round()} | Variance: ${variance.toStringAsFixed(1)} dB');
        }
      }
    }

    // Sort by stability (lower variance first) then by signal strength
    averagedAps.sort((a, b) {
      final aVariance = _calculateRssiVariance(apGroups[a.bssid]!.map((ap) => ap.level.toDouble()).toList());
      final bVariance = _calculateRssiVariance(apGroups[b.bssid]!.map((ap) => ap.level.toDouble()).toList());

      if (aVariance != bVariance) {
        return aVariance.compareTo(bVariance); // Lower variance first
      }
      return b.level.compareTo(a.level); // Then stronger signal first
    });

    // Limit to top maxAps
    return averagedAps.take(maxAps).toList();
  }

  // Enhanced RSSI variance calculation with outlier rejection
  double _calculateRssiVariance(List<double> values) {
    if (values.length < 2) return 0.0;

    // First pass: calculate initial mean and standard deviation
    double mean = values.reduce((a, b) => a + b) / values.length;
    double stdDev = sqrt(values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length);
    
    // Second pass: remove outliers (beyond 2 standard deviations)
    final filtered = values.where((v) => (v - mean).abs() <= 2 * stdDev).toList();
    
    // If we removed too many points, use original values
    if (filtered.length < values.length * 0.7) {
      filtered.clear();
      filtered.addAll(values);
    }
    
    // Recalculate with filtered data
    mean = filtered.reduce((a, b) => a + b) / filtered.length;
    final squaredDiffs = filtered.map((value) => pow(value - mean, 2)).toList();
    final variance = squaredDiffs.reduce((a, b) => a + b) / (filtered.length - 1);
    
    return sqrt(variance);
  }

  // Helper method to normalize channel width strings for consistent comparison
  String? _normalizeChannelWidth(String? channelWidth) {
    if (channelWidth == null || channelWidth.isEmpty) return null;

    // Convert to lowercase and extract the essential part
    String normalized = channelWidth.toLowerCase();

    // Handle different enum formats (e.g., "ChannelWidth.CHANNEL_WIDTH_20MHZ")
    if (normalized.contains('.')) {
      normalized = normalized.split('.').last;
    }

    // Handle cases where channelWidth might be an enum object
    if (normalized.contains('channelwidth')) {
      // Extract the part after 'channelwidth' (e.g., 'channelwidth_20mhz')
      if (normalized.contains('_')) {
        normalized = normalized.substring(normalized.lastIndexOf('_') + 1);
      }
    }

    // Map similar channel width values to standard forms
    switch (normalized) {
      case 'channel_width_20mhz':
      case '20mhz':
      case 'channelwidth_20mhz':
      case 'channel_width_20':
        return '20mhz';
      case 'channel_width_40mhz':
      case '40mhz':
      case 'channelwidth_40mhz':
      case 'channel_width_40':
        return '40mhz';
      case 'channel_width_80mhz':
      case '80mhz':
      case 'channelwidth_80mhz':
      case 'channel_width_80':
        return '80mhz';
      case 'channel_width_160mhz':
      case '160mhz':
      case 'channelwidth_160mhz':
      case 'channel_width_160':
        return '160mhz';
      default:
        return normalized; // Return as-is if no match
    }
  }

  Map<String, dynamic>? calculateSimpleDistance(
    Map<String, Map<String, dynamic>> liveFingerprint,
    Map<String, Map<String, dynamic>> storedFingerprint,
    String exhibitName,
    String docId,
    Map<String, dynamic> data) {

    final commonAps = <String>{};
    double weightedDistance = 0.0;
    int matchedCount = 0;

    print('  🔍 Comparing fingerprints for $exhibitName');
    print('    Live APs: ${liveFingerprint.keys.length}');
    print('    Stored APs: ${storedFingerprint.keys.length}');

    // Calculate how many exhibits each AP appears in (for weighting)
    final apFrequency = <String, int>{};
    for (var bssid in liveFingerprint.keys) {
      apFrequency[bssid] = 1; // Will be updated below
    }

    // Count occurrences of each AP across all exhibits
    for (var bssid in liveFingerprint.keys) {
      if (storedFingerprint.containsKey(bssid)) {
        commonAps.add(bssid);
        final liveRssi = liveFingerprint[bssid]!['rssi'] as int;
        final storedRssi = storedFingerprint[bssid]!['rssi'] as int;

        // Calculate RSSI difference with improved weighting (more realistic)
        final rssiDiff = (liveRssi - storedRssi).abs().toDouble();

        // Cap RSSI difference at reasonable maximum (30 dB is very significant)
        final cappedRssiDiff = min(rssiDiff, 30.0);

        // Scale RSSI difference more gradually (was 1:1, now more forgiving)
        final scaledRssiDiff = cappedRssiDiff * 0.5; // Reduce RSSI impact by half

        // Enhanced frequency comparison (not just band matching)
        final liveFreq = liveFingerprint[bssid]!['frequency'] as int;
        final storedFreq = storedFingerprint[bssid]!['frequency'] as int;
        final freqDiff = (liveFreq - storedFreq).abs().toDouble();

        // Scale frequency difference (smaller impact than RSSI, but consider tolerance)
        final scaledFreqDiff = (freqDiff <= FREQUENCY_TOLERANCE_MHZ) ? (freqDiff * 0.1) : (freqDiff * 0.2);

        // Channel width comparison with legacy compatibility
        final liveChannelWidth = liveFingerprint[bssid]!['channelWidth'] as String?;
        final storedChannelWidth = storedFingerprint[bssid]!['channelWidth'] as String?;

        // Normalize channel width strings for consistent comparison
        final liveChannelWidthNorm = _normalizeChannelWidth(liveChannelWidth);
        final storedChannelWidthNorm = _normalizeChannelWidth(storedChannelWidth);

        // SSID comparison - exact match bonus (ULTRA-PRECISE)
        final liveSsid = liveFingerprint[bssid]!['ssid'] as String?;
        final storedSsid = storedFingerprint[bssid]!['ssid'] as String?;
        final ssidMatch = (liveSsid == storedSsid) ? 0.0 : 3.0; // Relaxed penalty for different SSIDs

        // Channel number comparison - exact match bonus (ULTRA-PRECISE)
        final liveChannel = liveFingerprint[bssid]!['channel'] as int;
        final storedChannel = storedFingerprint[bssid]!['channel'] as int;
        final channelMatch = (liveChannel == storedChannel) ? 0.0 : 2.0; // Relaxed penalty for different channels

        // More strict channel width matching - penalize any differences
        final liveChannelWidthMatch = liveFingerprint[bssid]!['channelWidth'] as String?;
        final storedChannelWidthMatch = storedFingerprint[bssid]!['channelWidth'] as String?;
        final liveChannelWidthNormMatch = _normalizeChannelWidth(liveChannelWidthMatch);
        final storedChannelWidthNormMatch = _normalizeChannelWidth(storedChannelWidthMatch);
        final channelWidthMatch = (liveChannelWidthNormMatch == storedChannelWidthNormMatch ||
                                  (storedChannelWidthMatch == null && liveChannelWidthNormMatch != null)) ? 0.0 : 1.0;

        // Weight by how unique this AP is (less common APs get higher weight)
        final uniqueness = 1.0 / (apFrequency[bssid]! + 1);
        final weightMultiplier = 1.0 + uniqueness; // Relaxed weight for unique APs

        // Combined distance with all factors
        final combinedDiff = scaledRssiDiff + scaledFreqDiff + ssidMatch + channelMatch + channelWidthMatch;
        final weightedDiff = combinedDiff * weightMultiplier;

        weightedDistance += weightedDiff;
        matchedCount++;

        print('    📶 Match: $bssid | Live: $liveRssi | Stored: $storedRssi | RSSI_Diff: ${rssiDiff.toStringAsFixed(1)} (scaled: ${scaledRssiDiff.toStringAsFixed(1)}) | Freq_Diff: $freqDiff | SSID_Match: $ssidMatch | Channel_Match: $channelMatch | Ch_Match: $channelWidthMatch | ChWidth: $liveChannelWidth → $liveChannelWidthNorm | Stored: $storedChannelWidth → $storedChannelWidthNorm | Weight: ${uniqueness.toStringAsFixed(2)} | Total: ${combinedDiff.toStringAsFixed(1)}');
      }
    }

    if (matchedCount == 0) {
      print('    ❌ No matching APs');
      return null;
    }

    // Calculate fingerprint completeness (how many of the stored APs we can see)
    final storedApCount = storedFingerprint.keys.length;
    final completeness = matchedCount / storedApCount;

    // Calculate frequency consistency (bonus for matching frequency bands)
    double frequencyConsistency = 0.0;
    double channelWidthConsistency = 0.0;
    double ssidConsistency = 0.0;
    int frequencyMatches = 0;
    int channelWidthMatches = 0;
    int ssidMatches = 0;
    int totalFrequencyComparisons = 0;

    for (var bssid in commonAps) {
      final liveFreq = liveFingerprint[bssid]!['frequency'] as int;
      final storedFreq = storedFingerprint[bssid]!['frequency'] as int;
      final liveChannelWidth = liveFingerprint[bssid]!['channelWidth'] as String?;
      final storedChannelWidth = storedFingerprint[bssid]!['channelWidth'] as String?;

      totalFrequencyComparisons++;

      // Enhanced frequency consistency (exact frequency matching with tolerance)
      if (_isSameFrequencyBand(liveFreq, storedFreq)) {
        // Within same band, check if frequencies are close (within tolerance)
        if ((liveFreq - storedFreq).abs() <= FREQUENCY_TOLERANCE_MHZ) {
          frequencyMatches++;
        }
      }

      // Channel width consistency - handle legacy data gracefully
      final liveChannelWidthNorm = _normalizeChannelWidth(liveChannelWidth);
      final storedChannelWidthNorm = _normalizeChannelWidth(storedChannelWidth);

      // Count as match if: both null, both same, or stored is null (legacy compatibility)
      if (liveChannelWidthNorm == storedChannelWidthNorm ||
          (storedChannelWidth == null && liveChannelWidthNorm != null)) {
        channelWidthMatches++;
      }

      // SSID consistency - exact match
      final liveSsid = liveFingerprint[bssid]!['ssid'] as String?;
      final storedSsid = storedFingerprint[bssid]!['ssid'] as String?;
      if (liveSsid == storedSsid) {
        ssidMatches++;
      }
    }

    if (totalFrequencyComparisons > 0) {
      frequencyConsistency = frequencyMatches / totalFrequencyComparisons;
      channelWidthConsistency = channelWidthMatches / totalFrequencyComparisons;
      ssidConsistency = ssidMatches / totalFrequencyComparisons; // Fix missing ssid consistency
    }

    // Enhanced frequency diversity with band-specific scoring
    double diversityBonus = 0.0;
    final bandCounts = {
      '2.4GHz': 0,
      '5GHz': 0,
      'other': 0
    };
    
    for (final bssid in commonAps) {
      final freq = liveFingerprint[bssid]!['frequency'] as int;
      if (_is2_4GHzBand(freq)) {
        bandCounts['2.4GHz'] = bandCounts['2.4GHz']! + 1;
      } else if (_is5GHzBand(freq)) {
        bandCounts['5GHz'] = bandCounts['5GHz']! + 1;
      } else {
        bandCounts['other'] = bandCounts['other']! + 1;
      }
    }
    
    // Calculate band diversity score (0-1)
    final totalBands = (bandCounts['2.4GHz']! > 0 ? 1 : 0) + 
                      (bandCounts['5GHz']! > 0 ? 1 : 0);
    
    // Base bonus on number of bands and AP distribution
    if (totalBands >= 2 && matchedCount >= 4) {
      // More weight to 5GHz in high-interference environments
      final fiveGHzWeight = (bandCounts['5GHz']! / matchedCount) * 1.5;
      final twoPointFourGHzWeight = (bandCounts['2.4GHz']! / matchedCount) * 0.8;
      
      diversityBonus = 2.0 + (1.5 * fiveGHzWeight) + (0.5 * twoPointFourGHzWeight);
      print('    🌐 Enhanced frequency diversity: 2.4GHz: ${bandCounts['2.4GHz']}, 5GHz: ${bandCounts['5GHz']} | Bonus: ${diversityBonus.toStringAsFixed(2)}');
    }

    // Penalize incomplete fingerprints and reward frequency consistency (1-5m detection)
    final completenessPenalty = completeness < 0.3 ? 5.0 : 0.0; // Relaxed penalty for 1-5m radius
    final frequencyBonus = frequencyConsistency * 3.0; // Reduced from 10.0 - RSSI is more important
    final ssidBonus = ssidConsistency * 2.0; // Reduced from 6.0 - RSSI is more important

    final averageDistance = weightedDistance / matchedCount;
    final score = averageDistance + completenessPenalty - frequencyBonus - ssidBonus - diversityBonus + (2.7 / (matchedCount + 1)); // Reduced by 10% from 3.0

    print('    ✅ Final score: $score (Distance: $averageDistance, Completeness: ${(completeness * 100).toStringAsFixed(1)}%, FreqMatch: ${(frequencyConsistency * 100).toStringAsFixed(1)}%, SSIDMatch: ${(ssidConsistency * 100).toStringAsFixed(1)}%, ChWidthMatch: ${(channelWidthConsistency * 100).toStringAsFixed(1)}%, Diversity: $diversityBonus, APs: $matchedCount/$storedApCount)');

    // Show bonus calculations for debugging
    print('    💰 Bonuses: Freq=$frequencyBonus, SSID=$ssidBonus, Diversity=$diversityBonus | Penalty: $completenessPenalty');

    return {
      'docId': docId,
      'score': score,
      'distance': averageDistance,
      'matchingAps': matchedCount,
      'commonAps': commonAps.length,
      'completeness': completeness,
      'frequencyConsistency': frequencyConsistency,
      'channelWidthConsistency': channelWidthConsistency,
      'ssidConsistency': ssidConsistency,
      'name': exhibitName,
      'data': data,
    };
  }

  // --- 1-5 METER K-NN MATCHING ---
  Future<ExhibitMatchResult?> findClosestExhibit() async {
    const detectionTimeout = Duration(seconds: 30); // Overall timeout for detection

    try {
      return await _findClosestExhibitInternal().timeout(detectionTimeout, onTimeout: () {
        print('❌ Detection timed out after $detectionTimeout');
        return null;
      });
    } catch (e) {
      print('❌ Detection error: $e');
      return null;
    }
  }

  Future<ExhibitMatchResult?> _findClosestExhibitInternal() async {
    print('🔍 Starting exhibit detection (1-5m radius) with relaxed sensor fusion...');

    // Enhanced movement detection with adaptive thresholding
    final movementConfidence = getMovementConfidence();
    final isStationary = isUserStationary(threshold: 0.7);
    
    if (!isStationary) {
      print('🚶 User movement detected (confidence: ${(movementConfidence * 100).toStringAsFixed(1)}%)');
      if (movementConfidence < 0.4) {
        print('⚠️  High movement detected - requiring stronger signal evidence');
        // Increase minimum AP count and reduce variance threshold for moving users
        final adjustedMinAps = MIN_MATCHING_APS + 1;
        print('    Adjusted minimum APs: $adjustedMinAps (from $MIN_MATCHING_APS)');
      }
    }

    // Get sensor quality for confidence enhancement
    final sensorQuality = getSensorQuality();
    final sensorStability = sensorQuality['accelerometer_stability']!;
    print('📊 Sensor Quality: Movement=${(movementConfidence * 100).toStringAsFixed(1)}%, Accelerometer=${(sensorStability * 100).toStringAsFixed(1)}%');
    
    // Adjust detection parameters based on movement and environment
    final effectiveMinAps = movementConfidence < 0.4 ? MIN_MATCHING_APS + 1 : MIN_MATCHING_APS;
    final effectiveVarianceThreshold = movementConfidence < 0.4 
        ? RSSI_VARIANCE_THRESHOLD * 0.9 
        : RSSI_VARIANCE_THRESHOLD;
        
    if (movementConfidence < 0.4) {
      print('    🔄 Using adjusted parameters: MinAPs=$effectiveMinAps, MaxVariance=${effectiveVarianceThreshold.toStringAsFixed(1)}dB');
    }

    // Perform multi-scan averaging for stability and precision
    final currentScan = await _performMultiScan().timeout(const Duration(seconds: 15), onTimeout: () {
      print('❌ Multi-scan timed out');
      throw TimeoutException('Multi-scan timed out');
    });
    print('📡 Averaged scan: ${currentScan.length} stable networks');
    // Log current scan for debugging
    print('📱 Current Scan:');
    currentScan.forEach((ap) {
      print('   BSSID: ${ap.bssid} | RSSI: ${ap.level} | Freq: ${ap.frequency} | SSID: ${ap.ssid}');
    });

    if (currentScan.isEmpty) return null;

    // Get all exhibits from database
    final qs = await FirebaseFirestore.instance.collection('c_guru').get();
    print('📚 Found ${qs.docs.length} exhibits in database');

    if (qs.docs.isEmpty) return null;

    final List<Map<String, dynamic>> matchResults = [];

    // Calculate matches for all exhibits
    for (final doc in qs.docs) {
      try {
        final data = doc.data();
        final List<dynamic>? wifiFingerprintList = data['wifi_fingerprint'] as List<dynamic>?;

        if (wifiFingerprintList == null || wifiFingerprintList.isEmpty) continue;

        final Map<String, Map<String, dynamic>> storedFingerprint = {
          for (var item in wifiFingerprintList)
            if (item is Map<String, dynamic> && item['bssid'] is String && item['rssi'] is num)
              item['bssid'] as String: {
                  'rssi': (item['rssi'] as num).toInt(),
                  'frequency': (item['frequency'] as num?)?.toInt() ?? 2400,
                  'ssid': (item['ssid'] as String?) ?? '',
                  'channel': _frequencyToChannel((item['frequency'] as num?)?.toInt() ?? 2400),
              }
        };

        if (storedFingerprint.isEmpty) continue;

        // Log stored fingerprint for debugging
        print('📚 Stored Fingerprint for "${data['name']}":');
        storedFingerprint.forEach((bssid, details) {
          print('   BSSID: $bssid | RSSI: ${details['rssi']} | Freq: ${details['frequency']} | SSID: ${details['ssid']} | Channel: ${details['channel']}');
        });

        // ADAPTIVE filtering based on exhibit's stored AP count (inside exhibit loop)
        final storedApCount = storedFingerprint.keys.length;
        final adaptiveMinAps = min(MIN_MATCHING_APS, storedApCount); // Use stored count if less than min required
        final adaptiveCompleteness = storedApCount >= 4 ? 0.54 : (storedApCount >= 3 ? 0.45 : 0.36); // Relaxed by 10%

        // Enhance adaptive filtering with sensor data (reduced impact)
        final finalMinAps = movementConfidence > 0.8 ? adaptiveMinAps : max(1, adaptiveMinAps - 1); // More lenient when moving
        final finalCompleteness = movementConfidence > 0.8 ? adaptiveCompleteness : adaptiveCompleteness - 0.1; // More lenient when moving

        print('🎯 Enhanced Adaptive Filtering: MinAPs=$adaptiveMinAps→$finalMinAps, Completeness=${(adaptiveCompleteness * 100).toStringAsFixed(0)}%→${(finalCompleteness * 100).toStringAsFixed(0)}% (Movement: ${(movementConfidence * 100).toStringAsFixed(1)}%)');

        // Create live fingerprint for this specific exhibit
        final Map<String, Map<String, dynamic>> liveFingerprint = {};

        // ADAPTIVE RSSI filtering - start with relaxed threshold (eased up)
        int rssiThreshold = -60; // Start more relaxed (was -50)
        var candidateAps = currentScan.where((ap) => ap.level > rssiThreshold).toList();

        // Limit to top 20 APs to prevent overload
        if (candidateAps.length > 20) {
          candidateAps.sort((a, b) => b.level.compareTo(a.level));
          candidateAps = candidateAps.take(20).toList();
        }

        // If not enough APs, relax the threshold progressively (less aggressive)
        while (candidateAps.length < finalMinAps && rssiThreshold > -85) { // Allow down to -85 (was -80)
          rssiThreshold -= 10; // Relax by 10 dBm instead of 5
          candidateAps = currentScan.where((ap) => ap.level > rssiThreshold).toList();
          if (candidateAps.length > 20) {
            candidateAps.sort((a, b) => b.level.compareTo(a.level));
            candidateAps = candidateAps.take(20).toList();
          }
          print('🔄 Relaxed RSSI threshold to > $rssiThreshold dBm for exhibit "${data['name']}", found ${candidateAps.length} APs (Sensor Enhanced)');
        }

        // Final fallback: use top APs regardless of strength if still insufficient
        if (candidateAps.length < finalMinAps && currentScan.isNotEmpty) {
          candidateAps = currentScan.take(finalMinAps).toList(); // Use exactly what's needed
          print('🔄 Fallback: Using top ${candidateAps.length} APs regardless of signal strength for exhibit "${data['name']}" (Sensor Enhanced)');
        }

        candidateAps.sort((a, b) => b.level.compareTo(a.level)); // Strongest first

        // Select top APs with frequency diversity preference (reduced for precision)
        final selectedAps = <wifi_scan.WiFiAccessPoint>[];

        // FIRST PRIORITY: Select APs that match the stored fingerprint (if any)
        final matchingAps = candidateAps.where((ap) => storedFingerprint.containsKey(ap.bssid)).toList();
        if (matchingAps.isNotEmpty) {
          // Sort matching APs by RSSI (strongest first)
          matchingAps.sort((a, b) => b.level.compareTo(a.level));
          // Take up to 2 matching APs (or all if fewer)
          selectedAps.addAll(matchingAps.take(min(2, matchingAps.length)));
          print('🎯 Matching APs found: Selected ${selectedAps.length} APs that match stored fingerprint');
        }

        // SECOND PRIORITY: Fill remaining slots with frequency diversity
        final remainingSlots = 4 - selectedAps.length;
        if (remainingSlots > 0) {
          // For exhibits with very few APs, prioritize the most likely matches
          if (storedApCount <= 2) {
            // Just select the top remaining APs that could potentially match
            final remainingAps = candidateAps.where((ap) => !selectedAps.contains(ap)).take(remainingSlots);
            selectedAps.addAll(remainingAps);
            print('🎯 Small exhibit optimization: Added ${remainingAps.length} more APs for "${data['name']}"');
          } else {
            // Prioritize frequency diversity for remaining slots
            final remainingCandidateAps = candidateAps.where((ap) => !selectedAps.contains(ap)).toList();

            // Prioritize frequency diversity: aim for mix of 2.4GHz and 5GHz
            final aps2_4GHz = remainingCandidateAps.where((ap) => _is2_4GHzBand(ap.frequency)).toList();
            final aps5GHz = remainingCandidateAps.where((ap) => _is5GHzBand(ap.frequency)).toList();

            // Take up to remaining slots from each band
            selectedAps.addAll(aps2_4GHz.take(min(remainingSlots ~/ 2 + 1, aps2_4GHz.length)));
            final remainingAfter2_4GHz = remainingSlots - (selectedAps.length - matchingAps.length);
            selectedAps.addAll(aps5GHz.take(min(remainingAfter2_4GHz, aps5GHz.length)));

            // If still need more, fill with remaining strongest
            if (selectedAps.length < 4) {
              final finalRemaining = remainingCandidateAps.where((ap) => !selectedAps.contains(ap)).take(4 - selectedAps.length);
              selectedAps.addAll(finalRemaining);
            }

            // Limit to top 4 APs total
            selectedAps.take(4);
          }
        }

        // Create live fingerprint from selected APs
        for (var ap in selectedAps) {
          if (ap.bssid.isNotEmpty) {
            liveFingerprint[ap.bssid] = {
              'rssi': ap.level,
              'frequency': ap.frequency,
              'ssid': ap.ssid,
              'channelWidth': _normalizeChannelWidth(ap.channelWidth?.toString()),
              'channel': _frequencyToChannel(ap.frequency), // Add channel number
            };
          }
        }

        print('📡 Live Fingerprint:');
        liveFingerprint.forEach((bssid, details) {
          print('   BSSID: $bssid | RSSI: ${details['rssi']} | Freq: ${details['frequency']} | SSID: ${details['ssid']} | Channel: ${details['channel']}');
        });

        print('📡 AP Selection Summary for "${data['name']}":');
        print('   Total networks scanned: ${currentScan.length}');
        print('   Candidate networks (> $rssiThreshold dBm): ${candidateAps.length}');
        print('   Matching APs found: ${matchingAps.length}');
        print('   Selected for matching: ${selectedAps.length} APs (${matchingAps.length} matching + ${selectedAps.length - matchingAps.length} others)');
        print('   Stored APs in exhibit: $storedApCount');

        final matchResult = calculateSimpleDistance(liveFingerprint, storedFingerprint, data['name'] as String, doc.id, data);

        // Apply enhanced adaptive filtering to the result
        if (matchResult != null) {
          final matchingAps = matchResult['matchingAps'] as int;
          final completeness = matchResult['completeness'] as double;

          if (matchingAps >= finalMinAps && completeness >= finalCompleteness) {
            matchResults.add(matchResult);
            print('  ✅ ${data['name']} PASSED enhanced adaptive filtering: $matchingAps/$finalMinAps APs + ${(completeness * 100).toStringAsFixed(1)}%/${(finalCompleteness * 100).toStringAsFixed(0)}% completeness (Sensor Enhanced)');
          } else {
            print('  ❌ ${data['name']} FAILED enhanced adaptive filtering: $matchingAps/$finalMinAps APs needed, ${(completeness * 100).toStringAsFixed(1)}%/${(finalCompleteness * 100).toStringAsFixed(0)}% completeness needed (Sensor Enhanced)');
          }
        }
      } catch (e) {
        print('❌ Error processing exhibit ${doc.id}: $e');
        // Continue to next exhibit
      }
    }

    if (matchResults.isEmpty) {
      print('❌ No matches found');
      return null;
    }

    print('📊 ${matchResults.length} valid matches after adaptive filtering');

    // Sort by score (lower is better)
    matchResults.sort((a, b) => (a['score'] as double).compareTo(b['score'] as double));

    final bestMatch = matchResults.first;
    final secondBestMatch = matchResults.length > 1 ? matchResults[1] : null;

    final frequencyConsistency = bestMatch['frequencyConsistency'] as double;
    final exhibitName = bestMatch['name'] as String;
    final score = bestMatch['score'] as double;
    final matchingAps = bestMatch['matchingAps'] as int;
    final completeness = bestMatch['completeness'] as double;
    final channelWidthConsistency = bestMatch['channelWidthConsistency'] as double;
    final ssidConsistency = bestMatch['ssidConsistency'] as double;

    print('🏆 Best match: $exhibitName (Score: $score, APs: $matchingAps, Completeness: ${(completeness * 100).toStringAsFixed(1)}%, FreqMatch: ${(frequencyConsistency * 100).toStringAsFixed(1)}%, SSIDMatch: ${(ssidConsistency * 100).toStringAsFixed(1)}%, ChWidthMatch: ${(channelWidthConsistency * 100).toStringAsFixed(1)}%)');

    if (secondBestMatch != null) {
      final secondScore = secondBestMatch['score'] as double;
      final secondName = secondBestMatch['name'] as String;
      final scoreRatio = score / secondScore;

      // More intelligent ambiguity check based on score quality (1-5m detection)
      // If both scores are very good (low), be appropriately strict for 1-5m radius
      final isGoodMatch = score <= 7.2; // Relaxed by 10% from 8.0 for easier detection
      final effectiveThreshold = isGoodMatch ? 0.765 : AMBIGUITY_THRESHOLD; // Relaxed by 10% from 0.85

      print('🥈 Second best: $secondName (Score: $secondScore, Ratio: ${scoreRatio.toStringAsFixed(3)})');

      // If scores are identical, use tie-breaking criteria
      if (scoreRatio >= 0.99) { // Scores are essentially identical
        print('⚖️ Scores identical - using tie-breaking criteria...');

        // Tie-breaking: prefer match with higher completeness
        final secondCompleteness = secondBestMatch['completeness'] as double;
        final completenessDiff = completeness - secondCompleteness;

        // If completeness is significantly better, accept it
        if (completenessDiff > 0.1) {
          print('✅ Tie broken by completeness: ${(completeness * 100).toStringAsFixed(1)}% vs ${(secondCompleteness * 100).toStringAsFixed(1)}%');
        } else if (completenessDiff < -0.1) {
          print('❌ Tie broken by completeness - second match wins');
          return null;
        } else {
          // If completeness is also very close, check frequency consistency
          final secondFreqConsistency = secondBestMatch['frequencyConsistency'] as double;
          final currentFreqConsistency = bestMatch['frequencyConsistency'] as double;
          final freqConsistencyDiff = currentFreqConsistency - secondFreqConsistency;

          if (freqConsistencyDiff > 0.1) {
            print('✅ Tie broken by frequency consistency: ${(currentFreqConsistency * 100).toStringAsFixed(1)}% vs ${(secondFreqConsistency * 100).toStringAsFixed(1)}%');
          } else if (freqConsistencyDiff < -0.1) {
            print('❌ Tie broken by frequency consistency - second match wins');
            return null;
          } else {
            // If frequency consistency is also close, check SSID consistency
            final secondSsidConsistency = secondBestMatch['ssidConsistency'] as double;
            final currentSsidConsistency = bestMatch['ssidConsistency'] as double;
            final ssidConsistencyDiff = currentSsidConsistency - secondSsidConsistency;

            if (ssidConsistencyDiff > 0.1) {
              print('✅ Tie broken by SSID consistency: ${(currentSsidConsistency * 100).toStringAsFixed(1)}% vs ${(secondSsidConsistency * 100).toStringAsFixed(1)}%');
            } else if (ssidConsistencyDiff < -0.1) {
              print('❌ Tie broken by SSID consistency - second match wins');
              return null;
            } else {
              print('⚠️ Tie still unresolved - accepting first match');
            }
          }
        }
      } else if (scoreRatio > effectiveThreshold) {
        print('❌ Match rejected - ambiguous results (scores too similar)');
        return null;
      }
    }

    // Final confidence check
    if (score > MAX_DISTANCE_THRESHOLD) {
      print('❌ Match rejected - score too high: $score > $MAX_DISTANCE_THRESHOLD');
      return null;
    }

    // Enhanced confidence calculation based on score quality (1-5m detection)
    final baseConfidence = 1.0 / (score + 1.0);
    final isHighQualityMatch = score <= 6.3 && completeness >= 0.54; // Relaxed by 10% from 7.0 & 0.6

    // Apply sensor fusion enhancement (reduced impact)
    final sensorBonus = movementConfidence * 0.15; // Reduced from 0.3 (30% → 15% max bonus)
    final enhancedConfidence = (isHighQualityMatch ? baseConfidence * 1.15 : baseConfidence) + sensorBonus; // Reduced from 1.3

    print('🎯 Enhanced Confidence: ${(enhancedConfidence * 100).toStringAsFixed(1)}% (WiFi: ${(baseConfidence * 100).toStringAsFixed(1)}%, Sensor Bonus: ${(sensorBonus * 100).toStringAsFixed(1)}%, High Quality: $isHighQualityMatch)');

    final winningData = bestMatch['data'] as Map<String, dynamic>;

    return ExhibitMatchResult(
      id: bestMatch['docId'] as String,
      name: exhibitName,
      description: (winningData['description'] ?? '').toString(),
      audioUrl: (winningData['audioUrl'] as String?),
      confidenceDistance: enhancedConfidence,
    );
  }
}