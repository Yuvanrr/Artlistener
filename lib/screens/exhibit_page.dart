import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'location_service.dart';

// Audio player states for the audio player
enum AudioPlayerState { stopped, playing, paused, completed }

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
  List<String>? photoUrls; // Add image URLs
  bool _isDetecting = false; // State for scanning animation

  // Audio player and TTS setup
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayerState _playerState = AudioPlayerState.stopped;
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // Target SSID
  static const String targetSsid = 'PSG';

  @override
  void initState() {
    super.initState();

    exhibitName = 'Exhibit';
    exhibitDescription = 'Tap the button to detect location and play the description.';

    // Initialize location service with sensor fusion
    _locationService = LocationService();
    _initializeServices();

    // Audio player listeners
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
    _tts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((msg) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  Future<void> _initializeServices() async {
    print('🔄 Initializing enhanced detection services...');
    try {
      final sensorSuccess = await _locationService.initialize();
      print('✅ Services initialized (Sensors: $sensorSuccess)');
    } catch (e) {
      print('❌ Service initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize detection services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _tts.stop();
    _locationService.dispose(); // Clean up sensor fusion resources
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

  // Button action: detect PSG Wi‑Fi, compare RSSI against DB, speak description
  Future<void> _getNewExhibitDescription() async {
    try {
      // 1) Scan Wi‑Fi and pick the strongest AP for the target SSID
      final can = await wifi_scan.WiFiScan.instance.canStartScan();
      if (can != wifi_scan.CanStartScan.yes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission/services required for Wi‑Fi scan')),
        );
        return;
      }

      // Start scan and get fresh results
      await wifi_scan.WiFiScan.instance.getScannedResults(); // get existing if available
      final results = await wifi_scan.WiFiScan.instance.getScannedResults();
      final psgAps = results.where((ap) => ap.ssid == targetSsid).toList();

      if (psgAps.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WIFI network not found nearby')),
        );
        return;
      }

      // Choose the AP with the best signal (highest RSSI)
      psgAps.sort((a, b) => b.level.compareTo(a.level));
      final liveAp = psgAps.first;
      final liveRssi = liveAp.level;

      // 2) Query Firestore for documents with wifi.ssid == 'PSG'
      final qs = await FirebaseFirestore.instance
          .collection('c_guru')
          .where('wifi.ssid', isEqualTo: targetSsid)
          .get();

      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exhibits for PSG in database')),
        );
        return;
      }

      // 3) Pick the best match by closest RSSI difference
      QueryDocumentSnapshot<Map<String, dynamic>>? bestDoc;
      int bestDiff = 1 << 30;

      for (final doc in qs.docs) {
        final data = doc.data();
        final wifi = data['wifi'] as Map<String, dynamic>?;

        final storedRssi = (wifi?['rssi'] is num) ? (wifi?['rssi'] as num).toInt() : null;
        if (storedRssi == null) continue;

        final diff = (storedRssi - liveRssi).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          bestDoc = doc;
        }
      }

      if (bestDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching exhibit by signal strength')),
        );
        return;
      }

      final bestData = bestDoc!.data();
      final name = (bestData['name'] ?? '').toString();
      final description = (bestData['description'] ?? '').toString();
      final maybeAudio = (bestData['audioUrl'] as String?);

      // 4) Update UI and speak description
      if (!mounted) return;
      setState(() {
        exhibitName = result.name.isEmpty ? 'Exhibit' : result.name;
        exhibitDescription = result.description.isEmpty ? 'No description available.' : result.description;
        audioUrl = result.audioUrl;

        // Note: photoUrls would need to be fetched separately from Firestore if needed
        // For now, we'll leave it null since ExhibitMatchResult doesn't contain photo data
        photoUrls = null;

        _audioPlayer.stop();
        _isPlaying = false;
        _position = Duration.zero;
        _playerState = AudioPlayerState.stopped;
      });

      // Read aloud via TTS
      if (description.isNotEmpty) {
        await _tts.stop();
        await _tts.speak(description);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loaded exhibit from Wi‑Fi fingerprint')),
      );

    } catch (e) {
      if (!mounted) return;
      print('❌ Detection error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Detection failed: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
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

  Widget _buildAudioPlayerCard() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
                    color: Colors.amber,
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

  Widget _buildImageGallery() {
    if (photoUrls == null || photoUrls!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exhibit Images',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photoUrls!.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 300,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[600]!, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photoUrls![index],
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[800],
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 48,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanStatus() {
    final statusText = _isDetecting ? 'Enhanced WiFi + Motion Analysis...' : 'Ready';
    final statusIcon = _isDetecting ? Icons.wifi_find : Icons.location_on;
    final statusColor = _isDetecting ? Colors.amber[700]! : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          if (!_isDetecting && exhibitName != null && exhibitName != 'Exhibit')
            Text(
              ' (Enhanced)',
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue[400],
                fontWeight: FontWeight.w500,
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
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exhibit Name
            Text(
              exhibitName ?? 'Exhibit not found',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),

            // Optional streaming audio (if audioUrl provided in DB)
            if (audioUrl != null) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  children: [
                    Slider(
                      value: _position.inSeconds.clamp(0, _duration.inSeconds).toDouble(),
                      max: _duration.inSeconds == 0 ? 1 : _duration.inSeconds.toDouble(),
                      onChanged: (value) async {
                        await _audioPlayer.seek(Duration(seconds: value.toInt()));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(_position)),
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              size: 40,
                              color: Colors.black,
                            ),
                            onPressed: _playPauseAudio,
                          ),
                          Text(_formatDuration(_duration - _position)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Exhibit Description
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    exhibitDescription ??
                        'Exhibit description has not been retrieved or is unable to retrieve due to server issues.',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
                _buildScanStatus(),
              ],
            ),
            
            // Status subtitle
            if (_isDetecting)
              Text(
                'Analyzing WiFi signals and motion sensors for enhanced accuracy...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.amber[400],
                ),
              )
            else if (exhibitName != null && exhibitName != 'Exhibit')
              Text(
                'Exhibit detected using WiFi fingerprint + sensor validation',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.green[400],
                ),
              )
            else
              Text(
                'Advanced WiFi + sensor-based exhibit detection with enhanced accuracy',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[400],
                ),
              ),

            // Optional streaming audio player
            if (audioUrl != null) _buildAudioPlayerCard(),

            // Image gallery (if available)
            _buildImageGallery(),

            // Exhibit Description Content
            _buildContentCard(),

            // Detection Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _getNewExhibitDescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
                child: const Text(
                  'Get Exhibit (via Wi‑Fi)',
                  style: TextStyle(
                    color: Colors.white,
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