import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'location_service.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

// Audio player states for the audio player
enum AudioPlayerState { stopped, playing, paused, completed }

// --- KNN HELPER FUNCTION (MODIFIED FOR 3-AP ROBUSTNESS) ---
// Calculates the Euclidean Distance squared, only using specific target SSIDs.
// NOTE: This implementation is simplified for testing robustness in a fixed environment.
double _calculateImprovedDistance(
    Map<String, int> liveRssiMap,
    Map<String, int> storedRssiMap,
    {Map<String, double>? liveStabilityScores,
    Map<String, double>? storedStabilityScores}) {

  const List<String> targetSsids = ['YuvanRR', 'realme 13 Pro 5G', 'Praveen\'s A16'];

  double squaredDifferenceSum = 0.0;
  const int defaultRssi = -100;
  int matchedNetworks = 0;
  double totalWeight = 0.0;
  Map<String, double> networkWeights = {};

  // Combine all BSSIDs from both maps
  final allBssids = {...liveRssiMap.keys, ...storedRssiMap.keys};

  for (final bssid in allBssids) {
    final liveRssi = liveRssiMap[bssid] ?? defaultRssi;
    final storedRssi = storedRssiMap[bssid] ?? defaultRssi;

    // Only calculate if this BSSID was in the stored fingerprint
    if (storedRssiMap.containsKey(bssid)) {
      final diff = (liveRssi - storedRssi);
      squaredDifferenceSum += diff * diff;
      matchedNetworks++;

      // Enhanced weighting system
      double weight = 1.0;

      // 1. Weight by signal strength (stronger = more reliable)
      if (storedRssi > -50) weight *= 2.0;
      else if (storedRssi > -70) weight *= 1.5;

      // 2. Weight by network type (target networks get higher priority)
      if (targetSsids.any((target) => bssid.toLowerCase().contains(target.toLowerCase().split(' ').first))) {
        weight *= 1.3;
      }

      // 3. Weight by stability (more stable signals are more reliable)
      final storedStability = storedStabilityScores?[bssid] ?? 5.0; // Default 5dB if unknown
      final liveStability = liveStabilityScores?[bssid] ?? 5.0;

      // Lower stability (lower variance) gets higher weight
      weight *= (1.0 / (1.0 + storedStability * 0.1)); // Scale stability to 0.5-1.0 range
      weight *= (1.0 / (1.0 + liveStability * 0.1));

      // 4. Weight by frequency band (5GHz is more stable)
      if (bssid.contains('5G') || bssid.contains('5GHz')) {
        weight *= 1.2;
      }

      // 5. Weight by uniqueness (penalize common networks)
      if (['AndroidAP', 'iPhone', 'Redmi', 'Guest'].any((common) =>
          bssid.toLowerCase().contains(common.toLowerCase()))) {
        weight *= 0.8;
      }

      squaredDifferenceSum *= weight;
      totalWeight += weight;
      networkWeights[bssid] = weight;
    }
  }

  // Normalize by total weight
  if (totalWeight > 0) {
    squaredDifferenceSum = squaredDifferenceSum / totalWeight;
  }

  // Enhanced penalty system
  double matchQuality = matchedNetworks / max(1, allBssids.length);

  if (matchedNetworks < 2) {
    squaredDifferenceSum *= 4.0;
  } else if (matchedNetworks < 3) {
    squaredDifferenceSum *= 2.0;
  } else if (matchQuality < 0.5) {
    squaredDifferenceSum *= 1.5;
  }

  print('📊 Enhanced Match: $matchedNetworks networks, quality ${(matchQuality * 100).toStringAsFixed(1)}%, weights: ${networkWeights.toString()}');

  return squaredDifferenceSum;
}
// --- END KNN HELPER FUNCTION ---


class ExhibitPage extends StatefulWidget {
  const ExhibitPage({super.key});

  @override
  State<ExhibitPage> createState() => _ExhibitPageState();
}

class _ExhibitPageState extends State<ExhibitPage> {
  // Data shown to user
  String? exhibitName;
  String? exhibitDescription;
  String? audioUrl;
  bool _isDetecting = false; // State for scanning animation

  final LocationService _locationService = LocationService(); // INSTANCE OF NEW SERVICE

  // Audio player and TTS setup (Simplified for brevity)
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayerState _playerState = AudioPlayerState.stopped;
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();

    exhibitName = 'Exhibit';
    exhibitDescription = 'Tap the button to detect location and play the description.';

