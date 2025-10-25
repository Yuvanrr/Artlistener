import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wifi_scan/wifi_scan.dart' as wifi_scan;
import 'package:flutter_tts/flutter_tts.dart';

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

  // Audio player
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  AudioPlayerState _playerState = AudioPlayerState.stopped;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  // Target SSID
  static const String targetSsid = 'PSG';

  @override
  void initState() {
    super.initState();

    // Optional defaults while nothing is loaded
    exhibitName = 'Exhibit';
    exhibitDescription = 'Tap the button to detect location and play the description.';

    // Configure audio player listeners
    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
        _playerState = _isPlaying
            ? AudioPlayerState.playing
            : (state == PlayerState.paused
                ? AudioPlayerState.paused
                : AudioPlayerState.stopped);
      });
    });

    _audioPlayer.onDurationChanged.listen((Duration d) {
      setState(() {
        _duration = d;
      });
    });

    _audioPlayer.onPositionChanged.listen((Duration p) {
      setState(() {
        _position = p;
      });
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _playerState = AudioPlayerState.completed;
      });
    });

    // Configure TTS defaults
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US'); // adjust as needed
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
        setState(() {
          _playerState = AudioPlayerState.paused;
          _isPlaying = false;
        });
      } else {
        if (audioUrl != null) {
          if (_playerState == AudioPlayerState.stopped || _playerState == AudioPlayerState.completed) {
            await _audioPlayer.play(UrlSource(audioUrl!));
            setState(() {
              _playerState = AudioPlayerState.playing;
              _isPlaying = true;
            });
          } else {
            await _audioPlayer.resume();
            setState(() {
              _playerState = AudioPlayerState.playing;
              _isPlaying = true;
            });
          }
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
        exhibitName = name.isEmpty ? 'Exhibit' : name;
        exhibitDescription = description.isEmpty
            ? 'No description available.'
            : description;
        audioUrl = (maybeAudio != null && maybeAudio.isNotEmpty) ? maybeAudio : null;

        // Reset audio player state for any previous URL
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load exhibit: $e')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return [
      if (duration.inHours > 0) hours,
      minutes,
      seconds,
    ].join(':');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Artlistener',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
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
              ),
            ),
            const SizedBox(height: 20),

            // Get Exhibit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _getNewExhibitDescription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
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
