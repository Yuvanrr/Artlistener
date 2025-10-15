import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';

// Audio player states for the audio player
enum AudioPlayerState { stopped, playing, paused, completed }

// --- KNN HELPER FUNCTION (Assuming this is outside the class) ---
// Calculates the Euclidean Distance squared between two Wi-Fi fingerprints.
double _calculateEuclideanDistance(
    Map<String, int> liveRssiMap, Map<String, int> storedRssiMap) {
  double squaredDifferenceSum = 0.0;
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
  double? _bestDistance; // To show the confidence score
  bool _isDetecting = false; // State for scanning animation

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayerState _playerState = AudioPlayerState.stopped;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();

    exhibitName = 'Exhibit';
    exhibitDescription = 'Tap the button to detect location and play the description.';

    // Audio player listeners (Simplified for brevity)
    _audioPlayer.onPlayerStateChanged.listen((state) => setState(() => _isPlaying = state == PlayerState.playing));
    _audioPlayer.onDurationChanged.listen((d) => setState(() => _duration = d));
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _position = p));
    _audioPlayer.onPlayerComplete.listen((event) => setState(() {
      _isPlaying = false;
      _position = Duration.zero;
      _playerState = AudioPlayerState.completed;
    }));

    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
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

  // --- ACCURACY ENHANCEMENT: TEMPORAL AVERAGING (5 Scans) ---
  Future<Map<String, int>> _getAveragedFingerprint(int scanCount) async {
    final Map<String, List<int>> rssiHistory = {};

    for (int i = 0; i < scanCount; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 300)); 
      
      await wifi_scan.WiFiScan.instance.startScan();
      final currentScan = await wifi_scan.WiFiScan.instance.getScannedResults();
      
      for (var ap in currentScan) {
          if (ap.bssid.isNotEmpty) {
              rssiHistory.putIfAbsent(ap.bssid, () => []).add(ap.level);
          }
      }
    }

    final Map<String, int> averagedRssiMap = {};
    rssiHistory.forEach((bssid, rssiList) {
      final averageRssi = (rssiList.reduce((a, b) => a + b) / rssiList.length).round();
      averagedRssiMap[bssid] = averageRssi;
    });

    return averagedRssiMap;
  }
  // -------------------------------------------------------------------

  // --- KNN Matching Logic ---
  Future<void> _getNewExhibitDescription() async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Location Services/GPS.')),
        );
        setState(() => _isDetecting = false);
        return;
      }

      final can = await wifi_scan.WiFiScan.instance.canStartScan();
      if (can != wifi_scan.CanStartScan.yes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required for Wi‑Fi scan')),
        );
        setState(() => _isDetecting = false);
        return;
      }

      // Capture Live Fingerprint Vector using TEMPORAL AVERAGING
      final Map<String, int> liveRssiMap = await _getAveragedFingerprint(5); 

      if (liveRssiMap.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No stable Wi-Fi networks found.')),
        );
        setState(() => _isDetecting = false);
        return;
      }

      // Query Firestore for all exhibits
      final qs = await FirebaseFirestore.instance.collection('c_guru').get();

      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exhibits in database')),
        );
        setState(() => _isDetecting = false);
        return;
      }

      // Calculate Distance (KNN step)
      final List<Map<String, dynamic>> matchResults = [];
      
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

        final distanceSquared = _calculateEuclideanDistance(liveRssiMap, storedRssiMap);

        matchResults.add({
          'doc': doc,
          'distance': distanceSquared,
          'data': data,
        });
      }

      if (matchResults.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not match any exhibit fingerprints.')),
        );
        setState(() => _isDetecting = false);
        return;
      }

      // Find Best Match (Nearest Neighbor)
      matchResults.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      final bestMatch = matchResults.first;
      final bestData = bestMatch['data'] as Map<String, dynamic>;
      final confidenceDistance = bestMatch['distance'] as double;
      
      final name = (bestData['name'] ?? '').toString();
      final description = (bestData['description'] ?? '').toString();
      final maybeAudio = (bestData['audioUrl'] as String?);
      
      // Update UI and speak description
      if (!mounted) return;
      setState(() {
        exhibitName = name.isEmpty ? 'Exhibit' : name;
        exhibitDescription = description.isEmpty ? 'No description available.' : description;
        audioUrl = (maybeAudio != null && maybeAudio.isNotEmpty) ? maybeAudio : null;
        _bestDistance = confidenceDistance; 
        
        _audioPlayer.stop();
        _isPlaying = false;
        _position = Duration.zero;
        _playerState = AudioPlayerState.stopped;
        _isDetecting = false;
      });

      if (description.isNotEmpty) {
        await _tts.stop();
        await _tts.speak(description);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exhibit: $exhibitName found! Confidence: ${confidenceDistance.toStringAsFixed(0)}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDetecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Detection failed: ${e.toString()}')),
      );
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

  // Helper widget for the audio player card
  Widget _buildAudioPlayerCard() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      // Theme Change: Dark Background
      decoration: BoxDecoration(
        color: Colors.grey[900], 
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
              thumbColor: Colors.amber, // Theme Color
              activeTrackColor: Colors.amber, // Theme Color
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
                    color: Colors.amber, // Theme Color
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
              Text(
                'Exhibit Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
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
  
  // New widget for the scanning status indicator
  Widget _buildScanStatus() {
    final statusText = _isDetecting ? 'Scanning for Fingerprint...' : 'Detection Ready';
    final statusIcon = _isDetecting ? Icons.wifi_find : Icons.location_on;
    final statusColor = _isDetecting ? Colors.amber[700]! : Colors.green; // Amber for detecting

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
      backgroundColor: Colors.black, // Theme Change: Black Background
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
        backgroundColor: Colors.black, // Theme Change: Black AppBar
        elevation: 4,
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
                      color: Colors.white, // Theme Change: White text
                    ),
                  ),
                ),
                _buildScanStatus(),
              ],
            ),
            
            // Subtitle showing confidence
            if (_bestDistance != null)
              Text(
                'Location Confidence Score: ${_bestDistance!.toStringAsFixed(0)} (Lower is Better)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.amber[400], // Theme Change: Amber accent
                ),
              )
            else
              Text(
                'Waiting for detection signal...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400], // Subdued white/grey
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
                // Theme Change: Amber button with black text/icon
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