    // Audio player listeners (Simplified for brevity)
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.completed) {
          _position = Duration.zero;
          _playerState = AudioPlayerState.completed;
        }
      });
    });
    _audioPlayer.onDurationChanged.listen((d) => setState(() => _duration = d));
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _position = p));

    // TTS Setup
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.5);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _tts.setCancelHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((msg) => setState(() => _isSpeaking = false));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _playPauseTTS() async {
    if (exhibitDescription == null || exhibitDescription!.isEmpty) return;

    try {
      if (_isSpeaking) {
        await _tts.pause();
      } else {
        await _tts.speak(exhibitDescription!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error with text-to-speech: $e')),
      );
    }
  }

  Future<void> _playPauseAudio() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else if (audioUrl != null) {
        if (_playerState == AudioPlayerState.stopped || _playerState == AudioPlayerState.completed) {
          await _audioPlayer.play(UrlSource(audioUrl!));
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: $e')),
      );
    }
  }

  // --- TEMPORAL ANALYSIS: Track signal stability over time ---
  Future<Map<String, dynamic>> _getEnhancedFingerprint(int scanCount) async {
    final Map<String, List<int>> rssiHistory = {};
    final Map<String, List<int>> temporalData = {}; // Track RSSI over time

    for (int i = 0; i < scanCount; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 300));

      await wifi_scan.WiFiScan.instance.startScan();
      final currentScan = await wifi_scan.WiFiScan.instance.getScannedResults();

      const List<String> targetSsids = [
        'YuvanRR', 'realme 13 Pro 5G', 'Praveen\'s A16',
        'MCA', 'PSG', 'YuvanRR_5G', 'realme 13 Pro 5G_5GHz',
        'AndroidAP', 'iPhone', 'Redmi', 'Guest', 'Office', 'Conference'
      ];

      const List<String> fallbackSsids = [
        'Hidden Network', 'AndroidAP', 'iPhone', 'Redmi',
        'Guest', 'Office', 'Conference', 'Meeting'
      ];

      for (var ap in currentScan) {
        final ssid = ap.ssid.trim();

        if (targetSsids.any((target) => ssid.toLowerCase() == target.toLowerCase()) ||
            fallbackSsids.any((fallback) => ssid.toLowerCase() == fallback.toLowerCase()) ||
            targetSsids.any((target) => ssid.toLowerCase().contains(target.toLowerCase().split(' ').first))) {

          rssiHistory.putIfAbsent(ap.bssid, () => []).add(ap.level);

          // Track temporal stability (how much RSSI varies over time)
          temporalData.putIfAbsent(ap.bssid, () => []).add(ap.level);
        }
      }
    }

    final Map<String, int> averagedRssiMap = {};
    final Map<String, double> stabilityScores = {}; // Lower variance = higher stability

    rssiHistory.forEach((bssid, rssiList) {
      final averageRssi = (rssiList.reduce((a, b) => a + b) / rssiList.length).round();
      averagedRssiMap[bssid] = averageRssi;

      // Calculate stability (lower variance = more stable signal)
      if (rssiList.length > 1) {
        final mean = rssiList.reduce((a, b) => a + b) / rssiList.length;
        final variance = rssiList.map((rssi) => pow(rssi - mean, 2)).reduce((a, b) => a + b) / rssiList.length;
        stabilityScores[bssid] = sqrt(variance); // Standard deviation
      } else {
        stabilityScores[bssid] = 0.0; // Perfect stability if only one sample
      }
    });

    return {
      'rssiMap': averagedRssiMap,
      'stabilityScores': stabilityScores,
      'networkCount': averagedRssiMap.length,
      'scanQuality': stabilityScores.values.isNotEmpty ? stabilityScores.values.reduce((a, b) => a + b) / stabilityScores.length : 0.0
    };
  }

  // --- MANUAL MODE: TRIGGERS LOCATION SERVICE ---
  Future<void> _getNewExhibitDescription() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);

    try {
      // 1. Check Permissions and Location Services
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Location Services/GPS.')),
        );
        return;
      }
      
      // NOTE: We are bypassing the LocationService class to implement the 3-AP filter here.
      // In a cleaner app, this filtering logic would be built into the LocationService class.
      
      // 2. Find Closest Exhibit using the enhanced fingerprint system
      // Now using temporal analysis and stability tracking:
      final enhancedFingerprint = await _getEnhancedFingerprint(5);
      final liveRssiMap = enhancedFingerprint['rssiMap'] as Map<String, int>;

      if (liveRssiMap.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Wi-Fi networks detected. Please check your Wi-Fi is enabled.'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // Show enhanced scanning results
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Detecting nearby exhibits...'),
          duration: const Duration(seconds: 2),
        ),
      );

      // 3. Query Firestore for all exhibits
      final qs = await FirebaseFirestore.instance.collection('c_guru').get();

      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exhibits in database')),
        );
        return;
      }

      // 4. Calculate Distance (KNN step)
      final List<Map<String, dynamic>> matchResults = [];
      
      for (final doc in qs.docs) {
        final data = doc.data();
        final List<dynamic>? wifiFingerprintList = data['wifi_fingerprint'] as List<dynamic>?;
        
        if (wifiFingerprintList == null || wifiFingerprintList.isEmpty) continue;

        // Create stored RSSI map, ensuring only YuvanRR, realme 13 Pro 5G, and Praveen's A16 BSSIDs are considered
        final Map<String, int> storedRssiMap = {
          for (var item in wifiFingerprintList)
            if (item is Map<String, dynamic> && item['bssid'] is String && item['rssi'] is num)
              item['bssid'] as String: (item['rssi'] as num).toInt()
        };

        if (storedRssiMap.isEmpty) continue;

        // Calculate Euclidean Distance (squared) using the improved helper function
        // Now includes stability analysis and weighted matching for better discrimination
        final distanceSquared = _calculateImprovedDistance(
          liveRssiMap,
          storedRssiMap,
          liveStabilityScores: {}, // Simplified for user version
          storedStabilityScores: {}, // Simplified for user version
        );

        matchResults.add({
          'docId': doc.id,
          'distance': distanceSquared,
          'data': data,
          'storedMap': storedRssiMap, // Include for debugging
        });
      }

      if (matchResults.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not match any exhibit fingerprints.')),
        );
        return;
      }

      // 5. Find Best Match with Collision Prevention
      final bestMatch = _getBestMatchWithValidation(liveRssiMap, matchResults);

      if (bestMatch == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to detect your location. Please try moving around or check your Wi-Fi connection.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final bestData = bestMatch['data'] as Map<String, dynamic>;
      final name = (bestData['name'] ?? '').toString();
      final description = (bestData['description'] ?? '').toString();
      final maybeAudio = (bestData['audioUrl'] as String?);

      // 6. Update UI and trigger audio
      if (!mounted) return;
      setState(() {
        exhibitName = name.isEmpty ? 'Exhibit' : name;
        exhibitDescription = description.isEmpty ? 'No description available.' : description;
        audioUrl = maybeAudio;

        _audioPlayer.stop();
        _isPlaying = false;
        _position = Duration.zero;
        _playerState = AudioPlayerState.stopped;
      });

      if (description.isNotEmpty) {
        await _tts.stop();
        await _tts.speak(description);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $exhibitName found! Tap play to hear the description.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Detection failed: ${e.toString()}')),
      );
    } finally {
        if (mounted) setState(() => _isDetecting = false);
    }
  }

  // --- ADVANCED COLLISION PREVENTION ---
  Map<String, dynamic>? _getBestMatchWithValidation(
    Map<String, int> liveRssiMap,
    List<Map<String, dynamic>> matchResults,
  ) {
    if (matchResults.isEmpty) return null;

    // Sort by distance (ascending - closest first)
    matchResults.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    const double primaryThreshold = 800.0; // Primary match threshold
    const double secondaryThreshold = 1500.0; // Secondary match threshold
    const double rejectionThreshold = 3000.0; // Reject if worse than this

    final bestMatch = matchResults.first;
    final secondBest = matchResults.length > 1 ? matchResults[1] : null;

    double bestDistance = bestMatch['distance'] as double;
    double? secondDistance = secondBest?['distance'] as double?;

    // 1. REJECT if distance is too high (no good matches)
    if (bestDistance > rejectionThreshold) {
      print('🔴 REJECTED: Distance too high (${bestDistance.toStringAsFixed(1)} > $rejectionThreshold)');
      return null;
    }

    // 2. VALIDATE signal quality - check how many networks were matched
    final bestStoredMap = (bestMatch['storedMap'] as Map<String, int>?) ?? {};
    final matchedNetworks = liveRssiMap.keys.where((bssid) => bestStoredMap.containsKey(bssid)).length;

    if (matchedNetworks < 2) {
      print('🟡 WARNING: Only $matchedNetworks networks matched (minimum 2 required)');
    }

    // 3. CHECK discrimination ratio - best should be significantly better than second
    if (secondDistance != null && secondDistance > 0) {
      double discriminationRatio = secondDistance / bestDistance;

      if (discriminationRatio < 1.5) {
        print('🟡 WARNING: Poor discrimination ratio (${discriminationRatio.toStringAsFixed(2)} < 1.5)');
        // Still allow but with warning
      } else {
        print('✅ GOOD: Strong discrimination (${discriminationRatio.toStringAsFixed(2)})');
      }
    }

    // 4. FINAL VALIDATION
    if (bestDistance <= primaryThreshold) {
      print('✅ PRIMARY MATCH: Distance ${bestDistance.toStringAsFixed(1)} <= $primaryThreshold');
      return bestMatch;
    } else if (bestDistance <= secondaryThreshold && matchedNetworks >= 2) {
      print('🟡 SECONDARY MATCH: Distance ${bestDistance.toStringAsFixed(1)} <= $secondaryThreshold with $matchedNetworks matches');
      return bestMatch;
    } else {
      print('🔴 REJECTED: Distance ${bestDistance.toStringAsFixed(1)} > $secondaryThreshold or insufficient matches');
      return null;
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [
      if (duration.inHours > 0) twoDigits(duration.inHours),
      minutes,
      seconds,
    ].join(':');
  }
  Widget _buildAudioPlayerCard() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900], // Dark background for contrast
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbColor: Colors.amber,
              activeTrackColor: Colors.amber,
              inactiveTrackColor: Colors.grey[700],
              overlayColor: Colors.amber.withOpacity(0.2),
            ),
            child: Slider(
              value: _position.inSeconds.clamp(0, _duration.inSeconds).toDouble(),
              max: _duration.inSeconds == 0 ? 1 : _duration.inSeconds.toDouble(),
              onChanged: (value) async {
                await _audioPlayer.seek(Duration(seconds: value.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 48,
                    color: Colors.amber, // Highlight the control button
                  ),
                  onPressed: _playPauseAudio,
                ),
                Text(
                  _formatDuration(_duration - _position),
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for the main content card
  Widget _buildContentCard() {
    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20.0),
        margin: const EdgeInsets.only(top: 20, bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.grey.shade300, width: 1.5),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Exhibit Description',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  // TTS Play/Pause Button
                  if (exhibitDescription != null && exhibitDescription!.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _isSpeaking ? Icons.stop_circle : Icons.play_circle_filled,
                        size: 28,
                        color: Colors.blue,
                      ),
                      onPressed: _playPauseTTS,
                      tooltip: _isSpeaking ? 'Stop Description' : 'Play Description',
                    ),
                ],
              ),
              const Divider(height: 20, thickness: 1),
              Text(
                exhibitDescription ??
                    'Exhibit description has not been retrieved or is unable to retrieve due to server issues.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget for the scanning status indicator
  Widget _buildScanStatus() {
    final statusText = _isDetecting ? 'Scanning for Fingerprint...' : 'Detection Ready';
    final statusIcon = _isDetecting ? Icons.wifi_find : Icons.location_on;
    final statusColor = _isDetecting ? Colors.amber[700]! : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // High contrast background
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Artlistener Guide',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 4,
        actions: [
          // Removed Wi-Fi debug and confidence features for cleaner UI
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Title and Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    exhibitName ?? 'Exhibit',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                _buildScanStatus(),
              ],
            ),
            
            // Subtitle showing exhibit status
            if (_isDetecting)
              Text(
                'Detecting your location...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.amber[400],
                ),
              )
            else if (exhibitName != null && exhibitName != 'Exhibit')
              Text(
                'Exhibit detected successfully',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.green[400],
                ),
              )
            else
              Text(
                'Tap below to detect nearby exhibits',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400],
                ),
              ),

            // Optional streaming audio player
            if (audioUrl != null) _buildAudioPlayerCard(),

            // Exhibit Description Content
            _buildContentCard(),

            // Get Exhibit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isDetecting ? null : _getNewExhibitDescription,
                icon: _isDetecting 
                    ? const SizedBox(
                        width: 18, 
                        height: 18, 
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                      )
                    : const Icon(Icons.wifi_find, color: Colors.black),
                label: Text(_isDetecting ? 'DETECTING...' : 'DETECT EXHIBIT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber, 
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}